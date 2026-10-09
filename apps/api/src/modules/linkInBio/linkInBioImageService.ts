import type { VideoStorage } from '../storage/videoStorage.js';
import { randomUUID } from 'node:crypto';
import { createOwnerMutationLock } from '../account/ownerMutationLock.js';
import { isStorageKeyOwnedByUser } from '../storage/storageKeyPolicy.js';
import type { LinkInBioAppearance } from './linkInBioAppearance.js';
import { LinkInBioError, type LinkInBioStore } from './linkInBioStore.js';
import type { LinkInBioImage, LinkInBioImageStore } from './linkInBioImageStore.js';

export const profileImageMaxBytes = 512 * 1024;
const maximumDimension = 1280;
const slots = ['logo', 'cover', 'background'] as const;
const invalidImage = () => new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'เลือกรูป PNG ขนาดไม่เกิน 512 KB และด้านละไม่เกิน 1280 พิกเซล');
export const isProfileImageSlot = (value: unknown): value is LinkInBioImage['slot'] =>
  typeof value === 'string' && slots.includes(value as LinkInBioImage['slot']);
export const validateProfilePng = (bytes: Uint8Array) => {
  const data = Buffer.from(bytes);
  if (data.length < 57 || data.length > profileImageMaxBytes ||
      !data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ||
      data.readUInt32BE(8) !== 13 || data.toString('ascii', 12, 16) !== 'IHDR' ||
      data.toString('ascii', data.length - 8, data.length - 4) !== 'IEND') throw invalidImage();
  const width = data.readUInt32BE(16), height = data.readUInt32BE(20);
  if (!width || !height || width > maximumDimension || height > maximumDimension) throw invalidImage();
  let offset = 8;
  let hasPixels = false;
  while (offset < data.length) {
    if (offset + 12 > data.length) throw invalidImage();
    const length = data.readUInt32BE(offset);
    const type = data.toString('ascii', offset + 4, offset + 8);
    if (length > data.length - offset - 12 || (type === 'IHDR' && offset !== 8)) throw invalidImage();
    if (type === 'IDAT' && length > 0) hasPixels = true;
    if (type === 'IEND' && (length !== 0 || offset + 12 !== data.length)) throw invalidImage();
    offset += length + 12;
  }
  if (!hasPixels) throw invalidImage();
};
export const readProfileImageBase64 = (value: unknown) => {
  if (typeof value !== 'string' || !value || value.length > Math.ceil(profileImageMaxBytes / 3) * 4 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) throw invalidImage();
  const bytes = Buffer.from(value, 'base64');
  validateProfilePng(bytes);
  return bytes;
};

const imageKeys = (appearance?: LinkInBioAppearance) => [
  appearance?.logoKey, appearance?.coverKey, appearance?.background.imageKey
].filter((key): key is string => Boolean(key));
const draftReferenceVersion = (reference: string) => {
  const match = /^([a-f0-9]{32})_(\d+)$/.exec(reference);
  if (!match) return { base: reference, revision: 0 };
  const revision = Number(match[2]);
  if (!Number.isSafeInteger(revision) || revision < 1) {
    throw new LinkInBioError(400, 'LINK_IN_BIO_DRAFT_IMAGES_INVALID', 'ข้อมูลรุ่นแบบร่างไม่ถูกต้อง');
  }
  return { base: match[1]!, revision };
};
const readBoundedImage = async (response: Response): Promise<Uint8Array> => {
  const length = Number(response.headers.get('content-length'));
  if (length > profileImageMaxBytes || !response.body) throw invalidImage();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > profileImageMaxBytes) throw invalidImage();
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  const bytes = Buffer.concat(chunks);
  validateProfilePng(bytes);
  return bytes;
};

