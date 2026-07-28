import { readFile } from 'node:fs/promises';

import { describe, expect, it } from 'vitest';

const readCiConfig = async () =>
  readFile(new URL('../../../../.github/workflows/ci.yml', import.meta.url), 'utf8');

describe('GitHub CI dependency security config', () => {
  it('keeps native build tools installed while auditing only runtime dependencies used by PostDee', async () => {
    const source = await readCiConfig();

    expect(source).toContain('run: npm ci');
    expect(source).not.toContain('run: npm ci --omit=optional');
    expect(source).toContain(
      'run: npm audit --omit=dev --omit=optional --audit-level=high',
    );
  });
});
