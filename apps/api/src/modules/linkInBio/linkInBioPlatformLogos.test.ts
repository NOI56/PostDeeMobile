import { readFile } from 'node:fs/promises';
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
  ['facebook', 'https://fb.me/shop'],
  ['messenger', 'https://m.me/shop'],
  ['whatsapp', 'https://wa.me/66812345678'],
  ['google_maps', 'https://maps.app.goo.gl/shop']
] as const;
// Independently audited source canvas and nontransparent content bounds.
const contentMetrics = {
  youtube: { sourceWidth: 1255, sourceHeight: 1075, left: 214, top: 248, width: 827, height: 579 },
  shopee: { sourceWidth: 96, sourceHeight: 96, left: 5, top: 0, width: 86, height: 96 },
  lazada: { sourceWidth: 128, sourceHeight: 128, left: 0, top: 0, width: 128, height: 128 },
  line: { sourceWidth: 1001, sourceHeight: 1000, left: 0, top: 0, width: 1001, height: 1000 },
  tiktok: { sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  instagram: { sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  facebook: { sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  messenger: { sourceWidth: 128, sourceHeight: 128, left: 5, top: 7, width: 117, height: 116 },
  whatsapp: { sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  google_maps: { sourceWidth: 192, sourceHeight: 192, left: 27, top: 8, width: 138, height: 176 }
} as const;
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
    const logoPath = `/profile-platforms/${platform}.png${platform === 'youtube' ? '?v=2' : ''}`;
    expect(html).toContain(`<img src="${logoPath}" width="40" height="40" alt="">`);
    expect(html).toContain(`href="${url}"`);
    expect(html).toContain('<span>ไปที่ร้าน</span>');
  });

  it.each(platforms)('renders %s artwork with a centered 40px visible extent without stretching or clipping', (platform, url) => {
    const html = renderLinkInBioPage(profile([{ id: 'link', title: platform, url }]), 'test-nonce');
    const style = html.match(new RegExp(`\\.platform-icon\\[data-icon="${platform}"\\] img\\{([^}]*)\\}`))?.[1];
    expect(style).toBeDefined();
    const declarations = Object.fromEntries(style!.split(';').filter(Boolean).map((part) => part.split(':')));
    const width = Number.parseFloat(declarations.width);
    const height = Number.parseFloat(declarations.height);
    const left = Number.parseFloat(declarations.left);
    const top = Number.parseFloat(declarations.top);
    const source = contentMetrics[platform];
    const scale = width / source.sourceWidth;
    const visibleWidth = source.width * scale;
    const visibleHeight = source.height * scale;
    const visibleLeft = left + source.left * scale;
    const visibleTop = top + source.top * scale;
    expect(width / height).toBeCloseTo(source.sourceWidth / source.sourceHeight, 5);
    expect(Math.max(visibleWidth, visibleHeight)).toBeCloseTo(40, 5);
    expect(visibleLeft + visibleWidth / 2).toBeCloseTo(20, 5);
    expect(visibleTop + visibleHeight / 2).toBeCloseTo(20, 5);
    expect(visibleLeft).toBeGreaterThanOrEqual(-0.00001);
    expect(visibleTop).toBeGreaterThanOrEqual(-0.00001);
    expect(visibleLeft + visibleWidth).toBeLessThanOrEqual(40.00001);
    expect(visibleTop + visibleHeight).toBeLessThanOrEqual(40.00001);
    expect(html).toContain('.platform-icon.brand-logo{background:transparent;position:relative;overflow:hidden;border-radius:0}');
    expect(html).toContain('.platform-icon img{position:absolute;');
    expect(html).toContain('object-fit:contain');
  });

  it('leaves brand artwork transparent over custom buttons while retaining the generic-link background', () => {
    const html = renderLinkInBioPage(profile([
      { id: 'brand', title: 'YouTube', url: 'https://youtu.be/clip', buttonColor: '#2c5734' },
      { id: 'generic', title: 'เว็บอื่น', url: 'https://example.com/shop', buttonColor: '#2c5734' }
    ]), 'test-nonce');
    const brandStyle = html.match(/\.platform-icon\.brand-logo\{([^}]*)\}/)?.[1];
    const genericStyle = html.match(/\.platform-icon\{([^}]*)\}/)?.[1];
    expect(brandStyle).toContain('background:transparent');
    expect(brandStyle).not.toMatch(/background(?:-color)?:#fff/);
    expect(genericStyle).toContain('background:rgba(255,255,255,.14)');
    expect(html).toContain('.link-0{color:#ffffff;background:#2c5734;');
    expect(html).toContain('data-icon="website" aria-hidden="true"><svg');
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
    'https://example.com/shop'
  ])('uses the website fallback without fetching a logo for %s', (url) => {
    const html = renderLinkInBioPage(profile([{ id: 'link', title: 'ร้าน', url }]), 'test-nonce');
    expect(html).toContain('data-icon="website" aria-hidden="true"><svg');
    expect(html).not.toContain('<img');
  });

  it('keeps the generic fallback for invalid destinations', () => {
    const html = renderLinkInBioPage(profile([{ id: 'link', title: 'ร้าน', url: 'not a URL' }]), 'test-nonce');
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

  it.each(platforms)('keeps %s artwork dimensions and source bytes identical to the mobile asset', async (platform) => {
    const { app } = fixture();
    const result = await request(app).get(`/profile-platforms/${platform}.png`).expect(200);
    const mobile = await readFile(new URL(`../../../../mobile/assets/images/platforms/${platform}.png`, import.meta.url));
    expect(result.body).toEqual(mobile);
    expect(result.body.readUInt32BE(16)).toBe(contentMetrics[platform].sourceWidth);
    expect(result.body.readUInt32BE(20)).toBe(contentMetrics[platform].sourceHeight);
  });

  it('keeps the legacy YouTube URL working alongside the revision used to bypass its old one-day cache', async () => {
    const { app } = fixture();
    const legacy = await request(app).get('/profile-platforms/youtube.png').expect(200);
    const revision = await request(app).get('/profile-platforms/youtube.png?v=2').expect(200);
    expect(revision.body).toEqual(legacy.body);
    expect(revision.headers['cache-control']).toBe('public, max-age=86400');
    const html = renderLinkInBioPage(profile([{ id: 'link', title: 'YouTube', url: 'https://youtu.be/clip' }]), 'test-nonce');
    expect(html).toContain('src="/profile-platforms/youtube.png?v=2"');
    expect(html).not.toContain('src="/profile-platforms/youtube.png"');
  });

  it.each(['unknown.png', 'youtube.svg', 'YOUTUBE.png', 'LICENSES.md', '..%2Fprofile-fonts%2Fprompt-regular.ttf'])('refuses unlisted asset paths: %s', async (file) => {
    const { app } = fixture();
    await request(app).get(`/profile-platforms/${file}`).expect(404);
  });

  it('uses same-origin logos without broadening the published page CSP', async () => {
    const { app, store } = fixture();
    await store.publish({ userId: 'owner', storeName: 'ร้าน', slug: 'shop', links: [{ id: 'link', title: 'YouTube', url: 'https://youtu.be/clip' }] });
    const result = await request(app).get('/p/shop').expect(200);
    expect(result.text).toContain('src="/profile-platforms/youtube.png?v=2"');
    expect(result.headers['content-security-policy']).toContain("img-src 'self';");
    expect(result.headers['content-security-policy']).toContain("script-src 'none';");
    expect(result.headers['content-security-policy']).not.toContain('data:');
    expect(result.headers['cache-control']).toBe('no-store');
  });
});