export const createLinkInBioImageService = ({ store, storage, profiles, now = () => new Date(), fetcher = fetch }: {
  store: LinkInBioImageStore; storage: VideoStorage; profiles: LinkInBioStore;
  now?: () => Date; fetcher?: typeof fetch;
}) => {
  let lastCreatedAt = 0;
  const imageLock = createOwnerMutationLock();
  const withOwnerLock = async <T>(userId: string, operation: () => Promise<T>): Promise<T> => {
    const release = await imageLock.acquire(userId);
    try { return await operation(); } finally { release(); }
  };
  const pruneUnlocked = async (userId: string) => {
    const saved = await profiles.getForUser(userId);
    const keep = new Set(imageKeys(saved?.appearance));
    const images = await store.list(userId);
    const latestSlots = new Set<string>();
    for (const image of images) {
      if (!latestSlots.has(image.slot)) { keep.add(image.storageKey); latestSlots.add(image.slot); }
    }
    const cutoff = now().getTime() - 24 * 60 * 60 * 1000;
    for (const image of images) {
      if (image.legacyRetention !== false || image.draftReferences?.length || keep.has(image.storageKey) || image.createdAt.getTime() >= cutoff) continue;
      // Offline legacy references are unknown. Managed drafts pin their keys;
      // only unpinned replacements can expire after the grace window.
      if (imageKeys((await profiles.getForUser(userId))?.appearance).includes(image.storageKey)) continue;
      if (!await store.claimPrune(userId, image.storageKey)) continue;
      // A waiting SQL update can use an older profile snapshot. Once claimed,
      // no new publication can pin this key; check the committed profile anew.
      // If this read fails, retain the claim and never attempt object deletion.
      if (imageKeys((await profiles.getForUser(userId))?.appearance).includes(image.storageKey)) {
        await store.cancelPrune(userId, image.storageKey);
        continue;
      }
      // A storage timeout can mean deletion succeeded without a response.
      // Keep the claim on any interrupted cleanup; never pin uncertain bytes.
      await storage.deleteVideo(image.storageKey);
      await store.remove(userId, image.storageKey);
    }
  };
  const prune = (userId: string) => withOwnerLock(userId, () => pruneUnlocked(userId));
  const validateImages = async (userId: string, appearance: LinkInBioAppearance) => {
    const keys = [...new Set(imageKeys(appearance))];
    for (const key of keys) {
      const image = await store.get(key);
      if (!image || image.deletionClaimed || image.userId !== userId || !isStorageKeyOwnedByUser({ videoS3Key: key, userId })) {
        throw new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'รูปที่เลือกไม่พร้อมใช้งาน กรุณาอัปโหลดรูปอีกครั้ง');
      }
    }
    const reference = `publication_${randomUUID()}`;
    const pinned: string[] = [];
    const release = async () => {
      for (const key of pinned) await store.removeDraftReference(userId, key, reference);
    };
    try {
      for (const key of keys) {
        if (!await store.addDraftReference(userId, key, reference)) {
          throw new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'รูปที่เลือกไม่พร้อมใช้งาน กรุณาอัปโหลดรูปอีกครั้ง');
        }
        pinned.push(key);
      }
    } catch (error) {
      try { await release(); } catch { /* Retain extra protection on cleanup failure. */ }
      throw error;
    }
    return release;
  };
  const read = async (key: string, userId?: string) => {
    const image = await store.get(key);
    if (!image || image.deletionClaimed || (userId !== undefined && image.userId !== userId)) {
      throw new LinkInBioError(404, 'LINK_IN_BIO_IMAGE_NOT_FOUND', 'ไม่พบรูปภาพ');
    }
    if (image.bytes) return image.bytes;
    const access = await storage.createDownloadAccess(key);
    if (access.accessType !== 'signed-url' || !access.downloadUrl) throw new Error('Private image download is unavailable');
    const response = await fetcher(access.downloadUrl, { redirect: 'error', signal: AbortSignal.timeout(12_000) });
    if (!response.ok) throw new Error('Private image download failed');
    return readBoundedImage(response);
  };
  const protectDraft = (userId: string, draftId: string, keys: string[], mode: 'add' | 'replace') => withOwnerLock(userId, async () => {
    if (typeof draftId !== 'string' || !/^[a-zA-Z0-9_-]{8,80}$/.test(draftId) || !Array.isArray(keys) || keys.length > 3 ||
        keys.some((key) => typeof key !== 'string' || key.length > 512) || !['add', 'replace'].includes(mode)) {
      throw new LinkInBioError(400, 'LINK_IN_BIO_DRAFT_IMAGES_INVALID', 'ข้อมูลรูปแบบร่างไม่ถูกต้อง');
    }
    const wanted = new Set(keys);
    const version = draftReferenceVersion(draftId);
    const images = await store.list(userId);
    for (const key of wanted) {
      const image = images.find((entry) => entry.storageKey === key);
      if (!image || image.deletionClaimed || !isStorageKeyOwnedByUser({ videoS3Key: key, userId })) {
        throw new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'รูปที่เลือกไม่พร้อมใช้งาน กรุณาอัปโหลดรูปอีกครั้ง');
      }
      if (!(image.draftReferences ?? []).includes(draftId) && (image.draftReferences ?? []).length >= 32) {
        throw new LinkInBioError(429, 'LINK_IN_BIO_DRAFT_IMAGE_LIMIT', 'รูปนี้ถูกใช้ในแบบร่างหลายเครื่องเกินไป');
      }
    }
    // Add before releasing any old references. A failed write must keep prior
    // draft keys safe; callers replace only after their local save succeeds.
    for (const image of images.filter((entry) => wanted.has(entry.storageKey))) {
      if (!await store.addDraftReference(userId, image.storageKey, draftId)) {
        throw new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'รูปที่เลือกไม่พร้อมใช้งาน กรุณาอัปโหลดรูปอีกครั้ง');
      }
    }
    if (mode === 'replace') for (const image of images) {
      const references = image.draftReferences ?? [];
      for (const reference of references) {
        const storedVersion = draftReferenceVersion(reference);
        if (storedVersion.base === version.base && storedVersion.revision <= version.revision &&
            (reference !== draftId || !wanted.has(image.storageKey))) {
          await store.removeDraftReference(userId, image.storageKey, reference);
        }
      }
    }
  });
  return {
    prune, validateImages, read, withOwnerLock, protectDraft,
    upload: (userId: string, slot: LinkInBioImage['slot'], bytes: Uint8Array, legacyRetention = false) => withOwnerLock(userId, async () => {
      if (!isProfileImageSlot(slot)) throw invalidImage();
      validateProfilePng(bytes);
      await pruneUnlocked(userId);
      if ((await store.list(userId)).filter((image) => (image.legacyRetention !== false) === legacyRetention).length >= 20) {
        throw new LinkInBioError(429, 'LINK_IN_BIO_IMAGE_LIMIT', 'อัปโหลดรูปบ่อยเกินไป กรุณาลองใหม่ภายหลัง');
      }
      const upload = await storage.createUpload({ fileName: `profile-${slot}.png`, contentType: 'image/png', sizeBytes: bytes.length }, userId);
      try {
        if (upload.storageProvider !== 'mock-s3') {
          if (!upload.uploadUrl || upload.uploadMethod !== 'PUT') throw new Error('Private image upload is unavailable');
          const response = await fetcher(upload.uploadUrl, { method: 'PUT', headers: upload.uploadHeaders, body: Buffer.from(bytes), redirect: 'error', signal: AbortSignal.timeout(20_000) });
          if (!response.ok) throw new Error('Private image upload failed');
        }
        lastCreatedAt = Math.max(now().getTime(), lastCreatedAt + 1);
        await store.save({ id: upload.id, userId, slot, storageKey: upload.videoS3Key, sizeBytes: bytes.length,
          createdAt: new Date(lastCreatedAt), draftReferences: [], legacyRetention,
          ...(upload.storageProvider === 'mock-s3' ? { bytes } : {}) });
      } catch (error) {
        try { await storage.deleteVideo(upload.videoS3Key); } catch { /* Keep original error; owner cleanup includes this key. */ }
        throw error;
      }
      return { key: upload.videoS3Key };
    })
  };
};
export type LinkInBioImageService = ReturnType<typeof createLinkInBioImageService>;
