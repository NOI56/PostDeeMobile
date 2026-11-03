import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

import { premiumScenes } from './scenes.mjs';

const catalog = JSON.parse(await readFile(new URL('../../shared/profile-templates.json', import.meta.url), 'utf8'));
const premiumIds = catalog.templates.filter((template) => template.category === 'premium').map((template) => template.id);
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
const pngSize = (bytes) => [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];

test('there is exactly one picture for each premium catalog design', () => {
  assert.deepEqual(premiumScenes.map((scene) => scene.id), premiumIds);
});

// Copyright-safe artwork: every picture is generated from the shapes in this
// folder. No text or fonts that could carry a brand name, no embedded or
// linked images, and no references outside the SVG itself.
for (const scene of premiumScenes) {
  test(`${scene.id} is self-contained original vector art`, () => {
    const { svg } = scene.draw();
    assert.doesNotMatch(svg, /<(text|tspan|image|use|foreignObject|script|style|font)\b/i);
    assert.doesNotMatch(svg, /font-family|@import|href=/i);
    assert.deepEqual([...svg.matchAll(/https?:\/\/[^"\s]+/g)].map((match) => match[0]), ['http://www.w3.org/2000/svg']);
    for (const [, reference] of svg.matchAll(/url\(([^)]*)\)/g)) assert.match(reference, /^#[a-z][a-zA-Z\d-]*$/, reference);
  });

  test(`${scene.id} draws the same picture every time`, () => {
    assert.equal(scene.draw().svg, scene.draw().svg);
  });

  test(`${scene.id} ships as the same PNG to the public page and the app`, async () => {
    const [api, mobile] = await Promise.all([
      readFile(new URL(`../../apps/api/assets/profile-decorations/${scene.id}.png`, import.meta.url)),
      readFile(new URL(`../../apps/mobile/assets/images/profile_decorations/${scene.id}.png`, import.meta.url)),
    ]);
    assert.equal(hash(api), hash(mobile));
    const { width, height } = scene.draw();
    assert.deepEqual(pngSize(api), [width, height]);
    assert.ok(api.length < 1024 * 1024, `${scene.id} should stay under 1 MB`);
  });
}
