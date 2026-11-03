// Renders studio scenes in an isolated headless Edge/Chrome profile and waits
// for the studio to report back. The studio server must already be running.
// Usage: node scripts/3d-storefront-art/render.mjs <out-dir> <scene[:WxH]>... [--ss=3] [--swiftshader]
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = process.argv.slice(2);
const outDir = args.shift();
const flags = args.filter((value) => value.startsWith('--'));
const scenes = args.filter((value) => !value.startsWith('--'));
const ss = flags.find((value) => value.startsWith('--ss='))?.slice(5) ?? '3';
const tile = flags.find((value) => value.startsWith('--tile='))?.slice(7) ?? '64';
const port = flags.find((value) => value.startsWith('--port='))?.slice(7) ?? '4517';
const browser = process.env.STUDIO_BROWSER ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const gpuFlags = flags.includes('--swiftshader') ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : ['--enable-gpu', '--ignore-gpu-blocklist'];
const mtime = async (file) => (await stat(file).catch(() => null))?.mtimeMs ?? 0;

for (const spec of scenes) {
  const [scene, size = '1600x800'] = spec.split(':');
  const [width, height] = size.split('x');
  const statusFile = join(outDir, `${scene}.status.txt`);
  const before = await mtime(statusFile);
  const profile = await mkdtemp(join(tmpdir(), 'pd-art-'));
  const url = `http://127.0.0.1:${port}/?scene=${scene}&w=${width}&h=${height}&ss=${ss}&tile=${tile}&save=1`;
  const started = Date.now();
  const child = spawn(browser, ['--headless=new', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-sync', ...gpuFlags, url], { stdio: 'ignore' });
  let status = 'timeout';
  while (Date.now() - started < 15 * 60_000) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    if (await mtime(statusFile) > before) { status = (await readFile(statusFile, 'utf8')).trim(); break; }
  }
  child.kill();
  await new Promise((resolve) => setTimeout(resolve, 800));
  await rm(profile, { recursive: true, force: true }).catch(() => {});
  process.stdout.write(`${scene} ${width}x${height}: ${status} (${((Date.now() - started) / 1000).toFixed(1)}s)\n`);
}
