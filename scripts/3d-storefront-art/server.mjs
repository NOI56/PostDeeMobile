// Local-only studio for the second set of 3D storefront artwork.
// Serves the WebGL ray-marching studio and saves rendered PNGs to an output
// folder. Usage: node scripts/3d-storefront-art/server.mjs <out-dir> [port]
import { createServer } from 'node:http';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(process.argv[2] ?? join(root, 'out'));
const port = Number(process.argv[3] ?? 4517);
const types = { '.html': 'text/html; charset=utf-8', '.glsl': 'text/plain; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8' };
const safeName = /^[a-z][a-z\d-]{0,79}\.png$/;
const safeAsset = /^(studio\.html|common\.glsl|scenes\/[a-z][a-z\d-]{0,79}\.glsl)$/;

await mkdir(outDir, { recursive: true });
createServer(async (request, response) => {
  const url = new URL(request.url ?? '/', 'http://localhost');
  try {
    if (request.method === 'POST' && url.pathname.startsWith('/status/')) {
      const name = url.pathname.slice('/status/'.length);
      if (!/^[a-z][a-z\d-]{0,79}$/.test(name)) { response.writeHead(400).end('bad name'); return; }
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      await writeFile(join(outDir, `${name}.status.txt`), Buffer.concat(chunks));
      response.writeHead(204).end();
      return;
    }
    if (request.method === 'POST' && url.pathname.startsWith('/save/')) {
      const name = url.pathname.slice('/save/'.length);
      if (!safeName.test(name)) { response.writeHead(400).end('bad name'); return; }
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      await writeFile(join(outDir, name), Buffer.concat(chunks));
      response.writeHead(200, { 'content-type': 'text/plain' }).end(`saved ${name}`);
      return;
    }
    const asset = url.pathname === '/' ? 'studio.html' : url.pathname.slice(1);
    if (request.method !== 'GET' || !safeAsset.test(asset)) { response.writeHead(404).end(); return; }
    const body = await readFile(join(root, asset));
    response.writeHead(200, { 'content-type': types[asset.slice(asset.lastIndexOf('.'))], 'cache-control': 'no-store' }).end(body);
  } catch (error) {
    response.writeHead(500).end(String(error));
  }
}).listen(port, '127.0.0.1', () => process.stdout.write(`3D art studio on http://localhost:${port} -> ${outDir}\n`));
