import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createMockVideoStorage } from '../storage/videoStorage.js';
import { createInMemoryLinkInBioImageStore, createLinkInBioImageStoreFromConfig } from './linkInBioImageStore.js';
import { createLinkInBioImageService, validateProfilePng } from './linkInBioImageService.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';
import { defaultLinkInBioAppearance } from './linkInBioAppearance.js';

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7ioAAAAASUVORK5CYII=', 'base64');
const page = { storeName: 'ร้านทดสอบ', slug: 'image-shop', links: [{ id: 'shop', title: 'ซื้อสินค้า', url: 'https://example.com' }] };
const upload = (app: ReturnType<typeof createApp>, user = 'owner', slot = 'logo', imageBase64 = png.toString('base64')) =>
  request(app).post('/link-in-bio/images').set('x-postdee-user-id', user).send({ slot, imageBase64, draftId: 'device-test' });

describe('profile page images', () => {
  it('a stale replacement cannot release a newer revision, including a newer pin on the same image', async () => {
    const store = createInMemoryLinkInBioImageStore();
    const service = createLinkInBioImageService({ store, storage: createMockVideoStorage(), profiles: createInMemoryLinkInBioStore() });
    const base = '123456789012345678901234567890ab';
    const first = await service.upload('owner', 'logo', png);
    const second = await service.upload('owner', 'logo', png);
    await service.protectDraft('owner', `${base}_1`, [first.key], 'add');
    await service.protectDraft('owner', `${base}_2`, [second.key], 'add');
    await service.protectDraft('owner', `${base}_2`, [second.key], 'replace');
    // A timed-out older request finishes after the newer local draft was saved.
    await service.protectDraft('owner', `${base}_1`, [first.key], 'replace');
    expect((await store.get(second.key))?.draftReferences).toContain(`${base}_2`);
    await service.protectDraft('owner', `${base}_3`, [second.key], 'add');
    await service.protectDraft('owner', `${base}_2`, [], 'replace');
    expect((await store.get(second.key))?.draftReferences).toContain(`${base}_3`);
    await service.protectDraft('owner', `${base}_4`, [second.key], 'replace');
    expect((await store.get(first.key))?.draftReferences).toEqual([]);
    expect((await store.get(second.key))?.draftReferences).toEqual([`${base}_4`]);
    await expect(service.protectDraft('owner', `${base}_9007199254740992`, [], 'replace')).rejects.toMatchObject({ statusCode: 400 });
  });

  it('pins a publication across service instances until persistence commits and cleanup cannot remove the committed page image', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const storage = createMockVideoStorage();
    const profiles = createInMemoryLinkInBioStore();
    const first = createLinkInBioImageService({ store, storage, profiles, now: () => now });
    const second = createLinkInBioImageService({ store, storage, profiles, now: () => now });
    const image = await first.upload('owner', 'logo', png);
    await first.upload('owner', 'logo', png);
    now = new Date('2026-10-08T10:00:00Z');
    const appearance = { ...defaultLinkInBioAppearance(), logoKey: image.key };
    const release = await first.validateImages('owner', appearance);
    await second.prune('owner');
    expect(await store.get(image.key)).not.toBeNull();
    await profiles.publish({ ...page, userId: 'owner', appearance });
    await release();
    await second.prune('owner');
    expect(await store.get(image.key)).not.toBeNull();
  });

  it('retains publication protection when persistence fails with an uncertain result', async () => {
    const images = createInMemoryLinkInBioImageStore();
    const profiles = createInMemoryLinkInBioStore();
    const app = createApp({ linkInBioImageStore: images, linkInBioStore: {
      ...profiles, publish: async () => { throw new Error('Database response lost'); }
    } });
    const key = (await upload(app).expect(201)).body.image.key;
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'owner')
      .send({ ...page, appearance: { ...defaultLinkInBioAppearance(), logoKey: key } }).expect(503);
    expect((await images.get(key))?.draftReferences).toEqual([expect.stringMatching(/^publication_/)]);
  });

  it('returns accepted publication even when releasing its temporary image guard fails', async () => {
    const images = createInMemoryLinkInBioImageStore();
    const profiles = createInMemoryLinkInBioStore();
    const app = createApp({ linkInBioStore: profiles, linkInBioImageStore: {
      ...images, removeDraftReference: async () => { throw new Error('Cleanup unavailable'); }
    } });
    const key = (await upload(app).expect(201)).body.image.key;
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'owner')
      .send({ ...page, appearance: { ...defaultLinkInBioAppearance(), logoKey: key } }).expect(200);
    expect((await profiles.getForUser('owner'))?.appearance?.logoKey).toBe(key);
    await request(app).get('/p/image-shop').expect(200);
    expect((await images.get(key))?.draftReferences).toEqual([expect.stringMatching(/^publication_/)]);
  });
  it('keeps a saved device draft image after a canceled replacement, and releases only that device reference', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const service = createLinkInBioImageService({ store, storage: createMockVideoStorage(), profiles: createInMemoryLinkInBioStore(), now: () => now });
    const saved = await service.upload('owner', 'logo', png);
    await service.protectDraft('owner', 'device-a', [saved.key], 'add');
    await service.protectDraft('owner', 'device-b', [saved.key], 'add');
    await service.upload('owner', 'logo', png);
    now = new Date('2026-10-08T10:00:00Z');
    await service.prune('owner');
    expect(await store.get(saved.key)).not.toBeNull();
    await service.protectDraft('owner', 'device-a', [], 'replace');
    await service.prune('owner');
    expect(await store.get(saved.key)).not.toBeNull();
    await service.protectDraft('owner', 'device-b', [], 'replace');
    await service.prune('owner');
    expect(await store.get(saved.key)).toBeNull();
  });

  it('validates every draft reference before replacing existing protection and scopes references to the owner', async () => {
    const app = createApp();
    const key = (await upload(app).expect(201)).body.image.key;
    const protect = (user: string, keys: string[], draftId = 'device-a', mode = 'replace') =>
      request(app).put('/link-in-bio/draft-images').set('x-postdee-user-id', user).send({ draftId, keys, mode });
    await protect('owner', [key], 'device-a', 'add').expect(200);
    await protect('stranger', [key]).expect(400);
    await protect('owner', [key, 'uploads/owner/unknown/profile-logo.png']).expect(400);
    await protect('owner', [key], '../bad').expect(400);
    await protect('owner', [key, key, key, key]).expect(400);
    await protect('owner', []).expect(200);
    const firebase = createApp({ config: readServerConfig({ AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'test' }), firebaseVerifier: { verifyIdToken: async () => ({ id: 'owner', provider: 'firebase' }) } });
    await request(firebase).put('/link-in-bio/draft-images').send({ draftId: 'device-a', keys: [], mode: 'replace' }).expect(401);
  });

  it('retains legacy images with unknown offline references without consuming the managed upload allowance', async () => {
    const store = createInMemoryLinkInBioImageStore();
    for (let index = 0; index < 20; index++) await store.save({
      id: `legacy-${index}`, userId: 'owner', slot: 'logo', storageKey: `uploads/owner/legacy-${index}/profile-logo.png`,
      sizeBytes: png.length, createdAt: new Date('2026-01-01T00:00:00Z'), bytes: png
    });
    const service = createLinkInBioImageService({ store, storage: createMockVideoStorage(), profiles: createInMemoryLinkInBioStore() });
    await service.prune('owner');
    expect(await store.list('owner')).toHaveLength(20);
    await service.upload('owner', 'logo', png);
    expect(await store.list('owner')).toHaveLength(21);
  });

  it('claims an unpinned image before deleting bytes so a concurrent draft cannot save a disappearing image', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const storage = createMockVideoStorage();
    const profiles = createInMemoryLinkInBioStore();
    const firstService = createLinkInBioImageService({ store, storage, profiles, now: () => now });
    const otherService = createLinkInBioImageService({ store, storage, profiles, now: () => now });
    const original = await firstService.upload('owner', 'logo', png);
    await firstService.upload('owner', 'logo', png);
    now = new Date('2026-10-08T10:00:00Z');
    let started!: () => void, finish!: () => void;
    const deleting = new Promise<void>((resolve) => { started = resolve; });
    const deleted = new Promise<void>((resolve) => { finish = resolve; });
    storage.deleteVideo = async () => { started(); await deleted; };
    const prune = firstService.prune('owner');
    await deleting;
    await expect(otherService.protectDraft('owner', 'device-a', [original.key], 'add')).rejects.toMatchObject({ statusCode: 400 });
    await expect(otherService.read(original.key, 'owner')).rejects.toMatchObject({ statusCode: 404 });
    finish();
    await prune;
    expect(await store.get(original.key)).toBeNull();
  });

  it('keeps a deletion claim when object deletion is uncertain instead of confirming a possibly missing draft image', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const storage = createMockVideoStorage();
    const service = createLinkInBioImageService({ store, storage, profiles: createInMemoryLinkInBioStore(), now: () => now });
    const original = await service.upload('owner', 'logo', png);
    await service.upload('owner', 'logo', png);
    now = new Date('2026-10-08T10:00:00Z');
    storage.deleteVideo = async () => { throw new Error('storage unavailable'); };
    await expect(service.prune('owner')).rejects.toThrow('storage unavailable');
    await expect(service.protectDraft('owner', 'device-a', [original.key], 'add')).rejects.toMatchObject({ statusCode: 400 });
    expect((await store.get(original.key))?.deletionClaimed).toBe(true);
  });

  it('rechecks the committed page after a deletion claim with an older profile snapshot', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const storage = createMockVideoStorage();
    storage.deleteVideo = vi.fn(async () => undefined);
    const profiles = createInMemoryLinkInBioStore();
    const service = createLinkInBioImageService({ store, storage, profiles, now: () => now });
    const original = await service.upload('owner', 'logo', png);
    await service.upload('owner', 'logo', png);
    now = new Date('2026-10-08T10:00:00Z');
    const claim = store.claimPrune;
    store.claimPrune = async (owner, key) => {
      const claimed = await claim(owner, key);
      // Simulate a claim statement snapshot from before a publication commit.
      await profiles.publish({ ...page, userId: owner, appearance: { ...defaultLinkInBioAppearance(), logoKey: key } });
      return claimed;
    };
    await service.prune('owner');
    expect(storage.deleteVideo).not.toHaveBeenCalled();
    expect((await store.get(original.key))?.deletionClaimed).toBe(false);
    expect(await service.read(original.key, 'owner')).toEqual(png);
  });

  it('keeps a claim closed without deleting bytes if the fresh page lookup fails', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const storage = createMockVideoStorage();
    storage.deleteVideo = vi.fn(async () => undefined);
    const profiles = createInMemoryLinkInBioStore();
    const service = createLinkInBioImageService({ store, storage, profiles, now: () => now });
    const original = await service.upload('owner', 'logo', png);
    await service.upload('owner', 'logo', png);
    now = new Date('2026-10-08T10:00:00Z');
    const claim = store.claimPrune;
    store.claimPrune = async (owner, key) => {
      const claimed = await claim(owner, key);
      profiles.getForUser = async () => { throw new Error('Profile read unavailable'); };
      return claimed;
    };
    await expect(service.prune('owner')).rejects.toThrow('Profile read unavailable');
    expect(storage.deleteVideo).not.toHaveBeenCalled();
    expect((await store.get(original.key))?.deletionClaimed).toBe(true);
  });

  it('cannot claim an image when another service protects it after the pruning snapshot', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const storage = createMockVideoStorage();
    storage.deleteVideo = vi.fn(async () => undefined);
    const profiles = createInMemoryLinkInBioStore();
    const first = createLinkInBioImageService({ store, storage, profiles, now: () => now });
    const second = createLinkInBioImageService({ store, storage, profiles, now: () => now });
    const original = await first.upload('owner', 'logo', png);
    await first.upload('owner', 'logo', png);
    now = new Date('2026-10-08T10:00:00Z');
    const claim = store.claimPrune;
    let started!: () => void, finish!: () => void;
    const claiming = new Promise<void>((resolve) => { started = resolve; });
    const continueClaim = new Promise<void>((resolve) => { finish = resolve; });
    store.claimPrune = async (owner, key) => { started(); await continueClaim; return claim(owner, key); };
    const pruning = first.prune('owner');
    await claiming;
    await second.protectDraft('owner', 'device-a', [original.key], 'add');
    finish();
    await pruning;
    expect(storage.deleteVideo).not.toHaveBeenCalled();
    expect(await store.get(original.key)).not.toBeNull();
  });

  it('keeps legacy client uploads protected and separately bounded during upgrade', async () => {
    const store = createInMemoryLinkInBioImageStore();
    const app = createApp({ linkInBioImageStore: store });
    const oldClientUpload = () => request(app).post('/link-in-bio/images').set('x-postdee-user-id', 'owner')
      .send({ slot: 'logo', imageBase64: png.toString('base64') });
    for (let index = 0; index < 20; index++) await oldClientUpload().expect(201);
    await oldClientUpload().expect(429);
    expect((await store.list('owner')).every((image) => image.legacyRetention === true)).toBe(true);
    await upload(app).expect(201);
    expect(await store.list('owner')).toHaveLength(21);
  });

  it('uses bound owner/key parameters and atomic reference and deletion predicates with Prisma', async () => {
    const execute = vi.fn(async (_query: TemplateStringsArray, ..._values: unknown[]) => 1);
    const delegate = {
      findUnique: vi.fn(async () => null), findMany: vi.fn(async () => []),
      create: vi.fn(async () => undefined), deleteMany: vi.fn(async () => undefined)
    };
    const store = createLinkInBioImageStoreFromConfig({ postStore: 'prisma', prisma: { linkInBioImage: delegate, $executeRaw: execute } });
    const owner = 'owner-with-quotes\'--';
    expect(await store.addDraftReference(owner, 'owned-key', 'device-a')).toBe(true);
    await store.removeDraftReference(owner, 'owned-key', 'device-a');
    expect(await store.claimPrune(owner, 'owned-key')).toBe(true);
    await store.cancelPrune(owner, 'owned-key');
    for (const [query, ...values] of execute.mock.calls) {
      expect(query.join('')).not.toContain(owner);
      expect(query.join('')).toContain('"userId" = ');
      expect(query.join('')).toContain('"storageKey" = ');
      expect(query.join('')).toContain('"deletionClaimed" = false');
      expect(values).toContain(owner);
      expect(values).toContain('owned-key');
    }
    const claimSql = execute.mock.calls[2]![0].join('');
    expect(claimSql).toContain('"draftReferences" = \'[]\'::jsonb');
    expect(claimSql).toContain('"legacyRetention" = false');
    expect(claimSql).toContain('NOT EXISTS');
    expect(claimSql).toContain('"LinkInBioProfile"');
    expect(execute.mock.calls[3]![0].join('')).toContain('"deletionClaimed" = true');
    execute.mockResolvedValueOnce(0);
    expect(await store.addDraftReference(owner, 'claimed-key', 'device-a')).toBe(false);
  });

  it('uploads validated PNGs, provides owner-only preview and public images only after publication', async () => {
    const app = createApp();
    const result = await upload(app).expect(201);
    const key = result.body.image.key;
    expect(key).toMatch(/^uploads\/owner\/[^/]+\/profile-logo\.png$/);
    await request(app).get('/link-in-bio/image').query({ key }).set('x-postdee-user-id', 'owner').expect(200).expect('Content-Type', /image\/png/);
    await request(app).get('/link-in-bio/image').query({ key }).set('x-postdee-user-id', 'stranger').expect(404);
    await request(app).get('/p/image-shop/images/logo').expect(404);
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'owner').send({ ...page, appearance: { ...defaultLinkInBioAppearance(), logoKey: key } }).expect(200);
    const image = await request(app).get('/p/image-shop/images/logo').expect(200);
    expect(image.body).toEqual(png);
    expect(image.headers['cache-control']).toBe('no-store');
    expect(image.headers['x-content-type-options']).toBe('nosniff');
    await request(app).delete('/link-in-bio/publish').set('x-postdee-user-id', 'owner').expect(200);
    await request(app).get('/p/image-shop/images/logo').expect(404);
  });

  it('rejects other owners images and arbitrary keys without changing the published page', async () => {
    const app = createApp();
    const key = (await upload(app, 'other').expect(201)).body.image.key;
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'owner').send({ ...page, appearance: { ...defaultLinkInBioAppearance(), logoKey: key } }).expect(400);
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'owner').send({ ...page, appearance: { ...defaultLinkInBioAppearance(), logoKey: 'uploads/owner/unknown/profile-logo.png' } }).expect(400);
    await request(app).get('/p/image-shop').expect(404);
  });

  it('requires Firebase authentication, rejects SVG/invalid/base64/oversize/unknown slots', async () => {
    const app = createApp();
    for (const [slot, value] of [['logo', 'not-base64'], ['logo', Buffer.from('<svg/>').toString('base64')], ['unknown', png.toString('base64')], ['cover', Buffer.alloc(512 * 1024 + 1).toString('base64')]]) {
      await upload(app, 'owner', slot, value).expect(400);
    }
    const firebase = createApp({ config: readServerConfig({ AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'test' }), firebaseVerifier: { verifyIdToken: async () => ({ id: 'owner', provider: 'firebase' }) } });
    await request(firebase).post('/link-in-bio/images').send({ slot: 'logo', imageBase64: png.toString('base64') }).expect(401);
    await request(firebase).get('/link-in-bio/image').query({ key: 'unknown' }).expect(401);
  });

  it('keeps published image bytes unchanged while uploading a new draft image', async () => {
    const app = createApp();
    const original = (await upload(app).expect(201)).body.image.key;
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'owner').send({ ...page, appearance: { ...defaultLinkInBioAppearance(), logoKey: original } }).expect(200);
    const next = (await upload(app).expect(201)).body.image.key;
    expect(next).not.toBe(original);
    const owner = await request(app).get('/link-in-bio').set('x-postdee-user-id', 'owner');
    expect(owner.body.profile.appearance.logoKey).toBe(original);
    await request(app).get('/p/image-shop/images/logo').expect(200);
  });

  it('fails closed when the configured Prisma image delegate is missing', async () => {
    const store = createLinkInBioImageStoreFromConfig({ postStore: 'prisma' });
    await expect(store.list('owner')).rejects.toMatchObject({ statusCode: 503 });
  });

  it('compensates an object upload when persisting its metadata fails', async () => {
    const store = createInMemoryLinkInBioImageStore();
    store.save = vi.fn(async () => { throw new Error('database unavailable'); });
    const storage = createMockVideoStorage();
    storage.deleteVideo = vi.fn(async () => undefined);
    const service = createLinkInBioImageService({ store, storage, profiles: createInMemoryLinkInBioStore() });
    await expect(service.upload('owner', 'logo', png)).rejects.toThrow('database unavailable');
    expect(storage.deleteVideo).toHaveBeenCalledOnce();
  });

  it('prunes old unused images while retaining current drafts and saved profile references', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const profiles = createInMemoryLinkInBioStore();
    const service = createLinkInBioImageService({ store, storage: createMockVideoStorage(), profiles, now: () => now });
    const published = await service.upload('owner', 'logo', png);
    await profiles.publish({ ...page, userId: 'owner', appearance: { ...defaultLinkInBioAppearance(), logoKey: published.key } });
    const old = await service.upload('owner', 'cover', png);
    const latest = await service.upload('owner', 'cover', png);
    now = new Date('2026-10-07T10:00:00Z');
    await service.prune('owner');
    expect(await store.get(published.key)).not.toBeNull();
    expect(await store.get(old.key)).toBeNull();
    expect(await store.get(latest.key)).not.toBeNull();
  });

  it('serves only bundled font filenames and never filesystem traversal', async () => {
    const app = createApp();
    await request(app).get('/profile-fonts/prompt-regular.ttf').expect(200).expect('Content-Type', /font\/ttf/);
    await request(app).get('/profile-fonts/unknown.ttf').expect(404);
    await request(app).get('/profile-fonts/OFL.txt').expect(404);
  });

  it('bounds per-owner image storage and serializes simultaneous uploads', async () => {
    const store = createInMemoryLinkInBioImageStore();
    const service = createLinkInBioImageService({ store, storage: createMockVideoStorage(), profiles: createInMemoryLinkInBioStore() });
    const results = await Promise.allSettled(Array.from({ length: 22 }, () => service.upload('owner', 'logo', png)));
    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(20);
    expect(results.filter((result) => result.status === 'rejected')).toHaveLength(2);
    expect(await store.list('owner')).toHaveLength(20);
    expect(await service.upload('other-owner', 'logo', png)).toHaveProperty('key');
  });

  it('uses private object storage for real uploads and bounded authenticated downloads', async () => {
    const store = createInMemoryLinkInBioImageStore();
    const storage = createMockVideoStorage();
    const mockCreate = storage.createUpload;
    storage.createUpload = async (metadata, owner) => ({ ...(await mockCreate(metadata, owner)), storageProvider: 'r2', uploadUrl: 'https://private.invalid/upload', uploadMethod: 'PUT', uploadHeaders: { 'Content-Type': 'image/png' } });
    storage.createDownloadAccess = async (videoS3Key) => ({ videoS3Key, storageProvider: 'r2', accessType: 'signed-url', downloadUrl: 'https://private.invalid/download' });
    const fetcher = vi.fn<typeof fetch>(async (_url, init) => init?.method === 'PUT' ? new Response(null, { status: 200 }) : new Response(png, { headers: { 'Content-Type': 'image/png' } }));
    const service = createLinkInBioImageService({ store, storage, profiles: createInMemoryLinkInBioStore(), fetcher });
    const image = await service.upload('owner', 'logo', png);
    expect((await store.get(image.key))?.bytes).toBeUndefined();
    expect(await service.read(image.key, 'owner')).toEqual(png);
    expect(fetcher).toHaveBeenCalledWith('https://private.invalid/upload', expect.objectContaining({ method: 'PUT', redirect: 'error', signal: expect.any(AbortSignal) }));
    fetcher.mockResolvedValueOnce(new Response(Buffer.alloc(512 * 1024 + 1)));
    await expect(service.read(image.key, 'owner')).rejects.toMatchObject({ statusCode: 400 });
  });

  it('rejects image dimension bombs, trailing payloads and truncated chunks', () => {
    const huge = Buffer.from(png); huge.writeUInt32BE(100000, 16);
    expect(() => validateProfilePng(huge)).toThrow();
    expect(() => validateProfilePng(Buffer.concat([png, Buffer.from('<script/>')]))).toThrow();
    expect(() => validateProfilePng(png.subarray(0, 42))).toThrow();
  });

  it('account deletion clears profile images as well as public pages', async () => {
    const store = createInMemoryLinkInBioImageStore();
    const app = createApp({ linkInBioImageStore: store });
    const key = (await upload(app).expect(201)).body.image.key;
    await request(app).delete('/account').set('x-postdee-user-id', 'owner').expect(200);
    expect(await store.get(key)).toBeNull();
    await request(app).get('/link-in-bio/image').query({ key }).set('x-postdee-user-id', 'owner').expect(404);
  });

  it('serializes image validation and publication against pruning an older unused image', async () => {
    let now = new Date('2026-10-05T10:00:00Z');
    const store = createInMemoryLinkInBioImageStore();
    const storage = createMockVideoStorage();
    const app = createApp({ linkInBioImageStore: store, videoStorage: storage, now: () => now });
    const old = (await upload(app).expect(201)).body.image.key;
    await upload(app).expect(201);
    now = new Date('2026-10-07T10:00:00Z');
    let beginDelete!: () => void, finishDelete!: () => void;
    const deleting = new Promise<void>((resolve) => { beginDelete = resolve; });
    const deleted = new Promise<void>((resolve) => { finishDelete = resolve; });
    storage.deleteVideo = async (key) => { if (key === old) { beginDelete(); await deleted; } };
    const inFlightPrune = upload(app, 'owner', 'cover').then((result) => result);
    await deleting;
    const publishing = request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'owner')
      .send({ ...page, appearance: { ...defaultLinkInBioAppearance(), logoKey: old } }).then((result) => result);
    finishDelete();
    expect((await inFlightPrune).status).toBe(201);
    expect((await publishing).status).toBe(400);
    await request(app).get('/p/image-shop').expect(404);
  });
});
