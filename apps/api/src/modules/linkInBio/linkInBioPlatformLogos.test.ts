import express, { type RequestHandler } from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { renderLinkInBioPage } from './linkInBioRenderer.js';
import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore, type LinkInBioLink, type LinkInBioProfile } from './linkInBioStore.js';

const platforms = [
  ['youtube', 'https://youtu.be/clip'],
  ['shopee', 'https://shopee.co.th/shop'],
  ['lazada', 'https://s.lazada.co.th/shop'],
  ['line', 'https://lin.ee/shop'],
  ['tiktok', 'https://www.tiktok.com/@shop'],
  ['instagram', 'https://www.instagram.com/shop'],
  ['facebook', 'https://fb.me/shop']
] as const;
const profile = (links: LinkInBioLink[]): LinkInBioProfile => ({
  storeName: 'ร้าน', slug: 'shop', links, isPublished: true,
  publishedAt: '2026-10-06T10:00:00.000Z', updatedAt: '2026-10-06T10:00:00.000Z', publicPath: '/p/shop'
});
const fixture = () => {
  const app = express();
  const router = express.Router();
  const store = createInMemoryLinkInBioStore();
  const auth = vi.fn<RequestHandler>((_request, response) => { response.status(401).end(); });
  registerLinkInBioRoutes(router, auth, store);
  app.use(router);
  return { app, store, auth };
};

describe('public link platform logos', () => {
  it.each(platforms)('renders the bundled %s brand logo from a recognized URL', (platform, url) => {
    const html = renderLinkInBioPage(profile([{ id: 'link', title: 'ไปที่ร้าน', url }]), 'test-nonce');
    expect(html).toContain(`data-icon="${platform}"`);
    expect(html).toContain(`<img src="/profile-platforms/${platform}.png" width="40" height="40" alt="">`);
    expect(html).toContain(`href="${url}"`);
    expect(html).toContain('<span>ไปที่ร้าน</span>');
  });

  it('retains explicit platform selection and generic link selection', () => {
    const html = renderLinkInBioPage(profile([
      { id: 'manual', title: 'เลือกร้าน', url: 'https://example.com/shop', icon: 'shopee' },
      { id: 'generic', title: 'ลิงก์ปกติ', url: 'https://youtube.com/watch?v=clip', icon: 'link' }
    ]), 'test-nonce');
    expect(html).toContain('data-icon="shopee"');
    expect(html).toContain('src="/profile-platforms/shopee.png"');
    expect(html).toContain('data-icon="link" aria-hidden="true">↗</span>');
    expect(html).not.toContain('src="/profile-platforms/youtube.png"');
  });

  it.each([
    'https://youtube.com.attacker.invalid/shop',
    'https://notshopee.co.th/shop',
    'https://example.com/?url=https://line.me/shop',
    'https://example.com/shop',
    'not a URL'
  ])('uses the generic fallback without fetching a logo for %s', (url) => {
    const html = renderLinkInBioPage(profile([{ id: 'link', title: 'ร้าน', url }]), 'test-nonce');
    expect(html).toContain('data-icon="link" aria-hidden="true">↗</span>');
    expect(html).not.toContain('<img');
  });

  it('keeps escaped link text, URL attributes and custom button colors with brand artwork', () => {
    const html = renderLinkInBioPage(profile([{
      id: 'link', title: '<img src=x onerror=alert(1)>', url: 'https://youtube.com/watch?v=clip&list=shop',
      buttonColor: '#123456', textColor: '#abcdef'
    }]), 'test-nonce');
    expect(html).toContain('href="https://youtube.com/watch?v=clip&amp;list=shop"');
    expect(html).toContain('&lt;img src=x onerror=alert(1)&gt;');
    expect(html).not.toContain('<img src=x');
    expect(html).toContain('.link-0{color:#abcdef;background:#123456;');
    expect(html).toContain('rel="noopener noreferrer"');
    expect(html).toContain('platform-icon brand-logo');
  });

  it.each(platforms)('serves the bundled %s PNG publicly without involving owner authentication', async (platform) => {
    const { app, auth } = fixture();
    const result = await request(app).get(`/profile-platforms/${platform}.png`).expect(200).expect('Content-Type', /image\/png/);
    expect(Buffer.isBuffer(result.body)).toBe(true);
    expect(result.body.subarray(0, 8)).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    expect(result.headers['cache-control']).toBe('public, max-age=86400');
    expect(result.headers['x-content-type-options']).toBe('nosniff');
    expect(auth).not.toHaveBeenCalled();
  });

  it.each(['unknown.png', 'youtube.svg', 'YOUTUBE.png', 'LICENSES.md', '..%2Fprofile-fonts%2Fprompt-regular.ttf'])('refuses unlisted asset paths: %s', async (file) => {
    const { app } = fixture();
    await request(app).get(`/profile-platforms/${file}`).expect(404);
  });

  it('uses same-origin logos without broadening the published page CSP', async () => {
    const { app, store } = fixture();
    await store.publish({ userId: 'owner', storeName: 'ร้าน', slug: 'shop', links: [{ id: 'link', title: 'YouTube', url: 'https://youtu.be/clip' }] });
    const result = await request(app).get('/p/shop').expect(200);
    expect(result.text).toContain('src="/profile-platforms/youtube.png"');
    expect(result.headers['content-security-policy']).toContain("img-src 'self';");
    expect(result.headers['content-security-policy']).toContain("script-src 'none';");
    expect(result.headers['content-security-policy']).not.toContain('data:');
    expect(result.headers['cache-control']).toBe('no-store');
  });
});
