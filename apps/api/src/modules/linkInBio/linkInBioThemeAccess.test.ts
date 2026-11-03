import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { createMemoryTrialAccessStore, withTrialAccess } from '../admin/trialAccess.js';
import { createInMemoryMonthlyAddonStore } from '../billing/monthlyAddonStore.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createDefaultLinkInBioAppearance, createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
import { registerLinkInBioRoutes, type LinkInBioRouteOptions } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';
import { profileTemplates } from './profileTemplateCatalog.generated.js';
import { createFreeProfileThemeAppearance, hasPaidProfileThemeMembership,
  profileThemeRequiresMembership, readPurchasedProfileThemePlan, samePremiumProfileStyling } from './linkInBioThemeAccess.js';

const owner = { id: 'theme-owner', provider: 'firebase' as const };
const page = { storeName: 'Owner shop', slug: 'theme-shop', links: [
  { id: 'buy', title: 'Buy here', url: 'https://example.com/shop' }
] };
const premiumId = 'dimensional-clay-mint';
const premium = () => createDefaultLinkInBioTemplateAppearance(premiumId);
const publish = (app: express.Express, appearance?: unknown) => request(app).post('/link-in-bio/publish')
  .set('X-PostDee-Profile-Catalog', '4').send({ ...page, ...(appearance === undefined ? {} : { appearance }) });
const fixture = (options: LinkInBioRouteOptions = {}) => {
  let instant = '2026-11-03T00:00:00.000Z';
  const subscriptions = createSubscriptionStore({ now: () => instant });
  const store = createInMemoryLinkInBioStore();
  const app = express();
  app.use(express.json());
  const router = express.Router();
  const validateImages = vi.fn(async () => {});
  registerLinkInBioRoutes(router, (_req, res, next) => { res.locals.authUser = owner; next(); },
    store, undefined, { subscriptionStore: subscriptions, validateImages, ...options });
  app.use(router);
  return { app, store, subscriptions, validateImages, setNow: (value: string) => { instant = value; } };
};

describe('profile theme membership policy', () => {
  it('classifies every raw category, rather than the three categories visible in the picker', () => {
    for (const template of profileTemplates) {
      expect(profileThemeRequiresMembership({ templateId: template.id, themeId: template.themeId }), template.id)
        .toBe(template.category !== 'minimal');
    }
    for (const themeId of ['shop', 'pastel', 'dark', 'pink', 'garden', 'cards', 'future-theme']) {
      expect(profileThemeRequiresMembership({ templateId: null, themeId })).toBe(true);
    }
    expect(profileThemeRequiresMembership({ templateId: 'future-template', themeId: 'minimal' })).toBe(true);
    expect(profileThemeRequiresMembership({ templateId: null, themeId: 'minimal' })).toBe(false);
    expect(profileThemeRequiresMembership(undefined)).toBe(false);
  });

  it.each(['BASIC', undefined, 'UNKNOWN', 'toString', 'PRO_EXPIRED'])('does not infer paid membership from %s', plan => {
    expect(hasPaidProfileThemeMembership(plan)).toBe(false);
  });

  it.each(['STARTER', 'PRO', 'BUSINESS'])('recognizes active purchased %s access', plan => {
    expect(hasPaidProfileThemeMembership(plan)).toBe(true);
  });

  it('permits content changes while retaining every premium styling choice', () => {
    const saved = premium();
    expect(samePremiumProfileStyling(saved, { ...saved, description: 'New description', logoKey: 'uploads/logo.png',
      coverKey: 'uploads/cover.png', featuredLinkId: 'buy', featuredLabel: 'Featured',
      background: { ...saved.background, mode: 'image', imageKey: 'uploads/background.png' } })).toBe(true);
    expect(samePremiumProfileStyling(saved, { ...saved, buttonColor: '#123456' })).toBe(false);
    expect(samePremiumProfileStyling(saved, { ...saved, effects: { ...saved.effects, entrance: !saved.effects.entrance } })).toBe(false);
    expect(samePremiumProfileStyling(saved, createDefaultLinkInBioTemplateAppearance('dimensional-clay-peach'))).toBe(false);
  });

  it('creates a canonical simple render clone while retaining user content and the original saved appearance', () => {
    const saved = { ...premium(), description: 'Saved description', logoKey: 'uploads/logo.png', coverKey: 'uploads/cover.png',
      featuredLinkId: 'buy', featuredLabel: 'Best item',
      background: { ...premium().background, mode: 'image' as const, imageKey: 'uploads/background.png', overlay: 45 } };
    const before = structuredClone(saved);
    expect(createFreeProfileThemeAppearance(saved)).toEqual({ ...createDefaultLinkInBioAppearance(),
      description: saved.description, logoKey: saved.logoKey, coverKey: saved.coverKey,
      featuredLinkId: saved.featuredLinkId, featuredLabel: saved.featuredLabel,
      background: { ...createDefaultLinkInBioAppearance().background, mode: 'image', imageKey: saved.background.imageKey, overlay: 45 } });
    expect(saved).toEqual(before);
  });

  it('retains a hidden background reference without activating it in the simple fallback', () => {
    const saved = premium();
    saved.background = { ...saved.background, mode: 'gradient', imageKey: 'uploads/hidden-background.png' };
    const fallback = createFreeProfileThemeAppearance(saved);
    expect(fallback.background.mode).toBe(createDefaultLinkInBioAppearance().background.mode);
    expect(fallback.background.imageKey).toBe(saved.background.imageKey);
    expect(saved.background.mode).toBe('gradient');
  });

  it('strips development plan claims and fails closed for purchased-plan lookup errors', async () => {
    const subscriptions = createSubscriptionStore();
    expect(await readPurchasedProfileThemePlan(subscriptions, { ...owner, subscriptionPlan: 'BUSINESS' })).toBe('BASIC');
    expect(await readPurchasedProfileThemePlan({ getPlan: async () => 'PRO', getPurchasedPlan: async () => { throw new Error('unavailable'); } }, owner))
      .toBeUndefined();
  });
});

