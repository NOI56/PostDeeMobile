import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createDefaultLinkInBioAppearance, createDefaultLinkInBioTemplateAppearance, type LinkInBioAppearance } from './linkInBioAppearance.js';
import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';

const page = { storeName: 'ร้านของคุณ', slug: 'three-dimensional-shop', links: [
  { id: 'one', title: 'เว็บไซต์', url: 'https://example.com/shop' }
] };
const templateId = 'dimensional-clay-mint';
const fixture = () => {
  const app = express();
  app.use(express.json());
  const router = express.Router();
  const store = createInMemoryLinkInBioStore();
  const releaseImages = vi.fn(async () => {});
  const validateImages = vi.fn(async () => releaseImages);
  const onPublished = vi.fn(async () => {});
  registerLinkInBioRoutes(router, (_request, response, next) => {
    response.locals.authUser = { id: 'owner', provider: 'mock' };
    next();
  }, store, undefined, { subscriptionStore: {
    getPlan: async () => 'STARTER', getPurchasedPlan: async () => 'STARTER'
  }, validateImages, onPublished });
  app.use(router);
  return { app, store, validateImages, releaseImages, onPublished };
};
const publishDimensional = (app: ReturnType<typeof express>) => request(app)
  .post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '2')
  .send({ ...page, appearance: createDefaultLinkInBioTemplateAppearance(templateId) });

