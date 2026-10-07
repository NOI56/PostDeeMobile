import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import express, { type RequestHandler } from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';

const files = ['botanical-frame', 'forest', 'meadow', 'paper', 'letter-frame', 'collage-tape', 'gold-seal', 'tag-cord'];
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

  it.each(['unknown.png', 'forest.jpg', 'FOREST.png', 'paper.svg', '..%2Fforest.png', '%2Eenv'])('rejects non-allowlisted asset %s', async (file) => {
    const app = express();
    const router = express.Router();
    registerLinkInBioRoutes(router, (_request, response) => { response.status(401).end(); }, createInMemoryLinkInBioStore());
    app.use(router);
    await request(app).get(`/profile-decorations/${file}`).expect(404);
  });
});
