import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inflateSync } from 'node:zlib';

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifestFile = resolve(repositoryRoot, 'shared/profile-platforms.json');
const generatedFiles = {
  api: resolve(repositoryRoot, 'apps/api/src/modules/linkInBio/profilePlatformCatalog.generated.ts'),
  mobile: resolve(repositoryRoot, 'apps/mobile/lib/core/models/profile_platform_catalog.generated.dart')
};
const genericIds = new Set(['auto', 'link', 'website', 'email', 'phone']);
const originalIds = ['youtube', 'shopee', 'lazada', 'line', 'tiktok', 'instagram', 'facebook', 'messenger', 'whatsapp', 'google_maps'];
const text = (value) => typeof value === 'string' && value.length > 0 && !/[\u0000-\u001f\u007f]/.test(value);
const domain = (value) => typeof value === 'string' && value === value.toLowerCase() &&
  value.length <= 253 && value.split('.').length >= 2 && value.split('.').every((label) => /^[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?$/.test(label));
const httpUrl = (value) => {
  if (!text(value) || /\s/.test(value)) return false;
  try {
    const parsed = new URL(value);
    return ['https:', 'http:'].includes(parsed.protocol) && Boolean(parsed.hostname) && !parsed.username && !parsed.password;
  } catch {
    return false;
  }
};
const requireValue = (condition, message) => { if (!condition) throw new Error(message); };

export function validateProfilePlatformCatalog(manifest) {
  requireValue(manifest && manifest.version === 1 && Array.isArray(manifest.platforms), 'Expected version 1 platform catalog');
  requireValue(manifest.platforms.length === 100, 'Catalog must contain exactly 100 brand logos');
  const ids = new Set();
  const files = new Set();
  for (const platform of manifest.platforms) {
    const id = platform?.id;
    requireValue(typeof id === 'string' && /^[a-z][a-z\d_]{0,49}$/.test(id) && !genericIds.has(id), `Invalid brand ID: ${id}`);
    requireValue(!ids.has(id), `Duplicate brand ID: ${id}`);
    ids.add(id);
    requireValue(text(platform.name) && platform.name.length <= 80, `${id}: invalid name`);
    requireValue(text(platform.category), `${id}: invalid category`);
    for (const field of ['aliases', 'regions', 'domains', 'matches']) {
      requireValue(Array.isArray(platform[field]), `${id}: ${field} must be an array`);
    }
    requireValue(platform.aliases.every(text) && platform.regions.length > 0 && platform.regions.every(text), `${id}: invalid search metadata`);
    requireValue(platform.domains.every(domain), `${id}: invalid domain`);
    requireValue(platform.domains.length > 0 || platform.matches.length > 0, `${id}: no destination rule`);
    for (const match of platform.matches) {
      requireValue(match && domain(match.host), `${id}: invalid exact host`);
      requireValue(typeof match.subdomains === 'boolean', `${id}: subdomains must be explicitly true or false`);
      requireValue(typeof match.pathPrefix === 'string' && /^\/[a-zA-Z\d/_-]+$/.test(match.pathPrefix) &&
        !match.pathPrefix.endsWith('/') && !match.pathPrefix.includes('//'), `${id}: invalid path prefix`);
    }
    requireValue(httpUrl(platform.sampleUrl), `${id}: invalid sample URL`);
    const asset = platform.asset;
    requireValue(asset && asset.file === `${id}.png` && !files.has(asset.file), `${id}: asset must be a unique fixed PNG basename`);
    files.add(asset.file);
    requireValue(typeof asset.sha256 === 'string' && /^[a-f\d]{64}$/.test(asset.sha256), `${id}: invalid SHA-256`);
    requireValue(httpUrl(asset.sourceUrl) && httpUrl(asset.licenseUrl), `${id}: missing source or license URL`);
    for (const field of ['sourceWidth', 'sourceHeight', 'left', 'top', 'width', 'height']) {
      requireValue(Number.isInteger(asset[field]), `${id}: ${field} must be an integer`);
    }
    requireValue(asset.sourceWidth > 0 && asset.sourceHeight > 0 && asset.sourceWidth <= 4096 && asset.sourceHeight <= 4096,
      `${id}: invalid source canvas`);
    requireValue(asset.width > 0 && asset.height > 0 && asset.left >= 0 && asset.top >= 0 &&
      asset.left + asset.width <= asset.sourceWidth && asset.top + asset.height <= asset.sourceHeight, `${id}: artwork bounds exceed source canvas`);
  }
  requireValue(originalIds.every((id) => ids.has(id)), 'Catalog must preserve all 10 original brand IDs');
  return manifest.platforms;
}

const paeth = (left, top, previousLeft) => {
  const predicted = left + top - previousLeft;
  const leftDistance = Math.abs(predicted - left);
  const topDistance = Math.abs(predicted - top);
  const previousDistance = Math.abs(predicted - previousLeft);
  return leftDistance <= topDistance && leftDistance <= previousDistance ? left : topDistance <= previousDistance ? top : previousLeft;
};

// Decode only the PNG transparency channel using built-in zlib. Bounds are
// measured from source pixels independently of the catalog's display geometry.
export function readProfilePlatformPngMetrics(png) {
  requireValue(png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])), 'Expected a PNG image');
  requireValue(png.length >= 33 && png.toString('ascii', 12, 16) === 'IHDR', 'PNG header is missing');
  const sourceWidth = png.readUInt32BE(16);
  const sourceHeight = png.readUInt32BE(20);
  const colorType = png[25];
  requireValue(sourceWidth > 0 && sourceHeight > 0 && sourceWidth <= 4096 && sourceHeight <= 4096, 'PNG canvas exceeds audit limits');
  requireValue(png[24] === 8 && png[26] === 0 && png[27] === 0 && png[28] === 0, 'Expected a non-interlaced 8-bit PNG');
  const channels = ({ 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 })[colorType];
  requireValue(channels !== undefined, 'Unsupported PNG color type');
  const compressed = [];
  let transparency;
  let complete = false;
  for (let cursor = 8; cursor + 12 <= png.length;) {
    const length = png.readUInt32BE(cursor);
    requireValue(cursor + length + 12 <= png.length, 'Truncated PNG chunk');
    const type = png.toString('ascii', cursor + 4, cursor + 8);
    const data = png.subarray(cursor + 8, cursor + 8 + length);
    if (type === 'IDAT') compressed.push(data);
    if (type === 'tRNS') transparency = data;
    if (type === 'IEND') { complete = true; break; }
    cursor += length + 12;
  }
  requireValue(complete && compressed.length > 0, 'PNG image data is missing');
  const stride = sourceWidth * channels;
  const raw = inflateSync(Buffer.concat(compressed), { maxOutputLength: (stride + 1) * sourceHeight });
  requireValue(raw.length === (stride + 1) * sourceHeight, 'Invalid PNG scanline length');
  let previous = Buffer.alloc(stride);
  let left = sourceWidth;
  let top = sourceHeight;
  let right = -1;
  let bottom = -1;
  for (let y = 0; y < sourceHeight; y++) {
    const filter = raw[y * (stride + 1)];
    requireValue(filter <= 4, 'Unsupported PNG row filter');
    const row = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let index = 0; index < stride; index++) {
      const a = index >= channels ? row[index - channels] : 0;
      const b = previous[index];
      const c = index >= channels ? previous[index - channels] : 0;
      const predictor = filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b : filter === 3 ? Math.floor((a + b) / 2) : paeth(a, b, c);
      row[index] = (row[index] + predictor) & 255;
    }
    for (let x = 0; x < sourceWidth; x++) {
      const offset = x * channels;
      let alpha = 255;
      if (colorType === 6 || colorType === 4) alpha = row[offset + channels - 1];
      else if (colorType === 3) alpha = transparency?.[row[offset]] ?? 255;
      else if (colorType === 0 && transparency?.length === 2 && row[offset] === transparency.readUInt16BE(0)) alpha = 0;
      else if (colorType === 2 && transparency?.length === 6 && row[offset] === transparency.readUInt16BE(0) &&
        row[offset + 1] === transparency.readUInt16BE(2) && row[offset + 2] === transparency.readUInt16BE(4)) alpha = 0;
      if (alpha === 0) continue;
      left = Math.min(left, x); top = Math.min(top, y); right = Math.max(right, x); bottom = Math.max(bottom, y);
    }
    previous = row;
  }
  requireValue(right >= left && bottom >= top, 'Artwork is completely transparent');
  return { sourceWidth, sourceHeight, left, top, width: right - left + 1, height: bottom - top + 1 };
}