describe('expanded profile catalog compatibility', () => {
  it('lets a purchased Starter account publish a 3D template and exposes its real ID only to catalog 2 clients', async () => {
    const { app, store } = fixture();
    const published = await publishDimensional(app).expect(200);
    expect(published.body.profile.appearance.templateId).toBe(templateId);
    const read = await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '2').expect(200);
    expect(read.body.profile).toEqual(published.body.profile);
    const publishSpy = vi.spyOn(store, 'publish');
    expect((await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '3').expect(200)).body.profile).toEqual(published.body.profile);
    expect((await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '4').expect(200)).body.profile).toEqual(published.body.profile);
    for (const capability of [undefined, '', '1', '5', '3, 2', '2, 1', '03', 'garbage']) {
      const pending = request(app).get('/link-in-bio');
      if (capability !== undefined) pending.set('X-PostDee-Profile-Catalog', capability);
      const legacy = await pending.expect(200);
      expect(legacy.headers['cache-control']).toBe('no-store');
      expect(legacy.body.profile.appearance, String(capability)).toEqual({ ...read.body.profile.appearance, templateId: null });
    }
    expect(publishSpy).not.toHaveBeenCalled();
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(templateId);
    const publicPage = await request(app).get(`/p/${page.slug}`).expect(200);
    expect(publicPage.text).toContain(`data-template="${templateId}"`);
  });

  it('retains the stored 3D choice when an old client republishes its exact fallback snapshot', async () => {
    const { app, store } = fixture();
    await publishDimensional(app).expect(200);
    const legacy = await request(app).get('/link-in-bio').expect(200);
    const replayed = await request(app).post('/link-in-bio/publish').send({
      ...page, storeName: 'ชื่อใหม่', appearance: legacy.body.profile.appearance
    }).expect(200);
    expect(replayed.body.profile.appearance.templateId).toBeNull();
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(templateId);
    expect((await store.getForUser('owner'))?.storeName).toBe('ชื่อใหม่');
  });

  it('rejects an edited ambiguous legacy fallback without changing the published page or images', async () => {
    const { app, store, validateImages, releaseImages, onPublished } = fixture();
    await publishDimensional(app).expect(200);
    const legacy = await request(app).get('/link-in-bio').expect(200);
    const appearance = legacy.body.profile.appearance as LinkInBioAppearance;
    const before = await store.getForUser('owner');
    const publishSpy = vi.spyOn(store, 'publish');
    validateImages.mockClear();
    releaseImages.mockClear();
    onPublished.mockClear();
    const edited = await request(app).post('/link-in-bio/publish').send({
      ...page, storeName: 'ไม่ควรถูกบันทึก', appearance: { ...appearance, buttonColor: '#123456' }
    }).expect(409);
    expect(edited.body).toMatchObject({ status: 'error', code: 'LINK_IN_BIO_APPEARANCE_CONFLICT' });
    expect(edited.headers['cache-control']).toBe('no-store');
    expect(publishSpy).not.toHaveBeenCalled();
    expect(validateImages).not.toHaveBeenCalled();
    expect(releaseImages).not.toHaveBeenCalled();
    expect(onPublished).not.toHaveBeenCalled();
    expect(await store.getForUser('owner')).toEqual(before);
    expect((await request(app).get(`/p/${page.slug}`).expect(200)).text).toContain(`data-template="${templateId}"`);
  });

  it.each([undefined, '1', '5', 'garbage'])('rejects a stale fallback captured before a newer theme was saved (catalog %s)', async (capability) => {
    const { app, store, validateImages, releaseImages, onPublished } = fixture();
    await publishDimensional(app).expect(200);
    const legacy = await request(app).get('/link-in-bio').expect(200);
    await request(app).post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '2')
      .send({ ...page, appearance: createDefaultLinkInBioTemplateAppearance('dimensional-clay-peach') }).expect(200);
    const before = await store.getForUser('owner');
    const publishSpy = vi.spyOn(store, 'publish');
    validateImages.mockClear();
    releaseImages.mockClear();
    onPublished.mockClear();
    const replay = request(app).post('/link-in-bio/publish')
      .send({ ...page, storeName: 'ชื่อใหม่จากแอปรุ่นเก่า', appearance: legacy.body.profile.appearance });
    if (capability !== undefined) replay.set('X-PostDee-Profile-Catalog', capability);
    const conflict = await replay.expect(409);
    expect(conflict.body).toMatchObject({ status: 'error', code: 'LINK_IN_BIO_APPEARANCE_CONFLICT' });
    expect(publishSpy).not.toHaveBeenCalled();
    expect(validateImages).not.toHaveBeenCalled();
    expect(releaseImages).not.toHaveBeenCalled();
    expect(onPublished).not.toHaveBeenCalled();
    expect(await store.getForUser('owner')).toEqual(before);
    const publicPage = await request(app).get(`/p/${page.slug}`).expect(200);
    expect(publicPage.text).toContain('data-template="dimensional-clay-peach"');
    expect(publicPage.text).toContain('ร้านของคุณ');
    expect(publicPage.text).not.toContain('ชื่อใหม่จากแอปรุ่นเก่า');
  });

  it('does not overwrite concurrent styling while accepting an exact legacy fallback replay', async () => {
    const { app, store } = fixture();
    await publishDimensional(app).expect(200);
    const legacy = await request(app).get('/link-in-bio').expect(200);
    const getForUser = store.getForUser;
    let started!: () => void;
    let release!: () => void;
    const startedPromise = new Promise<void>((resolve) => { started = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    store.getForUser = async (userId) => {
      const snapshot = await getForUser(userId);
      started();
      await gate;
      return snapshot;
    };
    const replay = request(app).post('/link-in-bio/publish')
      .send({ ...page, appearance: legacy.body.profile.appearance }).then((response) => response);
    await startedPromise;
    await request(app).post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '2')
      .send({ ...page, appearance: createDefaultLinkInBioTemplateAppearance('dimensional-clay-peach') }).expect(200);
    release();
    expect((await replay).status).toBe(200);
    expect((await getForUser('owner'))?.appearance?.templateId).toBe('dimensional-clay-peach');
  });

  it('keeps deliberate classic template selection working for old clients', async () => {
    const { app, store } = fixture();
    await publishDimensional(app).expect(200);
    const appearance = createDefaultLinkInBioTemplateAppearance('minimal-white-editorial');
    const changed = await request(app).post('/link-in-bio/publish').send({ ...page, appearance }).expect(200);
    expect(changed.body.profile.appearance.templateId).toBe('minimal-white-editorial');
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe('minimal-white-editorial');
  });

  it.each(['shop', 'pastel', 'dark', 'pink', 'garden', 'cards'] as const)('keeps an explicit distinct %s legacy theme selection working', async (themeId) => {
    const { app, store } = fixture();
    await publishDimensional(app).expect(200);
    const appearance = createDefaultLinkInBioAppearance(themeId);
    const changed = await request(app).post('/link-in-bio/publish').send({ ...page, appearance }).expect(200);
    expect(changed.body.profile.appearance).toMatchObject({ templateId: null, themeId });
    expect((await store.getForUser('owner'))?.appearance).toEqual(appearance);
  });

  it('lets a catalog 2 client explicitly clear its template using null', async () => {
    const { app, store } = fixture();
    const published = await publishDimensional(app).expect(200);
    const changed = await request(app).post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '2')
      .send({ ...page, appearance: { ...published.body.profile.appearance, templateId: null } }).expect(200);
    expect(changed.body.profile.appearance.templateId).toBeNull();
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBeNull();
  });

  it('serializes unpublish responses for old clients without changing their stored choice', async () => {
    const { app, store } = fixture();
    await publishDimensional(app).expect(200);
    const legacy = await request(app).delete('/link-in-bio/publish').expect(200);
    expect(legacy.body.profile).toMatchObject({ isPublished: false, appearance: { templateId: null } });
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(templateId);
    const modern = await request(app).delete('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '2').expect(200);
    expect(modern.body.profile.appearance.templateId).toBe(templateId);
  });

  it('keeps classic catalog responses identical for clients without the new header', async () => {
    const { app } = fixture();
    const appearance = createDefaultLinkInBioTemplateAppearance('minimal-white-editorial');
    const published = await request(app).post('/link-in-bio/publish').send({ ...page, appearance }).expect(200);
    const legacy = await request(app).get('/link-in-bio').expect(200);
    const modern = await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '2').expect(200);
    expect(legacy.body).toEqual(modern.body);
    expect(legacy.body.profile.appearance).toEqual(appearance);
    expect(published.body.profile.appearance).toEqual(appearance);
  });
});