describe('profile theme publication and public membership boundary', () => {
  it('lets Basic publish minimal templates and rejects new premium, legacy and unknown choices without a write', async () => {
    const { app, store, validateImages } = fixture();
    const write = vi.spyOn(store, 'publish');
    await publish(app, premium()).expect(403)
      .expect(({ body }) => expect(body.code).toBe('LINK_IN_BIO_PREMIUM_THEME_REQUIRED'));
    await publish(app, { themeId: 'pink' }).expect(403);
    await publish(app, { themeId: 'minimal', templateId: 'future-template' }).expect(400);
    expect(write).not.toHaveBeenCalled();
    expect(validateImages).not.toHaveBeenCalled();
    const simple = profileTemplates.find(template => template.category === 'minimal')!;
    await publish(app, createDefaultLinkInBioTemplateAppearance(simple.id)).expect(200);
  });

  it.each(['STARTER', 'PRO', 'BUSINESS'] as const)('allows purchased %s to publish every premium category', async plan => {
    const { app, subscriptions } = fixture();
    await subscriptions.activatePlan(owner, plan);
    for (const category of ['cute', 'nature', 'luxury', 'creative', 'dimensional', 'cartoon']) {
      const template = profileTemplates.find(item => item.category === category)!;
      await publish(app, createDefaultLinkInBioTemplateAppearance(template.id)).expect(200);
      expect((await request(app).get(`/p/${page.slug}`).expect(200)).text).toContain(`data-template="${template.id}"`);
    }
  });

  it('does not treat an admin trial as purchased membership', async () => {
    const paid = createSubscriptionStore();
    const trials = createMemoryTrialAccessStore();
    await trials.mutate({ requestId: 'theme-trial', actorId: 'admin', userId: owner.id, action: 'GRANT',
      plan: 'PRO', days: 7, expectedVersion: 0, reason: 'Synthetic theme trial fixture' });
    const { app } = fixture({ subscriptionStore: withTrialAccess(paid, trials) });
    await publish(app, premium()).expect(403);
  });

  it('does not treat purchased post or caption credits as membership', async () => {
    const addons = createInMemoryMonthlyAddonStore();
    await addons.applyPurchase({ userId: 'credits-only-owner', productId: 'postdee_post100_caption50', transactionId: 'theme-credits',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2026-11-03T00:00:00.000Z' });
    const app = createApp({ monthlyAddonStore: addons });
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'credits-only-owner')
      .set('X-PostDee-Profile-Catalog', '4').send({ ...page, appearance: premium() }).expect(403);
  });

  it('does not accept a development paid header as purchased proof on authenticated publish', async () => {
    const app = createApp();
    await request(app).post('/link-in-bio/publish').set('x-postdee-user-id', 'header-only-owner')
      .set('x-postdee-subscription-plan', 'PRO').set('X-PostDee-Profile-Catalog', '4')
      .send({ ...page, appearance: premium(), plan: 'BUSINESS', purchasedPlan: 'BUSINESS', canUsePremiumProfileThemes: true })
      .expect(403).expect(({ body }) => expect(body.code).toBe('LINK_IN_BIO_PREMIUM_THEME_REQUIRED'));
  });

  it('preserves saved premium styling through expiry, content-only editing and restoration', async () => {
    const { app, store, subscriptions, setNow } = fixture();
    await subscriptions.activatePlan(owner, 'STARTER', { currentPeriodEnd: '2026-11-04T00:00:00.000Z' });
    const saved = { ...premium(), description: 'Original owner description' };
    await publish(app, saved).expect(200);
    setNow('2026-11-04T00:00:00.000Z');
    const before = await store.getForUser(owner.id);
    const write = vi.spyOn(store, 'publish');
    const freePage = await request(app).get(`/p/${page.slug}`).expect(200);
    expect(freePage.headers['cache-control']).toBe('no-store');
    expect(freePage.text).toContain('data-theme="minimal"');
    expect(freePage.text).not.toContain(`data-template="${premiumId}"`);
    expect(freePage.text).toContain(saved.description);
    expect(write).not.toHaveBeenCalled();
    expect(await store.getForUser(owner.id)).toEqual(before);
    const owned = await request(app).get('/link-in-bio').set('X-PostDee-Profile-Catalog', '4').expect(200);
    expect(owned.body.profile.appearance).toEqual(saved);
    const edited = { ...saved, description: 'Edited while expired', logoKey: 'uploads/owner/logo.png' };
    await publish(app, edited).expect(200);
    await publish(app, { ...edited, buttonColor: '#123456' }).expect(403);
    await publish(app, createDefaultLinkInBioTemplateAppearance('dimensional-clay-peach')).expect(403);
    expect((await store.getForUser(owner.id))?.appearance).toEqual(edited);
    await publish(app).expect(200);
    expect((await store.getForUser(owner.id))?.appearance).toEqual(edited);
    await subscriptions.activatePlan(owner, 'STARTER', { currentPeriodEnd: '2026-12-04T00:00:00.000Z' });
    const restored = await request(app).get(`/p/${page.slug}`).expect(200);
    expect(restored.headers['cache-control']).toBe('no-store');
    expect(restored.text).toContain(`data-template="${premiumId}"`);
    expect(restored.text).toContain(edited.description);
  });

  it('retains a hidden premium template on an exact old-catalog replay after expiry', async () => {
    const { app, store } = fixture();
    await store.publish({ ...page, userId: owner.id, appearance: premium() });
    const legacy = await request(app).get('/link-in-bio').expect(200);
    expect(legacy.body.profile.appearance.templateId).toBeNull();
    await request(app).post('/link-in-bio/publish').send({ ...page, appearance: legacy.body.profile.appearance }).expect(200);
    expect((await store.getForUser(owner.id))?.appearance?.templateId).toBe(premiumId);
  });

  it('fails closed on membership errors without rewriting or pruning saved appearance', async () => {
    const getPlan = vi.fn(async (): Promise<'BASIC'> => { throw new Error('Private database detail'); });
    const { app, store, validateImages } = fixture({ subscriptionStore: { getPlan } });
    await store.publish({ ...page, userId: owner.id, appearance: premium() });
    const before = await store.getForUser(owner.id);
    const write = vi.spyOn(store, 'publish');
    const pageResult = await request(app).get(`/p/${page.slug}`).expect(200);
    expect(pageResult.text).toContain('data-theme="minimal"');
    expect(pageResult.text).not.toContain(`data-template="${premiumId}"`);
    await publish(app, premium()).expect(503);
    expect(write).not.toHaveBeenCalled();
    expect(validateImages).not.toHaveBeenCalled();
    expect(await store.getForUser(owner.id)).toEqual(before);
  });

  it('uses only the owner in the stored public snapshot, never visitor identity or paid override headers', async () => {
    const { app, store, subscriptions } = fixture();
    await store.publish({ ...page, userId: owner.id, appearance: premium() });
    const getPlan = vi.spyOn(subscriptions, 'getPlan');
    const legacyRead = vi.spyOn(store, 'getPublishedBySlug');
    const result = await request(app).get(`/p/${page.slug}`).set('x-postdee-user-id', 'paid-visitor')
      .set('x-postdee-subscription-plan', 'BUSINESS').set('Authorization', 'Bearer visitor').expect(200);
    expect(result.text).not.toContain(`data-template="${premiumId}"`);
    expect(getPlan).toHaveBeenCalledWith({ id: owner.id, provider: 'firebase' });
    expect(legacyRead).not.toHaveBeenCalled();
  });

  it('checks paid membership inside the mutation guard after a queued request expires', async () => {
    let entered!: () => void;
    let release!: () => void;
    const enteredPromise = new Promise<void>(resolve => { entered = resolve; });
    const gate = new Promise<void>(resolve => { release = resolve; });
    const { app, store, subscriptions, setNow } = fixture({ withImageMutation: async (_id, operation) => {
      entered(); await gate; return operation();
    } });
    await subscriptions.activatePlan(owner, 'STARTER', { currentPeriodEnd: '2026-11-04T00:00:00.000Z' });
    const pending = publish(app, premium()).then(response => response);
    await enteredPromise;
    setNow('2026-11-04T00:00:00.000Z');
    release();
    expect((await pending).status).toBe(403);
    expect(await store.getForUser(owner.id)).toBeNull();
  });

  it('does not overwrite a concurrently saved premium style with an expired retention request', async () => {
    let entered!: () => void;
    let release!: () => void;
    const enteredPromise = new Promise<void>(resolve => { entered = resolve; });
    const gate = new Promise<void>(resolve => { release = resolve; });
    const { app, store } = fixture({ validateImages: async () => { entered(); await gate; } });
    await store.publish({ ...page, userId: owner.id, appearance: premium() });
    const pending = publish(app, { ...premium(), description: 'Stale content edit' }).then(response => response);
    await enteredPromise;
    const newer = createDefaultLinkInBioTemplateAppearance('dimensional-clay-peach');
    await store.publish({ ...page, userId: owner.id, appearance: newer });
    release();
    const result = await pending;
    expect(result.status).toBe(409);
    expect(result.body.code).toBe('LINK_IN_BIO_APPEARANCE_CONFLICT');
    expect((await store.getForUser(owner.id))?.appearance).toEqual(newer);
  });
});
