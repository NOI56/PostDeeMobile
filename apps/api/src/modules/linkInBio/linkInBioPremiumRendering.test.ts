import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
import { linkInBioColorContrast } from './linkInBioCompositionStyles.js';
import { linkInBioPremiumDesigns, linkInBioPremiumOrnament } from './linkInBioPremiumStyles.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import type { LinkInBioProfile } from './linkInBioStore.js';
import { getProfileTemplate, profileTemplates } from './profileTemplateCatalog.generated.js';

// The premium release: twenty original pictures on five page layouts.
const designs = {
  'premium-gold-leaf': 'crest', 'premium-white-marble': 'portal', 'premium-thai-gold': 'crest', 'premium-art-deco': 'cameo',
  'premium-emerald-facet': 'vitrine', 'premium-pearl-strand': 'portal', 'premium-velvet-wine': 'atelier', 'premium-champagne': 'cameo',
  'premium-guilloche': 'cameo', 'premium-rose-gold': 'vitrine', 'premium-midnight-stars': 'cameo', 'premium-black-onyx': 'atelier',
  'premium-silk-ribbon': 'portal', 'premium-crystal': 'vitrine', 'premium-damask': 'crest', 'premium-golden-palms': 'atelier',
  'premium-spotlight': 'cameo', 'premium-colonnade': 'portal', 'premium-leather-stitch': 'atelier', 'premium-sapphire-wave': 'vitrine'
} as const;
const designIds = Object.keys(designs) as (keyof typeof designs)[];
const longName = 'ร้านเครื่องประดับเงินแท้งานฝีมือช่างไทยส่งตรงจากเชียงใหม่ทั่วประเทศ';
const page = (templateId: string, linkCount = 4): LinkInBioProfile => ({
  storeName: longName, slug: 'premium-shop',
  links: Array.from({ length: linkCount }, (_, index) => ({ id: `link-${index}`, title: `ช่องทางที่ ${index + 1}`, url: `https://example.com/${index}` })),
  appearance: { ...createDefaultLinkInBioTemplateAppearance(templateId), description: 'ร้านจริงของเจ้าของ' },
  isPublished: true, publishedAt: null, updatedAt: '', publicPath: '/p/premium-shop'
});
const scope = '[data-template-category="premium"]';
// Declarations of every rule with a premium-scoped selector ending in suffix,
// including selectors grouped with a comma.
const scoped = (html: string, suffix: string) => [...html.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
  .filter((match) => match[1]!.split(',').some((selector) => selector.includes(scope) && selector.trim().endsWith(suffix)))
  .map((match) => match[2]!).join(';');
const fill = (html: string, index: number) => html.match(new RegExp(`\\.link-${index}\\{color:[^;]+;background:([^;]+);`))?.[1];

describe('premium storefront designs', () => {
  it('ships exactly the twenty premium designs, each with its own geometry', () => {
    const premium = profileTemplates.filter((template) => template.category === 'premium');
    expect(premium.map((template) => template.id)).toEqual(designIds);
    expect(Object.keys(linkInBioPremiumDesigns)).toEqual(designIds);
    expect(premium.every((template) => template.since === 5 && template.themeId === 'minimal' && template.font === 'prompt')).toBe(true);
  });

  it.each(designIds)('renders %s with its catalog layout, real owner content and its own picture', (templateId) => {
    const html = renderLinkInBioPage(page(templateId), 'nonce');
    const composition = designs[templateId];
    expect(getProfileTemplate(templateId)?.layout.composition).toBe(composition);
    expect(html).toContain(`data-template="${templateId}" data-template-category="premium"`);
    expect(html).toContain(`data-composition="${composition}"`);
    const art = `<img class="profile-premium-art" src="/profile-decorations/${templateId}.png" alt="" aria-hidden="true">`;
    const wrapper = { portal: 'profile-premium-arch', vitrine: 'profile-premium-frame' }[composition as string];
    expect(html).toContain(`<div class="profile-premium-hero">${wrapper ? `<span class="${wrapper}">${art}</span>` : art}`);
    expect(html).toContain(`<h1>${longName}</h1>`);
    expect(html).toContain('ร้านจริงของเจ้าของ');
    expect(html).toContain('ช่องทางที่ 4');
    // Long Thai names and link titles wrap instead of overflowing small phones.
    expect(scoped(html, ' .profile-header h1')).toContain('overflow-wrap:anywhere');
    expect(scoped(html, ' .link-copy')).toContain('min-width:0');
    expect(html).toMatch(/@media\(max-width:400px\)\{body\[data-template\]\[data-template-category="premium"\]\[data-composition\]/);
    // Every link gets a finished edge, and no other category's hero leaks in.
    expect(scoped(html, ' a')).toMatch(/border:|clip-path:/);
    expect(html).not.toMatch(/profile-3d-|profile-cartoon-|<script\b|undefinedpx|NaN/);
    // The fixed initial size comes from the avatar, not a missing table entry.
    expect(scoped(html, ' .logo.avatar-initial')).toContain(`font-size:${Math.round(linkInBioPremiumDesigns[templateId]!.avatarSize * .4)}px`);
  });

  it('keeps every default text readable on its page, panel and link', () => {
    for (const templateId of designIds) {
      const palette = getProfileTemplate(templateId)!.palette;
      for (const background of [palette.background, palette.gradient, palette.surface]) {
        for (const text of [palette.name, palette.description, palette.category]) {
          expect(linkInBioColorContrast(text, background), templateId).toBeGreaterThanOrEqual(4.5);
        }
      }
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      const linkFill = fill(html, 0)!;
      expect(linkInBioColorContrast(palette.buttonText, linkFill === 'transparent' ? palette.surface : linkFill), templateId).toBeGreaterThanOrEqual(4.5);
    }
  });

  it('replaces the picture with an uploaded cover and keeps owner colors', () => {
    for (const templateId of designIds) {
      const profile = page(templateId);
      profile.appearance!.surfaceColor = '#123456';
      profile.appearance!.coverKey = 'profiles/owner/cover.png';
      profile.links[0] = { ...profile.links[0]!, buttonColor: '#654321', textColor: '#ffffff' };
      const html = renderLinkInBioPage(profile, 'nonce');
      expect(html, templateId).toContain('class="cover profile-premium-cover" src="/p/premium-shop/images/cover"');
      expect(html, templateId).not.toContain(`/profile-decorations/${templateId}.png`);
      // The cover sits in the hero only, never also above the page.
      expect(html.match(/images\/cover/g), templateId).toHaveLength(1);
      expect(scoped(html, ' .profile-premium-cover'), templateId).toContain('object-fit:cover');
      expect(scoped(html, ' main'), templateId).toContain('background:#123456');
      expect(fill(html, 0), templateId).toBe('#654321');
      expect(html, templateId).not.toContain('profiles/owner/');
    }
  });

  it('places the avatar on the edge, in the middle, on the sill or beside the name', () => {
    const rule = (templateId: keyof typeof designs) => scoped(renderLinkInBioPage(page(templateId), 'nonce'), ' .profile-premium-hero .logo');
    expect(rule('premium-gold-leaf')).toContain('bottom:-46px;left:calc(50% - 46px)');
    expect(rule('premium-art-deco')).toContain('top:calc(50% - 48px);left:calc(50% - 48px)');
    expect(rule('premium-white-marble')).toContain('bottom:-42px;left:calc(50% - 42px)');
    expect(rule('premium-velvet-wine')).toContain('bottom:-40px;left:var(--pd-premium-side)');
    expect(rule('premium-emerald-facet')).toContain('grid-column:1;grid-row:2');
    const portal = renderLinkInBioPage(page('premium-pearl-strand'), 'nonce');
    expect(scoped(portal, ' .profile-premium-arch')).toContain('border-radius:999px 999px 6px 6px');
    const vitrine = renderLinkInBioPage(page('premium-crystal'), 'nonce');
    expect(scoped(vitrine, ' .profile-header')).toContain('grid-template-columns:72px minmax(0,1fr)');
  });

  it('draws the diamond ornament under centred names and a short rule under left names', () => {
    for (const templateId of designIds) {
      const after = scoped(renderLinkInBioPage(page(templateId), 'nonce'), ' .profile-copy::after');
      if (designs[templateId] === 'vitrine') expect(after, templateId).toBe('');
      else if (designs[templateId] === 'atelier') expect(after, templateId).toContain('width:48px;height:1px');
      else expect(after, templateId).toContain(`clip-path:${linkInBioPremiumOrnament}`);
    }
  });

  it('frames, fades and finishes each design as its geometry says', () => {
    for (const templateId of designIds) {
      const design = linkInBioPremiumDesigns[templateId]!;
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      expect(scoped(html, ' main::after').includes('inset:10px'), templateId).toBe(design.frame);
      const fades = ['crest', 'cameo', 'atelier'].includes(designs[templateId]) && design.fade !== false;
      expect(scoped(html, ' .profile-premium-hero::after').includes('linear-gradient'), templateId).toBe(fades);
      const links = scoped(html, ' a');
      const before = scoped(html, ' a::before');
      switch (design.material) {
        case 'plate': expect(links, templateId).toContain('background-image:linear-gradient(180deg,#ffffff38'); break;
        case 'gilded': expect(before, templateId).toMatch(/inset:4px;border:1px solid #[0-9a-f]{6}73/); break;
        case 'notched': expect(links, templateId).toContain('clip-path:polygon(10px 0'); break;
        case 'hairline': expect(links, templateId).toMatch(/border:0;border-bottom:1px solid/); break;
        case 'stitched': expect(before, templateId).toContain('border:1.5px dashed currentColor'); break;
        case 'pearl': expect(links, templateId).toContain('box-shadow:inset 0 1px 0 #ffffff'); break;
      }
    }
  });

  it('serves open hairline rows on the panel and keeps filled links filled', () => {
    for (const templateId of designIds) {
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      const open = getProfileTemplate(templateId)!.layout.button === 'outline';
      expect(fill(html, 0) === 'transparent', templateId).toBe(open);
    }
  });
});
