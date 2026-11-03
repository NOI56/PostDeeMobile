import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import type { LinkInBioProfile } from './linkInBioStore.js';
import { getProfileTemplate, profileTemplates } from './profileTemplateCatalog.generated.js';

// The cartoon release: twenty original drawings on seven cartoon page layouts.
const designs = {
  'cartoon-doodle-shop': 'banner', 'cartoon-comic-panels': 'panels', 'cartoon-tag-buddy': 'beside',
  'cartoon-sticker-sheet': 'banner', 'cartoon-chalkboard': 'banner', 'cartoon-street-front': 'signboard',
  'cartoon-chat-bubbles': 'chat', 'cartoon-signposts': 'beside', 'cartoon-crayon-sky': 'banner',
  'cartoon-rocket-night': 'banner',
  'cartoon-puppet-stage': 'stage', 'cartoon-corkboard': 'pinboard', 'cartoon-treasure-map': 'banner',
  'cartoon-party-bunting': 'banner', 'cartoon-jigsaw': 'beside', 'cartoon-pixel-land': 'banner',
  'cartoon-rainy-day': 'beside', 'cartoon-hot-air-balloons': 'beside', 'cartoon-under-the-sea': 'stage',
  'cartoon-tiny-town': 'banner'
} as const;
const designIds = Object.keys(designs) as (keyof typeof designs)[];
const longName = 'ร้านเสื้อผ้ามือสองคุณภาพดีราคาเป็นกันเองส่งทั่วประเทศไทย';
const page = (templateId: string, linkCount = 4): LinkInBioProfile => ({
  storeName: longName, slug: 'cartoon-shop',
  links: Array.from({ length: linkCount }, (_, index) => ({ id: `link-${index}`, title: `ช่องทางที่ ${index + 1}`, url: `https://example.com/${index}` })),
  appearance: { ...createDefaultLinkInBioTemplateAppearance(templateId), description: 'ร้านจริงของเจ้าของ' },
  isPublished: true, publishedAt: null, updatedAt: '', publicPath: '/p/cartoon-shop'
});
const scope = '[data-template-category="cartoon"]';
// Declarations of every rule with a cartoon-scoped selector ending in suffix,
// including selectors grouped with a comma.
const scoped = (html: string, suffix: string) => [...html.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
  .filter((match) => match[1]!.split(',').some((selector) => selector.includes(scope) && selector.trim().endsWith(suffix)))
  .map((match) => match[2]!).join(';');
const fill = (html: string, index: number) => html.match(new RegExp(`\\.link-${index}\\{color:[^;]+;background:([^;]+);`))?.[1];

describe('cartoon storefront designs', () => {
  it('ships exactly the twenty approved cartoon designs', () => {
    expect(profileTemplates.filter((template) => template.category === 'cartoon').map((template) => template.id)).toEqual(designIds);
  });

  it.each(designIds)('renders %s with its catalog layout, real owner content and its own drawing', (templateId) => {
    const html = renderLinkInBioPage(page(templateId), 'nonce');
    expect(getProfileTemplate(templateId)?.layout.composition).toBe(designs[templateId]);
    expect(html).toContain(`data-template-category="cartoon"`);
    expect(html).toContain(`data-composition="${designs[templateId]}"`);
    expect(html).toContain(`<img class="profile-cartoon-art" src="/profile-decorations/${templateId}.png" alt="" aria-hidden="true">`);
    expect(html).toContain(`<h1>${longName}</h1>`);
    expect(html).toContain('ร้านจริงของเจ้าของ');
    expect(html).toContain('ช่องทางที่ 4');
    // Long Thai names and link titles wrap instead of overflowing small phones.
    expect(scoped(html, ' .profile-header h1')).toContain('overflow-wrap:anywhere');
    expect(scoped(html, ' .link-copy')).toContain('min-width:0');
    expect(html).toMatch(/@media\(max-width:400px\)\{body\[data-template\]\[data-template-category="cartoon"\]\[data-composition\]/);
    // Every design gives its links a drawn edge.
    expect(scoped(html, ' a')).toMatch(/border:|clip-path:|background-image:/);
    // The 3D hero is never used for cartoon pages.
    expect(html).not.toContain('profile-3d-');
    expect(html).not.toMatch(/<script\b/);
  });

  it('replaces the drawing with an uploaded cover and keeps owner colors', () => {
    for (const templateId of designIds) {
      const profile = page(templateId);
      profile.appearance!.surfaceColor = '#123456';
      profile.appearance!.coverKey = 'profiles/owner/cover.png';
      profile.links[0] = { ...profile.links[0]!, buttonColor: '#654321', textColor: '#ffffff' };
      const html = renderLinkInBioPage(profile, 'nonce');
      expect(html, templateId).toContain('class="cover profile-cartoon-cover" src="/p/cartoon-shop/images/cover"');
      expect(html, templateId).not.toContain(`/profile-decorations/${templateId}.png`);
      expect(scoped(html, ' .profile-cartoon-cover'), templateId).toContain('object-fit:cover');
      expect(scoped(html, ' main'), templateId).toContain('background:#123456');
      expect(fill(html, 0), templateId).toBe('#654321');
      expect(html, templateId).not.toContain('profiles/owner/');
    }
  });

  it('crops banner drawings full width with the avatar overlapping their edge', () => {
    for (const templateId of designIds.filter((id) => designs[id] === 'banner')) {
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      expect(scoped(html, ' .profile-cartoon-art'), templateId).toContain('object-fit:cover');
      expect(scoped(html, ' .profile-cartoon-hero'), templateId).toContain('width:calc(100% + 2 * var(--pd-cartoon-side))');
      expect(scoped(html, ' .profile-cartoon-hero .logo'), templateId).toContain('position:absolute');
    }
  });

  it('places beside drawings next to the avatar and keeps their transparent art whole', () => {
    for (const templateId of designIds.filter((id) => designs[id] === 'beside')) {
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      expect(scoped(html, ' .profile-header'), templateId).toContain('grid-template-columns:minmax(0,1fr) minmax(0,1.45fr)');
      expect(scoped(html, ' .profile-cartoon-art'), templateId).toContain('object-fit:contain');
    }
  });

  it('hangs the owner logo as the shop sign above the drawn shopfront', () => {
    const html = renderLinkInBioPage(page('cartoon-street-front'), 'nonce');
    expect(html).toMatch(/<span class="profile-cartoon-sign"><div class="logo avatar-initial"/);
    const sign = scoped(html, ' .profile-cartoon-sign');
    expect(sign).toContain('position:absolute');
    expect(sign).toContain('top:');
    expect(sign).toContain('border:3px solid');
    expect(scoped(html, ' .profile-cartoon-hero::before')).toContain('border-left:3px solid');
  });

  it('frames comic panels and puts the name in a caption box', () => {
    const html = renderLinkInBioPage(page('cartoon-comic-panels'), 'nonce');
    const template = getProfileTemplate('cartoon-comic-panels')!;
    expect(scoped(html, ' .profile-cartoon-art')).toContain(`border:3px solid ${template.palette.name}`);
    expect(scoped(html, ' .profile-copy')).toContain(`background:${template.palette.gradient}`);
    expect(scoped(html, ' .profile-copy')).toContain(`border:3px solid ${template.palette.name}`);
    expect(html).toMatch(/@media\(max-width:400px\)\{[^@]*\.profile-header\{grid-template-columns:64px minmax\(0,1fr\)/);
  });

  it('lays chat links out as alternating speech bubbles with tails', () => {
    const html = renderLinkInBioPage(page('cartoon-chat-bubbles'), 'nonce');
    expect(scoped(html, ' .link-item')).toContain('width:88%');
    expect(scoped(html, ' .link-item[data-rhythm="1"]')).toContain('justify-self:end');
    expect(scoped(html, ' a::after')).toContain('background:inherit');
    expect(scoped(html, ' .profile-copy::after')).toContain('background:inherit');
  });

  it('cuts signpost links into arrows and keeps keyboard focus visible outside the clip', () => {
    const html = renderLinkInBioPage(page('cartoon-signposts'), 'nonce');
    expect(scoped(html, ' a')).toContain('clip-path:polygon(');
    expect(scoped(html, ' .link-item:focus-within')).toContain('outline:3px solid');
    expect(scoped(html, ' .link-item')).toContain('filter:drop-shadow(');
  });

  it('draws chalk links as dashed outlines with readable chalk text', () => {
    const profile = page('cartoon-chalkboard');
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(fill(html, 0)).toBe('transparent');
    expect(scoped(html, ' a')).toContain('border:2px dashed var(--pd-link-button)');
    expect(scoped(html, ' main')).toContain('border:10px solid');
  });

  it('tilts stickers alternately as a still pose, not an animation', () => {
    const html = renderLinkInBioPage(page('cartoon-sticker-sheet'), 'nonce');
    expect(scoped(html, ' .link-item[data-rhythm="0"] a')).toContain('transform:rotate(-1deg)');
    expect(scoped(html, ' .link-item[data-rhythm="1"] a')).toContain('transform:rotate(1deg)');
    expect(scoped(html, ' a')).not.toMatch(/transition|animation/);
  });

  it('cycles comic, sticker and chat fills only while the default colors are kept', () => {
    for (const templateId of ['cartoon-comic-panels', 'cartoon-sticker-sheet', 'cartoon-chat-bubbles', 'cartoon-corkboard', 'cartoon-party-bunting', 'cartoon-jigsaw', 'cartoon-hot-air-balloons']) {
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      const fills = [0, 1, 2, 3].map((index) => fill(html, index));
      expect(new Set(fills).size, templateId).toBeGreaterThan(1);
      expect(fills[0], templateId).toBe(getProfileTemplate(templateId)!.palette.button);
      const custom = page(templateId);
      custom.appearance!.buttonColor = '#204060';
      custom.appearance!.buttonStyle = { ...custom.appearance!.buttonStyle, color: '#ffffff' };
      const customHtml = renderLinkInBioPage(custom, 'nonce');
      expect([0, 1, 2, 3].map((index) => fill(customHtml, index)), templateId).toEqual(Array(4).fill('#204060'));
    }
  });

  it('outlines crayon links in rotating crayon colors', () => {
    const html = renderLinkInBioPage(page('cartoon-crayon-sky'), 'nonce');
    const borders = [0, 1, 2, 3].map((rhythm) => scoped(html, ` .link-item[data-rhythm="${rhythm}"] a`));
    expect(new Set(borders).size).toBe(4);
    for (const border of borders) expect(border).toMatch(/border-color:#[0-9a-f]{6}/);
  });

  it('keeps cartoon artwork filenames on the fixed same-origin allowlist', () => {
    const html = renderLinkInBioPage(page('cartoon-rocket-night'), 'nonce');
    expect([...html.matchAll(/src="([^"]+)"/g)].map((match) => match[1]).filter((src) => src!.includes('decorations')))
      .toEqual(['/profile-decorations/cartoon-rocket-night.png']);
  });
});

describe('second cartoon set', () => {
  it('centers the avatar inside the stage and sea drawings', () => {
    for (const templateId of ['cartoon-puppet-stage', 'cartoon-under-the-sea']) {
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      const avatar = scoped(html, ' .profile-cartoon-hero .logo');
      expect(avatar, templateId).toContain('position:absolute');
      expect(avatar, templateId).toMatch(/top:calc\(50% - \d+px\)/);
      expect(avatar, templateId).toMatch(/left:calc\(50% - \d+px\)/);
      expect(scoped(html, ' .profile-cartoon-art'), templateId).toContain('object-fit:cover');
      expect(scoped(html, ' .profile-copy'), templateId).toContain('text-align:center');
    }
  });

  it('pins the owner logo to the corkboard as a photo', () => {
    const html = renderLinkInBioPage(page('cartoon-corkboard'), 'nonce');
    expect(html).toMatch(/<span class="profile-cartoon-photo"><div class="logo avatar-initial"/);
    const photo = scoped(html, ' .profile-cartoon-photo');
    expect(photo).toContain('position:absolute');
    expect(photo).toContain('background:#ffffff');
    expect(photo).toContain('transform:rotate(-3deg)');
    expect(scoped(html, ' .profile-cartoon-photo::before')).toContain('border-radius:50%');
    // The initial stays centred inside the photo.
    expect(scoped(html, ' .profile-cartoon-photo .logo')).not.toContain('display:block');
    // Each sticky-note link has its own push pin.
    expect(scoped(html, ' a::before')).toContain('border-radius:50%');
  });

  it('joins treasure-map links with a dotted trail', () => {
    const html = renderLinkInBioPage(page('cartoon-treasure-map'), 'nonce');
    expect(scoped(html, ' .link-item + .link-item::before')).toContain('dotted');
    expect(scoped(html, ' .link-item')).toContain('position:relative');
  });

  it('cuts bunting links into swallowtail flags and pixel links into stepped corners', () => {
    const bunting = renderLinkInBioPage(page('cartoon-party-bunting'), 'nonce');
    expect(scoped(bunting, ' a')).toContain('clip-path:polygon(0 0,100% 0,calc(100% - 16px) 50%,100% 100%,0 100%)');
    expect(scoped(bunting, ' .link-item:focus-within')).toContain('outline:3px solid');
    const pixel = renderLinkInBioPage(page('cartoon-pixel-land'), 'nonce');
    expect(scoped(pixel, ' a')).toMatch(/clip-path:polygon\(0 8px,4px 8px,4px 4px,8px 4px,8px 0/);
    expect(scoped(pixel, ' .link-item')).toMatch(/filter:drop-shadow\(3px 0 0 #[0-9a-f]{6}\)/);
    expect(scoped(pixel, ' .link-item:focus-within')).toContain('outline:3px solid');
  });

  it('gives jigsaw links a knob and a socket', () => {
    const html = renderLinkInBioPage(page('cartoon-jigsaw'), 'nonce');
    expect(scoped(html, ' a::after')).toContain('background:inherit');
    expect(scoped(html, ' a::after')).toContain('right:-11px');
    expect(scoped(html, ' a::before')).toContain('left:-11px');
    expect(scoped(html, ' a::before')).toContain(`background:${getProfileTemplate('cartoon-jigsaw')!.palette.surface}`);
  });

  it('adds raindrops, bubbles and road lines as small drawn details', () => {
    expect(scoped(renderLinkInBioPage(page('cartoon-rainy-day'), 'nonce'), ' a::after')).toContain('border-radius:0 50% 50% 50%');
    const sea = renderLinkInBioPage(page('cartoon-under-the-sea'), 'nonce');
    expect(scoped(sea, ' a::before')).toContain('border-radius:50%');
    expect(scoped(sea, ' a::after')).toContain('border-radius:50%');
    expect(scoped(renderLinkInBioPage(page('cartoon-tiny-town'), 'nonce'), ' a')).toContain('repeating-linear-gradient(90deg');
  });
});
