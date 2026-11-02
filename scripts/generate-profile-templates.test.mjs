import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import { validateProfileTemplateCatalog, generateProfileTemplateTypeScript, generateProfileTemplateDart } from './generate-profile-templates.mjs';

const source = JSON.parse(await readFile(new URL('../shared/profile-templates.json', import.meta.url), 'utf8'));
test('authored catalog adds twenty 3D and ten cartoon templates to the existing one hundred', () => {
  assert.equal(source.version, 4);
  assert.equal(validateProfileTemplateCatalog(source).templates.length, 130);
  assert.deepEqual(source.categories.map((category) => category.id), ['minimal', 'cute', 'nature', 'luxury', 'creative', 'dimensional', 'cartoon']);
  assert.match(generateProfileTemplateTypeScript(source), /export const profileTemplateCatalogVersion = 4/);
  assert.match(generateProfileTemplateDart(source), /const profileTemplateCatalogVersion = 4/);
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
  for (const category of source.categories.filter((category) => !['dimensional', 'cartoon'].includes(category.id))) {
    const templates = source.templates.filter((template) => template.category === category.id);
    assert.deepEqual(templates.slice(0, 3).map((template) => template.layout.composition), representatives[category.id]);
    assert.deepEqual(templates.map((template) => template.layout.composition).sort(), [...compositions].sort());
  }
  assert.match(generateProfileTemplateTypeScript(source), /export type ProfileTemplateComposition/);
  assert.match(generateProfileTemplateDart(source), /final String composition;/);
});

test('the first 3D release keeps four clay, three paper and three glass designs', () => {
  const dimensional = source.templates.filter((template) => template.category === 'dimensional' && template.since === undefined);
  assert.equal(dimensional.length, 10);
  assert.equal(new Set(dimensional.map((template) => template.name)).size, 10);
  assert.deepEqual(['clay', 'paper-stack', 'frosted'].map((composition) => dimensional.filter((template) => template.layout.composition === composition).length), [4, 3, 3]);
  assert.ok(dimensional.every((template) => template.themeId === 'minimal'));
});

test('the second 3D release adds ten scenes on five new layouts after the first ten', () => {
  const dimensional = source.templates.filter((template) => template.category === 'dimensional');
  assert.equal(dimensional.length, 20);
  assert.equal(new Set(dimensional.map((template) => template.name)).size, 20);
  const added = dimensional.slice(10);
  assert.ok(added.every((template) => template.since === 3 && template.themeId === 'minimal'));
  assert.ok(dimensional.slice(0, 10).every((template) => template.since === undefined));
  assert.deepEqual(['showcase', 'split-art', 'tile-grid', 'neon', 'slab'].map((composition) => added.filter((template) => template.layout.composition === composition).length), [3, 2, 2, 1, 2]);
  assert.ok(added.every((template) => !['clay', 'paper-stack', 'frosted'].includes(template.layout.composition)));
  assert.match(generateProfileTemplateTypeScript(source), /since\?: 3 \| 4/);
});

test('the cartoon release adds ten original designs on five cartoon layouts', () => {
  const cartoon = source.templates.filter((template) => template.category === 'cartoon');
  assert.equal(source.categories.at(-1).name, 'การ์ตูน');
  assert.deepEqual(cartoon.map((template) => template.id), [
    'cartoon-doodle-shop', 'cartoon-comic-panels', 'cartoon-tag-buddy', 'cartoon-sticker-sheet', 'cartoon-chalkboard',
    'cartoon-street-front', 'cartoon-chat-bubbles', 'cartoon-signposts', 'cartoon-crayon-sky', 'cartoon-rocket-night'
  ]);
  assert.deepEqual(source.templates.slice(120).map((template) => template.category), Array(10).fill('cartoon'));
  assert.equal(new Set(cartoon.map((template) => template.name)).size, 10);
  assert.ok(cartoon.every((template) => template.since === 4 && template.themeId === 'minimal'));
  assert.deepEqual(['banner', 'beside', 'signboard', 'panels', 'chat'].map((composition) => cartoon.filter((template) => template.layout.composition === composition).length), [5, 2, 1, 1, 1]);
  assert.ok(cartoon.every((template) => template.effects.stickers === 'none' && template.effects.background === false));
  assert.match(generateProfileTemplateTypeScript(source), /'cartoon'/);
  assert.match(generateProfileTemplateTypeScript(source), /'signboard'/);
});

test('cartoon layouts stay inside their category and every cartoon design names its release', () => {
  const borrowed = structuredClone(source);
  borrowed.templates[120].layout.composition = 'showcase';
  assert.throws(() => validateProfileTemplateCatalog(borrowed), /composition does not belong/);
  const leaked = structuredClone(source);
  leaked.templates[0].layout.composition = 'banner';
  assert.throws(() => validateProfileTemplateCatalog(leaked), /composition does not belong/);
  const unmarked = structuredClone(source);
  delete unmarked.templates[120].since;
  assert.throws(() => validateProfileTemplateCatalog(unmarked), /release marker/);
  const older = structuredClone(source);
  older.templates[120].since = 3;
  assert.throws(() => validateProfileTemplateCatalog(older), /release marker/);
});

test('catalog release markers stay on templates added after release 2', () => {
  const marked = structuredClone(source);
  marked.templates[0].since = 3;
  assert.throws(() => validateProfileTemplateCatalog(marked), /release marker/);
  const borrowed = structuredClone(source);
  borrowed.templates[119].since = 4;
  assert.throws(() => validateProfileTemplateCatalog(borrowed), /release marker/);
  const future = structuredClone(source);
  future.templates[129].since = 5;
  assert.throws(() => validateProfileTemplateCatalog(future), /release marker/);
});

test('all existing published template values and their order remain unchanged', () => {
  const legacy = source.templates.filter((template) => !['dimensional', 'cartoon'].includes(template.category));
  assert.equal(createHash('sha256').update(JSON.stringify(legacy)).digest('hex'), 'dbb85250b867a68d924d15968835bed51238434a260690d33e14ef9716f96756');
  // The first 3D release (catalog 2) is also frozen for saved pages.
  assert.equal(createHash('sha256').update(JSON.stringify(source.templates.slice(0, 110))).digest('hex'), '73e4332758fc7785a9a18d3a5f9b0ad682a1c6cb02724c18991b30190c5d61d4');
  // Catalog 3 (both 3D releases) is frozen too; cartoon designs are appended.
  assert.equal(createHash('sha256').update(JSON.stringify(source.templates.slice(0, 120))).digest('hex'), '8ede8e0242d40a9d9204403d05c62e73688e0b0b4ec47b510ac05b437b78f940');
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
  assert.deepEqual(source.templates.filter((template) => !['dimensional', 'cartoon'].includes(template.category)).map((template) => template.id).sort(), publishedIds);
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
