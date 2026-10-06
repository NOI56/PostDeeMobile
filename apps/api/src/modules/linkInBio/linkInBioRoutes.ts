import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import type { RequestHandler, Response, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import { LinkInBioError, type LinkInBioLink, type LinkInBioProfile, type LinkInBioStore } from './linkInBioStore.js';
import { linkInBioFonts, linkInBioIcons, normalizeStoredLinkInBioAppearance, readLinkInBioAppearance, readLinkInBioColor, type LinkInBioAppearance, type LinkInBioFont, type LinkInBioIcon } from './linkInBioAppearance.js';
import { renderLinkInBioPage } from './linkInBioRenderer.js';
import { linkInBioPlatformLogoFiles } from './linkInBioPlatformLogos.js';
import { readLinkInBioUrl } from './linkInBioDestinations.js';

export type LinkInBioRouteOptions = {
  validateImages?: (userId: string, appearance: LinkInBioAppearance) => Promise<void>;
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

export const registerLinkInBioRoutes = (
  router: Router, authMiddleware: RequestHandler, store: LinkInBioStore, userStore?: UserStore,
  options: LinkInBioRouteOptions = {}
) => {
  router.get('/profile-platforms/:file', (request, response) => {
    const file = request.params.file;
    if (typeof file !== 'string' || !Object.values(linkInBioPlatformLogoFiles).includes(file)) { response.status(404).end(); return; }
    response.set('Cache-Control', 'public, max-age=86400').set('X-Content-Type-Options', 'nosniff').type('image/png')
      .sendFile(fileURLToPath(new URL(`../../../assets/profile-platforms/${file}`, import.meta.url)), { dotfiles: 'allow' });
  });
  router.use('/link-in-bio', (_request, response, next) => {
    response.set('Cache-Control', 'no-store');
    next();
  });
  router.get('/link-in-bio', authMiddleware, async (_request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    response.set('Cache-Control', 'no-store');
    try {
      response.json({ status: 'ok', profile: await store.getForUser(user.id) });
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
      await userStore?.ensure(user);
      const commit = async () => {
        const appearance = input.appearance ?? normalizeStoredLinkInBioAppearance((await store.getForUser(user.id))?.appearance, input.links);
        if (appearance.logoKey || appearance.coverKey || appearance.background.imageKey) {
          if (!options.validateImages) throw new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'ระบบรูปหน้าโปรไฟล์ยังไม่พร้อม กรุณานำรูปออกก่อนเผยแพร่');
        }
        await options.validateImages?.(user.id, appearance);
        // Omitted appearance remains omitted at the atomic store update, so an
        // older client cannot overwrite a concurrent appearance customization.
        return store.publish({ ...input, userId: user.id });
      };
      // The same image-owner guard protects pruning and this validate/write
      // boundary. Cleanup below runs after release to avoid a nested lock.
      const profile = options.withImageMutation
        ? await options.withImageMutation(user.id, commit)
        : await commit();
      // A cleanup failure after the commit cannot change publication success.
      try { await options.onPublished?.(user.id, profile); } catch { /* The page is already committed. */ }
      response.json({ status: 'ok', profile });
    } catch (error) { respondError(response, error); }
  });
  router.delete('/link-in-bio/publish', authMiddleware, async (_request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    response.set('Cache-Control', 'no-store');
    try {
      response.json({ status: 'ok', profile: await store.unpublish(user.id) });
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