export async function validateProfilePlatformAssets(platforms, root = repositoryRoot) {
  for (const platform of platforms) {
    const apiPath = resolve(root, 'apps/api/assets/profile-platforms', platform.asset.file);
    const mobilePath = resolve(root, 'apps/mobile/assets/images/platforms', platform.asset.file);
    const [api, mobile] = await Promise.all([readFile(apiPath), readFile(mobilePath)]);
    requireValue(api.equals(mobile), `${platform.id}: API and mobile artwork differ`);
    requireValue(createHash('sha256').update(api).digest('hex') === platform.asset.sha256, `${platform.id}: artwork hash differs from audited source`);
    const metrics = readProfilePlatformPngMetrics(api);
    for (const [field, value] of Object.entries(metrics)) requireValue(platform.asset[field] === value, `${platform.id}: ${field} differs from actual PNG pixels`);
  }
}

const runtimePlatforms = (platforms) => platforms.map((platform) => {
  const asset = Object.fromEntries(['file', 'sourceWidth', 'sourceHeight', 'left', 'top', 'width', 'height']
    .map((field) => [field, platform.asset[field]]));
  return { id: platform.id, name: platform.name, category: platform.category, aliases: platform.aliases, regions: platform.regions,
    domains: platform.domains, matches: platform.matches, sampleUrl: platform.sampleUrl, asset };
});

