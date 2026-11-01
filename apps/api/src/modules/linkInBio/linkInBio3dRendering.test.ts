import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore, type LinkInBioProfile } from './linkInBioStore.js';

const templateIds = [
  'dimensional-clay-mint', 'dimensional-clay-peach',
  'dimensional-clay-cloud', 'dimensional-clay-sand',
  'dimensional-paper-fold', 'dimensional-paper-stage', 'dimensional-paper-ribbon',
  'dimensional-glass-lavender', 'dimensional-glass-mist', 'dimensional-glass-sage'
] as const;
const links = [
  { id: 'shop', title: 'ซื้อ <สินค้า>', url: 'https://shopee.co.th/shop', icon: 'shopee' as const },
  { id: 'contact', title: 'ส่งอีเมล', url: 'mailto:shop@example.com', icon: 'email' as const }
];
const page = (templateId: string): LinkInBioProfile => ({
  storeName: 'ร้าน <ของคุณ>', slug: 'three-d-shop', links: links.map((link) => ({ ...link })),
  appearance: { ...createDefaultLinkInBioTemplateAppearance(templateId),
    description: 'รายละเอียด <ร้าน>', logoKey: 'profiles/owner/logo.png' },
  isPublished: true, publishedAt: null, updatedAt: '', publicPath: '/p/three-d-shop'
});

