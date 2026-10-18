import { mkdir, copyFile } from 'node:fs/promises';
const source = new URL('../src/modules/admin/web/', import.meta.url);
const destination = new URL('../dist/modules/admin/web/', import.meta.url);
await mkdir(destination, { recursive: true });
for (const name of ['admin.html', 'admin.css', 'admin.js']) {
  await copyFile(new URL(name, source), new URL(name, destination));
}
