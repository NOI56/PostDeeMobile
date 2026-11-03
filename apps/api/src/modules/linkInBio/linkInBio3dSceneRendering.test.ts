import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import type { LinkInBioProfile } from './linkInBioStore.js';
import { getProfileTemplate } from './profileTemplateCatalog.generated.js';

// The second 3D release: each scene uses one of five new page layouts.
const scenes = {
  'dimensional-chrome-night': 'showcase', 'dimensional-lowpoly-dawn': 'showcase', 'dimensional-zen-garden': 'showcase',
  'dimensional-wood-blocks': 'split-art', 'dimensional-parcel-stack': 'split-art',
  'dimensional-ceramic-tiles': 'tile-grid', 'dimensional-pop-shapes': 'tile-grid',
  'dimensional-neon-sign': 'neon',
  'dimensional-concrete-slab': 'slab', 'dimensional-terrazzo-steps': 'slab'
} as const;
const sceneIds = Object.keys(scenes) as (keyof typeof scenes)[];
const longName = 'ร้านเสื้อผ้ามือสองคุณภาพดีราคาเป็นกันเองส่งทั่วประเทศไทย';
const page = (templateId: string, linkCount = 2): LinkInBioProfile => ({
  storeName: longName, slug: 'scene-shop',
  links: Array.from({ length: linkCount }, (_, index) => ({ id: `link-${index}`, title: `ช่องทางที่ ${index + 1}`, url: `https://example.com/${index}` })),
  appearance: { ...createDefaultLinkInBioTemplateAppearance(templateId), description: 'ร้านจริงของเจ้าของ' },
  isPublished: true, publishedAt: null, updatedAt: '', publicPath: '/p/scene-shop'
});
const scoped = (html: string, suffix: string) => {
  const rules = [...html.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
    .filter((match) => match[1]!.includes('[data-template-category="dimensional"]') && match[1]!.trim().endsWith(suffix));
  return rules.map((match) => match[2]!).join(';');
};

describe('second-release 3D scene layouts', () => {
  it.each(sceneIds)('renders %s with its catalog layout, real content and artwork', (templateId) => {
    const html = renderLinkInBioPage(page(templateId), 'nonce');
    expect(getProfileTemplate(templateId)?.layout.composition).toBe(scenes[templateId]);
    expect(html).toContain(`data-composition="${scenes[templateId]}"`);
    expect(html).toContain(`class="profile-3d-art" src="/profile-decorations/${templateId}.png" alt="" aria-hidden="true"`);
    expect(html).toContain(`<h1>${longName}</h1>`);
    expect(html).toContain('ร้านจริงของเจ้าของ');
    expect(html).toContain('ช่องทางที่ 2');
    // Long Thai names and link titles wrap instead of overflowing small phones.
    expect(scoped(html, ' .profile-header h1')).toContain('overflow-wrap:anywhere');
    expect(scoped(html, ' .link-copy')).toContain('min-width:0');
    expect(html).toMatch(/@media\(max-width:400px\)\{body\[data-template\]\[data-template-category="dimensional"\]\[data-composition\]/);
    // Every scene gives its links a physical edge.
    expect(scoped(html, ' a')).toContain('box-shadow:');
    expect(html).not.toMatch(/<script\b/);
  });

  it('bleeds opaque showcase and neon artwork as a cropped banner', () => {
    for (const templateId of ['dimensional-chrome-night', 'dimensional-lowpoly-dawn', 'dimensional-zen-garden', 'dimensional-neon-sign']) {
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      expect(scoped(html, ' .profile-3d-art'), templateId).toContain('object-fit:cover');
      expect(scoped(html, ' .profile-3d-hero .logo'), templateId).toContain('position:absolute');
    }
    expect(scoped(renderLinkInBioPage(page('dimensional-chrome-night'), 'nonce'), ' .profile-copy')).toContain('text-align:left');
    expect(scoped(renderLinkInBioPage(page('dimensional-lowpoly-dawn'), 'nonce'), ' .profile-copy')).toContain('text-align:center');
  });

  it('places split, tile and slab art beside, above or below the owner text', () => {
    for (const templateId of ['dimensional-wood-blocks', 'dimensional-parcel-stack', 'dimensional-ceramic-tiles', 'dimensional-pop-shapes', 'dimensional-concrete-slab', 'dimensional-terrazzo-steps']) {
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      expect(scoped(html, ' .profile-3d-hero'), templateId).toContain('display:contents');
      expect(scoped(html, ' .profile-3d-art'), templateId).toContain('object-fit:contain');
    }
    expect(scoped(renderLinkInBioPage(page('dimensional-wood-blocks'), 'nonce'), ' .profile-header')).toContain('grid-template-columns:minmax(0,1fr) minmax(0,1.45fr)');
    expect(scoped(renderLinkInBioPage(page('dimensional-concrete-slab'), 'nonce'), ' .profile-3d-art')).toContain('order:2');
  });

  it('pairs tile-grid links and lets a lone last tile take the whole row', () => {
    const html = renderLinkInBioPage(page('dimensional-ceramic-tiles', 3), 'nonce');
    expect(scoped(html, ' ul')).toContain('grid-template-columns:repeat(2,minmax(0,1fr))');
    expect(scoped(html, ' .fill-row')).toContain('grid-column:1/-1');
    expect(html.match(/class="link-item[^"]*fill-row/g)).toHaveLength(1);
    expect(renderLinkInBioPage(page('dimensional-ceramic-tiles', 4), 'nonce')).not.toMatch(/class="link-item[^"]*fill-row/);
  });

  it('keeps outline scenes transparent only while their default text stays readable', () => {
    for (const templateId of ['dimensional-zen-garden', 'dimensional-neon-sign']) {
      const profile = page(templateId);
      const text = profile.appearance!.buttonStyle.color;
      expect(renderLinkInBioPage(profile, 'nonce'), templateId).toContain(`.link-0{color:${text};background:transparent;`);
      expect(scoped(renderLinkInBioPage(profile, 'nonce'), ' a'), templateId).toContain('border:');
    }
    const neon = page('dimensional-neon-sign');
    expect(scoped(renderLinkInBioPage(neon, 'nonce'), ' a')).toContain(`0 0 14px ${neon.appearance!.buttonColor}73`);
  });

  it('honors owner colors, cover and surface on the new scenes', () => {
    const profile = page('dimensional-parcel-stack');
    profile.appearance!.surfaceColor = '#123456';
    profile.appearance!.coverKey = 'profiles/owner/cover.png';
    profile.links[0] = { ...profile.links[0]!, buttonColor: '#654321', textColor: '#ffffff' };
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(scoped(html, ' main')).toContain('background:#123456');
    expect(html).toContain('class="cover profile-3d-cover" src="/p/scene-shop/images/cover"');
    expect(html).not.toContain('/profile-decorations/dimensional-parcel-stack.png');
    expect(scoped(html, ' .profile-3d-cover')).toContain('object-fit:cover');
    expect(html).toContain('.link-0{color:#ffffff;background:#654321;');
    expect(html).not.toContain('profiles/owner/');
  });

  it('leaves the first ten 3D designs on their original hero rules', () => {
    const html = renderLinkInBioPage(page('dimensional-clay-mint'), 'nonce');
    expect(scoped(html, ' .profile-3d-art')).toContain('position:absolute');
    expect(scoped(html, ' .profile-3d-hero')).not.toContain('display:contents');
  });
});
