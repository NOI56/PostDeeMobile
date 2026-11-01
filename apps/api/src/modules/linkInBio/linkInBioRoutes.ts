import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import type { Request, RequestHandler, Response, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import { maxProfileLinksByPlan, readPlanLabel } from '../subscriptions/subscriptionEntitlements.js';
import type { SubscriptionPlan, SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { LinkInBioError, type LinkInBioLink, type LinkInBioProfile, type LinkInBioStore } from './linkInBioStore.js';
import { linkInBioFonts, linkInBioIcons, normalizeStoredLinkInBioAppearance, readLinkInBioAppearance, readLinkInBioColor, type LinkInBioAppearance, type LinkInBioFont, type LinkInBioIcon } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import { linkInBioPlatformLogoFiles } from './linkInBioPlatformLogos.js';
import { readLinkInBioUrl } from './linkInBioDestinations.js';
import { getProfileTemplate, profileTemplateCatalogVersion, profileTemplates } from './profileTemplateCatalog.generated.js';

export type LinkInBioRouteOptions = {
  subscriptionStore?: Pick<SubscriptionStore, 'getPlan'>;
  validateImages?: (userId: string, appearance: LinkInBioAppearance) => Promise<void | (() => Promise<void>)>;
  onPublished?: (userId: string, profile: LinkInBioProfile) => Promise<void>;
  withImageMutation?: (userId: string, operation: () => Promise<LinkInBioProfile>) => Promise<LinkInBioProfile>;
};

const slugPattern = /^(?=.{3,40}$)[a-z0-9]+(?:-[a-z0-9]+)*$/;
const readText = (value: unknown, maximum: number) => {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= maximum ? trimmed : undefined;
};

const readPublishInput = (body: unknown) => {
  if (typeof body !== 'object' || body === null) return undefined;
  const input = body as Record<string, unknown>;
  const storeName = readText(input.storeName, 80);
  const slug = readText(input.slug, 40)?.toLowerCase();
  if (!storeName || !slug || !slugPattern.test(slug) || !Array.isArray(input.links) || input.links.length < 1 || input.links.length > 20) return undefined;
  const links: LinkInBioLink[] = [];
  const ids = new Set<string>();
  for (const item of input.links) {
    if (typeof item !== 'object' || item === null) return undefined;
    const id = readText(item.id, 80);
    const title = readText(item.title, 80);
    const url = readLinkInBioUrl(item.url);
    if (!id || !title || !url || ids.has(id)) return undefined;
    ids.add(id);
    const link: LinkInBioLink = { id, title, url };
    const custom = item as Record<string, unknown>;
    if (custom.category !== undefined) {
      if (typeof custom.category !== 'string' || custom.category.length > 60) return undefined;
      if (custom.category.trim()) link.category = custom.category.trim();
    }
    if (custom.icon !== undefined) {
      if (!linkInBioIcons.includes(custom.icon as LinkInBioIcon)) return undefined;
      link.icon = custom.icon as LinkInBioIcon;
    }
    if (custom.font !== undefined) {
      if (!linkInBioFonts.includes(custom.font as LinkInBioFont)) return undefined;
      link.font = custom.font as LinkInBioFont;
    }
    for (const field of ['textColor', 'buttonColor'] as const) {
      if (custom[field] !== undefined) {
        const color = readLinkInBioColor(custom[field]);
        if (!color) return undefined;
        link[field] = color;
      }
    }
    links.push(link);
  }
  const appearance = input.appearance === undefined ? undefined : readLinkInBioAppearance(input.appearance, links);
  if (input.appearance !== undefined && !appearance) return undefined;
  return { storeName, slug, links, appearance };
};

const respondError = (response: Response, error: unknown) => {
  const known = error instanceof LinkInBioError;
  response.status(known ? error.statusCode : 503).json({
    status: 'error',
    code: known ? error.code : 'LINK_IN_BIO_UNAVAILABLE',
    message: known ? error.message : 'ระบบหน้าเว็บร้านค้ายังไม่พร้อม กรุณาลองใหม่ภายหลัง'
  });
};

const profileCatalogHeader = 'X-PostDee-Profile-Catalog';
const supportsCurrentProfileCatalog = (request: Request) =>
  request.get(profileCatalogHeader) === String(profileTemplateCatalogVersion);

// Older installed apps reject unknown template IDs. Give only those clients
// the same editable colors/content with the existing legacy theme as fallback.
// This is response serialization only; stored and public page styling is intact.
const profileForClient = (profile: LinkInBioProfile | null, currentCatalog: boolean): LinkInBioProfile | null => {
  const appearance = profile?.appearance;
  if (currentCatalog || !profile || !appearance ||
      getProfileTemplate(appearance.templateId)?.category !== 'dimensional') return profile;
  return { ...profile, appearance: { ...appearance, templateId: null } };
};

export const registerLinkInBioRoutes = (
  router: Router, authMiddleware: RequestHandler, store: LinkInBioStore, userStore?: UserStore,
  options: LinkInBioRouteOptions = {}
) => {
  const decorationFiles = ['botanical-frame.png', 'forest.png', 'meadow.png', 'paper.png', 'letter-frame.png', 'collage-tape.png', 'gold-seal.png', 'tag-cord.png',
    ...profileTemplates.filter((template) => template.category === 'dimensional').map((template) => `${template.id}.png`)];
  router.get('/profile-decorations/:file', (request, response) => {
    const file = request.params.file;
    if (typeof file !== 'string' || !decorationFiles.includes(file)) { response.status(404).end(); return; }
    response.set('Cache-Control', 'public, max-age=86400').set('X-Content-Type-Options', 'nosniff').type('image/png')
      .sendFile(fileURLToPath(new URL(`../../../assets/profile-decorations/${file}`, import.meta.url)), { dotfiles: 'allow' });
  });
  router.get('/profile-platforms/:file', (request, response) => {
    const file = request.params.file;
    if (typeof file !== 'string' || !Object.values(linkInBioPlatformLogoFiles).includes(file)) { response.status(404).end(); return; }
    response.set('Cache-Control', 'public, max-age=86400').set('X-Content-Type-Options', 'nosniff').type('image/png')
      .sendFile(fileURLToPath(new URL(`../../../assets/profile-platforms/${file}`, import.meta.url)), { dotfiles: 'allow' });
  });
  router.use('/link-in-bio', (_request, response, next) => {
    response.set('Cache-Control', 'no-store');
    response.vary(profileCatalogHeader);
    next();
  });
  router.get('/link-in-bio', authMiddleware, async (request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    response.set('Cache-Control', 'no-store');
    try {
      response.json({ status: 'ok', profile: profileForClient(await store.getForUser(user.id), supportsCurrentProfileCatalog(request)) });
    } catch (error) { respondError(response, error); }
  });
  router.post('/link-in-bio/publish', authMiddleware, async (request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    const input = readPublishInput(request.body);
    if (!input) {
      response.status(400).json({ status: 'error', code: 'LINK_IN_BIO_INVALID_INPUT', message: 'กรุณาตรวจชื่อร้าน ชื่อหน้าเว็บ และลิงก์ให้ถูกต้อง' });
      return;
    }
    response.set('Cache-Control', 'no-store');
    try {
      let plan: SubscriptionPlan | undefined;
      try { plan = await options.subscriptionStore?.getPlan(user); } catch { /* Fail closed below. */ }
      const maxProfileLinks = plan ? maxProfileLinksByPlan[plan] : undefined;
      if (!plan || typeof maxProfileLinks !== 'number') {
        throw new LinkInBioError(503, 'LINK_IN_BIO_ENTITLEMENTS_UNAVAILABLE', 'ตรวจสอบสิทธิ์ลิงก์ร้านไม่ได้ กรุณาลองใหม่ภายหลัง');
      }
      if (input.links.length > maxProfileLinks) {
        response.status(403).json({
          status: 'error', code: 'LINK_IN_BIO_LINK_LIMIT_EXCEEDED',
          message: `แพ็กเกจ ${readPlanLabel(plan)} เปิดใช้ลิงก์ร้านได้สูงสุด ${maxProfileLinks} ลิงก์ กรุณาเลือกเปิดใช้ไม่เกินสิทธิ์ก่อนเผยแพร่`,
          plan, maxProfileLinks, requestedLinks: input.links.length
        });
        return;
      }
      await userStore?.ensure(user);
      const imageGuard: { release?: () => Promise<void> } = {};
      const commit = async () => {
        let publishInput = input;
        const legacyFallback = !supportsCurrentProfileCatalog(request) &&
          input.appearance?.themeId === 'minimal' && input.appearance.templateId === null;
        const previous = input.appearance === undefined || legacyFallback
          ? await store.getForUser(user.id) : null;
        const storedAppearance = normalizeStoredLinkInBioAppearance(previous?.appearance, input.links);
        if (legacyFallback && getProfileTemplate(storedAppearance.templateId)?.category === 'dimensional') {
          if (JSON.stringify(input.appearance) !== JSON.stringify({ ...storedAppearance, templateId: null })) {
            // A legacy client cannot distinguish an edited fallback from a stale
            // snapshot. Refuse both rather than silently removing a newer theme.
            throw new LinkInBioError(409, 'LINK_IN_BIO_APPEARANCE_CONFLICT',
              'รูปแบบหน้าเว็บเปลี่ยนไป กรุณาโหลดข้อมูลใหม่หรืออัปเดตแอปก่อนบันทึกอีกครั้ง');
          }
          // Exact fallback replay is a no-op on styling. Omit it from the atomic
          // write just like a legacy request without appearance. Known classic
          // IDs and distinct legacy themes remain explicit replacements;
          // catalog 2 clients can explicitly clear templateId with null.
          publishInput = { ...input, appearance: undefined };
        }
        const appearance = publishInput.appearance ?? storedAppearance;
        if (appearance.logoKey || appearance.coverKey || appearance.background.imageKey) {
          if (!options.validateImages) throw new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'ระบบรูปหน้าโปรไฟล์ยังไม่พร้อม กรุณานำรูปออกก่อนเผยแพร่');
        }
        const releaseImages = await options.validateImages?.(user.id, appearance);
        imageGuard.release = typeof releaseImages === 'function' ? releaseImages : undefined;
        // Omitted appearance remains omitted at the atomic store update, so an
        // older client cannot overwrite a concurrent appearance customization.
        return store.publish({ ...publishInput, userId: user.id });
      };
      // The same image-owner guard protects pruning and this validate/write
      // boundary. Cleanup below runs after release to avoid a nested lock.
      const profile = options.withImageMutation
        ? await options.withImageMutation(user.id, commit)
        : await commit();
      // Keep guards after an uncertain write. After a confirmed commit, SQL
      // pruning also checks the persisted profile before claiming an image.
      try { await imageGuard.release?.(); } catch { /* Publication is already accepted. */ }
      // A cleanup failure after the commit cannot change publication success.
      try { await options.onPublished?.(user.id, profile); } catch { /* The page is already committed. */ }
      response.json({ status: 'ok', profile: profileForClient(profile, supportsCurrentProfileCatalog(request)) });
    } catch (error) { respondError(response, error); }
  });
  router.delete('/link-in-bio/publish', authMiddleware, async (request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    response.set('Cache-Control', 'no-store');
    try {
      response.json({ status: 'ok', profile: profileForClient(await store.unpublish(user.id), supportsCurrentProfileCatalog(request)) });
    } catch (error) { respondError(response, error); }
  });
  router.get('/p/:slug', async (request, response) => {
    response.set('Cache-Control', 'no-store');
    const slug = request.params.slug;
    if (typeof slug !== 'string' || !slugPattern.test(slug)) { response.status(404).type('text').send('ไม่พบหน้าเว็บร้านค้า'); return; }
    try {
      const profile = await store.getPublishedBySlug(slug);
      if (!profile) { response.status(404).type('text').send('ไม่พบหน้าเว็บร้านค้า'); return; }
      const nonce = randomBytes(18).toString('base64');
      response.set('Content-Security-Policy', `default-src 'none'; script-src 'none'; style-src 'nonce-${nonce}'; img-src 'self'; font-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'`);
      response.type('html').send(renderLinkInBioPage(profile, nonce));
    } catch (error) { respondError(response, error); }
  });
};
