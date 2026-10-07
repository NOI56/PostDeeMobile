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
for (const [label, mutate] of [
  ['missing category', (value) => value.categories.pop()],
  ['duplicate ID', (value) => { value.templates[1].id = value.templates[0].id; }],
  ['missing template', (value) => value.templates.pop()],
  ['unknown category', (value) => { value.templates[0].category = 'unknown'; }],
  ['invalid header', (value) => { value.templates[0].layout.header = 'injected'; }],
  ['repeated structural combination', (value) => { value.templates[1].layout = value.templates[0].layout; }],
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
