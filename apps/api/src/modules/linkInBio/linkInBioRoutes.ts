import { randomBytes } from 'node:crypto';
import type { RequestHandler, Response, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import { LinkInBioError, type LinkInBioLink, type LinkInBioProfile, type LinkInBioStore } from './linkInBioStore.js';

const slugPattern = /^(?=.{3,40}$)[a-z0-9]+(?:-[a-z0-9]+)*$/;
const readText = (value: unknown, maximum: number) => {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= maximum ? trimmed : undefined;
};
const readUrl = (value: unknown) => {
  if (typeof value !== 'string' || /[\u0000-\u001f\u007f]/.test(value)) return undefined;
  const url = value.trim();
  if (url.length > 2048 || !/^https?:\/\//i.test(url) || /\s/.test(url)) return undefined;
  try {
    const parsed = new URL(url);
    if (!parsed.hostname || parsed.username || parsed.password || !['https:', 'http:'].includes(parsed.protocol)) return undefined;
    const normalized = parsed.href;
    return normalized.length <= 2048 ? normalized : undefined;
  } catch {
    return undefined;
  }
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
    const url = readUrl(item.url);
    if (!id || !title || !url || ids.has(id)) return undefined;
    ids.add(id);
    links.push({ id, title, url });
  }
  return { storeName, slug, links };
};

const escapeHtml = (value: string) => value.replace(/[&<>"']/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
})[character]!);

const renderPage = (profile: LinkInBioProfile, nonce: string) => `<!doctype html>
<html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer"><title>${escapeHtml(profile.storeName)} | PostDee</title>
<style nonce="${nonce}">
*{box-sizing:border-box}body{margin:0;background:#fff8ef;color:#253529;font-family:system-ui,-apple-system,sans-serif;line-height:1.6}
main{width:min(100% - 32px,520px);margin:48px auto;padding:32px 24px;border:1px solid #eadfcb;border-radius:24px;background:#fff}
.brand{color:#537844;font-size:14px;font-weight:700;letter-spacing:1px}h1{font-size:28px;line-height:1.4;overflow-wrap:anywhere;margin:16px 0 8px}
p{color:#687065;margin:0 0 28px}ul{list-style:none;padding:0;margin:0;display:grid;gap:12px}a{display:block;border-radius:14px;background:#305d36;color:#fff;padding:16px 20px;text-decoration:none;font-weight:600;overflow-wrap:anywhere}
a:hover{background:#254d2b}a:focus-visible{outline:3px solid #d5a22f;outline-offset:4px}footer{text-align:center;font-size:12px;color:#687065;margin-top:28px}
@media(max-width:400px){main{margin:24px auto;padding:24px 18px}h1{font-size:24px}}
</style></head><body><main><div class="brand">PostDee</div><h1>${escapeHtml(profile.storeName)}</h1>
<p>เลือกช่องทางที่ต้องการได้เลย</p><ul>${profile.links.map((link) => `<li><a href="${escapeHtml(link.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(link.title)}</a></li>`).join('')}</ul>
<footer>สร้างหน้าเว็บร้านค้าด้วย PostDee</footer></main></body></html>`;

const respondError = (response: Response, error: unknown) => {
  const known = error instanceof LinkInBioError;
  response.status(known ? error.statusCode : 503).json({
    status: 'error',
    code: known ? error.code : 'LINK_IN_BIO_UNAVAILABLE',
    message: known ? error.message : 'ระบบหน้าเว็บร้านค้ายังไม่พร้อม กรุณาลองใหม่ภายหลัง'
  });
};

export const registerLinkInBioRoutes = (
  router: Router, authMiddleware: RequestHandler, store: LinkInBioStore, userStore?: UserStore
) => {
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
      response.json({ status: 'ok', profile: await store.publish({ ...input, userId: user.id }) });
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
      response.set('Content-Security-Policy', `default-src 'none'; script-src 'none'; style-src 'nonce-${nonce}'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'`);
      response.type('html').send(renderPage(profile, nonce));
    } catch (error) { respondError(response, error); }
  });
};
