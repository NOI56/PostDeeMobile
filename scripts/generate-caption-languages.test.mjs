import assert from 'node:assert/strict';
import { readFile, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import {
  validateCaptionLanguageCatalog,
  generateCaptionLanguageTypeScript,
  generateCaptionLanguageDart,
  runCaptionLanguageGenerator,
} from './generate-caption-languages.mjs';

const source = JSON.parse(await readFile(new URL('../shared/caption-languages.json', import.meta.url), 'utf8'));

test('catalog contains 109 distinct documented text languages and preserves existing choices', () => {
  assert.equal(validateCaptionLanguageCatalog(source).languages.length, 109);
  assert.equal(new Set(source.languages.map(({ code }) => code)).size, 109);
  const legacy = {
    th: 'ไทย', en: 'English', zh: '中文', ja: '日本語', ko: '한국어',
    vi: 'Tiếng Việt', id: 'Bahasa Indonesia', ms: 'Bahasa Melayu', lo: 'ລາວ',
    km: 'ខ្មែរ', my: 'မြန်မာ', es: 'Español', fr: 'Français', de: 'Deutsch',
    pt: 'Português', ar: 'العربية', hi: 'हिन्दी',
  };
  for (const [code, nativeName] of Object.entries(legacy)) {
    assert.equal(source.languages.find((row) => row.code === code)?.nativeName, nativeName);
  }
  assert.equal(source.languages.filter(({ code }) => code.startsWith('zh')).length, 1);
  assert.equal(source.languages.some(({ code }) => code === 'auto'), false);
  assert.deepEqual(source.languages.find(({ code }) => code === 'he').aliases, ['iw']);
  assert.deepEqual(source.languages.find(({ code }) => code === 'fil').aliases, ['tl']);
  assert.deepEqual(source.languages.find(({ code }) => code === 'mni-Mtei').scripts, ['Meetei_Mayek']);
});

test('all native, English and Thai labels contain meaningful text', () => {
  for (const language of source.languages) {
    for (const field of ['nativeName', 'englishName', 'thaiName']) {
      assert.ok(language[field].trim().length > 1, `${language.code}: ${field}`);
      assert.notEqual(language[field], language.code);
      assert.doesNotMatch(language[field], /undefined|\ufffd/u);
    }
    assert.match(language.thaiName, /\p{Script=Thai}/u);
  }
});

test('script metadata allows legitimate multiple scripts instead of assuming Latin', () => {
  const scripts = (code) => source.languages.find((language) => language.code === code).scripts;
  assert.deepEqual(scripts('he'), ['Hebrew']);
  for (const script of ['Cyrillic', 'Latin']) assert.ok(scripts('sr').includes(script));
  for (const script of ['Latin', 'Cyrillic', 'Arabic']) assert.ok(scripts('uz').includes(script));
  for (const script of ['Gurmukhi', 'Arabic']) assert.ok(scripts('pa').includes(script));
  for (const script of ['Arabic', 'Devanagari']) assert.ok(scripts('sd').includes(script));
  for (const script of ['Cyrillic', 'Mongolian']) assert.ok(scripts('mn').includes(script));
});

for (const [label, mutate, error] of [
  ['missing language', (value) => value.languages.pop(), /109 languages/],
  ['duplicate code', (value) => { value.languages[1].code = value.languages[0].code; }, /duplicate.*code/i],
  ['missing code', (value) => { delete value.languages[0].code; }, /code/],
  ['automatic entry', (value) => { value.languages[0].code = 'auto'; }, /code/],
  ['missing label', (value) => { delete value.languages[0].thaiName; }, /thaiName/],
  ['fallback code label', (value) => { value.languages[0].nativeName = value.languages[0].code; }, /nativeName/],
  ['native label from unrelated default locale', (value) => { value.languages.find(({ code }) => code === 'he').nativeName = 'ฮีบรู'; }, /nativeName.*script/],
  ['malformed alias', (value) => { value.languages[0].aliases = ['../en']; }, /alias/],
  ['duplicate alias', (value) => { value.languages[0].aliases = ['aa', 'aa']; }, /alias/],
  ['alias colliding with canonical code', (value) => { value.languages[0].aliases = ['en']; }, /alias/],
  ['alias colliding with another alias', (value) => { value.languages[0].aliases = ['iw']; }, /alias/],
  ['missing aliases', (value) => { delete value.languages[0].aliases; }, /aliases/],
  ['invalid script', (value) => { value.languages[0].scripts = ['Imaginary_Script']; }, /script/],
  ['missing scripts', (value) => { value.languages[0].scripts = []; }, /script/],
  ['duplicate scripts', (value) => { value.languages[0].scripts = ['Latin', 'Latin']; }, /script/],
  ['missing source', (value) => { delete value.source; }, /source/],
  ['speech scope', (value) => { value.source.scope = 'all-audio-languages'; }, /text scope/],
  ['invalid source date', (value) => { value.source.updated = '2026-02-31'; }, /date/],
  ['incorrect documented count', (value) => { value.source.documentedLanguageCount = 110; }, /109/],
]) {
  test(`rejects ${label}`, () => {
    const changed = structuredClone(source);
    mutate(changed);
    assert.throws(() => validateCaptionLanguageCatalog(changed), error);
  });
}

test('API and Dart generation preserve aliases and script-specific identifiers', () => {
  const ts = generateCaptionLanguageTypeScript(source);
  const dart = generateCaptionLanguageDart(source);
  assert.match(ts, /export const captionLanguageCatalog =/);
  assert.match(ts, /as const;/);
  assert.match(ts, /export type CaptionLanguageCode/);
  assert.match(ts, /Readonly<Record<string, CaptionLanguageCode>>/);
  assert.match(dart, /class CaptionLanguageDetails/);
  assert.match(dart, /const captionLanguageCatalog = <CaptionLanguageDetails>\[/);
  assert.match(dart, /const captionLanguageNativeNames = <String, String>\{/);
  for (const output of [ts, dart]) {
    assert.match(output, /mni-Mtei/);
    assert.match(output, /mni-mtei/);
    assert.match(output, /iw/);
    assert.match(output, /fil/);
  }
});

test('check accepts generated files, rejects drift and never overwrites stale output', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'postdee-caption-catalog-'));
  try {
    const sourceFile = join(directory, 'languages.json');
    const outputFiles = { api: join(directory, 'languages.ts'), mobile: join(directory, 'languages.dart') };
    await writeFile(sourceFile, JSON.stringify(source));
    await runCaptionLanguageGenerator({ sourceFile, outputFiles });
    await runCaptionLanguageGenerator({ check: true, sourceFile, outputFiles });
    await writeFile(outputFiles.mobile, '// stale output\n');
    await assert.rejects(runCaptionLanguageGenerator({ check: true, sourceFile, outputFiles }), /stale/);
    assert.equal(await readFile(outputFiles.mobile, 'utf8'), '// stale output\n');
  } finally {
    await rm(directory, { recursive: true });
  }
});
