// Renders the cartoon storefront drawings from scenes.mjs to PNG with an
// isolated headless Edge/Chrome profile. Nothing is downloaded.
// Usage: node scripts/cartoon-storefront-art/render.mjs [--out=<dir>] [--install] [scene-id ...]
//   --install copies each PNG byte-identically to the API and Mobile asset folders.
import { spawn } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { cartoonScenes } from './scenes.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const args = process.argv.slice(2);
const outDir = resolve(args.find((value) => value.startsWith('--out='))?.slice(6) ?? join(tmpdir(), 'postdee-cartoon-art'));
const install = args.includes('--install');
const wanted = args.filter((value) => !value.startsWith('--'));
const browser = process.env.STUDIO_BROWSER ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const targets = [resolve(root, 'apps/api/assets/profile-decorations'), resolve(root, 'apps/mobile/assets/images/profile_decorations')];

const run = (command, commandArgs) => new Promise((resolvePromise, reject) => {
  const child = spawn(command, commandArgs, { stdio: 'ignore' });
  const timer = setTimeout(() => { child.kill(); reject(new Error('browser timed out')); }, 60_000);
  child.on('exit', () => { clearTimeout(timer); resolvePromise(); });
  child.on('error', (error) => { clearTimeout(timer); reject(error); });
});

await mkdir(outDir, { recursive: true });
for (const scene of cartoonScenes.filter((entry) => wanted.length === 0 || wanted.includes(entry.id))) {
  const { width, height, svg } = scene.draw();
  const svgFile = join(outDir, `${scene.id}.svg`);
  const pngFile = join(outDir, `${scene.id}.png`);
  await writeFile(svgFile, svg, 'utf8');
  await rm(pngFile, { force: true });
  const profile = await mkdtemp(join(tmpdir(), 'pd-cartoon-'));
  try {
    await run(browser, ['--headless=new', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', '--disable-extensions',
      '--disable-sync', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000', `--window-size=${width},${height}`,
      `--screenshot=${pngFile}`, pathToFileURL(svgFile).href]);
  } finally {
    await rm(profile, { recursive: true, force: true }).catch(() => {});
  }
  const size = (await stat(pngFile)).size;
  if (install) for (const target of targets) await copyFile(pngFile, join(target, `${scene.id}.png`));
  process.stdout.write(`${scene.id} ${width}x${height} ${(size / 1024).toFixed(0)} KB${install ? ' installed' : ''}\n`);
}
process.stdout.write(`Output: ${outDir}\n`);
