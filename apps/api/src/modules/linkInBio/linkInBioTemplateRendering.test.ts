import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
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
    for (const field of ['header', 'links', 'button', 'decoration', 'avatar'] as const) {
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

  it.each(['centered', 'left', 'split', 'cover', 'badge'])('renders %s with an initial fallback and safe cover fallback where needed', (header) => {
    const template = profileTemplates.find((entry) => entry.layout.header === header)!;
    const profile = createProfile(template.id);
    profile.appearance!.logoKey = null;
    profile.appearance!.coverKey = null;
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('avatar-initial');
    expect(html).not.toContain('/images/logo');
    expect(html).not.toContain('/images/cover');
    expect(html.includes('class="cover cover-fallback"')).toBe(header === 'cover');
  });

  it('uses a two-column grid with full-width categories without changing link order', () => {
    const template = profileTemplates.find((entry) => entry.layout.links === 'grid')!;
    const html = renderLinkInBioPage(createProfile(template.id), 'nonce');
    expect(html).toContain('grid-template-columns:repeat(2,minmax(0,1fr))');
    expect(html).toContain('.category{grid-column:1/-1}');
    expect(html).toContain('min-height:112px');
  });

  it('uses per-link custom fills even when the template has outline buttons', () => {
    const template = profileTemplates.find((entry) => entry.layout.button === 'outline')!;
    const html = renderLinkInBioPage(createProfile(template.id), 'nonce');
    expect(html).toContain('.link-0{color:#ffffff;background:#123456;');
    expect(html).toContain('background:transparent;');
    expect(html).toContain('custom-button');
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
