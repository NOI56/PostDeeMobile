import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioAppearance, createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import type { LinkInBioLink, LinkInBioProfile } from './linkInBioStore.js';
import { profileTemplates } from './profileTemplateCatalog.generated.js';

const templateFor = (composition: string) => profileTemplates.find((entry) => entry.layout.composition === composition)!.id;
const profile = (storeName: string, links: LinkInBioLink[], appearance = createDefaultLinkInBioAppearance('pink')): LinkInBioProfile => ({
  storeName, slug: 'shop', links, appearance, isPublished: true, publishedAt: null, updatedAt: '', publicPath: '/p/shop'
});
const link = (id: string, category?: string, title = id): LinkInBioLink => ({ id, title, url: `https://example.com/${id}`, ...(category ? { category } : {}) });
const initialOf = (html: string) => html.match(/class="logo avatar-initial" aria-hidden="true">([^<]*)<\/div>/)?.[1];
const fillRowIds = (html: string) => [...html.matchAll(/<li class="link-item[^"]*fill-row[^"]*"[^>]*><a class="link-(\d+)/g)].map((match) => Number(match[1]));

describe('avatar initial without an uploaded logo', () => {
  it.each([
    ['ร้านผ้าไหมบ้านนา', 'ผ'],
    ['ร้าน ป้าแดง', 'ป'],
    ['เจ๊ปูขายดี', 'จ'],
    ['ร้านไหมทอง', 'ห'],
    ['ร้าน', 'ร'],
    ['  @postdee shop', 'p'],
    ['บ้านนา', 'บ'],
    ['😀', '😀'],
    ['', 'ร']
  ])('uses a meaningful letter for %s', (storeName, expected) => {
    expect(initialOf(renderLinkInBioPage(profile(storeName, [link('a')]), 'nonce'))).toBe(expected);
  });

  it('renders the meaningful letter on a template', () => {
    const appearance = createDefaultLinkInBioTemplateAppearance(templateFor('seal'));
    expect(initialOf(renderLinkInBioPage(profile('เจ๊ปูขายดี', [link('a')], appearance), 'nonce'))).toBe('จ');
  });

  it('escapes a markup character used as the initial', () => {
    expect(initialOf(renderLinkInBioPage(profile('<ร้าน>', [link('a')]), 'nonce'))).toBe('ร');
    expect(initialOf(renderLinkInBioPage(profile('<>', [link('a')]), 'nonce'))).toBe('&lt;');
  });
});

describe('phone numbers stay on one line', () => {
  it('keeps a phone number in a link title together while escaping the rest', () => {
    const html = renderLinkInBioPage(profile('ร้าน', [{ id: 'tel', title: 'โทร <ด่วน> 081-234-5678 & LINE', url: 'tel:0812345678' }]), 'nonce');
    expect(html).toContain('<span>โทร &lt;ด่วน&gt; <span class="keep-together">081-234-5678</span> &amp; LINE</span>');
    expect(html).toContain('.keep-together{display:inline-block;max-width:100%}');
  });

  it('keeps spaced and international numbers in titles and descriptions together', () => {
    const appearance = { ...createDefaultLinkInBioAppearance('minimal'), description: 'สายด่วน 02 123 4567 ทุกวัน' };
    const html = renderLinkInBioPage(profile('ร้าน', [{ id: 'tel', title: 'WhatsApp +66 81 234 5678', url: 'https://wa.me/66812345678' }], appearance), 'nonce');
    expect(html).toContain('WhatsApp <span class="keep-together">+66 81 234 5678</span>');
    expect(html).toContain('สายด่วน <span class="keep-together">02 123 4567</span> ทุกวัน');
  });

  it('leaves short numbers and plain text unchanged', () => {
    const html = renderLinkInBioPage(profile('ร้าน', [{ id: 'sale', title: 'ลด 20% เหลือ 199 บาท', url: 'https://example.com' }]), 'nonce');
    expect(html).toContain('<span>ลด 20% เหลือ 199 บาท</span>');
    expect(html).not.toContain('class="keep-together"');
  });
});

describe('Thai store names', () => {
  it.each(profileTemplates.map((template) => [template.id]))('does not letter-space the %s store name', (templateId) => {
    const html = renderLinkInBioPage(profile('ร้านผ้าไหม', [link('a')], createDefaultLinkInBioTemplateAppearance(templateId)), 'nonce');
    for (const rule of html.match(/h1\{[^}]*\}/g) ?? []) {
      expect(rule).not.toMatch(/letter-spacing:[1-9]/);
    }
  });
});

describe('grid layouts without a half-empty last row', () => {
  it.each(['bicolor', 'gallery', 'window-grid'])('fills the row with the last %s tile of an odd group', (composition) => {
    const appearance = createDefaultLinkInBioTemplateAppearance(templateFor(composition));
    const html = renderLinkInBioPage(profile('ร้าน', [link('a', 'ซื้อ'), link('b', 'ซื้อ'), link('c', 'ซื้อ'), link('d', 'ติดต่อ'), link('e', 'ติดต่อ')], appearance), 'nonce');
    expect(fillRowIds(html)).toEqual([2]);
    expect(html).toContain(`[data-composition="${composition}"] li.link-item.fill-row{grid-column:1/-1;transform:none}`);
  });

  it.each(['collage', 'glass'])('fills the row when a %s tile would be alone after a full-width link', (composition) => {
    const appearance = createDefaultLinkInBioTemplateAppearance(templateFor(composition));
    const groups = [link('a', 'หนึ่ง'), link('b', 'หนึ่ง'), link('c', 'สอง'), link('d', 'สอง'), link('e', 'สอง'),
      ...['f', 'g', 'h', 'i', 'j', 'k'].map((id) => link(id, 'สาม'))];
    expect(fillRowIds(renderLinkInBioPage(profile('ร้าน', groups, appearance), 'nonce'))).toEqual([1, 10]);
  });

  it('counts uncategorized links with the group above them', () => {
    const appearance = createDefaultLinkInBioTemplateAppearance(templateFor('bicolor'));
    expect(fillRowIds(renderLinkInBioPage(profile('ร้าน', [link('a', 'ซื้อ'), link('b', 'ซื้อ'), link('c')], appearance), 'nonce'))).toEqual([2]);
  });

  it.each(['seal', 'editorial', 'ribbon'])('never marks %s list links', (composition) => {
    const appearance = createDefaultLinkInBioTemplateAppearance(templateFor(composition));
    expect(fillRowIds(renderLinkInBioPage(profile('ร้าน', [link('a'), link('b'), link('c')], appearance), 'nonce'))).toEqual([]);
  });
});

describe('3D storefront readability', () => {
  it.each(profileTemplates.filter((template) => template.category === 'dimensional'))
  ('keeps $id artwork, depth and native readable content together', (template) => {
    const appearance = { ...createDefaultLinkInBioTemplateAppearance(template.id), description: 'โทร 02 123 4567 ทุกวัน' };
    const html = renderLinkInBioPage(profile('ร้านเจ๊ปู', [link('a', undefined, 'โทร 081-234-5678')], appearance), 'nonce');
    expect(initialOf(html)).toBe('จ');
    expect(html).toContain('class="profile-3d-hero"');
    expect(html).toContain(`class="profile-3d-art" src="/profile-decorations/${template.id}.png"`);
    expect(html).toContain('data-template-category="dimensional"');
    expect(html).toMatch(/data-template-category="dimensional"\][^{]* a\{[^}]*box-shadow:/);
    expect(html).toContain('โทร <span class="keep-together">081-234-5678</span>');
    expect(html).toContain('โทร <span class="keep-together">02 123 4567</span> ทุกวัน');
    // A lone tile in a paired 3D tile grid takes the whole row; lists never do.
    expect(fillRowIds(html)).toEqual(template.layout.composition === 'tile-grid' ? [0] : []);
    expect(html).not.toMatch(/<script\b/);
  });
});
