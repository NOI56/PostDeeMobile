import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { validateProfileTemplateCatalog, generateProfileTemplateTypeScript, generateProfileTemplateDart } from './generate-profile-templates.mjs';

const source = JSON.parse(await readFile(new URL('../shared/profile-templates.json', import.meta.url), 'utf8'));
test('authored catalog contains exactly one hundred valid, distinct templates', () => {
  assert.equal(validateProfileTemplateCatalog(source).templates.length, 100);
  assert.match(generateProfileTemplateTypeScript(source), /getProfileTemplate/);
  assert.match(generateProfileTemplateDart(source), /ProfileTemplatePalette/);
});
test('each category exposes twenty distinct page compositions with the three agreed references first', () => {
  const representatives = {
  "minimal": [
    "editorial",
    "bicolor",
    "portrait"
  ],
  "cute": [
    "scallop",
    "collage",
    "window"
  ],
  "nature": [
    "botanical",
    "glass",
    "torn"
  ],
  "luxury": [
    "seal",
    "tag",
    "gallery"
  ],
  "creative": [
    "poster",
    "window-grid",
    "ticket"
  ]
};
  const compositions = ["editorial","bicolor","portrait","scallop","collage","window","botanical","glass","torn","seal","tag","gallery","poster","window-grid","ticket","rail","ribbon","notebook","arch","staircase"];
  for (const category of source.categories) {
    const templates = source.templates.filter((template) => template.category === category.id);
    assert.deepEqual(templates.slice(0, 3).map((template) => template.layout.composition), representatives[category.id]);
    assert.deepEqual(templates.map((template) => template.layout.composition).sort(), [...compositions].sort());
  }
  assert.match(generateProfileTemplateTypeScript(source), /export type ProfileTemplateComposition/);
  assert.match(generateProfileTemplateDart(source), /final String composition;/);
});

test('bicolor and scallop keep the accepted hairline links with readable surface text', () => {
  const templates = source.templates.filter((template) => ['bicolor', 'scallop'].includes(template.layout.composition));
  assert.equal(templates.length, 10);
  for (const template of templates) {
    assert.equal(template.layout.button, 'outline', template.id);
    assert.equal(template.palette.button, template.palette.category, template.id);
    assert.equal(template.palette.buttonText, template.palette.name, template.id);
  }
});

test('poster and collage default text remains readable on their pastel link cycle', () => {
  const templates = source.templates.filter((template) => ['poster', 'collage'].includes(template.layout.composition));
  assert.equal(templates.length, 10);
  for (const template of templates) {
    assert.equal(template.palette.button, template.id === 'creative-yellow-pop' ? '#ff6a48' : template.palette.gradient, template.id);
    assert.equal(template.palette.buttonText, template.palette.name, template.id);
  }
});

test('the accepted forest glass base keeps white page text and light link buttons', () => {
  const template = source.templates.find((entry) => entry.id === 'nature-greenhouse');
  assert.equal(template.layout.composition, 'glass');
  for (const field of ['background', 'gradient', 'surface']) assert.equal(template.palette[field], '#182a16');
  for (const field of ['name', 'description', 'category', 'brand']) assert.equal(template.palette[field], '#ffffff');
  assert.equal(template.palette.button, '#edf3e9');
  assert.equal(template.palette.buttonText, '#203522');
  assert.equal(template.font, 'anuphan');
  assert.equal(template.effects.background, false);
});

test('the accepted mint window and minimal bases retain their panel colors and square buttons', () => {
  const window = source.templates.find((template) => template.id === 'cute-candy-box');
  assert.equal(window.palette.background, '#e8f4ec');
  assert.equal(window.palette.gradient, '#e5dbf7');
  assert.equal(window.palette.surface, '#ffffff');
  assert.equal(window.palette.button, '#f8d4e1');
  assert.equal(window.palette.buttonText, window.palette.name);
  for (const id of ['minimal-mono-pair', 'minimal-clean-cover']) {
    assert.equal(source.templates.find((template) => template.id === id).buttonRadius, 'square', id);
  }
});

test('the accepted creative window and ticket keep their distinct frame and page colors', () => {
  const window = source.templates.find((template) => template.id === 'creative-play-blocks');
  assert.equal(window.palette.background, '#fff9e6');
  assert.equal(window.palette.gradient, '#b18df4');
  assert.equal(window.palette.surface, '#d9f9b9');
  assert.equal(window.palette.button, '#d2bfff');
  assert.equal(window.palette.buttonText, '#1d1b21');
  const ticket = source.templates.find((template) => template.id === 'creative-retro-cover');
  assert.equal(ticket.palette.background, '#8fd3f4');
  assert.equal(ticket.palette.gradient, '#8fd3f4');
  assert.equal(ticket.palette.surface, '#ff7458');
  assert.equal(ticket.palette.button, '#fff9e6');
  assert.equal(ticket.palette.buttonText, '#171717');
  assert.equal(ticket.buttonRadius, 'rounded');
});

