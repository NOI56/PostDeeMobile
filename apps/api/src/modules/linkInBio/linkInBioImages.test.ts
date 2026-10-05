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
  request(app).post('/link-in-bio/images').set('x-postdee-user-id', user).send({ slot, imageBase64 });

describe('profile page images', () => {
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