export function generateProfilePlatformTypeScript(platforms) {
  return `// Generated from shared/profile-platforms.json by scripts/generate-profile-platforms.mjs.\n// Do not edit; artwork and recognition metadata are maintained in the source catalog.\n\nexport const profilePlatformCatalog = ${JSON.stringify(runtimePlatforms(platforms), null, 2)} as const;\n\nexport type ProfilePlatformDefinition = (typeof profilePlatformCatalog)[number];\nexport type ProfilePlatformId = ProfilePlatformDefinition['id'];\nexport type ProfilePlatformMatch = { readonly host: string; readonly pathPrefix: string; readonly subdomains: boolean };\nexport type ProfilePlatformMetric = { sourceWidth: number; sourceHeight: number; left: number; top: number; width: number; height: number };\n\nconst mapProfilePlatforms = <T>(select: (platform: ProfilePlatformDefinition) => T): Record<ProfilePlatformId, T> => {\n  const values = {} as Record<ProfilePlatformId, T>;\n  for (const platform of profilePlatformCatalog) values[platform.id] = select(platform);\n  return values;\n};\n\nexport const profilePlatformIds = profilePlatformCatalog.map((platform) => platform.id);\nexport const profilePlatformNames = mapProfilePlatforms<string>((platform) => platform.name);\nexport const profilePlatformFiles = mapProfilePlatforms<string>((platform) => platform.asset.file);\nexport const profilePlatformMetrics = mapProfilePlatforms<ProfilePlatformMetric>((platform) => {\n  const { file: _file, ...metric } = platform.asset;\n  return metric;\n});\nexport const profilePlatformDomains = mapProfilePlatforms<readonly string[]>((platform) => platform.domains);\nexport const profilePlatformMatches = mapProfilePlatforms<readonly ProfilePlatformMatch[]>((platform) => platform.matches);\n`;
}

