import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import express, { type RequestHandler } from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';

const files = ['botanical-frame', 'forest', 'meadow', 'paper', 'letter-frame', 'collage-tape', 'gold-seal', 'tag-cord',
  'dimensional-clay-mint', 'dimensional-clay-peach', 'dimensional-clay-cloud', 'dimensional-clay-sand',
  'dimensional-paper-fold', 'dimensional-paper-stage', 'dimensional-paper-ribbon',
  'dimensional-glass-lavender', 'dimensional-glass-mist', 'dimensional-glass-sage',
  'dimensional-chrome-night', 'dimensional-lowpoly-dawn', 'dimensional-zen-garden', 'dimensional-wood-blocks',
  'dimensional-parcel-stack', 'dimensional-ceramic-tiles', 'dimensional-pop-shapes', 'dimensional-neon-sign',
  'dimensional-concrete-slab', 'dimensional-terrazzo-steps',
  'cartoon-doodle-shop', 'cartoon-comic-panels', 'cartoon-tag-buddy', 'cartoon-sticker-sheet', 'cartoon-chalkboard',
  'cartoon-street-front', 'cartoon-chat-bubbles', 'cartoon-signposts', 'cartoon-crayon-sky', 'cartoon-rocket-night',
  'cartoon-puppet-stage', 'cartoon-corkboard', 'cartoon-treasure-map', 'cartoon-party-bunting', 'cartoon-jigsaw',
  'cartoon-pixel-land', 'cartoon-rainy-day', 'cartoon-hot-air-balloons', 'cartoon-under-the-sea', 'cartoon-tiny-town'];
const hash = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

describe('bundled profile decoration artwork', () => {
  it.each(files)('serves only bundled %s PNG artwork with mobile parity', async (name) => {
    const app = express();
    const router = express.Router();
    const auth = vi.fn<RequestHandler>((_request, response) => { response.status(401).end(); });
    registerLinkInBioRoutes(router, auth, createInMemoryLinkInBioStore());
    app.use(router);
    const response = await request(app).get(`/profile-decorations/${name}.png`).expect(200).expect('Content-Type', /image\/png/);
    expect(response.headers['cache-control']).toBe('public, max-age=86400');
    expect(response.headers['x-content-type-options']).toBe('nosniff');
    expect(auth).not.toHaveBeenCalled();
    const [api, mobile] = await Promise.all([
      readFile(new URL(`../../../assets/profile-decorations/${name}.png`, import.meta.url)),
      readFile(new URL(`../../../../mobile/assets/images/profile_decorations/${name}.png`, import.meta.url)),
    ]);
    expect(api.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
    expect(hash(response.body)).toBe(hash(api));
    expect(hash(mobile)).toBe(hash(api));
  }, 15000);

  it.each(['unknown.png', 'forest.jpg', 'FOREST.png', 'paper.svg', '..%2Fforest.png', '%2Eenv', 'cartoon-doodle-shop.svg', 'cartoon-unknown.png'])('rejects non-allowlisted asset %s', async (file) => {
    const app = express();
    const router = express.Router();
    registerLinkInBioRoutes(router, (_request, response) => { response.status(401).end(); }, createInMemoryLinkInBioStore());
    app.use(router);
    await request(app).get(`/profile-decorations/${file}`).expect(404);
  });
});
