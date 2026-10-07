import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createDefaultLinkInBioAppearance } from './linkInBioAppearance.js';
import { registerLinkInBioRoutes, type LinkInBioRouteOptions } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore, LinkInBioError } from './linkInBioStore.js';

const page = { storeName: 'ร้าน', slug: 'shop', links: [{ id: 'buy', title: 'ซื้อ', url: 'https://shopee.co.th/shop' }] };
const fixture = (options?: LinkInBioRouteOptions) => {
  const app = express();
  app.use(express.json());
  const router = express.Router();
  const store = createInMemoryLinkInBioStore();
  registerLinkInBioRoutes(router, (_request, response, next) => {
    response.locals.authUser = { id: 'owner', provider: 'mock' };
    next();
  }, store, undefined, options);
  app.use(router);
  return { app, store };
};

describe('link in bio customization routes', () => {
  it.each(['pink', 'garden', 'cards'])('persists %s effects and serves a safe CSS-only page', async (themeId) => {
    const { app } = fixture();
    const appearance = { themeId, effects: { background: false, entrance: true, featured: true, stickers: 'flowers' } };
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance }).expect(200);
    const saved = await request(app).get('/link-in-bio').expect(200);
    expect(saved.body.profile.appearance).toMatchObject(appearance);
    // An older client omitting appearance must keep the new snapshot.
    const legacy = await request(app).post('/link-in-bio/publish').send(page).expect(200);
    expect(legacy.body.profile.appearance).toMatchObject(appearance);
    const rendered = await request(app).get('/p/shop').expect(200);
    expect(rendered.text).toContain(`data-theme="${themeId}"`);
    expect(rendered.text).toContain('data-stickers="flowers"');
    expect(rendered.text).not.toContain('<script');
    expect(rendered.headers['content-security-policy']).toContain("script-src 'none'");
    expect(rendered.headers['content-security-policy']).toContain("style-src 'nonce-");
    expect(rendered.headers['cache-control']).toBe('no-store');
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance: { ...appearance, effects: { stickers: 'url(evil)' } } }).expect(400);
    expect((await request(app).get('/link-in-bio').expect(200)).body.profile.appearance).toMatchObject(appearance);
  });

  it('returns normalized defaults to old clients and retains styling on their later publish', async () => {
    const { app } = fixture();
    const initial = await request(app).post('/link-in-bio/publish').send(page).expect(200);
    expect(initial.body.profile.appearance).toEqual(createDefaultLinkInBioAppearance());
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance: { themeId: 'dark' } }).expect(200);
    const legacy = await request(app).post('/link-in-bio/publish').send(page).expect(200);
    expect(legacy.body.profile.appearance.themeId).toBe('dark');
  });

  it('does not overwrite a concurrently customized appearance with a legacy publish snapshot', async () => {
    const { app, store } = fixture();
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance: { themeId: 'dark' } }).expect(200);
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
    const legacy = request(app).post('/link-in-bio/publish').send(page).then((response) => response);
    await startedPromise;
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance: { themeId: 'pastel' } }).expect(200);
    release();
    expect((await legacy).body.profile.appearance.themeId).toBe('pastel');
  });

  it('supports categorized and individually styled links while escaping all text', async () => {
    const { app } = fixture();
    await request(app).post('/link-in-bio/publish').send({ ...page,
      links: [{ ...page.links[0], category: '<script>โปรโมชัน</script>', icon: 'shopee', font: 'prompt', textColor: '#ffccdd', buttonColor: '#123456' }],
      appearance: { description: '<script>สวัสดี</script>', featuredLinkId: 'buy', featuredLabel: '<b>โปรวันนี้</b>', nameStyle: { font: 'prompt' } }
    }).expect(200);
    const result = await request(app).get('/p/shop').expect(200);
    expect(result.text).toContain('&lt;script&gt;สวัสดี&lt;/script&gt;');
    expect(result.text).toContain('&lt;script&gt;โปรโมชัน&lt;/script&gt;');
    expect(result.text).toContain('&lt;b&gt;โปรวันนี้&lt;/b&gt;');
    expect(result.text).toContain('#123456');
    expect(result.text).toContain('/profile-fonts/prompt-regular.ttf');
    expect(result.text).toContain('data-icon="shopee"');
    expect(result.text).not.toContain('<script>');
    expect(result.headers['content-security-policy']).toContain("img-src 'self'");
    expect(result.headers['content-security-policy']).toContain("font-src 'self'");
    expect(result.headers['cache-control']).toBe('no-store');
  });

  it.each([
    { category: 'x'.repeat(61) }, { icon: 'javascript' }, { font: 'remote' },
    { textColor: '#123456;}' }, { buttonColor: 'url(https://evil)' }
  ])('rejects unsafe link customization %#', async (invalid) => {
    const { app } = fixture();
    await request(app).post('/link-in-bio/publish').send({ ...page, links: [{ ...page.links[0], ...invalid }] }).expect(400);
  });

  it('refuses image references if no owner validator is configured', async () => {
    const { app, store } = fixture();
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance: { logoKey: 'profiles/owner/logo.png' } }).expect(400);
    expect(await store.getForUser('owner')).toBeNull();
  });

  it('checks image ownership before writing and renders same-origin slot paths without exposing keys', async () => {
    const validateImages = vi.fn(async () => {});
    const { app } = fixture({ validateImages });
    const appearance = { logoKey: 'profiles/owner/logo.png', coverKey: 'profiles/owner/cover.png', background: { mode: 'image', imageKey: 'profiles/owner/background.png' } };
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance }).expect(200);
    expect(validateImages).toHaveBeenCalledWith('owner', expect.objectContaining({ logoKey: appearance.logoKey }));
    const { text } = await request(app).get('/p/shop').expect(200);
    for (const slot of ['logo', 'cover', 'background']) expect(text).toContain(`/p/shop/images/${slot}`);
    expect(text).not.toContain('profiles/owner/');
  });

  it('darkens a background image with black opacity while keeping the selected fallback color', async () => {
    const { app } = fixture({ validateImages: async () => {} });
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance: {
      background: { mode: 'image', color: '#e6f1ff', imageKey: 'profiles/owner/background.png', overlay: 80 }
    } }).expect(200);
    const { text } = await request(app).get('/p/shop').expect(200);
    expect(text).toContain('background-color:#e6f1ff');
    expect(text).toContain('linear-gradient(rgba(0,0,0,0.8),rgba(0,0,0,0.8)),url("/p/shop/images/background")');
    expect(text).not.toContain('rgba(230,241,255,0.8)');
  });

  it('uses the selected solid fallback color when an image background has no image key', async () => {
    const { app } = fixture();
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance: {
      background: { mode: 'image', color: '#e6f1ff', imageKey: null, overlay: 80 }
    } }).expect(200);
    const { text } = await request(app).get('/p/shop').expect(200);
    expect(text).toContain('body{margin:0;background:#e6f1ff;font-family:');
    expect(text).not.toContain('background-image:');
  });

  it('keeps the previous page when image validation fails', async () => {
    const validateImages = vi.fn(async (_owner: string, appearance: ReturnType<typeof createDefaultLinkInBioAppearance>) => {
      if (appearance.logoKey) throw new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'invalid image');
    });
    const { app, store } = fixture({ validateImages });
    await request(app).post('/link-in-bio/publish').send(page).expect(200);
    await request(app).post('/link-in-bio/publish').send({ ...page, storeName: 'changed', appearance: { logoKey: 'profiles/other/logo.png' } }).expect(400);
    expect((await store.getForUser('owner'))!.storeName).toBe('ร้าน');
  });

  it('returns committed publication even if post-publication image cleanup fails', async () => {
    const onPublished = vi.fn(async () => { throw new Error('cleanup unavailable'); });
    const { app, store } = fixture({ onPublished });
    await request(app).post('/link-in-bio/publish').send(page).expect(200);
    expect(onPublished).toHaveBeenCalledWith('owner', expect.objectContaining({ isPublished: true }));
    expect((await store.getForUser('owner'))!.isPublished).toBe(true);
  });

  it('keeps appearance loading, ownership validation and commit in one image mutation guard, then cleans up outside it', async () => {
    let locked = false;
    const events: string[] = [];
    const { app, store } = fixture({
      withImageMutation: async (userId, operation) => {
        expect(userId).toBe('owner');
        locked = true;
        events.push('lock');
        try { return await operation(); } finally { locked = false; events.push('unlock'); }
      },
      validateImages: async () => { expect(locked).toBe(true); events.push('validate'); },
      onPublished: async () => { expect(locked).toBe(false); events.push('cleanup'); }
    });
    const getForUser = store.getForUser;
    store.getForUser = async (owner) => { expect(locked).toBe(true); events.push('load'); return getForUser(owner); };
    const publish = store.publish;
    store.publish = async (input) => { expect(locked).toBe(true); events.push('commit'); return publish(input); };
    await request(app).post('/link-in-bio/publish').send(page).expect(200);
    expect(events).toEqual(['lock', 'load', 'validate', 'commit', 'unlock', 'cleanup']);
  });

  it('does not write or clean up when the image mutation guard cannot be acquired', async () => {
    const validateImages = vi.fn(async () => {});
    const onPublished = vi.fn(async () => {});
    const { app, store } = fixture({
      withImageMutation: async () => { throw new LinkInBioError(503, 'LINK_IN_BIO_IMAGES_UNAVAILABLE', 'guard unavailable'); },
      validateImages, onPublished
    });
    await request(app).post('/link-in-bio/publish').send(page).expect(503);
    expect(await store.getForUser('owner')).toBeNull();
    expect(validateImages).not.toHaveBeenCalled();
    expect(onPublished).not.toHaveBeenCalled();
  });
});