const dartString = (value) => `'${value.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;
const dartList = (values) => `[${values.map(dartString).join(', ')}]`;

export function generateProfilePlatformDart(platforms) {
  const definitions = runtimePlatforms(platforms).map((platform) => `  ProfilePlatformDefinition(\n    id: ${dartString(platform.id)},\n    name: ${dartString(platform.name)},\n    category: ${dartString(platform.category)},\n    aliases: ${dartList(platform.aliases)},\n    regions: ${dartList(platform.regions)},\n    domains: ${dartList(platform.domains)},\n    matches: [${platform.matches.map((match) => `ProfilePlatformMatch(host: ${dartString(match.host)}, pathPrefix: ${dartString(match.pathPrefix)}, subdomains: ${match.subdomains})`).join(', ')}],\n    sampleUrl: ${dartString(platform.sampleUrl)},\n    asset: ProfilePlatformArtwork(\n      file: ${dartString(platform.asset.file)},\n${['sourceWidth', 'sourceHeight', 'left', 'top', 'width', 'height'].map((field) => `      ${field}: ${platform.asset[field]}.0,`).join('\n')}\n    ),\n  ),`).join('\n');
  return `// Generated from shared/profile-platforms.json by scripts/generate-profile-platforms.mjs.\n// Do not edit; artwork and recognition metadata are maintained in the source catalog.\n\nclass ProfilePlatformMatch {\n  const ProfilePlatformMatch({required this.host, required this.pathPrefix, required this.subdomains});\n  final String host;\n  final String pathPrefix;\n  final bool subdomains;\n}\n\nclass ProfilePlatformArtwork {\n  const ProfilePlatformArtwork({required this.file, required this.sourceWidth, required this.sourceHeight, required this.left, required this.top, required this.width, required this.height});\n  final String file;\n  final double sourceWidth;\n  final double sourceHeight;\n  final double left;\n  final double top;\n  final double width;\n  final double height;\n}\n\nclass ProfilePlatformDefinition {\n  const ProfilePlatformDefinition({required this.id, required this.name, required this.category, required this.aliases, required this.regions, required this.domains, required this.matches, required this.sampleUrl, required this.asset});\n  final String id;\n  final String name;\n  final String category;\n  final List<String> aliases;\n  final List<String> regions;\n  final List<String> domains;\n  final List<ProfilePlatformMatch> matches;\n  final String sampleUrl;\n  final ProfilePlatformArtwork asset;\n}\n\nconst profilePlatformCatalog = <ProfilePlatformDefinition>[\n${definitions}\n];\n\nconst profilePlatformIds = <String>{\n${platforms.map((platform) => `  ${dartString(platform.id)},`).join('\n')}\n};\n\nconst profilePlatformNames = <String, String>{\n${platforms.map((platform) => `  ${dartString(platform.id)}: ${dartString(platform.name)},`).join('\n')}\n};\n\nfinal profilePlatformsById = Map<String, ProfilePlatformDefinition>.unmodifiable({\n  for (final platform in profilePlatformCatalog) platform.id: platform,\n});\n`;
}

export const isCurrentProfilePlatformCatalog = (existing, expected) =>
  typeof existing === 'string' && existing.replace(/\r\n/g, '\n') === expected;

export async function runProfilePlatformGenerator({ check = false } = {}) {
  const platforms = validateProfilePlatformCatalog(JSON.parse(await readFile(manifestFile, 'utf8')));
  await validateProfilePlatformAssets(platforms);
  const outputs = [[generatedFiles.api, generateProfilePlatformTypeScript(platforms)], [generatedFiles.mobile, generateProfilePlatformDart(platforms)]];
  for (const [file, content] of outputs) {
    if (check) {
      const existing = await readFile(file, 'utf8').catch(() => undefined);
      requireValue(isCurrentProfilePlatformCatalog(existing, content), `Generated catalog is stale: ${file}. Run node scripts/generate-profile-platforms.mjs`);
    } else {
      await writeFile(file, content, 'utf8');
    }
  }
  process.stdout.write(`Validated 100 brand logos, API/mobile image parity, PNG bounds and ${check ? 'checked' : 'generated'} both catalogs.\n`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const args = process.argv.slice(2);
  if (args.some((argument) => argument !== '--check') || args.length > 1) {
    process.stderr.write('Usage: node scripts/generate-profile-platforms.mjs [--check]\n');
    process.exitCode = 1;
  } else {
    await runProfilePlatformGenerator({ check: args.includes('--check') }).catch((error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    });
  }
}
