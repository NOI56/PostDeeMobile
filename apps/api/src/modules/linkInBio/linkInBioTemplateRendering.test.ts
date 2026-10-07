import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioAppearance, createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore, type LinkInBioProfile } from './linkInBioStore.js';
import { profileTemplates } from './profileTemplateCatalog.generated.js';

const links = [
  { id: 'buy', title: 'ซื้อ <สินค้า>', url: 'https://shopee.co.th/shop', category: 'ร้าน <วันนี้>', icon: 'shopee' as const, buttonColor: '#123456', textColor: '#ffffff', font: 'prompt' as const },
  { id: 'email', title: 'ส่งอีเมล', url: 'mailto:shop@example.com', category: 'ติดต่อ', icon: 'email' as const },
  { id: 'phone', title: 'โทรหาเรา', url: 'tel:+66812345678', category: 'ติดต่อ', icon: 'phone' as const }
];

const createProfile = (templateId: string): LinkInBioProfile => ({
  storeName: 'ร้าน <ของเรา>', slug: 'template-shop', links,
  appearance: { ...createDefaultLinkInBioTemplateAppearance(templateId), description: 'รายละเอียด <ร้าน>',
    featuredLinkId: 'buy', featuredLabel: 'โปร <พิเศษ>', logoKey: 'profiles/owner/logo.png',
    coverKey: 'profiles/owner/cover.png', effects: { background: true, entrance: true, featured: true, stickers: 'flowers' } },
  isPublished: true, publishedAt: null, updatedAt: '', publicPath: '/p/template-shop'
});

