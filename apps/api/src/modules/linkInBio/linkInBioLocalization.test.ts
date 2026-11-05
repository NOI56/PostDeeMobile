import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioAppearance } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';

const page = {
  storeName: 'ร้านชา & Tea', slug: 'tea-shop',
  links: [{ id: 'shop', title: 'เปิดลิงก์ของร้าน', category: 'ช่องทางร้าน', url: 'https://example.com/shop' }]
};
const appearance = () => ({
  ...createDefaultLinkInBioAppearance('cards'),
  logoKey: 'profiles/owner/logo.png', coverKey: 'profiles/owner/cover.png'
});
const fixture = async () => {
  const store = createInMemoryLinkInBioStore();
  const profile = await store.publish({ ...page, userId: 'owner', appearance: appearance() });
  const app = express();
  registerLinkInBioRoutes(app, (_request, _response, next) => next(), store, undefined, {
    subscriptionStore: { getPlan: async () => 'STARTER', getPurchasedPlan: async () => 'STARTER' }
  });
  return { app, store, profile };
};
const expectLanguage = (html: string, language: 'th' | 'en') => {
  expect(html).toContain(`<html lang="${language}">`);
  if (language === 'th') {
    expect(html).toContain('<p class="description">เลือกช่องทางที่ต้องการได้เลย</p>');
    expect(html).toContain('<footer>สร้างหน้าเว็บร้านค้าด้วย PostDee</footer>');
    expect(html).toContain('<span class="link-cta">เปิดลิงก์</span>');
    expect(html).toContain('alt="ภาพปกของ ร้านชา &amp; Tea"');
    expect(html).toContain('alt="โลโก้ ร้านชา &amp; Tea"');
  } else {
    expect(html).toContain('<p class="description">Choose a channel below</p>');
    expect(html).toContain('<footer>Create your store page with PostDee</footer>');
    expect(html).toContain('<span class="link-cta">Open link</span>');
    expect(html).toContain('alt="Cover image for ร้านชา &amp; Tea"');
    expect(html).toContain('alt="Logo for ร้านชา &amp; Tea"');
  }
};

describe('public store page language', () => {
  it.each(['th', 'en'] as const)('localizes the renderer fixed strings in %s', async (language) => {
    const { profile } = await fixture();
    expectLanguage(renderLinkInBioPage(profile, 'test-nonce', language), language);
  });

  it('defaults the optional renderer language to English', async () => {
    const { profile } = await fixture();
    expectLanguage(renderLinkInBioPage(profile, 'test-nonce'), 'en');
  });

  it.each([
    [undefined, 'en'], ['', 'en'], ['ja-JP,fr;q=0.9', 'en'],
    ['th', 'th'], ['en', 'en'], ['TH-th,en;q=0.8', 'th'], ['en-GB,th;q=0.8', 'en'],
    ['th;q=0.3,en;q=0.9', 'en'], ['en;q=0.2,th;q=0.9', 'th'],
    ['ja;q=1,th;q=0.8,en;q=0.4', 'th'], ['th;q=0,en;q=0.5', 'en'],
    ['en;q=0,th;q=0.5', 'th'], ['th,en', 'th'], ['en,th', 'en'], ['*', 'en'],
    ['en-US,th;q=0.9,en;q=0.8', 'en'], ['th-TH,en;q=0.9,th;q=0.8', 'th'],
    ['en;q=0.8,th;q=0.9,en-US', 'en'], ['th;q=0.8,en;q=0.9,th-TH', 'th'],
    ['en-US,th;q=1,en;q=0.8', 'en'], ['th-TH,en;q=1,th;q=0.8', 'th'],
    ['EN-us,th;q=0.9,EN;q=0.8', 'en'],
    ['en-US;q=0,th;q=0.6', 'th'], ['th-TH;q=0,en;q=0.6', 'en'],
    ['th;q=0,en;q=0', 'en'], ['th;q=invalid,en;q=0.5', 'en'],
    ['*;q=1,th;q=0.5', 'en'], ['en;q=0,*;q=1', 'th'], ['th;q=0,*;q=1', 'en'],
    ['ja-JP,*;q=0.9,th;q=0.5', 'en'], ['th-TH,*;q=0.5', 'th']
  ] as const)('negotiates Accept-Language %s as %s', async (header, language) => {
    const { app } = await fixture();
    const visit = request(app).get('/p/tea-shop');
    if (header !== undefined) visit.set('Accept-Language', header);
    const result = await visit.expect(200).expect('Content-Type', /html/);
    expectLanguage(result.text, language);
    expect(result.headers.vary.toLowerCase().split(/,\s*/)).toContain('accept-language');
    expect(result.headers['cache-control']).toBe('no-store');
    const nonce = result.text.match(/<style nonce="([^"]+)"/)?.[1];
    expect(nonce).toBeTruthy();
    expect(result.headers['content-security-policy']).toContain(`style-src 'nonce-${nonce}'`);
    expect(result.headers['content-security-policy']).toContain("script-src 'none'");
  });

  it.each(['th', 'en'] as const)('keeps owner content unchanged for %s visitors', async (language) => {
    const { app, store } = await fixture();
    const authored = { ...appearance(), description: 'เลือกช่องทางที่ต้องการได้เลย',
      featuredLinkId: 'shop', featuredLabel: 'โปรของร้าน' };
    await store.publish({ ...page, userId: 'owner', appearance: authored });
    const { text } = await request(app).get('/p/tea-shop').set('Accept-Language', language).expect(200);
    expect(text).toContain('<h1>ร้านชา &amp; Tea</h1>');
    expect(text).toContain('<p class="description">เลือกช่องทางที่ต้องการได้เลย</p>');
    expect(text).toContain('<li class="category">ช่องทางร้าน</li>');
    expect(text).toContain('<span>เปิดลิงก์ของร้าน</span>');
    expect(text).toContain('<span class="featured-label">โปรของร้าน</span>');
    expect(text).toContain('href="https://example.com/shop"');
    expect((await store.getForUser('owner'))?.appearance).toEqual(authored);
  });

  it.each([
    ['th', 'ไม่พบหน้าเว็บร้านค้า'], ['en', 'Store page not found'],
    [undefined, 'Store page not found'], ['ja-JP', 'Store page not found'],
    ['th;q=0.2,en;q=0.8', 'Store page not found'],
    ['en-US,th;q=0.9,en;q=0.8', 'Store page not found'],
    ['th-TH,en;q=0.9,th;q=0.8', 'ไม่พบหน้าเว็บร้านค้า']
  ] as const)('localizes absent, hidden and invalid pages for %s', async (header, message) => {
    const { app, store } = await fixture();
    await store.unpublish('owner');
    for (const path of ['/p/missing', '/p/tea-shop', '/p/-invalid']) {
      const visit = request(app).get(path);
      if (header !== undefined) visit.set('Accept-Language', header);
      const result = await visit.expect(404).expect('Content-Type', /text\/plain/);
      expect(result.text).toBe(message);
      expect(result.headers.vary.toLowerCase().split(/,\s*/)).toContain('accept-language');
      expect(result.headers['cache-control']).toBe('no-store');
    }
  });
});
