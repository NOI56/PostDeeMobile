import { readFile } from 'node:fs/promises';

import { describe, expect, it } from 'vitest';

describe('publishWorkerRunner entrypoint', () => {
  it('loads dotenv before reading worker configuration', async () => {
    const source = await readFile(new URL('./publishWorkerRunner.ts', import.meta.url), 'utf8');

    expect(source.trimStart().startsWith("import 'dotenv/config';")).toBe(true);
  });
});
