import { fileURLToPath } from 'node:url';
import type { RequestHandler, Router, Response } from 'express';
import { readAuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import { LinkInBioError, type LinkInBioStore } from './linkInBioStore.js';
import { isProfileImageSlot, readProfileImageBase64, type LinkInBioImageService } from './linkInBioImageService.js';

const fail = (response: Response, error: unknown) => {
  const known = error instanceof LinkInBioError;
  response.status(known ? error.statusCode : 503).json({ status: 'error',
    code: known ? error.code : 'LINK_IN_BIO_IMAGES_UNAVAILABLE',
    message: known ? error.message : 'ระบบรูปหน้าเว็บยังไม่พร้อม กรุณาลองใหม่ภายหลัง' });
};
const sendImage = (response: Response, bytes: Uint8Array) => {
  response.set('Cache-Control', 'no-store').set('X-Content-Type-Options', 'nosniff').type('image/png').send(Buffer.from(bytes));
};

export const registerLinkInBioImageRoutes = (router: Router, auth: RequestHandler,
  service: LinkInBioImageService, profiles: LinkInBioStore, userStore: UserStore, uploadLimit: RequestHandler) => {
  router.put('/link-in-bio/draft-images', auth, uploadLimit, async (request, response) => {
    response.set('Cache-Control', 'no-store');
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    try {
      await userStore.ensure(user);
      await service.protectDraft(user.id, request.body?.draftId, request.body?.keys, request.body?.mode);
      response.json({ status: 'ok' });
    } catch (error) { fail(response, error); }
  });
  router.post('/link-in-bio/images', auth, uploadLimit, async (request, response) => {
    response.set('Cache-Control', 'no-store');
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    try {
      const slot: unknown = request.body?.slot;
      if (!isProfileImageSlot(slot)) throw new LinkInBioError(400, 'LINK_IN_BIO_IMAGE_INVALID', 'เลือกประเภทของรูปให้ถูกต้อง');
      const bytes = readProfileImageBase64(request.body?.imageBase64);
      const draftId: unknown = request.body?.draftId;
      if (draftId !== undefined && (typeof draftId !== 'string' || !/^[a-zA-Z0-9_-]{8,80}$/.test(draftId))) {
        throw new LinkInBioError(400, 'LINK_IN_BIO_DRAFT_IMAGES_INVALID', 'ข้อมูลรูปแบบร่างไม่ถูกต้อง');
      }
      await userStore.ensure(user);
      const image = await service.upload(user.id, slot, bytes, draftId === undefined);
      response.status(201).json({ status: 'ok', image });
    } catch (error) { fail(response, error); }
  });
  router.get('/link-in-bio/image', auth, async (request, response) => {
    response.set('Cache-Control', 'no-store');
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    const key = request.query.key;
    if (typeof key !== 'string' || key.length > 512) { response.status(404).end(); return; }
    try { sendImage(response, await service.read(key, user.id)); } catch (error) { fail(response, error); }
  });
  router.get('/p/:slug/images/:slot', async (request, response) => {
    response.set('Cache-Control', 'no-store');
    const { slug, slot } = request.params;
    if (typeof slug !== 'string' || !/^(?=.{3,40}$)[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || !isProfileImageSlot(slot)) { response.status(404).end(); return; }
    try {
      const profile = await profiles.getPublishedBySlug(slug);
      const appearance = profile?.appearance;
      const key = slot === 'logo' ? appearance?.logoKey : slot === 'cover' ? appearance?.coverKey : appearance?.background.imageKey;
      if (!key) { response.status(404).end(); return; }
      sendImage(response, await service.read(key));
    } catch (error) { fail(response, error); }
  });
  router.get('/profile-fonts/:file', (request, response) => {
    const file = request.params.file;
    if (typeof file !== 'string' || !/^(?:prompt|anuphan)-(?:regular|semibold)\.ttf$/.test(file)) { response.status(404).end(); return; }
    response.set('Cache-Control', 'public, max-age=86400').type('font/ttf')
      .sendFile(fileURLToPath(new URL(`../../../assets/profile-fonts/${file}`, import.meta.url)), { dotfiles: 'allow' });
  });
};
