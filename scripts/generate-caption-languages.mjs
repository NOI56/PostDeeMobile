import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifestFile = resolve(root, 'shared/caption-languages.json');
const generatedFiles = {
  api: resolve(root, 'apps/api/src/modules/captions/captionLanguages.generated.ts'),
  mobile: resolve(root, 'apps/mobile/lib/core/models/caption_language_catalog.generated.dart'),
};
const sourceUrl = 'https://firebase.google.com/docs/ai-logic/models#supported-languages';
const expectedLanguageCount = 109;
const requireValue = (condition, message) => { if (!condition) throw new Error(message); };
const meaningfulText = (value) => typeof value === 'string' && value.trim().length > 1 &&
  !/[\u0000-\u001f\u007f\ufffd]/u.test(value) && !/^(undefined|null|unknown)$/iu.test(value);
const validDate = (value) => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/u.test(value) &&
  Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
const languageTag = /^[a-z]{2,3}(?:-[A-Z][a-z]{3})?$/u;
const aliasTag = /^[a-z]{2,3}(?:-[a-z\d]{2,8})*$/u;

export function validateCaptionLanguageCatalog(manifest) {
  requireValue(manifest?.version === 1, 'Expected version 1 caption language catalog');
  requireValue(manifest.source?.url === sourceUrl, 'Expected official Google source URL');
  requireValue(manifest.source.scope === 'general-use-text-input-output', 'Expected general-use text scope, not speech coverage');
  requireValue(validDate(manifest.source.updated) && validDate(manifest.source.checked) &&
    manifest.source.updated <= manifest.source.checked, 'Invalid source date');
  requireValue(manifest.source.documentedLanguageCount === expectedLanguageCount, 'Expected 109 documented languages');
  requireValue(Array.isArray(manifest.source.notes) && manifest.source.notes.length > 0 &&
    manifest.source.notes.every(meaningfulText), 'Expected source limitations');
  requireValue(Array.isArray(manifest.languages) && manifest.languages.length === expectedLanguageCount, 'Expected 109 languages');

  const codes = new Set();
  for (const language of manifest.languages) {
    requireValue(typeof language?.code === 'string' && languageTag.test(language.code) && language.code !== 'auto', `Invalid language code: ${language?.code}`);
    requireValue(!codes.has(language.code.toLowerCase()), `Duplicate language code: ${language.code}`);
    codes.add(language.code.toLowerCase());
    for (const field of ['nativeName', 'englishName', 'thaiName']) {
      requireValue(meaningfulText(language[field]) && language[field] !== language.code, `${language.code}: invalid ${field}`);
    }
    requireValue(/\p{Script=Thai}/u.test(language.thaiName), `${language.code}: invalid thaiName`);
    requireValue(Array.isArray(language.scripts) && language.scripts.length > 0 &&
      new Set(language.scripts).size === language.scripts.length, `${language.code}: missing or duplicate scripts`);
    for (const script of language.scripts) {
      requireValue(typeof script === 'string' && /^[A-Z][A-Za-z_]+$/u.test(script), `${language.code}: invalid script`);
      try {
        new RegExp(`\\p{Script=${script}}`, 'u');
      } catch {
        throw new Error(`${language.code}: unsupported Unicode script ${script}`);
      }
    }
    requireValue(language.scripts.some((script) => new RegExp(`\\p{Script=${script}}`, 'u').test(language.nativeName)), `${language.code}: nativeName does not use a declared script`);
    requireValue(Array.isArray(language.aliases), `${language.code}: missing aliases`);
  }

  const aliases = new Set(codes);
  for (const language of manifest.languages) {
    for (const alias of language.aliases) {
      requireValue(typeof alias === 'string' && aliasTag.test(alias) && alias !== 'auto' && !aliases.has(alias), `${language.code}: invalid or colliding alias ${alias}`);
      aliases.add(alias);
    }
  }
  return manifest;
}

const generatedHeader = '// Generated from shared/caption-languages.json by scripts/generate-caption-languages.mjs.\n// Do not edit; maintain the source catalog and regenerate both clients.\n// Text output choices; this catalog does not certify audio recognition coverage.\n';
const aliasEntries = (manifest) => manifest.languages.flatMap(({ code, aliases }) =>
  [code.toLowerCase(), ...aliases].map((alias) => [alias, code]));

export function generateCaptionLanguageTypeScript(manifest) {
  return `${generatedHeader}\nexport const captionLanguageCatalog = ${JSON.stringify(manifest.languages, null, 2)} as const;\n\nexport type CaptionLanguageCode = (typeof captionLanguageCatalog)[number]['code'];\n\nexport const captionLanguageAliases: Readonly<Record<string, CaptionLanguageCode>> = ${JSON.stringify(Object.fromEntries(aliasEntries(manifest)), null, 2)};\n`;
}

const dartString = (value) => `'${value.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;

export function generateCaptionLanguageDart(manifest) {
  const definitions = manifest.languages.map((language) => `  CaptionLanguageDetails(\n    code: ${dartString(language.code)},\n    nativeName: ${dartString(language.nativeName)},\n    englishName: ${dartString(language.englishName)},\n    thaiName: ${dartString(language.thaiName)},\n    aliases: <String>[${language.aliases.map(dartString).join(', ')}],\n  ),`).join('\n');
  const aliases = aliasEntries(manifest).map(([alias, code]) => `  ${dartString(alias)}: ${dartString(code)},`).join('\n');
  const nativeNames = manifest.languages.map(({ code, nativeName }) => `  ${dartString(code)}: ${dartString(nativeName)},`).join('\n');
  return `${generatedHeader}\nclass CaptionLanguageDetails {\n  const CaptionLanguageDetails({\n    required this.code,\n    required this.nativeName,\n    required this.englishName,\n    required this.thaiName,\n    required this.aliases,\n  });\n\n  final String code;\n  final String nativeName;\n  final String englishName;\n  final String thaiName;\n  final List<String> aliases;\n}\n\nconst captionLanguageCatalog = <CaptionLanguageDetails>[\n${definitions}\n];\n\nconst captionLanguageAliases = <String, String>{\n${aliases}\n};\n\nconst captionLanguageNativeNames = <String, String>{\n${nativeNames}\n};\n`;
}

export async function runCaptionLanguageGenerator({ check = false, sourceFile = manifestFile, outputFiles = generatedFiles } = {}) {
  const manifest = validateCaptionLanguageCatalog(JSON.parse(await readFile(sourceFile, 'utf8')));
  const outputs = [
    [outputFiles.api, generateCaptionLanguageTypeScript(manifest)],
    [outputFiles.mobile, generateCaptionLanguageDart(manifest)],
  ];
  // Check all outputs before writing anything. --check is strictly read-only.
  for (const [file, content] of outputs) {
    if (check) {
      const existing = await readFile(file, 'utf8').catch(() => undefined);
      requireValue(typeof existing === 'string' && existing.replace(/\r\n/g, '\n') === content, `Generated caption catalog is stale: ${file}. Run node scripts/generate-caption-languages.mjs`);
    }
  }
  if (!check) {
    for (const [file, content] of outputs) await writeFile(file, content, 'utf8');
  }
  process.stdout.write(`Validated ${manifest.languages.length} caption languages and ${check ? 'checked' : 'generated'} API/mobile catalog parity.\n`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const args = process.argv.slice(2);
  if (args.some((argument) => argument !== '--check') || args.length > 1) {
    process.stderr.write('Usage: node scripts/generate-caption-languages.mjs [--check]\n');
    process.exitCode = 1;
  } else {
    await runCaptionLanguageGenerator({ check: args.includes('--check') }).catch((error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    });
  }
}
