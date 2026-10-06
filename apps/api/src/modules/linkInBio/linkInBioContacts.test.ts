import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import type { LinkInBioIcon } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import type { LinkInBioProfile } from './linkInBioStore.js';

const page = { storeName: 'ร้าน', slug: 'contact-shop', links: [{ id: 'contact', title: 'ติดต่อร้าน', url: 'https://example.com/' }] };
const render = (url: string, icon?: string) => renderLinkInBioPage({
  ...page, links: [{ ...page.links[0]!, url, ...(icon ? { icon } : {}) }],
  isPublished: true, publishedAt: '2026-10-06T16:00:00Z', updatedAt: '2026-10-06T16:00:00Z', publicPath: '/p/contact-shop'
} as LinkInBioProfile, 'test-nonce');

describe('profile contact destinations', () => {
  it.each([
    ['messenger', 'https://m.me/shop'], ['messenger', 'https://www.messenger.com/t/shop'],
    ['messenger', 'https://www.facebook.com/messages/t/shop'],
    ['whatsapp', 'https://wa.me/66812345678'], ['whatsapp', 'https://api.whatsapp.com/send?phone=66812345678'],
    ['google_maps', 'https://maps.app.goo.gl/shop'], ['google_maps', 'https://goo.gl/maps/shop'],
    ['google_maps', 'https://www.google.com/maps/place/shop'], ['google_maps', 'https://maps.google.co.th/?q=shop']
  ])('detects %s and serves its bundled artwork for %s', async (icon, url) => {
    expect(render(url)).toContain(`data-icon="${icon}"`);
    expect(render(url)).toContain(`src="/profile-platforms/${icon}.png"`);
    await request(createApp()).get(`/profile-platforms/${icon}.png`).expect(200).expect('Content-Type', /image\/png/);
  });

  it.each([
    ['website', 'https://example.com/shop'], ['email', 'mailto:shop+sales@example.com'], ['phone', 'tel:+66812345678']
  ])('publishes and renders a safe %s contact with a decorative vector icon', async (icon, url) => {
    const app = createApp();
    const published = await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'contact-owner')
      .send({ ...page, links: [{ ...page.links[0]!, url, icon }] }).expect(200);
    expect(published.body.profile.links[0]).toMatchObject({ url, icon });
    const html = (await request(app).get('/p/contact-shop').expect(200)).text;
    expect(html).toContain(`data-icon="${icon}"`);
    expect(html).toContain('<svg');
    expect(html).toContain(`href="${url}"`);
    if (icon !== 'website') expect(html).not.toContain('target="_blank"');
    expect(html).not.toContain('/profile-platforms/undefined');
    expect(render(url)).toContain(`data-icon="${icon}"`);
  });

  it.each(['https://m.me.evil.example/shop', 'https://notwhatsapp.com/shop', 'https://maps.app.goo.gl.evil.example/shop',
    'https://google.com/search?q=maps', 'https://google.com/mapshop', 'https://goo.gl/other'])
  ('uses the website icon for non-platform hosts or non-map paths: %s', (url) => {
    expect(render(url)).toContain('data-icon="website"');
    expect(render(url)).not.toContain('<img');
  });

  it('keeps a manually selected generic icon and platform override', () => {
    expect(render('https://wa.me/66812345678', 'link')).toContain('data-icon="link"');
    expect(render('https://example.com', 'messenger')).toContain('src="/profile-platforms/messenger.png"');
  });

  it.each(['messenger', 'whatsapp', 'google_maps', 'website', 'email', 'phone'] as const)
  ('accepts the explicit %s choice without altering its HTTP destination', async (icon: LinkInBioIcon) => {
    const published = await request(createApp()).post('/link-in-bio/publish').set('x-postdee-user-id', 'contact-owner')
      .send({ ...page, links: [{ ...page.links[0]!, icon }] }).expect(200);
    expect(published.body.profile.links[0]).toEqual({ ...page.links[0]!, icon });
    expect(render(page.links[0]!.url, icon)).toContain(`data-icon="${icon}"`);
  });

  it.each([
    [' MAILTO:Shop+Sales@Example.COM ', 'mailto:Shop+Sales@Example.COM'],
    [' TEL:+66812345678 ', 'tel:+66812345678'],
    ['tel:1234567', 'tel:1234567'], ['tel:+123456789012345', 'tel:+123456789012345'],
    [`mailto:${'a'.repeat(64)}@${'b'.repeat(63)}.${'c'.repeat(63)}.${'d'.repeat(58)}.co`,
      `mailto:${'a'.repeat(64)}@${'b'.repeat(63)}.${'c'.repeat(63)}.${'d'.repeat(58)}.co`]
  ])('accepts and normalizes safe contact destination %s', async (url, normalized) => {
    const app = createApp();
    const published = await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'contact-owner')
      .send({ ...page, links: [{ ...page.links[0]!, url }] }).expect(200);
    expect(published.body.profile.links[0].url).toBe(normalized);
    const html = (await request(app).get('/p/contact-shop').expect(200)).text;
    expect(html).toContain(`href="${normalized}"`);
    expect(html).not.toContain('target="_blank"');
    expect(html).not.toContain('<img');
  });

  it.each(['mailto', 'mailto:', 'mailto://shop@example.com', 'mailto:a@example.com,b@example.com',
    'mailto:shop@example.com?subject=hi', 'mailto:shop%0d%0abcc@example.com', 'mailto:a..b@example.com',
    'mailto:a@-example.com', 'tel:', 'tel:+123', 'tel:+66812345678;ext=1', 'tel:*123#',
    'tel:%2B66812345678', 'sms:+66812345678', 'javascript:alert(1)', 'data:text/html,x',
    'mailto:.a@example.com', 'mailto:a.@example.com', 'mailto:a@example-.com', 'mailto:a@example..com',
    'mailto:a@localhost', 'mailto:a@example.123', 'mailto:a@exa_mple.com', 'mailto:a@example.com#recipient',
    'mailto:a@example.com\n', 'mailto:a@例子.com', 'mailto:a@example.com?bcc=other@example.com',
    `mailto:${'a'.repeat(65)}@example.com`, `mailto:a@${'b'.repeat(64)}.com`,
    `mailto:${'a'.repeat(64)}@${'b'.repeat(63)}.${'c'.repeat(63)}.${'d'.repeat(59)}.co`,
    'tel:123456', 'tel:1234567890123456', 'tel:++66812345678', 'tel:+66 812345678', 'tel:+66812345678\t'])
  ('rejects unsafe or unsupported contact destinations without replacing the published profile: %s', async (url) => {
    const app = createApp();
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'contact-owner').send(page).expect(200);
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'contact-owner')
      .send({ ...page, links: [{ ...page.links[0]!, url }] }).expect(400);
    const saved = await request(app).get('/link-in-bio').set('x-postdee-user-id', 'contact-owner').expect(200);
    expect(saved.body.profile.links).toEqual(page.links);
  });
});
