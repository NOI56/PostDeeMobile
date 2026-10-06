import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { linkInBioIcons } from './linkInBioAppearance.js';
import { resolveLinkInBioIcon } from './linkInBioDestinations.js';
import { getLinkInBioPlatformLogoGeometry, linkInBioPlatformLogoFiles, linkInBioPlatformLogoMetrics } from './linkInBioPlatformLogos.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import type { LinkInBioProfile } from './linkInBioStore.js';

const page = (url: string): LinkInBioProfile => ({
  storeName: 'ร้าน', slug: 'global-shop', links: [{ id: 'global', title: 'ชื่อที่เจ้าของร้านตั้งเอง', url }],
  isPublished: true, publishedAt: '2026-10-07T01:00:00Z', updatedAt: '2026-10-07T01:00:00Z', publicPath: '/p/global-shop'
});

describe('worldwide profile platform catalog', () => {
  it.each([
    ['website', 'https://google.com/%6daps'],
    ['website', 'https://google.com/maps%2Fplace'],
    ['website', 'https://google.com/mapshop'],
    ['website', 'https://google.com/search?q=/maps/place'],
    ['website', 'https://docs.google.com/maps/place'],
    ['website', 'https://sub.goo.gl/maps/place'],
    ['google_maps', 'https://google.com/maps/place'],
    ['messenger', 'https://www.facebook.com/messages/t/shop'],
    ['facebook', 'https://www.facebook.com/messageshop'],
    ['facebook', 'https://www.facebook.com/%6dessages/t/shop']
  ])('uses exact host and escaped path segment boundaries for %s at %s', (icon, url) => {
    expect(resolveLinkInBioIcon({ id: 'boundary', title: 'ไปที่ร้าน', url })).toBe(icon);
  });

  it.each([
    ['reddit', 'https://www.reddit.com/user/shop'],
    ['discord', 'https://discord.gg/shop'],
    ['spotify', 'https://open.spotify.com/artist/shop'],
    ['telegram', 'https://t.me/shop'],
    ['pinterest', 'https://www.pinterest.com/shop']
  ])('automatically recognizes the %s destination without changing a custom title', (id, url) => {
    expect(resolveLinkInBioIcon({ id: 'global', title: 'ชื่อเดิม', url })).toBe(id);
    const html = renderLinkInBioPage(page(url), 'catalog-test-nonce');
    expect(html).toContain(`data-icon="${id}"`);
    expect(html).toContain('ชื่อที่เจ้าของร้านตั้งเอง');
    expect(html).toContain(`src="/profile-platforms/${id}.png"`);
  });

  it('has exactly 100 brands, with the original brand IDs and five generic choices intact', async () => {
    const { profilePlatformCatalog, profilePlatformIds } = await import('./profilePlatformCatalog.generated.js');
    expect(profilePlatformCatalog).toHaveLength(100);
    expect(new Set(profilePlatformIds).size).toBe(100);
    expect(profilePlatformIds).toEqual(expect.arrayContaining([
      'youtube', 'shopee', 'lazada', 'line', 'tiktok', 'instagram', 'facebook', 'messenger', 'whatsapp', 'google_maps'
    ]));
    expect(new Set(linkInBioIcons).size).toBe(105);
    expect(linkInBioIcons).toEqual(expect.arrayContaining(['auto', 'link', 'website', 'email', 'phone', ...profilePlatformIds]));
    expect(Object.keys(linkInBioPlatformLogoFiles)).toHaveLength(100);
  });

  it('keeps the generated API definitions aligned with the shared source catalog', async () => {
    const { profilePlatformCatalog } = await import('./profilePlatformCatalog.generated.js');
    const manifest = JSON.parse(await readFile(new URL('../../../../../shared/profile-platforms.json', import.meta.url), 'utf8'));
    expect(manifest.version).toBe(1);
    expect(manifest.platforms).toHaveLength(100);
    for (const source of manifest.platforms) {
      const platform = profilePlatformCatalog.find((entry) => entry.id === source.id);
      expect(platform, source.id).toBeDefined();
      const asset = Object.fromEntries(['file', 'sourceWidth', 'sourceHeight', 'left', 'top', 'width', 'height']
        .map((field) => [field, source.asset[field]]));
      expect(platform).toEqual({
        id: source.id, name: source.name, category: source.category,
        aliases: source.aliases, regions: source.regions, domains: source.domains,
        matches: source.matches, sampleUrl: source.sampleUrl, asset
      });
    }
  });

  it('recognizes every independent sample URL, preserves manual overrides, and rejects misleading hosts', async () => {
    const { profilePlatformCatalog } = await import('./profilePlatformCatalog.generated.js');
    for (const platform of profilePlatformCatalog) {
      const link = { id: 'global', title: platform.name, url: platform.sampleUrl };
      expect(resolveLinkInBioIcon(link), platform.id).toBe(platform.id);
      expect(resolveLinkInBioIcon({ ...link, icon: 'link' }), platform.id).toBe('link');
      expect(resolveLinkInBioIcon({ ...link, url: 'https://example.invalid/', icon: platform.id }), platform.id).toBe(platform.id);
      const host = new URL(platform.sampleUrl).hostname;
      expect(resolveLinkInBioIcon({ ...link, url: `https://${host}.attacker.invalid/profile` }), platform.id).toBe('website');
      expect(resolveLinkInBioIcon({ ...link, url: `https://example.invalid/?url=${platform.sampleUrl}` }), platform.id).toBe('website');
    }
  });

  it('serves all 100 original images with matching source hashes, dimensions and mobile bytes', async () => {
    const manifest = JSON.parse(await readFile(new URL('../../../../../shared/profile-platforms.json', import.meta.url), 'utf8'));
    const app = createApp();
    for (const platform of manifest.platforms) {
      const response = await request(app).get(`/profile-platforms/${platform.asset.file}`).expect(200).expect('Content-Type', /image\/png/);
      expect(response.headers['cache-control'], platform.id).toBe('public, max-age=86400');
      expect(response.headers['x-content-type-options'], platform.id).toBe('nosniff');
      expect(response.body.subarray(0, 8), platform.id).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      expect(response.body.readUInt32BE(16), platform.id).toBe(platform.asset.sourceWidth);
      expect(response.body.readUInt32BE(20), platform.id).toBe(platform.asset.sourceHeight);
      expect(createHash('sha256').update(response.body).digest('hex'), platform.id).toBe(platform.asset.sha256);
      const mobile = await readFile(new URL(`../../../../mobile/assets/images/platforms/${platform.asset.file}`, import.meta.url));
      expect(response.body, platform.id).toEqual(mobile);
      expect(linkInBioPlatformLogoMetrics[platform.id as keyof typeof linkInBioPlatformLogoMetrics], platform.id).toEqual({
        sourceWidth: platform.asset.sourceWidth, sourceHeight: platform.asset.sourceHeight,
        left: platform.asset.left, top: platform.asset.top, width: platform.asset.width, height: platform.asset.height
      });
      const geometry = getLinkInBioPlatformLogoGeometry(platform.id as keyof typeof linkInBioPlatformLogoFiles);
      const scale = geometry.width / platform.asset.sourceWidth;
      expect(Math.max(platform.asset.width * scale, platform.asset.height * scale), platform.id).toBeCloseTo(40, 5);
      expect(geometry.left + (platform.asset.left + platform.asset.width / 2) * scale, platform.id).toBeCloseTo(20, 5);
      expect(geometry.top + (platform.asset.top + platform.asset.height / 2) * scale, platform.id).toBeCloseTo(20, 5);
    }
  }, 15_000);

  it('allows each brand in publication without changing the owner scope or the 20-link page limit', async () => {
    const { profilePlatformCatalog } = await import('./profilePlatformCatalog.generated.js');
    const app = createApp();
    for (let offset = 0; offset < profilePlatformCatalog.length; offset += 20) {
      const links = profilePlatformCatalog.slice(offset, offset + 20).map((platform) => ({
        id: platform.id, title: platform.name, url: platform.sampleUrl, icon: platform.id
      }));
      const published = await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'global-owner')
        .send({ storeName: 'ร้านทั่วโลก', slug: 'global-shop', links }).expect(200);
      expect(published.body.profile.links).toEqual(links.map((link) => ({ ...link, url: new URL(link.url).href })));
      const owner = await request(app).get('/link-in-bio').set('x-postdee-user-id', 'global-owner').expect(200);
      expect(owner.body.profile.links).toEqual(published.body.profile.links);
      const other = await request(app).get('/link-in-bio').set('x-postdee-user-id', 'other-owner').expect(200);
      expect(other.body.profile).toBeNull();
    }
    const links = Array.from({ length: 21 }, (_, index) => ({ id: `link-${index}`, title: 'เว็บร้าน', url: 'https://example.invalid/' }));
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'global-owner')
      .send({ storeName: 'ร้านทั่วโลก', slug: 'global-shop', links }).expect(400);
    const publicPage = await request(app).get('/p/global-shop').expect(200);
    expect(publicPage.headers['content-security-policy']).toContain("img-src 'self';");
    expect(publicPage.headers['content-security-policy']).toContain("script-src 'none';");
  });
});