describe('3D storefront rendering', () => {
  it.each(templateIds)('renders %s with decorative art and editable native content', (templateId) => {
    const html = renderLinkInBioPage(page(templateId), 'test-nonce');
    expect(html).toContain('data-template-category="dimensional"');
    expect(html).toContain('class="profile-3d-hero"');
    expect(html).toContain(`class="profile-3d-art" src="/profile-decorations/${templateId}.png" alt="" aria-hidden="true"`);
    expect(html).toContain('<img class="logo" src="/p/three-d-shop/images/logo"');
    expect(html).toContain('img.logo{object-fit:contain;object-position:center}');
    expect(html).toContain('<h1>ร้าน &lt;ของคุณ&gt;</h1>');
    expect(html).toContain('รายละเอียด &lt;ร้าน&gt;');
    expect(html).toContain('ซื้อ &lt;สินค้า&gt;');
    expect(html).toContain('href="https://shopee.co.th/shop" target="_blank" rel="noopener noreferrer"');
    expect(html).toContain('href="mailto:shop@example.com"><');
    expect(html.indexOf('class="profile-3d-hero"')).toBeLessThan(html.indexOf('<h1>'));
    expect(html).not.toContain('profiles/owner/');
    expect(html).not.toMatch(/<script\b|https?:\/\/[^\s"')]+\.png/);
    expect(html).toContain('@media(prefers-reduced-motion:reduce)');
  });

  it.each(templateIds)('lets the owner replace %s header artwork with their own cover', (templateId) => {
    const profile = page(templateId);
    profile.appearance!.coverKey = 'profiles/owner/custom-cover.png';
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('class="cover profile-3d-cover" src="/p/three-d-shop/images/cover"');
    expect(html).not.toContain(`/profile-decorations/${templateId}.png`);
    expect(html).toContain('src="/p/three-d-shop/images/logo"');
    expect(html).not.toContain('profiles/owner/');
  });

  it.each(templateIds)('keeps custom colors, long content and background authoritative in %s', (templateId) => {
    const profile = page(templateId);
    profile.appearance!.background = { mode: 'image', color: '#abcdef', gradientColor: '#fedcba',
      imageKey: 'profiles/owner/background.png', overlay: 30 };
    profile.appearance!.nameStyle = { color: '#102030', font: 'prompt' };
    profile.links = [{ ...links[0], title: 'ชื่อช่องทางยาว'.repeat(20), buttonColor: '#123456', textColor: '#ffffff' }];
    const html = renderLinkInBioPage(profile, 'nonce');
    expect(html).toContain('/p/three-d-shop/images/background');
    expect(html).toContain('.link-0{color:#ffffff;background:#123456;');
    expect(html).toContain('--pd-link-button:#123456;--pd-link-text:#ffffff');
    expect(html).toContain('color:#102030;font-family:"Prompt"');
    expect(html).toContain('min-width:0');
    expect(html).toContain('overflow-wrap:anywhere');
    expect(html).toContain('ชื่อช่องทางยาว'.repeat(20));
    expect(html).not.toContain('profiles/owner/');
  });

  it('leaves an existing minimal template free of 3D art and selectors', () => {
    const html = renderLinkInBioPage(page('minimal-white-editorial'), 'nonce');
    expect(html).not.toContain('class="profile-3d-hero"');
    expect(html).not.toContain('profile-3d-art');
    expect(html).not.toContain('data-template-category="dimensional"');
  });

  it('uses frosted translucency only with the default readable button palette', () => {
    const profile = page('dimensional-glass-lavender');
    const button = profile.appearance!.buttonColor;
    const text = profile.appearance!.buttonStyle.color;
    expect(renderLinkInBioPage(profile, 'nonce')).toContain(`.link-0{color:${text};background:${button}eb;`);
    profile.links[0] = { ...links[0], textColor: '#ffffff' };
    expect(renderLinkInBioPage(profile, 'nonce')).toContain(`.link-0{color:#ffffff;background:${button};`);
    profile.links[0] = { ...links[0], buttonColor: '#123456', textColor: '#ffffff' };
    expect(renderLinkInBioPage(profile, 'nonce')).toContain('.link-0{color:#ffffff;background:#123456;');
    profile.appearance!.buttonStyle.color = '#123456';
    expect(renderLinkInBioPage(profile, 'nonce')).toContain(`.link-1{color:#123456;background:${button};`);
  });

  it('keeps the default panel open to its page background but honors an explicit surface color', () => {
    const profile = page('dimensional-glass-lavender');
    expect(renderLinkInBioPage(profile, 'nonce')).toMatch(/data-template-category="dimensional"\][^{]* main\{[^}]*background:transparent/);
    profile.appearance!.surfaceColor = '#123456';
    expect(renderLinkInBioPage(profile, 'nonce')).toMatch(/data-template-category="dimensional"\][^{]* main\{[^}]*background:#123456/);
  });

  it('gives 3D material rules higher specificity than the existing composition resets', () => {
    for (const templateId of templateIds) {
      const html = renderLinkInBioPage(page(templateId), 'nonce');
      const materialRules = [...html.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
        .filter((match) => match[1]!.includes('data-template-category="dimensional"') &&
          match[1]!.trim().endsWith(' a') && match[2]!.includes('box-shadow:'));
      expect(materialRules.length).toBeGreaterThan(0);
      // Existing resets select body[data-template][data-composition] a.
      // Three category attributes must outrank those two even after new
      // template-specific resets are appended elsewhere in the stylesheet.
      for (const rule of materialRules) {
        expect((rule[1]!.match(/\[[^\]]+\]/g) ?? []).length, templateId).toBeGreaterThan(2);
      }
    }
  });
});

describe('3D storefront access', () => {
  it.each(templateIds)('allows Basic to publish %s and a visitor to open it without authentication', async (templateId) => {
    const app = express();
    app.use(express.json());
    const router = express.Router();
    registerLinkInBioRoutes(router, (req, res, next) => {
      if (req.headers.authorization !== 'Bearer owner-token') { res.status(401).end(); return; }
      res.locals.authUser = { id: 'owner', provider: 'mock' };
      next();
    }, createInMemoryLinkInBioStore(), undefined, {
      subscriptionStore: { getPlan: async () => 'BASIC' }
    });
    app.use(router);
    const input = { storeName: 'ร้านของคุณ', slug: 'three-d-shop', links,
      appearance: { templateId } };
    await request(app).post('/link-in-bio/publish').send(input).expect(401);
    await request(app).post('/link-in-bio/publish').set('Authorization', 'Bearer owner-token')
      .set('X-PostDee-Profile-Catalog', '2').send(input).expect(200);
    const publicPage = await request(app).get('/p/three-d-shop').expect(200);
    expect(publicPage.text).toContain(`data-template="${templateId}"`);
    expect(publicPage.text).toContain('class="profile-3d-hero"');
    expect(publicPage.headers['cache-control']).toBe('no-store');
    expect(publicPage.headers['content-security-policy']).toContain("script-src 'none'");
    expect(publicPage.headers['content-security-policy']).toContain("img-src 'self'");
    const rejected = await request(app).post('/link-in-bio/publish').set('Authorization', 'Bearer owner-token')
      .set('X-PostDee-Profile-Catalog', '2')
      .send({ ...input, links: [...links, { id: 'third', title: 'สาม', url: 'https://example.com' }] }).expect(403);
    expect(rejected.body.code).toBe('LINK_IN_BIO_LINK_LIMIT_EXCEEDED');
    expect((await request(app).get('/p/three-d-shop').expect(200)).text).toContain(`data-template="${templateId}"`);
  });
});
