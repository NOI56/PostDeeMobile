import { describe, expect, it } from 'vitest';
import { readLinkInBioAppearance } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';

const links = [
  { id: 'shop', title: 'ซื้อสินค้าที่ Shopee', url: 'https://shopee.co.th/shop', category: 'ช่องทางร้าน' },
  { id: 'chat', title: 'ทักแชท LINE', url: 'https://line.me/R/shop' }
];
const effects = { background: true, entrance: true, featured: true, stickers: 'flowers' };

describe('profile themes and optional motion', () => {
  it.each(['pink', 'garden', 'cards'])('accepts and persists the %s theme without replacing profile content', async (themeId) => {
    const appearance = readLinkInBioAppearance({ themeId, description: 'ร้านเดิม', effects, featuredLinkId: 'shop' }, links);
    expect(appearance).toMatchObject({ themeId, description: 'ร้านเดิม', effects });
    const store = createInMemoryLinkInBioStore();
    await store.publish({ userId: 'owner', storeName: 'ร้านของคุณ', slug: 'new-theme', links, appearance });
    const profile = (await store.getPublishedBySlug('new-theme'))!;
    expect(profile.appearance).toMatchObject({ themeId, effects });
    expect(profile.links).toEqual(links);
    const html = renderLinkInBioPage(profile, 'safe-nonce');
    expect(html).toContain(`data-theme="${themeId}"`);
    expect(html).toContain('prefers-reduced-motion');
    expect(html).not.toContain('หยุดการเคลื่อนไหว');
    expect(html).not.toContain('pause-motion');
    expect(html).toContain('aria-hidden="true"');
    expect(html).toContain('animation:none!important');
    expect(html).not.toMatch(/<script\b/i);
    expect(html).toContain('href="https://shopee.co.th/shop" target="_blank" rel="noopener noreferrer"');
    expect(html).toContain('/profile-platforms/shopee.png');
    if (themeId === 'cards') expect(html).toContain('เปิดลิงก์');
  });

  it('keeps legacy profiles static and motion control absent when every effect is off', () => {
    const appearance = readLinkInBioAppearance({ themeId: 'minimal' }, links)!;
    expect(appearance).toMatchObject({ effects: { background: false, entrance: false, featured: false, stickers: 'none' } });
    const html = renderLinkInBioPage({ storeName: 'ร้าน', slug: 'legacy', links, appearance,
      isPublished: true, publishedAt: null, updatedAt: '', publicPath: '/p/legacy' }, 'nonce');
    expect(html).not.toContain('id="pause-motion"');
    expect(html).not.toContain('class="decorations');
  });

  it.each(['minimal', 'shop', 'pastel', 'dark', 'pink', 'garden', 'cards'])('removes the public pause control from %s while retaining selected effects and reduced motion', (themeId) => {
    const appearance = readLinkInBioAppearance({ themeId, effects }, links)!;
    const html = renderLinkInBioPage({ storeName: 'ร้าน', slug: 'motion', links, appearance,
      isPublished: true, publishedAt: null, updatedAt: '', publicPath: '/p/motion' }, 'nonce');
    expect(html).not.toMatch(/pause-motion|motion-control|when-paused|หยุดการเคลื่อนไหว|เล่นการเคลื่อนไหว/);
    expect(html).toContain('class="background-motion"');
    expect(html).toContain('data-stickers="flowers"');
    expect(html).toContain('motion-featured');
    expect(html).toContain('@media(prefers-reduced-motion:reduce)');
    expect(html).toContain('animation:none!important');
  });

  it.each([
    null, [], 'animate', { background: 'true' }, { entrance: 1 },
    { featured: null }, { stickers: 'flowers;display:none' }, { stickers: 'snow' }
  ])('rejects malformed effect settings %#', (value) => {
    expect(readLinkInBioAppearance({ effects: value }, links)).toBeUndefined();
  });

  it('normalizes partial effect settings without sharing defaults', () => {
    const first = readLinkInBioAppearance({ effects: { stickers: 'hearts' } }, links)!;
    expect(first).toMatchObject({ effects: { background: false, entrance: false, featured: false, stickers: 'hearts' } });
    const second = readLinkInBioAppearance({ effects: { stickers: 'sparkles' } }, links)!;
    expect(second).toMatchObject({ effects: { stickers: 'sparkles' } });
    expect(first).toMatchObject({ effects: { stickers: 'hearts' } });
  });
});
