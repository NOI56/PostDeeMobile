import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifestFile = resolve(root, 'shared/profile-templates.json');
const generatedFiles = {
  api: resolve(root, 'apps/api/src/modules/linkInBio/profileTemplateCatalog.generated.ts'),
  mobile: resolve(root, 'apps/mobile/lib/core/models/profile_template_catalog.generated.dart'),
};
const categoryIds = ['minimal', 'cute', 'nature', 'luxury', 'creative'];
const paletteFields = ['background', 'gradient', 'surface', 'button', 'name', 'description', 'category', 'buttonText', 'brand'];
const layoutOptions = {
  header: ['centered', 'left', 'split', 'cover', 'badge'],
  links: ['list', 'grid'], button: ['solid', 'outline', 'soft', 'raised'],
  decoration: ['none', 'line', 'dots', 'frame', 'stripe'], avatar: ['circle', 'rounded', 'square'],
};
const requireValue = (condition, message) => { if (!condition) throw new Error(message); };
const text = (value) => typeof value === 'string' && value.length > 0 && !/[\u0000-\u001f\u007f]/.test(value);
const luminance = (hex) => {
  const [red, green, blue] = hex.slice(1).match(/../g).map((channel) => parseInt(channel, 16) / 255)
    .map((channel) => channel <= .04045 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4);
  return red * .2126 + green * .7152 + blue * .0722;
};
const contrast = (foreground, background) => (Math.max(luminance(foreground), luminance(background)) + .05) /
  (Math.min(luminance(foreground), luminance(background)) + .05);