describe('categorized profile template rendering', () => {
  it.each(profileTemplates)('renders $id using its catalog layout without losing existing content or link customization', (template) => {
    const html = renderLinkInBioPage(createProfile(template.id), 'safe-nonce');
    expect(html).toContain(`data-template="${template.id}"`);
    for (const field of ['header', 'links', 'button', 'decoration', 'avatar', 'composition'] as const) {
      expect(html).toContain(`data-${field}="${template.layout[field]}"`);
    }
    expect(html).toContain('ร้าน &lt;ของเรา&gt;');
    expect(html).toContain('รายละเอียด &lt;ร้าน&gt;');
    expect(html).toContain('ร้าน &lt;วันนี้&gt;');
    expect(html).toContain('โปร &lt;พิเศษ&gt;');
    expect(html).toContain('/p/template-shop/images/logo');
    expect(html).toContain('/p/template-shop/images/cover');
    expect(html).not.toContain('profiles/owner/');
    expect(html).toContain('href="https://shopee.co.th/shop" target="_blank" rel="noopener noreferrer"');
    expect(html).toContain('href="mailto:shop@example.com"><');
    expect(html).toContain('href="tel:+66812345678"><');
    expect(html.indexOf('href="https://shopee')).toBeLessThan(html.indexOf('href="mailto:'));
    expect(html.indexOf('href="mailto:')).toBeLessThan(html.indexOf('href="tel:'));
    expect(html).toContain('background:#123456');
    expect(html).toContain('color:#ffffff');
    expect(html).toContain('font-family:"Prompt"');
    expect(html).toContain('width:40px;height:40px');
    expect(html).toContain('/profile-platforms/shopee.png');
    expect(html).toContain('data-stickers="flowers"');
    expect(html).toContain('@media(prefers-reduced-motion:reduce)');
    expect(html).not.toMatch(/pause-motion|motion-control|หยุดการเคลื่อนไหว|<script\b|style="/i);
  });

  it('shows the complete uploaded logo centered in every template while cover and background photos retain cropping', () => {
    for (const template of profileTemplates) {
      const profile = createProfile(template.id);
      profile.appearance!.background = { ...profile.appearance!.background, mode: 'image', imageKey: 'profiles/owner/background.png' };
      const html = renderLinkInBioPage(profile, 'nonce');
      expect(html.includes(`data-composition="${template.layout.composition}"] img.logo{object-fit:contain;object-position:center}`)).toBe(true);
      expect(html).toContain('<img class="logo" src="/p/template-shop/images/logo"');
      expect(html).toContain('<img class="cover" src="/p/template-shop/images/cover"');
      expect(html).toMatch(/\.cover\{[^}]*object-fit:cover/);
      expect(html).toContain('background-size:cover;background-position:center;');
      expect(html).toContain('/p/template-shop/images/background');
      expect(html).not.toContain('profiles/owner/');
    }
  });

  it.each(['centered', 'left', 'split', 'cover', 'badge'])('renders %s with an initial fallback without inserting a generic cover into its composition', (header) => {
    const template = profileTemplates.find((entry) => entry.layout.header === header)!;
    const profile = createProfile(template.id);
    profile.appearance!.logoKey = null;
    profile.appearance!.coverKey = null;
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('avatar-initial');
    expect(html).not.toContain('/images/logo');
    expect(html).not.toContain('/images/cover');
    expect(html.includes('class="cover cover-fallback"')).toBe(template.layout.composition === 'torn');
  });

  it('creates a meadow cover for the torn-paper composition without requiring an uploaded image', () => {
    const template = profileTemplates.find((entry) => entry.layout.composition === 'torn')!;
    const profile = createProfile(template.id);
    profile.appearance!.coverKey = null;
    expect(renderLinkInBioPage(profile, 'nonce')).toContain('class="cover cover-fallback"');
  });

  it('uses white header copy directly on the stock forest and keeps the editorial fallback avatar out of its design', () => {
    const forest = createProfile('nature-greenhouse');
    forest.appearance!.logoKey = null;
    forest.appearance!.coverKey = null;
    const html = renderLinkInBioPage(forest, 'nonce');
    expect(html).toContain('background-image:url("/profile-decorations/forest.png")');
    expect(html).toMatch(/data-composition="glass"\] \.profile-header\{[^}]*background:transparent/);
    expect(html).toMatch(/data-composition="glass"\] footer\{[^}]*background:transparent/);
    expect(html).toMatch(/data-composition="glass"\] footer\{[^}]*margin-top:auto/);
    const editorial = renderLinkInBioPage(createProfile('minimal-white-editorial'), 'nonce');
    expect(editorial).toContain('.logo.avatar-initial{display:none}');
    expect(editorial).toContain('/p/template-shop/images/logo');
  });

  it('uses a two-column grid with full-width categories without changing link order', () => {
    const template = profileTemplates.find((entry) => entry.layout.links === 'grid')!;
    const html = renderLinkInBioPage(createProfile(template.id), 'nonce');
    expect(html).toContain('grid-template-columns:repeat(2,minmax(0,1fr))');
    expect(html).toContain('.category{grid-column:1/-1}');
    expect(html).toContain('min-height:112px');
    expect(html).toContain('padding:16px 14px 38px');
  });

  it('uses per-link custom fills even when the template has outline buttons', () => {
    const template = profileTemplates.find((entry) => entry.layout.button === 'outline')!;
    const html = renderLinkInBioPage(createProfile(template.id), 'nonce');
    expect(html).toContain('.link-0{color:#ffffff;background:#123456;');
    expect(html).toContain('background:transparent;');
    expect(html).toContain('custom-button');
  });

  it('retains the old filled-button snapshot when new outline rows would make its white text unreadable', () => {
    const profile = createProfile('nature-olive-garden');
    const stored = { ...profile.appearance!, surfaceColor: '#fffef8', buttonColor: '#718852', buttonStyle: { color: '#ffffff', font: 'anuphan' as const } };
    profile.appearance = stored;
    profile.links = [{ id: 'old', title: 'ลิงก์เดิม', url: 'https://example.com' }];
    const before = JSON.stringify(stored);
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('.link-0{color:#ffffff;background:#718852;');
    expect(JSON.stringify(stored)).toBe(before);
  });

  it('uses an existing fill for custom white text on a bright outline preset', () => {
    const profile = createProfile('minimal-white-editorial');
    profile.appearance!.buttonColor = '#123456';
    profile.links = [{ id: 'white', title: 'สีของร้าน', url: 'https://example.com', textColor: '#ffffff' }];
    expect(renderLinkInBioPage(profile, 'nonce')).toContain('.link-0{color:#ffffff;background:#123456;');
  });

  it('keeps custom colors and fonts authoritative in the multicolor poster composition', () => {
    const template = profileTemplates.find((entry) => entry.layout.composition === 'poster')!;
    const profile = createProfile(template.id);
    profile.appearance!.buttonColor = '#123456';
    profile.appearance!.buttonStyle = { color: '#ffffff', font: 'prompt' };
    profile.links = [{ id: 'one', title: 'หนึ่ง', url: 'https://example.com/1' }, { id: 'two', title: 'สอง', url: 'https://example.com/2' }];
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('.link-0{color:#ffffff;background:#123456;font-family:"Prompt"');
    expect(html).toContain('.link-1{color:#ffffff;background:#123456;font-family:"Prompt"');
  });

  it('lets the owner change collage button corners while retaining its paper border and shadow', () => {
    const profile = createProfile('cute-sticker-layers');
    for (const [shape, radius] of [['pill', '999px'], ['rounded', '16px'], ['square', '4px']] as const) {
      profile.appearance!.buttonRadius = shape;
      const html = renderLinkInBioPage(profile, 'nonce');
      expect(html.includes(`data-composition="collage"] a{border:1px solid ${profile.appearance!.categoryStyle.color}66;border-radius:${radius};box-shadow:3px 4px 0`)).toBe(true);
    }
  });

  it('honors owner torn-paper button corners without changing their border and shadow', () => {
    const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === 'torn')!.id);
    for (const [shape, radius] of [['pill', '999px'], ['rounded', '16px'], ['square', '4px']] as const) {
      profile.appearance!.buttonRadius = shape;
      const html = renderLinkInBioPage(profile, 'nonce');
      expect(html.includes(`data-composition="torn"] a{border:1px solid ${profile.appearance!.categoryStyle.color}33;border-radius:${radius};min-height:64px;padding:12px 14px;box-shadow:2px 3px 0`)).toBe(true);
    }
  });

  it('matches the native rail, notebook and staircase header geometry without changing their content', () => {
    for (const [composition, columns, logoColumn, copyColumn] of [
      ['rail', '52px minmax(0,1fr)', '1', '2'],
      ['notebook', 'minmax(0,1fr) 48px', '2', '1'],
      ['staircase', 'minmax(0,1fr) 44px', '2', '1']
    ]) {
      const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === composition)!.id);
      const html = renderLinkInBioPage(profile, 'nonce');
      const prefix = `data-composition="${composition}"]`;
      expect(html.includes(`${prefix} .profile-header{display:grid;grid-template-columns:${columns}`)).toBe(true);
      expect(html.includes(`${prefix} .logo{grid-column:${logoColumn};grid-row:1`)).toBe(true);
      expect(html.includes(`${prefix} .profile-copy{grid-column:${copyColumn};grid-row:1`)).toBe(true);
      expect(html).toContain('ร้าน &lt;ของเรา&gt;');
      expect(html).toContain('รายละเอียด &lt;ร้าน&gt;');
    }
  });

  it('uses numbered hairline rail rows only when their resolved fill is transparent', () => {
    const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === 'rail')!.id);
    profile.appearance!.buttonColor = '#123456';
    profile.links = [
      { id: 'default', title: 'เส้นใต้', url: 'https://example.com/default' },
      { id: 'custom', title: 'สีของร้าน', url: 'https://example.com/custom', buttonColor: '#123456', textColor: '#ffffff', font: 'prompt' },
      { id: 'snapshot', title: 'ตัวอักษรขาวเดิม', url: 'https://example.com/snapshot', textColor: '#ffffff' }
    ];
    const html = renderLinkInBioPage(profile, 'nonce');
    const body = html.slice(html.indexOf('<body'));
    const classes = [...body.matchAll(/<a class="([^"]+)"/g)].map((match) => match[1]!.split(' '));
    expect(classes[0]).toContain('rail-outline');
    expect(classes[1]).toContain('custom-button');
    expect(classes[1]).not.toContain('rail-outline');
    expect(classes[2]).not.toContain('rail-outline');
    expect(body.match(/rail-outline/g)).toHaveLength(1);
    expect(html.includes(`data-composition="rail"] a.rail-outline{min-height:64px;padding:12px 16px;border:0;border-bottom:1px solid ${profile.appearance!.categoryStyle.color}73;border-radius:0;box-shadow:none}`)).toBe(true);
    expect(html.includes('data-composition="rail"] a.rail-outline::before{content:none}')).toBe(true);
    expect(html).toContain('.link-1{color:#ffffff;background:#123456;font-family:"Prompt"');
    expect(html).toContain('.link-2{color:#ffffff;background:#123456;');
    expect(body).toContain('class="link-number" aria-hidden="true">01</span>');
  });

  it('honors owner-filled button corners in all six hairline compositions', () => {
    for (const composition of ['editorial', 'scallop', 'botanical', 'seal', 'rail', 'notebook']) {
      const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === composition)!.id);
      for (const [shape, radius] of [['pill', '999px'], ['rounded', '16px'], ['square', '4px']] as const) {
        profile.appearance!.buttonRadius = shape;
        const html = renderLinkInBioPage(profile, 'nonce');
        expect(html.includes(`data-composition="${composition}"] a.filled-button{border-radius:${radius}}`)).toBe(true);
        expect(html).toContain('.link-0{color:#ffffff;background:#123456;font-family:"Prompt"');
        expect(html.includes(`data-composition="${composition}"] a${composition === 'rail' ? '.rail-outline' : ''}{`)).toBe(true);
        expect(html).toContain('border-radius:0;');
      }
    }
  });

  it('honors hairline corners for global filled colors and older white-text snapshots', () => {
    for (const composition of ['editorial', 'scallop', 'botanical', 'seal', 'rail', 'notebook']) {
      const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === composition)!.id);
      profile.appearance!.buttonColor = '#123456';
      profile.appearance!.buttonStyle = { color: '#ffffff', font: 'prompt' };
      profile.appearance!.buttonRadius = 'pill';
      profile.links = [{ id: 'global', title: 'สีทั้งหน้า', url: 'https://example.com/global' }];
      const html = renderLinkInBioPage(profile, 'nonce');
      const body = html.slice(html.indexOf('<body'));
      expect(body.includes('filled-button')).toBe(true);
      expect(body.includes('custom-button')).toBe(false);
      expect(body.includes('rail-outline')).toBe(false);
      expect(html.includes(`data-composition="${composition}"] a.filled-button{border-radius:999px}`)).toBe(true);
      expect(html).toContain('.link-0{color:#ffffff;background:#123456;font-family:"Prompt"');
    }
    const old = createProfile('nature-olive-garden');
    old.appearance = { ...old.appearance!, surfaceColor: '#fffef8', buttonColor: '#718852', buttonStyle: { color: '#ffffff', font: 'anuphan' }, buttonRadius: 'rounded' };
    old.links = [{ id: 'old', title: 'ลิงก์เดิม', url: 'https://example.com/old' }];
    const before = JSON.stringify(old.appearance);
    const html = renderLinkInBioPage(old, 'nonce');
    expect(html.slice(html.indexOf('<body')).includes('filled-button')).toBe(true);
    expect(html.includes('data-composition="botanical"] a.filled-button{border-radius:16px}')).toBe(true);
    expect(JSON.stringify(old.appearance)).toBe(before);
  });

  it('keeps an opaque owner surface on image backgrounds in every open composition', () => {
    for (const composition of ['editorial', 'botanical', 'glass', 'gallery', 'poster', 'rail', 'ribbon', 'staircase', 'collage']) {
      const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === composition)!.id);
      profile.appearance!.background = { ...profile.appearance!.background, mode: 'image', imageKey: 'profiles/owner/background.png' };
      const html = renderLinkInBioPage(profile, 'nonce');
      const mainStyle = html.split(`body[data-template][data-composition="${composition}"] main{`).slice(1).map((part) => part.split('}')[0]!).filter((part) => part.includes('background:')).at(-1)!;
      expect(mainStyle.includes(`background:${profile.appearance!.surfaceColor}`)).toBe(true);
      expect(mainStyle.includes('background:transparent')).toBe(false);
      expect(html).toContain('/p/template-shop/images/background');
      expect(html).not.toContain('url("/profile-decorations/paper.png")');
      expect(html).not.toContain('url("/profile-decorations/forest.png")');
    }
  });

  it('keeps a glass owner surface override opaque in the panel, header and footer', () => {
    const profile = createProfile('nature-greenhouse');
    profile.appearance!.surfaceColor = '#eeeeee';
    const html = renderLinkInBioPage(profile, 'nonce');
    for (const selector of ['main', '.profile-header', 'footer']) {
      const declaration = html.split(`body[data-template][data-composition="glass"] ${selector}{`).slice(1).map((part) => part.split('}')[0]!).filter((part) => part.includes('background:')).at(-1)!;
      expect(declaration.includes('background:#eeeeee')).toBe(true);
      expect(declaration.includes('background:transparent')).toBe(false);
    }
    expect(html).toContain('url("/profile-decorations/forest.png")');
    expect(profile.appearance!.surfaceColor).toBe('#eeeeee');
  });

  it('puts the arch around the owned cover and avatar with the store copy outside it', () => {
    const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === 'arch')!.id);
    const html = renderLinkInBioPage(profile, 'nonce');
    const body = html.slice(html.indexOf('<body'));
    expect(body).toMatch(/<header class="profile-header"><div class="arch-hero"><img class="cover"[^>]*><img class="logo"[^>]*><\/div><div class="profile-copy"><h1>/);
    expect(body.match(/\/p\/template-shop\/images\/cover/g)).toHaveLength(1);
    profile.appearance!.coverKey = null;
    profile.appearance!.logoKey = null;
    expect(renderLinkInBioPage(profile, 'nonce')).toContain('<div class="arch-hero"><div class="logo avatar-initial"');
  });

  it('keeps the native ribbon title wash and honors all owner button corner choices', () => {
    const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === 'ribbon')!.id);
    for (const [shape, radius] of [['pill', '999px'], ['rounded', '16px'], ['square', '4px']] as const) {
      profile.appearance!.buttonRadius = shape;
      const html = renderLinkInBioPage(profile, 'nonce');
      expect(html.includes(`data-composition="ribbon"] .profile-copy{display:inline-block;max-width:100%;padding:12px 18px;background:${profile.appearance!.categoryStyle.color}1f`)).toBe(true);
      expect(html.includes(`data-composition="ribbon"] a{min-height:64px;border-radius:${radius};`)).toBe(true);
      expect(html).not.toContain('clip-path:polygon(0 0,100% 0,calc(100% - 12px) 50%');
    }
  });

  it('uses one accent row followed by light portrait rows only for an untouched default preset', () => {
    const template = profileTemplates.find((entry) => entry.layout.composition === 'portrait')!;
    const profile = createProfile(template.id);
    profile.links = [
      { id: 'one', title: 'หนึ่ง', url: 'https://example.com/1' },
      { id: 'two', title: 'สอง', url: 'https://example.com/2' },
      { id: 'three', title: 'สาม', url: 'https://example.com/3', buttonColor: '#123456', textColor: '#ffffff' }
    ];
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain(`.link-0{color:${template.palette.buttonText};background:${template.palette.button};`);
    expect(html).toContain(`.link-1{color:${template.palette.name};background:${template.palette.surface};`);
    expect(html).toContain('.link-2{color:#ffffff;background:#123456;');
    profile.appearance!.buttonColor = '#123456';
    expect(renderLinkInBioPage(profile, 'nonce')).toContain(`.link-1{color:${template.palette.buttonText};background:#123456;`);
  });

  it('resets mixed-card rhythm only at a displayed category heading while keeping global numbering', () => {
    const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === 'collage')!.id);
    profile.links = Array.from({ length: 6 }, (_, index) => ({ id: `${index}`, title: `${index}`, url: `https://example.com/${index}`, category: index === 0 ? 'แรก' : index >= 3 ? 'ถัดไป' : undefined }));
    const body = renderLinkInBioPage(profile, 'nonce').split('<body')[1]!;
    const positions = [...body.matchAll(/data-position="(\d+)" data-rhythm="(\d+)"/g)].map((match) => [Number(match[1]), Number(match[2])]);
    expect(positions).toEqual([[1, 0], [2, 1], [3, 2], [4, 0], [5, 1], [6, 2]]);
  });

  it.each(['minimal', 'shop', 'pastel', 'dark', 'pink', 'garden', 'cards'] as const)('retains the legacy %s page without introducing new template markup or artwork', (theme) => {
    const profile = createProfile(profileTemplates[0]!.id);
    profile.appearance = createDefaultLinkInBioAppearance(theme);
    profile.appearance.logoKey = 'profiles/owner/logo.png';
    profile.appearance.coverKey = 'profiles/owner/cover.png';
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain(`data-theme="${theme}"`);
    expect(html).not.toMatch(/data-composition=|data-position=|class="profile-copy"|class="link-number"|\/profile-decorations\//);
    expect(html).toContain('href="mailto:shop@example.com"');
    expect(html).toContain('width:40px;height:40px');
    expect(html).toContain('<img class="logo" src="/p/template-shop/images/logo"');
    expect(html).toMatch(/\.logo\{[^}]*object-fit:cover/);
    expect(html).toMatch(/\.cover\{[^}]*object-fit:cover/);
    expect(html).not.toContain('img.logo{object-fit:contain;');
  });

  it.each(['editorial', 'bicolor', 'portrait', 'scallop', 'collage', 'window', 'botanical', 'glass', 'torn', 'seal', 'tag', 'gallery', 'poster', 'window-grid', 'ticket', 'rail', 'ribbon', 'notebook', 'arch', 'staircase'])('gives %s a distinct page composition while retaining all twenty real links', (composition) => {
    const template = profileTemplates.find((entry) => entry.layout.composition === composition)!;
    const profile = createProfile(template.id);
    profile.links = Array.from({ length: 20 }, (_, index) => ({
      id: `link-${index}`, title: `ลิงก์จริง ${index + 1}`, url: `https://example.com/${index + 1}`,
      category: index === 0 ? 'เริ่มต้น' : index === 10 ? 'เพิ่มเติม' : undefined
    }));
    profile.appearance!.featuredLinkId = null;
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain(`data-composition="${composition}"`);
    expect(html).toContain(`body[data-template][data-composition="${composition}"]`);
    expect(html).toContain('class="profile-copy"');
    const body = html.slice(html.indexOf('<body'));
    expect(body.match(/class="link-number"/g)).toHaveLength(20);
    expect(body.match(/href="https:\/\/example\.com\//g)).toHaveLength(20);
    for (let index = 1; index <= 20; index++) expect(body).toContain(`data-position="${index}"`);
    expect(body).toContain('>เริ่มต้น</li>');
    expect(body).toContain('>เพิ่มเติม</li>');
    expect(body.indexOf('href="https://example.com/1"')).toBeLessThan(body.indexOf('href="https://example.com/20"'));
    expect(body).not.toMatch(/<script\b|pause-motion|หยุดการเคลื่อนไหว/);
  });

  it('keeps an owned custom background visible instead of replacing it with the forest artwork', () => {
    const template = profileTemplates.find((entry) => entry.layout.composition === 'glass')!;
    const profile = createProfile(template.id);
    profile.appearance!.background = { mode: 'image', color: '#abcdef', gradientColor: '#123456', imageKey: 'profiles/owner/background.png', overlay: 40 };
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('/p/template-shop/images/background');
    expect(html).toContain('data-custom-background="true"');
    expect(html).not.toContain('url("/profile-decorations/forest.png")');
  });

  it('keeps changed background colors authoritative instead of inserting stock photography', () => {
    const template = profileTemplates.find((entry) => entry.layout.composition === 'glass')!;
    const profile = createProfile(template.id);
    profile.appearance!.background = { ...profile.appearance!.background, mode: 'solid', color: '#abcdef' };
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('background:#abcdef');
    expect(html).not.toContain('url("/profile-decorations/forest.png")');
  });

  it('keeps full-page paper and mint gingham confined to their default backgrounds', () => {
    for (const [id, expected] of [['cute-sticker-layers', '/profile-decorations/paper.png'], ['cute-candy-box', 'background-size:24px 24px']] as const) {
      const profile = createProfile(id);
      expect(renderLinkInBioPage(profile, 'nonce')).toContain(expected);
      profile.appearance!.background = { ...profile.appearance!.background, mode: 'solid', color: '#abcdef' };
      expect(renderLinkInBioPage(profile, 'nonce')).not.toContain(expected);
    }
    const window = renderLinkInBioPage(createProfile('cute-candy-box'), 'nonce');
    expect(window).toMatch(/data-composition="window"\] main\{[^}]*background:#ffffff/);
  });

  it('matches the native pastel window with three filled pink, yellow and mint chrome dots', () => {
    const profile = createProfile('cute-candy-box');
    profile.appearance!.background.gradientColor = '#ddeeff';
    const html = renderLinkInBioPage(profile, 'nonce');
    const chrome = html.split('body[data-template][data-composition="window"] main::after{').at(-1)!.split('}')[0]!;
    expect(chrome.includes('width:12px;height:12px;border:0;')).toBe(true);
    expect(chrome.includes('background:#f997ac;')).toBe(true);
    expect(chrome.includes('box-shadow:19px 0 0 #f8d779,38px 0 0 #96c6a0;')).toBe(true);
    expect(html.includes('height:36px;background:#ddeeff;')).toBe(true);
  });

  it('uses each window catalog avatar shape for both uploaded logos and initial fallbacks', () => {
    for (const template of profileTemplates.filter((entry) => entry.layout.composition === 'window')) {
      const profile = createProfile(template.id);
      const radius = template.layout.avatar === 'circle' ? '50%' : template.layout.avatar === 'rounded' ? '10.56px' : '3px';
      const selector = `data-composition="window"] .logo{width:48px;height:48px;border-radius:${radius};`;
      const owned = renderLinkInBioPage(profile, 'nonce');
      expect(owned.includes(selector)).toBe(true);
      expect(owned).toContain('/p/template-shop/images/logo');
      profile.appearance!.logoKey = null;
      const initial = renderLinkInBioPage(profile, 'nonce');
      expect(initial.includes(selector)).toBe(true);
      expect(initial).toContain('class="logo avatar-initial"');
    }
  });

  it('uses the retro-window lilac, cream, lime and pink sequence while preserving explicit colors', () => {
    const profile = createProfile('creative-play-blocks');
    profile.links = Array.from({ length: 4 }, (_, index) => ({ id: `${index}`, title: `${index}`, url: `https://example.com/${index}` }));
    const html = renderLinkInBioPage(profile, 'nonce');
    for (const [index, color] of ['#d2bfff', '#fff9e6', '#d9f9b9', '#f8d4e1'].entries()) {
      expect(html).toContain(`.link-${index}{color:#1d1b21;background:${color};`);
    }
    profile.links[1] = { ...profile.links[1]!, buttonColor: '#123456', textColor: '#ffffff' };
    expect(renderLinkInBioPage(profile, 'nonce')).toContain('.link-1{color:#ffffff;background:#123456;');
  });

  it.each(['editorial', 'bicolor', 'portrait', 'scallop', 'collage', 'window', 'botanical', 'glass', 'torn', 'seal', 'tag', 'gallery', 'poster', 'window-grid', 'ticket', 'rail', 'ribbon', 'notebook', 'arch', 'staircase'])('centers the %s initial without overflowing a small avatar', (composition) => {
    const profile = createProfile(profileTemplates.find((entry) => entry.layout.composition === composition)!.id);
    profile.appearance!.logoKey = null;
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('.logo.avatar-initial{display:grid;place-items:center;line-height:1}');
    expect(html).toMatch(new RegExp(`data-composition="${composition}"\\] \\.logo\\.avatar-initial\\{font-size:\\d+px\\}`));
    expect(html).toContain('display:flow-root');
  });

  it('references only fixed same-origin composition artwork and preserves reduced motion', () => {
    const compositions = ['botanical', 'glass', 'torn', 'scallop', 'collage', 'seal', 'tag'];
    const expectedAssets = ['botanical-frame', 'forest', 'meadow', 'letter-frame', 'collage-tape', 'gold-seal', 'tag-cord'];
    for (const [index, composition] of compositions.entries()) {
      const template = profileTemplates.find((entry) => entry.layout.composition === composition)!;
      const html = renderLinkInBioPage(createProfile(template.id), 'nonce');
      expect(html).toContain(`/profile-decorations/${expectedAssets[index]}.png`);
      expect(html).toContain('@media(prefers-reduced-motion:reduce)');
      expect(html).not.toMatch(/https?:\/\/[^\s"')]+\.png/);
    }
  });
});

describe('categorized profile template publication routes', () => {
  it('accepts and persists all 100 templates with their layout and nonce CSP, while old clients preserve the saved template', async () => {
    const app = express();
    app.use(express.json());
    const router = express.Router();
    registerLinkInBioRoutes(router, (_request, response, next) => {
      response.locals.authUser = { id: 'owner', provider: 'mock' };
      next();
    }, createInMemoryLinkInBioStore());
    app.use(router);
    for (const template of profileTemplates) {
      const page = { storeName: 'ร้าน', slug: 'templates', links, appearance: { templateId: template.id } };
      const published = await request(app).post('/link-in-bio/publish').send(page).expect(200);
      expect(published.body.profile.appearance.templateId).toBe(template.id);
      const saved = await request(app).get('/link-in-bio').expect(200);
      expect(saved.body.profile.appearance.templateId).toBe(template.id);
      const rendered = await request(app).get('/p/templates').expect(200);
      expect(rendered.text).toContain(`data-template="${template.id}"`);
      expect(rendered.headers['content-security-policy']).toContain("script-src 'none'");
      expect(rendered.headers['content-security-policy']).toContain("style-src 'nonce-");
      expect(rendered.headers['content-security-policy']).toContain("img-src 'self'");
      expect(rendered.headers['cache-control']).toBe('no-store');
    }
    const latestId = profileTemplates.at(-1)!.id;
    await request(app).post('/link-in-bio/publish').send({ storeName: 'ร้าน', slug: 'templates', links }).expect(200);
    expect((await request(app).get('/link-in-bio').expect(200)).body.profile.appearance.templateId).toBe(latestId);
    for (const templateId of ['unknown', 'minimal-99', '" onclick="bad', {}, 7]) {
      await request(app).post('/link-in-bio/publish').send({ storeName: 'ร้าน', slug: 'templates', links, appearance: { templateId } }).expect(400);
      expect((await request(app).get('/link-in-bio').expect(200)).body.profile.appearance.templateId).toBe(latestId);
    }
  });
});
