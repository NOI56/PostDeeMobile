import { describe, expect, it } from 'vitest';

import { createDefaultLinkInBioAppearance, readLinkInBioAppearance } from './linkInBioAppearance.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';

const links = [{ id: 'shop', title: 'Shop', url: 'https://example.com/' }];

describe('link in bio appearance', () => {
  it('normalizes a partial appearance from its selected preset without sharing mutable defaults', () => {
    const result = readLinkInBioAppearance({ themeId: 'pastel', description: '  สินค้าของร้าน  ' }, links)!;
    expect(result).toMatchObject({ version: 1, themeId: 'pastel', description: 'สินค้าของร้าน', buttonRadius: 'pill', buttonColor: '#8b5fbf' });
    result.nameStyle.color = '#000000';
    expect(createDefaultLinkInBioAppearance('pastel').nameStyle.color).toBe('#473258');
  });

  it.each([
    { version: 2 }, { themeId: 'custom' }, { description: 'x'.repeat(281) },
    { buttonColor: 'red;display:none' }, { surfaceColor: '#fff' }, { buttonRadius: '99px' },
    { nameStyle: { font: 'evil' } }, { nameStyle: { color: '#ffffff;}' } },
    { background: { mode: 'url' } }, { background: { overlay: -1 } },
    { background: { overlay: 81 } }, { background: { overlay: 1.5 } },
    { background: { imageKey: 'https://evil.example/image.png' } },
    { logoKey: '../owner/image' }, { coverKey: 'a'.repeat(513) }, { logoKey: 7 },
    { featuredLinkId: 'missing' }, { featuredLabel: 'x'.repeat(41) }
  ])('rejects invalid appearance %#', (input) => {
    expect(readLinkInBioAppearance(input, links)).toBeUndefined();
  });

  it('accepts safe keys and only a featured link present in the published links', () => {
    expect(readLinkInBioAppearance({
      logoKey: 'profiles/owner/logo.png', featuredLinkId: 'shop',
      background: { mode: 'image', imageKey: 'profiles/owner/background.png', overlay: 80 }
    }, links)).toMatchObject({ logoKey: 'profiles/owner/logo.png', featuredLinkId: 'shop' });
  });

  it('preserves customization for a legacy publish and returns independent nested copies', async () => {
    const store = createInMemoryLinkInBioStore();
    const input = { userId: 'owner', storeName: 'ร้าน', slug: 'shop', links };
    const appearance = createDefaultLinkInBioAppearance('dark');
    await store.publish({ ...input, appearance });
    const first = (await store.getForUser('owner'))!;
    first.appearance!.nameStyle.color = '#000000';
    const republished = await store.publish(input);
    expect(republished.appearance).toEqual(appearance);
    await store.unpublish('owner');
    expect((await store.getForUser('owner'))!.appearance).toEqual(appearance);
  });
});