test('the accepted scrapbook base keeps square paper-card corners as its editable default', () => {
  const template = source.templates.find((entry) => entry.id === 'cute-sticker-layers');
  assert.equal(template.layout.composition, 'collage');
  assert.equal(template.buttonRadius, 'square');
});

test('retains every previously published template ID so saved pages keep their selection', () => {
  const publishedIds = [
  "creative-blue-pair",
  "creative-collage-grid",
  "creative-color-cabinet",
  "creative-color-patches",
  "creative-comic-panels",
  "creative-contrast-cards",
  "creative-fun-frame",
  "creative-ink-frame",
  "creative-marker-notes",
  "creative-modern-layers",
  "creative-neon-blocks",
  "creative-orange-seal",
  "creative-play-blocks",
  "creative-pop-ring",
  "creative-pop-sunday",
  "creative-retro-cover",
  "creative-stacked-posters",
  "creative-vivid-lines",
  "creative-yellow-pop",
  "creative-yellow-studio",
  "cute-bow-box",
  "cute-candy-box",
  "cute-candy-pop",
  "cute-cherry-cream",
  "cute-cotton-clouds",
  "cute-doll-cabinet",
  "cute-flower-petals",
  "cute-gift-cards",
  "cute-heart-seal",
  "cute-love-letter",
  "cute-marshmallow-cards",
  "cute-paper-hearts",
  "cute-pastel-picnic",
  "cute-pink-notebook",
  "cute-soft-bakery",
  "cute-sticker-layers",
  "cute-sugar-gems",
  "cute-sweet-postcard",
  "cute-thin-ribbon",
  "cute-tiny-friends",
  "luxury-black-gallery",
  "luxury-black-studio",
  "luxury-brass-frame",
  "luxury-champagne-lines",
  "luxury-emerald-room",
  "luxury-gem-box",
  "luxury-gold-lines",
  "luxury-gold-seal",
  "luxury-ink-cards",
  "luxury-jewel-cabinet",
  "luxury-marble-shelf",
  "luxury-onyx-seal",
  "luxury-paired-monogram",
  "luxury-pearl-box",
  "luxury-platinum-cards",
  "luxury-premium-album",
  "luxury-premium-seal",
  "luxury-silver-signature",
  "luxury-velvet-cards",
  "luxury-wine-grid",
  "minimal-clean-cover",
  "minimal-daily-studio",
  "minimal-easy-grid",
  "minimal-fine-lines",
  "minimal-layered-note",
  "minimal-light-cards",
  "minimal-little-spaces",
  "minimal-mono-pair",
  "minimal-open-shelf",
  "minimal-pebble-tiles",
  "minimal-picture-frame",
  "minimal-pocket-board",
  "minimal-quiet-blocks",
  "minimal-side-lines",
  "minimal-signature-cards",
  "minimal-simple-ring",
  "minimal-stacked-paper",
  "minimal-studio-seal",
  "minimal-white-editorial",
  "minimal-white-paper",
  "nature-clay-pots",
  "nature-craft-studio",
  "nature-flower-shelf",
  "nature-forest-postcard",
  "nature-garden-basket",
  "nature-garden-veranda",
  "nature-grass-lines",
  "nature-greenhouse",
  "nature-herbal-tea",
  "nature-leaf-cards",
  "nature-leaf-pair",
  "nature-leaf-seal",
  "nature-linen-frame",
  "nature-little-wreath",
  "nature-morning-garden",
  "nature-olive-garden",
  "nature-paper-fibers",
  "nature-pressed-notebook",
  "nature-wood-layers",
  "nature-wooden-desk"
];
  assert.deepEqual(source.templates.map((template) => template.id).sort(), publishedIds);
});
for (const [label, mutate] of [
  ['missing category', (value) => value.categories.pop()],
  ['duplicate ID', (value) => { value.templates[1].id = value.templates[0].id; }],
  ['missing template', (value) => value.templates.pop()],
  ['unknown category', (value) => { value.templates[0].category = 'unknown'; }],
  ['invalid header', (value) => { value.templates[0].layout.header = 'injected'; }],
  ['missing composition', (value) => { delete value.templates[0].layout.composition; }],
  ['unknown composition', (value) => { value.templates[0].layout.composition = 'injected'; }],
  ['repeated page composition', (value) => { value.templates[1].layout.composition = value.templates[0].layout.composition; }],
  ['invalid color', (value) => { value.templates[0].palette.name = 'red;display:none'; }],
  ['unreadable default text', (value) => { value.templates[0].palette.description = '#ffffff'; }],
  ['unreadable button text', (value) => { value.templates[0].palette.buttonText = value.templates[0].palette.surface; }],
  ['invalid font', (value) => { value.templates[0].font = 'remote-font'; }],
  ['invalid effect', (value) => { value.templates[0].effects.stickers = 'injected'; }],
]) {
  test(`rejects ${label}`, () => {
    const changed = structuredClone(source);
    mutate(changed);
    assert.throws(() => validateProfileTemplateCatalog(changed));
  });
}