const sceneId = 'dimensional-neon-sign';
const publishScene = (app: ReturnType<typeof express>) => request(app)
  .post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '3')
  .send({ ...page, appearance: createDefaultLinkInBioTemplateAppearance(sceneId) });

describe('second 3D release compatibility', () => {
  it('shows the new 3D scenes only to catalog 3 clients while catalog 2 keeps the first ten', async () => {
    const { app, store } = fixture();
    const published = await publishScene(app).expect(200);
    expect(published.body.profile.appearance.templateId).toBe(sceneId);
    const current = await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '3').expect(200);
    expect(current.body.profile).toEqual(published.body.profile);
    for (const capability of [undefined, '1', '2', '5']) {
      const pending = request(app).get('/link-in-bio');
      if (capability !== undefined) pending.set('X-PostDee-Profile-Catalog', capability);
      const older = await pending.expect(200);
      expect(older.headers.vary).toContain('X-PostDee-Profile-Catalog');
      expect(older.body.profile.appearance).toEqual({ ...current.body.profile.appearance, templateId: null });
    }
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(sceneId);
    expect((await request(app).get(`/p/${page.slug}`).expect(200)).text).toContain(`data-template="${sceneId}"`);

    await publishDimensional(app).expect(200);
    const firstRelease = await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '2').expect(200);
    expect(firstRelease.body.profile.appearance.templateId).toBe(templateId);
  });

  it('keeps the new scene when a catalog 2 app replays its exact fallback, and refuses an edited one', async () => {
    const { app, store } = fixture();
    await publishScene(app).expect(200);
    const older = await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '2').expect(200);
    const replayed = await request(app).post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '2')
      .send({ ...page, storeName: 'ชื่อจากแอปรุ่นก่อน', appearance: older.body.profile.appearance }).expect(200);
    expect(replayed.body.profile.appearance.templateId).toBeNull();
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(sceneId);
    expect((await store.getForUser('owner'))?.storeName).toBe('ชื่อจากแอปรุ่นก่อน');
    const before = await store.getForUser('owner');
    const edited = await request(app).post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '2')
      .send({ ...page, appearance: { ...older.body.profile.appearance, buttonColor: '#123456' } }).expect(409);
    expect(edited.body.code).toBe('LINK_IN_BIO_APPEARANCE_CONFLICT');
    expect(await store.getForUser('owner')).toEqual(before);
  });

  it('lets a catalog 2 app deliberately switch from a new scene to a first-release 3D design', async () => {
    const { app, store } = fixture();
    await publishScene(app).expect(200);
    await publishDimensional(app).expect(200);
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(templateId);
  });

  it('serializes unpublish responses per catalog without changing the stored scene', async () => {
    const { app, store } = fixture();
    await publishScene(app).expect(200);
    const older = await request(app).delete('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '2').expect(200);
    expect(older.body.profile).toMatchObject({ isPublished: false, appearance: { templateId: null } });
    const current = await request(app).delete('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '3').expect(200);
    expect(current.body.profile.appearance.templateId).toBe(sceneId);
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(sceneId);
  });
});

