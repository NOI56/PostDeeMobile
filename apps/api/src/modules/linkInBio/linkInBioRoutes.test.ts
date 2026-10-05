import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';
import { createLinkInBioStoreFromConfig } from './linkInBioStoreFactory.js';
import { createDefaultLinkInBioAppearance } from './linkInBioAppearance.js';

const page = {
  storeName: 'ร้านของดี',
  slug: 'my-shop',
  links: [{ id: 'shop', title: 'เลือกซื้อสินค้า', url: 'https://example.com/shop' }]
};
const publish = (app: ReturnType<typeof createApp>, userId: string, body = page) =>
  request(app).post('/link-in-bio/publish').set('x-postdee-user-id', userId).send(body);

describe('link in bio routes', () => {
  it('requires authentication for the owner endpoints', async () => {
    const app = createApp({
      config: readServerConfig({ AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'test-project' }),
      firebaseVerifier: { verifyIdToken: async () => ({ id: 'owner', provider: 'firebase' }) }
    });
    await request(app).get('/link-in-bio').expect(401);
    await request(app).post('/link-in-bio/publish').send(page).expect(401);
    await request(app).delete('/link-in-bio/publish').expect(401);
  });

  it('starts empty, normalizes the slug, and returns a relative public path', async () => {
    const app = createApp({ now: () => new Date('2026-10-05T10:00:00Z') });
    await request(app).get('/link-in-bio').set('x-postdee-user-id', 'owner').expect(200, {
      status: 'ok', profile: null
    });
    const result = await publish(app, 'owner', { ...page, slug: '  MY-SHOP  ' })
      .set('Host', 'attacker.invalid').expect(200);
    expect(result.body.profile).toEqual({
      ...page,
      appearance: createDefaultLinkInBioAppearance(),
      isPublished: true,
      publishedAt: '2026-10-05T10:00:00.000Z',
      updatedAt: '2026-10-05T10:00:00.000Z',
      publicPath: '/p/my-shop'
    });
    const read = await request(app).get('/link-in-bio').set('x-postdee-user-id', 'owner');
    expect(read.body).toEqual(result.body);
  });

  it('does not read or overwrite another owner through body or query parameters', async () => {
    const app = createApp();
    await publish(app, 'owner-a').expect(200);
    await request(app).get('/link-in-bio?userId=owner-a').set('x-postdee-user-id', 'owner-b')
      .expect(200, { status: 'ok', profile: null });
    await publish(app, 'owner-b', { ...page, userId: 'owner-a' } as typeof page).expect(409);
    const owner = await request(app).get('/link-in-bio').set('x-postdee-user-id', 'owner-a');
    expect(owner.body.profile.storeName).toBe(page.storeName);
  });

  it('publishes responsive Thai HTML without requiring the viewer to log in', async () => {
    const app = createApp();
    await publish(app, 'owner').expect(200);
    const result = await request(app).get('/p/my-shop').expect(200).expect('Content-Type', /html/);
    expect(result.text).toContain('lang="th"');
    expect(result.text).toContain('name="viewport"');
    expect(result.text).toContain('ร้านของดี');
    expect(result.text).toContain('href="https://example.com/shop"');
    expect(result.headers['content-security-policy']).toContain("script-src 'none'");
    const nonce = result.text.match(/<style nonce="([^"]+)"/)?.[1];
    expect(nonce).toBeTruthy();
    expect(result.headers['content-security-policy']).toContain(`'nonce-${nonce}'`);
    expect(result.headers['cache-control']).toBe('no-store');
  });

  it('escapes stored names, titles, and URL attributes in the public page', async () => {
    const app = createApp();
    await publish(app, 'owner', {
      ...page,
      storeName: '<script>alert("x")</script>',
      links: [{ id: 'link', title: '<img src=x onerror=alert(1)>', url: 'https://example.com/?a=1&b=2' }]
    }).expect(200);
    const { text } = await request(app).get('/p/my-shop').expect(200);
    expect(text).not.toContain('<script>');
    expect(text).not.toContain('<img');
    expect(text).toContain('&lt;script&gt;');
    expect(text).toContain('&lt;img');
    expect(text).toContain('?a=1&amp;b=2');
    expect(text).toContain('rel="noopener noreferrer"');
  });

  it('unpublishes only the current owner and reserves their slug', async () => {
    const app = createApp();
    await publish(app, 'owner-a').expect(200);
    await publish(app, 'owner-b', { ...page, slug: 'other-shop' }).expect(200);
    const result = await request(app).delete('/link-in-bio/publish?userId=owner-b')
      .set('x-postdee-user-id', 'owner-a').expect(200);
    expect(result.body.profile).toMatchObject({ slug: 'my-shop', isPublished: false, publicPath: null });
    await request(app).get('/p/my-shop').expect(404);
    await request(app).get('/p/other-shop').expect(200);
    await publish(app, 'owner-b').expect(409).expect(({ body }) => {
      expect(body.code).toBe('LINK_IN_BIO_SLUG_TAKEN');
    });
    await publish(app, 'owner-a').expect(200);
    await request(app).get('/p/my-shop').expect(200);
  });

  it('does not create a page when unpublishing an empty account', async () => {
    const app = createApp();
    await request(app).delete('/link-in-bio/publish').set('x-postdee-user-id', 'owner')
      .expect(200, { status: 'ok', profile: null });
    await request(app).get('/p/missing').expect(404);
  });

  it('allows the owner to change their slug and releases the previous one', async () => {
    const app = createApp();
    await publish(app, 'owner-a').expect(200);
    await publish(app, 'owner-a', { ...page, slug: 'new-shop' }).expect(200);
    await request(app).get('/p/my-shop').expect(404);
    await publish(app, 'owner-b').expect(200);
  });

  it('lets only one owner claim the same slug concurrently', async () => {
    const app = createApp();
    const results = await Promise.all([publish(app, 'owner-a'), publish(app, 'owner-b')]);
    expect(results.map(({ status }) => status).sort()).toEqual([200, 409]);
    expect(results.find(({ status }) => status === 409)?.body.code).toBe('LINK_IN_BIO_SLUG_TAKEN');
  });

  it('removes the public page and frees the slug when the owner deletes their account', async () => {
    const app = createApp();
    await publish(app, 'owner-a').expect(200);
    await request(app).delete('/account').set('x-postdee-user-id', 'owner-a').expect(200);
    await request(app).get('/p/my-shop').expect(404);
    await request(app).get('/link-in-bio').set('x-postdee-user-id', 'owner-a')
      .expect(200, { status: 'ok', profile: null });
    await publish(app, 'owner-a').expect(409);
    await publish(app, 'owner-b').expect(200);
  });

  it('waits for an in-flight publish before account deletion and prevents later publication', async () => {
    const store = createInMemoryLinkInBioStore();
    let signalStarted!: () => void;
    let releasePublish!: () => void;
    const started = new Promise<void>((resolve) => { signalStarted = resolve; });
    const gate = new Promise<void>((resolve) => { releasePublish = resolve; });
    const app = createApp({
      linkInBioStore: {
        ...store,
        publish: async (input) => {
          signalStarted();
          await gate;
          return store.publish(input);
        }
      }
    });
    const publishing = publish(app, 'owner').then((response) => response.status);
    await started;
    let deletionCompleted = false;
    const deleting = request(app).delete('/account').set('x-postdee-user-id', 'owner')
      .then((response) => { deletionCompleted = true; return response.status; });
    await new Promise<void>((resolve) => setImmediate(resolve));
    expect(deletionCompleted).toBe(false);
    releasePublish();
    expect(await publishing).toBe(200);
    expect(await deleting).toBe(200);
    await request(app).get('/p/my-shop').expect(404);
    await publish(app, 'owner').expect(409);
  });

  it('reports storage unavailability instead of treating it as an absent page', async () => {
    const app = createApp({
      linkInBioStore: createLinkInBioStoreFromConfig({ config: { postStore: 'prisma' } })
    });
    for (const path of ['/p/my-shop', '/link-in-bio']) {
      const result = await request(app).get(path).set('x-postdee-user-id', 'owner').expect(503);
      expect(result.body.code).toBe('LINK_IN_BIO_UNAVAILABLE');
      expect(result.headers['cache-control']).toBe('no-store');
    }
  });

  it.each([
    'javascript:alert(1)', 'data:text/html,<script>x</script>', 'ftp://example.com/a',
    '//example.com/a', 'https:example.com', 'https://user:password@example.com',
    'https://user@example.com', 'https://example.com/a\n', 'https://example.com/has space',
    'https://', 'https://example.com/' + 'a'.repeat(2048)
  ])('rejects unsafe or invalid URL %s', async (url) => {
    const app = createApp();
    await publish(app, 'owner', { ...page, links: [{ ...page.links[0]!, url }] }).expect(400);
    await request(app).get('/p/my-shop').expect(404);
  });

  it.each([
    { storeName: '' }, { storeName: 'a'.repeat(81) }, { slug: 'ab' }, { slug: '-my-shop' },
    { slug: 'my-shop-' }, { slug: 'my--shop' }, { slug: 'ร้านค้า' }, { slug: 'a'.repeat(41) }, { links: [] },
    { links: Array.from({ length: 21 }, (_, i) => ({ ...page.links[0]!, id: `link-${i}` })) },
    { links: [page.links[0], page.links[0]] },
    { links: [{ ...page.links[0]!, id: '' }] }, { links: [{ ...page.links[0]!, id: 'a'.repeat(81) }] },
    { links: [{ ...page.links[0]!, title: '' }] }, { links: [{ ...page.links[0]!, title: 'a'.repeat(81) }] }
  ])('rejects invalid input %# without overwriting an existing page', async (invalid) => {
    const app = createApp();
    await publish(app, 'owner').expect(200);
    await publish(app, 'owner', { ...page, ...invalid } as typeof page).expect(400)
      .expect('Cache-Control', 'no-store');
    const result = await request(app).get('/link-in-bio').set('x-postdee-user-id', 'owner');
    expect(result.body.profile).toMatchObject(page);
  });
});