export function validateProfileTemplateCatalog(manifest) {
  requireValue(manifest && manifest.version === 1 && Array.isArray(manifest.categories) && Array.isArray(manifest.templates), 'Expected version 1 profile template catalog');
  requireValue(manifest.categories.length === 5 && manifest.categories.every((category, index) => category.id === categoryIds[index] && text(category.name)), 'Expected the five agreed template categories');
  requireValue(manifest.templates.length === 100, 'Expected exactly 100 profile templates');
  const ids = new Set();
  for (const template of manifest.templates) {
    requireValue(template && categoryIds.includes(template.category) && text(template.name) && template.name.length <= 80, 'Invalid template category or name');
    requireValue(typeof template.id === 'string' && /^[a-z][a-z\d-]{0,79}$/.test(template.id) && template.id.startsWith(`${template.category}-`) && !ids.has(template.id), `Invalid or duplicate template ID: ${template.id}`);
    ids.add(template.id);
    requireValue(['minimal', 'shop', 'pastel', 'dark', 'pink', 'garden', 'cards'].includes(template.themeId), `${template.id}: invalid fallback theme`);
    for (const [field, options] of Object.entries(layoutOptions)) requireValue(options.includes(template.layout?.[field]), `${template.id}: invalid layout ${field}`);
    for (const field of paletteFields) requireValue(typeof template.palette?.[field] === 'string' && /^#[a-f\d]{6}$/.test(template.palette[field]), `${template.id}: invalid palette ${field}`);
    const palette = template.palette;
    const backgrounds = [palette.background, palette.gradient, palette.surface];
    for (const field of ['name', 'description', 'category', 'brand']) {
      requireValue(backgrounds.every((background) => contrast(palette[field], background) >= 4.5), `${template.id}: default ${field} text needs readable contrast`);
    }
    // Outline buttons use buttonColor as their border and have a transparent
    // fill. Check their text against the surface, not against the border.
    const buttonBackgrounds = template.layout.button === 'outline' ? backgrounds : [palette.button];
    requireValue(buttonBackgrounds.every((background) => contrast(palette.buttonText, background) >= 4.5), `${template.id}: default button text needs readable contrast`);
    requireValue(['anuphan', 'prompt', 'system'].includes(template.font), `${template.id}: invalid font`);
    requireValue(['rounded', 'pill', 'square'].includes(template.buttonRadius), `${template.id}: invalid radius`);
    for (const field of ['background', 'entrance', 'featured']) requireValue(typeof template.effects?.[field] === 'boolean', `${template.id}: invalid effect ${field}`);
    requireValue(['none', 'hearts', 'flowers', 'sparkles'].includes(template.effects?.stickers), `${template.id}: invalid stickers`);
  }
  for (const category of categoryIds) {
    const templates = manifest.templates.filter((template) => template.category === category);
    requireValue(templates.length === 20, `${category}: expected twenty templates`);
    requireValue(new Set(templates.map((template) => template.name)).size === 20, `${category}: template names must differ`);
    requireValue(new Set(templates.map((template) => `${template.layout.header}/${template.layout.links}/${template.layout.button}`)).size === 20, `${category}: expected twenty distinct header/link/button combinations`);
  }
  return manifest;
}

export function generateProfileTemplateTypeScript(manifest) {
  return `// Generated from shared/profile-templates.json by scripts/generate-profile-templates.mjs.\n// Do not edit; maintain the authored source catalog and regenerate both clients.\n\nexport type ProfileTemplateCategoryId = 'minimal' | 'cute' | 'nature' | 'luxury' | 'creative';\nexport type ProfileTemplateLayout = {\n  header: 'centered' | 'left' | 'split' | 'cover' | 'badge';\n  links: 'list' | 'grid';\n  button: 'solid' | 'outline' | 'soft' | 'raised';\n  decoration: 'none' | 'line' | 'dots' | 'frame' | 'stripe';\n  avatar: 'circle' | 'rounded' | 'square';\n};\nexport type ProfileTemplatePalette = { ${paletteFields.map((field) => `${field}: string`).join('; ')} };\nexport type ProfileTemplateDefinition = {\n  id: string; name: string; category: ProfileTemplateCategoryId;\n  themeId: 'minimal' | 'shop' | 'pastel' | 'dark' | 'pink' | 'garden' | 'cards';\n  layout: ProfileTemplateLayout; palette: ProfileTemplatePalette;\n  font: 'anuphan' | 'prompt' | 'system'; buttonRadius: 'rounded' | 'pill' | 'square';\n  effects: { background: boolean; entrance: boolean; featured: boolean; stickers: 'none' | 'hearts' | 'flowers' | 'sparkles' };\n};\n\nexport const profileTemplateCategories: readonly { id: ProfileTemplateCategoryId; name: string }[] = ${JSON.stringify(manifest.categories, null, 2)};\n\nexport const profileTemplates: readonly ProfileTemplateDefinition[] = ${JSON.stringify(manifest.templates, null, 2)};\n\nconst templatesById = new Map(profileTemplates.map((template) => [template.id, template]));\nexport const getProfileTemplate = (id: string | null | undefined): ProfileTemplateDefinition | undefined => typeof id === 'string' ? templatesById.get(id) : undefined;\n`;
}

const dartString = (value) => `'${value.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;
export function generateProfileTemplateDart(manifest) {
  const definitions = manifest.templates.map((template) => `  ProfileTemplate(\n    id: ${dartString(template.id)}, name: ${dartString(template.name)},\n    category: ${dartString(template.category)}, themeId: ${dartString(template.themeId)},\n    layout: ProfileTemplateLayout(\n${Object.entries(template.layout).map(([field, value]) => `      ${field}: ${dartString(value)},`).join('\n')}\n    ),\n    palette: ProfileTemplatePalette(\n${paletteFields.map((field) => `      ${field}: ${dartString(template.palette[field])},`).join('\n')}\n    ),\n    font: ${dartString(template.font)}, buttonRadius: ${dartString(template.buttonRadius)},\n    effects: {\n${Object.entries(template.effects).map(([field, value]) => `      ${dartString(field)}: ${typeof value === 'string' ? dartString(value) : value},`).join('\n')}\n    },\n  ),`).join('\n');
  return `// Generated from shared/profile-templates.json by scripts/generate-profile-templates.mjs.\n// Do not edit; maintain the authored source catalog and regenerate both clients.\n\nclass ProfileTemplateLayout {\n  const ProfileTemplateLayout({required this.header, required this.links, required this.button, required this.decoration, required this.avatar});\n  final String header;\n  final String links;\n  final String button;\n  final String decoration;\n  final String avatar;\n}\n\nclass ProfileTemplatePalette {\n  const ProfileTemplatePalette({${paletteFields.map((field) => `required this.${field}`).join(', ')}});\n${paletteFields.map((field) => `  final String ${field};`).join('\n')}\n}\n\nclass ProfileTemplate {\n  const ProfileTemplate({required this.id, required this.name, required this.category, required this.themeId, required this.layout, required this.palette, required this.font, required this.buttonRadius, required this.effects});\n  final String id;\n  final String name;\n  final String category;\n  final String themeId;\n  final ProfileTemplateLayout layout;\n  final ProfileTemplatePalette palette;\n  final String font;\n  final String buttonRadius;\n  final Map<String, Object?> effects;\n}\n\nconst profileTemplateCategories = <String, String>{\n${manifest.categories.map((category) => `  ${dartString(category.id)}: ${dartString(category.name)},`).join('\n')}\n};\n\nconst profileTemplates = <ProfileTemplate>[\n${definitions}\n];\n\nfinal _profileTemplatesById = Map<String, ProfileTemplate>.unmodifiable({\n  for (final template in profileTemplates) template.id: template,\n});\n\nProfileTemplate? getProfileTemplate(String? id) => _profileTemplatesById[id];\n`;
}

export async function runProfileTemplateGenerator({ check = false } = {}) {
  const manifest = validateProfileTemplateCatalog(JSON.parse(await readFile(manifestFile, 'utf8')));
  const outputs = [[generatedFiles.api, generateProfileTemplateTypeScript(manifest)], [generatedFiles.mobile, generateProfileTemplateDart(manifest)]];
  for (const [file, content] of outputs) {
    if (check) {
      const existing = await readFile(file, 'utf8').catch(() => undefined);
      requireValue(typeof existing === 'string' && existing.replace(/\r\n/g, '\n') === content, `Generated template catalog is stale: ${file}. Run node scripts/generate-profile-templates.mjs`);
    } else {
      await writeFile(file, content, 'utf8');
    }
  }
  process.stdout.write(`Validated five categories, 100 templates, unique layouts and ${check ? 'checked' : 'generated'} API/mobile catalog parity.\n`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const args = process.argv.slice(2);
  if (args.some((argument) => argument !== '--check') || args.length > 1) {
    process.stderr.write('Usage: node scripts/generate-profile-templates.mjs [--check]\n');
    process.exitCode = 1;
  } else {
    await runProfileTemplateGenerator({ check: args.includes('--check') }).catch((error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    });
  }
}