const cartoonId = 'cartoon-street-front';
const publishCartoon = (app: ReturnType<typeof express>, catalog = '4') => request(app)
  .post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', catalog)
  .send({ ...page, appearance: createDefaultLinkInBioTemplateAppearance(cartoonId) });

describe('cartoon release compatibility', () => {
  it('shows cartoon designs only to catalog 4 clients while older apps keep their fallback', async () => {
    const { app, store } = fixture();
    const published = await publishCartoon(app).expect(200);
    expect(published.body.profile.appearance.templateId).toBe(cartoonId);
    const current = await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '4').expect(200);
    expect(current.body.profile).toEqual(published.body.profile);
    for (const capability of [undefined, '1', '2', '3', '5', '04']) {
      const pending = request(app).get('/link-in-bio');
      if (capability !== undefined) pending.set('X-PostDee-Profile-Catalog', capability);
      const older = await pending.expect(200);
      expect(older.headers.vary).toContain('X-PostDee-Profile-Catalog');
      expect(older.headers['cache-control']).toBe('no-store');
      expect(older.body.profile.appearance, String(capability)).toEqual({ ...current.body.profile.appearance, templateId: null });
    }
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(cartoonId);
    expect((await request(app).get(`/p/${page.slug}`).expect(200)).text).toContain(`data-template="${cartoonId}"`);
  });

  it('keeps 3D designs visible to catalog 4 clients', async () => {
    const { app } = fixture();
    await publishScene(app).expect(200);
    expect((await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '4').expect(200)).body.profile.appearance.templateId).toBe(sceneId);
  });

  it('keeps the cartoon design when a catalog 3 app replays its exact fallback, and refuses an edited one', async () => {
    const { app, store } = fixture();
    await publishCartoon(app).expect(200);
    const older = await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '3').expect(200);
    const replayed = await request(app).post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '3')
      .send({ ...page, storeName: 'ชื่อจากแอปรุ่นก่อน', appearance: older.body.profile.appearance }).expect(200);
    expect(replayed.body.profile.appearance.templateId).toBeNull();
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(cartoonId);
    expect((await store.getForUser('owner'))?.storeName).toBe('ชื่อจากแอปรุ่นก่อน');
    const before = await store.getForUser('owner');
    const edited = await request(app).post('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '3')
      .send({ ...page, appearance: { ...older.body.profile.appearance, buttonColor: '#123456' } }).expect(409);
    expect(edited.body.code).toBe('LINK_IN_BIO_APPEARANCE_CONFLICT');
    expect(await store.getForUser('owner')).toEqual(before);
  });

  it('lets a catalog 3 app deliberately switch from a cartoon design to a 3D scene', async () => {
    const { app, store } = fixture();
    await publishCartoon(app).expect(200);
    await publishScene(app).expect(200);
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(sceneId);
  });

  it('serializes unpublish responses per catalog without changing the stored cartoon design', async () => {
    const { app, store } = fixture();
    await publishCartoon(app).expect(200);
    const older = await request(app).delete('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '3').expect(200);
    expect(older.body.profile).toMatchObject({ isPublished: false, appearance: { templateId: null } });
    const current = await request(app).delete('/link-in-bio/publish').set('X-PostDee-Profile-Catalog', '4').expect(200);
    expect(current.body.profile.appearance.templateId).toBe(cartoonId);
    expect((await store.getForUser('owner'))?.appearance?.templateId).toBe(cartoonId);
  });
});
