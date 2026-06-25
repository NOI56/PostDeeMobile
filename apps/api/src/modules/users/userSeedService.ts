import type { AuthUser } from '../auth/authTypes.js';
import type { AppUser, UserStore } from './userStore.js';

type SeedEnv = Record<string, string | undefined>;

const readOptional = (env: SeedEnv, key: string) => {
  const value = env[key]?.trim();
  return value && value.length > 0 ? value : undefined;
};

export const buildSeedAuthUser = (env: SeedEnv = process.env): AuthUser => {
  const id = readOptional(env, 'MOCK_USER_ID') ?? 'local-dev-user';

  return {
    id,
    provider: 'mock',
    email: readOptional(env, 'SEED_USER_EMAIL') ?? `${id}@postdee.local`,
    displayName: readOptional(env, 'SEED_USER_DISPLAY_NAME') ?? 'PostDee Local Seller'
  };
};

export const seedMockUser = async ({
  userStore,
  env = process.env
}: {
  userStore: UserStore;
  env?: SeedEnv;
}): Promise<AppUser> => userStore.ensure(buildSeedAuthUser(env));
