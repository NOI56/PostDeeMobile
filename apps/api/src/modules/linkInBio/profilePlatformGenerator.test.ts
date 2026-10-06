import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const generator = await import(new URL('../../../../../scripts/generate-profile-platforms.mjs', import.meta.url).href);
const execFileAsync = promisify(execFile);
const originalArtwork = {
  youtube: { sha256: '1027b1b0517727adb9697155a270744381c3ce9b047b1c8bd8a9389dc7d07a83', sourceWidth: 1255, sourceHeight: 1075, left: 214, top: 248, width: 827, height: 579 },
  shopee: { sha256: '26b67120cbdf3123fe70f747d42ba6adeedc59cdf9c66085afa0343930ef0897', sourceWidth: 96, sourceHeight: 96, left: 5, top: 0, width: 86, height: 96 },
  lazada: { sha256: '9b2af701cb4f10425aeaecf9175cce3e74d7655ffdead15149a9a2ecc81b3cb2', sourceWidth: 128, sourceHeight: 128, left: 0, top: 0, width: 128, height: 128 },
  line: { sha256: '5e93437eb5ec0dcdece92d1562fcd435d1d521cca5c013d2d9e15b544a1d8a39', sourceWidth: 1001, sourceHeight: 1000, left: 0, top: 0, width: 1001, height: 1000 },
  tiktok: { sha256: 'd08e3acc4b31bfcca4c67031ebfc6c78e22b27db3e6601f261d905af6a8df568', sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  instagram: { sha256: '2604bd33f5e75ecd2ca39599d4aef92ed0f5072a5bc39a7cf79635dda74b9fff', sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  facebook: { sha256: '7ed849718cc5c019fa76ae2ca29ed0119e6ba7bfa92727c768c5ce36388bfee1', sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  messenger: { sha256: '3cda2d1ea91b6c87baa3b43b2ed28c9c57e434014d649f4aaa06e8a0c8b7d98e', sourceWidth: 128, sourceHeight: 128, left: 5, top: 7, width: 117, height: 116 },
  whatsapp: { sha256: '1103b5dfe5420b191202c3f31b8e03efaaf954f9e4ab117b089587ed910442dc', sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  google_maps: { sha256: 'abfef074006dec3c9808eb9cf87ea1145107a263f71377aa17e791032a5c85c4', sourceWidth: 192, sourceHeight: 192, left: 27, top: 8, width: 138, height: 176 }
};

const fixture = () => ({
  version: 1,
  platforms: [...Object.keys(originalArtwork), ...Array.from({ length: 90 }, (_, index) => `app_${index}`)].map((id) => ({
    id, name: id, category: 'social', aliases: [], regions: ['Global'], domains: [`${id.replace(/_/g, '-')}.example`], matches: [],
    sampleUrl: `https://${id.replace(/_/g, '-')}.example/shop`,
    asset: { file: `${id}.png`, sha256: 'a'.repeat(64), sourceWidth: 128, sourceHeight: 128, left: 0, top: 0, width: 128, height: 128,
      sourceUrl: 'https://example.com/artwork.png', licenseUrl: 'https://example.com/brand-guidelines' }
  }))
});

describe('profile platform generator audits', () => {
  it('accepts generated catalogs checked out with either LF or Windows CRLF line endings', () => {
    const generated = generator.generateProfilePlatformTypeScript(fixture().platforms);
    expect(generator.isCurrentProfilePlatformCatalog(generated, generated)).toBe(true);
    expect(generator.isCurrentProfilePlatformCatalog(generated.replace(/\n/g, '\r\n'), generated)).toBe(true);
    const dart = generator.generateProfilePlatformDart(fixture().platforms);
    expect(generator.isCurrentProfilePlatformCatalog(dart.replace(/\n/g, '\r\n'), dart)).toBe(true);
  });

  it('continues rejecting a missing or changed generated catalog when line endings are normalized', () => {
    const generated = generator.generateProfilePlatformTypeScript(fixture().platforms);
    const changed = generated.replace('youtube', 'changed_platform').replace(/\n/g, '\r\n');
    expect(generator.isCurrentProfilePlatformCatalog(changed, generated)).toBe(false);
    expect(generator.isCurrentProfilePlatformCatalog(`${generated} `, generated)).toBe(false);
    expect(generator.isCurrentProfilePlatformCatalog(undefined, generated)).toBe(false);
  });

  it('checks generated API and Dart catalogs against the source manifest during the API test suite', async () => {
    const script = fileURLToPath(new URL('../../../../../scripts/generate-profile-platforms.mjs', import.meta.url));
    const result = await execFileAsync(process.execPath, [script, '--check']);
    expect(result.stdout).toContain('Validated 100 brand logos');
    expect(result.stdout).toContain('checked both catalogs');
    expect(result.stderr).toBe('');
  });

  it.each(Object.entries(originalArtwork))('preserves %s baseline bytes and measures the original PNG artwork independently', async (id, audited) => {
    const image = await readFile(new URL(`../../../assets/profile-platforms/${id}.png`, import.meta.url));
    expect(createHash('sha256').update(image).digest('hex')).toBe(audited.sha256);
    const { sha256: _sha256, ...metrics } = audited;
    expect(generator.readProfilePlatformPngMetrics(image)).toEqual(metrics);
  });

  it('requires 100 unique brands, retains the original IDs, and accepts extra provenance notes', () => {
    const manifest = fixture();
    Object.assign(manifest.platforms[0].asset, { preparation: 'Original source pixels preserved', retrievedAt: '2026-10-07' });
    expect(generator.validateProfilePlatformCatalog(manifest)).toHaveLength(100);
    const api = generator.generateProfilePlatformTypeScript(manifest.platforms);
    const mobile = generator.generateProfilePlatformDart(manifest.platforms);
    expect(api).not.toContain('retrievedAt');
    expect(mobile).not.toContain('retrievedAt');
    expect(api).not.toContain('Original source pixels preserved');
    expect(mobile).toContain('final profilePlatformsById');
  });

  it.each([
    ['wrong count', (manifest: ReturnType<typeof fixture>) => manifest.platforms.pop()],
    ['duplicate ID', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[1].id = manifest.platforms[0].id; }],
    ['generic brand ID', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].id = 'auto'; }],
    ['removed original ID', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].id = 'other_app'; manifest.platforms[0].asset.file = 'other_app.png'; }],
    ['asset path traversal', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].asset.file = '../youtube.png'; }],
    ['asset mismatch', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].asset.file = 'other.png'; }],
    ['invalid hash', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].asset.sha256 = 'not-a-hash'; }],
    ['bounds outside artwork', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].asset.left = 1; }],
    ['credential source URL', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].asset.sourceUrl = 'https://private@example.com/logo.png'; }],
    ['non-HTTP license URL', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].asset.licenseUrl = 'javascript:alert(1)'; }],
    ['invalid domain', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].domains = ['youtube.com/path']; }],
    ['no destination rule', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].domains = []; }],
    ['invalid sample destination', (manifest: ReturnType<typeof fixture>) => { manifest.platforms[0].sampleUrl = 'mailto:shop@example.com'; }]
  ])('refuses an unsafe or inconsistent source manifest: %s', (_name, mutate) => {
    const manifest = fixture();
    mutate(manifest);
    expect(() => generator.validateProfilePlatformCatalog(manifest)).toThrow();
  });

  it('rejects arbitrary files and truncated PNG images instead of trusting declared dimensions', async () => {
    expect(() => generator.readProfilePlatformPngMetrics(Buffer.from('not a PNG'))).toThrow();
    const image = await readFile(new URL('../../../assets/profile-platforms/messenger.png', import.meta.url));
    expect(() => generator.readProfilePlatformPngMetrics(image.subarray(0, 40))).toThrow();
    const interlaced = Buffer.from(image);
    interlaced[28] = 1;
    expect(() => generator.readProfilePlatformPngMetrics(interlaced)).toThrow(/non-interlaced/);
  });
});
