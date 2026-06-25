import { describe, expect, it, vi } from 'vitest';

import { buildSeedAuthUser, seedMockUser } from './userSeedService.js';

describe('userSeedService', () => {
  it('builds a safe local seed user from defaults', () => {
    expect(buildSeedAuthUser({})).toEqual({
      id: 'local-dev-user',
      provider: 'mock',
      email: 'local-dev-user@postdee.local',
      displayName: 'PostDee Local Seller'
    });
  });

  it('builds a seed user from environment overrides', () => {
    expect(
      buildSeedAuthUser({
        MOCK_USER_ID: 'seller-a',
        SEED_USER_EMAIL: 'seller@example.com',
        SEED_USER_DISPLAY_NAME: 'Seller A'
      })
    ).toEqual({
      id: 'seller-a',
      provider: 'mock',
      email: 'seller@example.com',
      displayName: 'Seller A'
    });
  });

  it('upserts the seed user through the provided user store', async () => {
    const userStore = {
      ensure: vi.fn(async (authUser) => ({
        id: authUser.id,
        firebaseUid: `mock:${authUser.id}`,
        email: authUser.email ?? 'local-dev-user@postdee.local',
        displayName: authUser.displayName,
        createdAt: '2026-06-01T00:00:00.000Z',
        updatedAt: '2026-06-01T00:00:00.000Z'
      }))
    };

    await expect(
      seedMockUser({
        userStore,
        env: {
          MOCK_USER_ID: 'seller-a',
          SEED_USER_EMAIL: 'seller@example.com'
        }
      })
    ).resolves.toMatchObject({
      id: 'seller-a',
      email: 'seller@example.com'
    });
    expect(userStore.ensure).toHaveBeenCalledWith({
      id: 'seller-a',
      provider: 'mock',
      email: 'seller@example.com',
      displayName: 'PostDee Local Seller'
    });
  });
});
