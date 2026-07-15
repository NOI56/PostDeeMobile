# PostPeer User Social Connections Implementation Plan

> Historical implementation plan: the final runtime diverged from the proposed
> signed-state callback architecture. It uses PostPeer profile state and
> explicit `POST /social-connections/refresh` polling. Unchecked steps below do
> not describe current completion status; use `API.md`, `ARCHITECTURE.md`, and
> the current route code as the source of truth.

> **Current-state addendum (2026-07-15):** The active runtime ensures a fresh
> `User` before saving a PostPeer profile and sends a required stable
> pseudonymous profile name. Publish `202 pending/publishing` responses are
> polled for roughly two minutes; success requires a real platform URL/id and
> `GET /posts` returns user-scoped `platformResults`. Controlled-first requests
> use YouTube `private` and TikTok `SELF_ONLY` (`draft: false`). Only explicitly
> safe pre-accept failures are retried; unknown outcomes require checking the
> provider before retry. `FACEBOOK_REELS` remains an internal compatibility key
> for Facebook Page Video, not Reels. Real connected-account E2E is still
> pending.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-owned PostPeer social account connections so each authenticated PostDee user publishes to their own connected social accounts.

**Architecture:** Add a `SocialConnection` store backed by Prisma in production and memory in tests/local development. Authenticated API routes create PostPeer connect links, receive provider callbacks, and expose connection status to the mobile app. The publish worker resolves the PostPeer account id from the post owner's stored connection; operator env account ids are allowed only for non-production smoke tests.

**Tech Stack:** Express, TypeScript, Vitest, Prisma, Flutter, Dart, url_launcher, PostPeer API.

---

## Scope Check

The spec touches backend storage/routes, publish worker wiring, mobile profile UI, and docs. These pieces are not independent: the mobile UI depends on the backend API contract, and publishing depends on the same stored connection data. Keep this as one plan with backend tasks first, then mobile, then documentation and verification.

## File Structure

- Create `apps/api/src/modules/socialConnections/socialConnectionStore.ts`: platform-safe types, in-memory store, and helpers used by routes and publisher wiring.
- Create `apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.ts`: Prisma-backed store following the existing device-token repository style.
- Create `apps/api/src/modules/socialConnections/socialConnectionStoreFactory.ts`: chooses Prisma when available, otherwise memory.
- Create `apps/api/src/modules/socialConnections/postPeerConnectState.ts`: signed state token creation and validation.
- Create `apps/api/src/modules/socialConnections/postPeerConnectClient.ts`: PostPeer create-link adapter with clear unavailable/provider-failure errors.
- Create `apps/api/src/modules/socialConnections/socialConnectionRoutes.ts`: authenticated status/connect/disconnect routes and PostPeer callback routes.
- Create tests beside each backend module.
- Modify `apps/api/prisma/schema.prisma` and add a migration SQL file for `SocialConnection`.
- Modify `apps/api/src/config/env.ts` and `apps/api/src/config/env.test.ts` for connect-client env vars.
- Modify `apps/api/src/app.ts`, `apps/api/src/modules/account/accountRoutes.ts`, and `apps/api/src/workers/publishWorkerRunner.ts` to wire the store.
- Modify `apps/api/src/workers/publishWorker.ts`, `apps/api/src/workers/postPeerPublisher.ts`, and `apps/api/src/workers/platformPublisherFactory.ts` so publishing can resolve per-user account ids.
- Modify `apps/mobile/pubspec.yaml`, `apps/mobile/lib/core/network/postdee_api_client.dart`, and `apps/mobile/lib/features/profile/profile_screen.dart` for mobile connection status and connect actions.
- Modify mobile profile tests and backend docs after the core behavior is working.

---

### Task 1: Backend SocialConnection Store And Prisma Model

**Files:**
- Modify: `apps/api/prisma/schema.prisma`
- Create: `apps/api/prisma/migrations/20260626090000_add_social_connections/migration.sql`
- Create: `apps/api/src/modules/socialConnections/socialConnectionStore.ts`
- Create: `apps/api/src/modules/socialConnections/socialConnectionStore.test.ts`
- Create: `apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.ts`
- Create: `apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.test.ts`
- Create: `apps/api/src/modules/socialConnections/socialConnectionStoreFactory.ts`

- [ ] **Step 1: Write failing memory-store tests**

Create `apps/api/src/modules/socialConnections/socialConnectionStore.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

import {
  createInMemorySocialConnectionStore,
  supportedSocialConnectionPlatforms
} from './socialConnectionStore.js';

describe('createInMemorySocialConnectionStore', () => {
  it('lists every supported platform as disconnected for a new user', async () => {
    const store = createInMemorySocialConnectionStore({
      now: () => '2026-06-26T09:00:00.000Z'
    });

    await expect(store.listForUser('seller-1')).resolves.toEqual(
      supportedSocialConnectionPlatforms.map((platform) => ({
        platform,
        connected: false
      }))
    );
  });

  it('upserts and lists a user-owned connection without leaking to another user', async () => {
    const store = createInMemorySocialConnectionStore({
      now: () => '2026-06-26T09:00:00.000Z'
    });

    await store.upsert({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1',
      displayName: '@seller_one',
      externalAccountId: 'tiktok-user-1'
    });

    expect(await store.getAccountId({ userId: 'seller-1', platform: 'TIKTOK' })).toBe(
      'acct-tiktok-1'
    );
    expect(await store.getAccountId({ userId: 'seller-2', platform: 'TIKTOK' })).toBeUndefined();

    const sellerOne = await store.listForUser('seller-1');
    expect(sellerOne.find((connection) => connection.platform === 'TIKTOK')).toMatchObject({
      platform: 'TIKTOK',
      connected: true,
      displayName: '@seller_one',
      externalAccountId: 'tiktok-user-1',
      connectedAt: '2026-06-26T09:00:00.000Z'
    });
  });

  it('disconnects and deletes all connections for a user', async () => {
    const store = createInMemorySocialConnectionStore();

    await store.upsert({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1'
    });
    await store.upsert({
      userId: 'seller-1',
      platform: 'FACEBOOK_REELS',
      postPeerAccountId: 'acct-facebook-1'
    });

    await expect(store.disconnect({ userId: 'seller-1', platform: 'TIKTOK' })).resolves.toBe(true);
    await expect(store.getAccountId({ userId: 'seller-1', platform: 'TIKTOK' })).resolves.toBeUndefined();

    await store.deleteAllForUser?.('seller-1');
    await expect(store.getAccountId({ userId: 'seller-1', platform: 'FACEBOOK_REELS' })).resolves.toBeUndefined();
  });
});
```

- [ ] **Step 2: Run memory-store tests and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/socialConnections/socialConnectionStore.test.ts
```

Expected: fail because `socialConnectionStore.ts` does not exist.

- [ ] **Step 3: Implement memory store and shared types**

Create `apps/api/src/modules/socialConnections/socialConnectionStore.ts`:

```ts
import type { Platform } from '../posts/postStore.js';

export type SocialConnectionPlatform =
  | 'TIKTOK'
  | 'YOUTUBE_SHORTS'
  | 'INSTAGRAM_REELS'
  | 'FACEBOOK_REELS';

export const supportedSocialConnectionPlatforms: SocialConnectionPlatform[] = [
  'TIKTOK',
  'YOUTUBE_SHORTS',
  'INSTAGRAM_REELS',
  'FACEBOOK_REELS'
];

export const isSocialConnectionPlatform = (
  value: unknown
): value is SocialConnectionPlatform =>
  typeof value === 'string' &&
  supportedSocialConnectionPlatforms.includes(value as SocialConnectionPlatform);

export const isPublishableSocialPlatform = (
  platform: Platform
): platform is SocialConnectionPlatform => isSocialConnectionPlatform(platform);

export type SocialConnection = {
  userId: string;
  platform: SocialConnectionPlatform;
  postPeerAccountId: string;
  displayName?: string;
  externalAccountId?: string;
  connectedAt: string;
  updatedAt: string;
};

export type SocialConnectionStatus = {
  platform: SocialConnectionPlatform;
  connected: boolean;
  displayName?: string;
  externalAccountId?: string;
  connectedAt?: string;
};

export type UpsertSocialConnectionInput = {
  userId: string;
  platform: SocialConnectionPlatform;
  postPeerAccountId: string;
  displayName?: string;
  externalAccountId?: string;
};

export type GetSocialConnectionAccountIdInput = {
  userId: string;
  platform: SocialConnectionPlatform;
};

export type DisconnectSocialConnectionInput = {
  userId: string;
  platform: SocialConnectionPlatform;
};

export type SocialConnectionStore = {
  listForUser: (userId: string) => Promise<SocialConnectionStatus[]>;
  getAccountId: (input: GetSocialConnectionAccountIdInput) => Promise<string | undefined>;
  upsert: (input: UpsertSocialConnectionInput) => Promise<SocialConnection>;
  disconnect: (input: DisconnectSocialConnectionInput) => Promise<boolean>;
  deleteAllForUser?: (userId: string) => Promise<void>;
};

const connectionKey = (userId: string, platform: SocialConnectionPlatform) =>
  `${userId}:${platform}`;

const toStatus = (
  platform: SocialConnectionPlatform,
  connection?: SocialConnection
): SocialConnectionStatus =>
  connection
    ? {
        platform,
        connected: true,
        displayName: connection.displayName,
        externalAccountId: connection.externalAccountId,
        connectedAt: connection.connectedAt
      }
    : {
        platform,
        connected: false
      };

export const createInMemorySocialConnectionStore = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): SocialConnectionStore => {
  const connections = new Map<string, SocialConnection>();

  return {
    listForUser: async (userId) =>
      supportedSocialConnectionPlatforms.map((platform) =>
        toStatus(platform, connections.get(connectionKey(userId, platform)))
      ),
    getAccountId: async ({ userId, platform }) =>
      connections.get(connectionKey(userId, platform))?.postPeerAccountId,
    upsert: async ({ userId, platform, postPeerAccountId, displayName, externalAccountId }) => {
      const key = connectionKey(userId, platform);
      const existing = connections.get(key);
      const timestamp = now();
      const connection: SocialConnection = {
        userId,
        platform,
        postPeerAccountId,
        displayName,
        externalAccountId,
        connectedAt: existing?.connectedAt ?? timestamp,
        updatedAt: timestamp
      };

      connections.set(key, connection);
      return connection;
    },
    disconnect: async ({ userId, platform }) => connections.delete(connectionKey(userId, platform)),
    deleteAllForUser: async (userId) => {
      for (const [key, connection] of connections) {
        if (connection.userId === userId) {
          connections.delete(key);
        }
      }
    }
  };
};
```

- [ ] **Step 4: Run memory-store tests and verify GREEN**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/socialConnections/socialConnectionStore.test.ts
```

Expected: pass.

- [ ] **Step 5: Add Prisma schema and migration**

Modify `apps/api/prisma/schema.prisma` by adding the relation to `User`:

```prisma
  socialConnections SocialConnection[]
```

Add the model:

```prisma
model SocialConnection {
  id                String   @id @default(cuid())
  userId            String
  platform          Platform
  postPeerAccountId String
  displayName       String?
  externalAccountId String?
  connectedAt       DateTime @default(now())
  createdAt         DateTime @default(now())
  updatedAt         DateTime @updatedAt
  user              User     @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([userId, platform])
  @@index([userId])
}
```

Create `apps/api/prisma/migrations/20260626090000_add_social_connections/migration.sql`:

```sql
CREATE TABLE "SocialConnection" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "platform" "Platform" NOT NULL,
    "postPeerAccountId" TEXT NOT NULL,
    "displayName" TEXT,
    "externalAccountId" TEXT,
    "connectedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SocialConnection_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SocialConnection_userId_platform_key" ON "SocialConnection"("userId", "platform");
CREATE INDEX "SocialConnection_userId_idx" ON "SocialConnection"("userId");

ALTER TABLE "SocialConnection" ADD CONSTRAINT "SocialConnection_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
```

- [ ] **Step 6: Write Prisma repository tests**

Create `apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';

import { createPrismaSocialConnectionRepository } from './prismaSocialConnectionRepository.js';

describe('createPrismaSocialConnectionRepository', () => {
  it('lists connected and disconnected platform statuses', async () => {
    const prisma = {
      socialConnection: {
        findMany: vi.fn().mockResolvedValue([
          {
            userId: 'seller-1',
            platform: 'TIKTOK',
            postPeerAccountId: 'acct-tiktok-1',
            displayName: '@seller_one',
            externalAccountId: 'external-1',
            connectedAt: new Date('2026-06-26T09:00:00.000Z'),
            updatedAt: new Date('2026-06-26T09:00:00.000Z')
          }
        ]),
        findUnique: vi.fn(),
        upsert: vi.fn(),
        deleteMany: vi.fn()
      }
    };

    const repository = createPrismaSocialConnectionRepository({ prisma });
    const statuses = await repository.listForUser('seller-1');

    expect(prisma.socialConnection.findMany).toHaveBeenCalledWith({
      where: { userId: 'seller-1' },
      select: expect.any(Object)
    });
    expect(statuses.find((status) => status.platform === 'TIKTOK')).toMatchObject({
      platform: 'TIKTOK',
      connected: true,
      displayName: '@seller_one',
      externalAccountId: 'external-1',
      connectedAt: '2026-06-26T09:00:00.000Z'
    });
    expect(statuses.find((status) => status.platform === 'YOUTUBE_SHORTS')).toEqual({
      platform: 'YOUTUBE_SHORTS',
      connected: false
    });
  });

  it('upserts by userId and platform', async () => {
    const prisma = {
      socialConnection: {
        findMany: vi.fn(),
        findUnique: vi.fn(),
        upsert: vi.fn().mockResolvedValue({
          userId: 'seller-1',
          platform: 'TIKTOK',
          postPeerAccountId: 'acct-tiktok-1',
          displayName: '@seller_one',
          externalAccountId: null,
          connectedAt: new Date('2026-06-26T09:00:00.000Z'),
          updatedAt: new Date('2026-06-26T09:00:00.000Z')
        }),
        deleteMany: vi.fn()
      }
    };

    const repository = createPrismaSocialConnectionRepository({ prisma });
    await repository.upsert({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1',
      displayName: '@seller_one'
    });

    expect(prisma.socialConnection.upsert).toHaveBeenCalledWith({
      where: { userId_platform: { userId: 'seller-1', platform: 'TIKTOK' } },
      update: {
        postPeerAccountId: 'acct-tiktok-1',
        displayName: '@seller_one',
        externalAccountId: null
      },
      create: {
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'acct-tiktok-1',
        displayName: '@seller_one',
        externalAccountId: null
      },
      select: expect.any(Object)
    });
  });
});
```

- [ ] **Step 7: Run Prisma repository tests and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/socialConnections/prismaSocialConnectionRepository.test.ts
```

Expected: fail because `prismaSocialConnectionRepository.ts` does not exist.

- [ ] **Step 8: Implement Prisma repository and factory**

Create `apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.ts`:

```ts
import type {
  SocialConnection,
  SocialConnectionPlatform,
  SocialConnectionStore
} from './socialConnectionStore.js';
import { supportedSocialConnectionPlatforms } from './socialConnectionStore.js';

type PrismaSocialConnection = {
  userId: string;
  platform: string;
  postPeerAccountId: string;
  displayName: string | null;
  externalAccountId: string | null;
  connectedAt: Date;
  updatedAt: Date;
};

type SocialConnectionSelect = {
  userId: true;
  platform: true;
  postPeerAccountId: true;
  displayName: true;
  externalAccountId: true;
  connectedAt: true;
  updatedAt: true;
};

type SocialConnectionDelegate = {
  findMany: (args: {
    where: { userId: string };
    select: SocialConnectionSelect;
  }) => Promise<PrismaSocialConnection[]>;
  findUnique: (args: {
    where: { userId_platform: { userId: string; platform: string } };
    select: { postPeerAccountId: true };
  }) => Promise<{ postPeerAccountId: string } | null>;
  upsert: (args: {
    where: { userId_platform: { userId: string; platform: string } };
    update: { postPeerAccountId: string; displayName: string | null; externalAccountId: string | null };
    create: {
      userId: string;
      platform: string;
      postPeerAccountId: string;
      displayName: string | null;
      externalAccountId: string | null;
    };
    select: SocialConnectionSelect;
  }) => Promise<PrismaSocialConnection>;
  deleteMany: (args: { where: { userId: string; platform?: string } }) => Promise<{ count: number }>;
};

export type PrismaSocialConnectionClient = {
  socialConnection: SocialConnectionDelegate;
};

const socialConnectionSelect = {
  userId: true,
  platform: true,
  postPeerAccountId: true,
  displayName: true,
  externalAccountId: true,
  connectedAt: true,
  updatedAt: true
} satisfies SocialConnectionSelect;

const mapConnection = (record: PrismaSocialConnection): SocialConnection => ({
  userId: record.userId,
  platform: record.platform as SocialConnectionPlatform,
  postPeerAccountId: record.postPeerAccountId,
  displayName: record.displayName ?? undefined,
  externalAccountId: record.externalAccountId ?? undefined,
  connectedAt: record.connectedAt.toISOString(),
  updatedAt: record.updatedAt.toISOString()
});

export const createPrismaSocialConnectionRepository = ({
  prisma
}: {
  prisma: PrismaSocialConnectionClient;
}): SocialConnectionStore => ({
  listForUser: async (userId) => {
    const records = await prisma.socialConnection.findMany({
      where: { userId },
      select: socialConnectionSelect
    });
    const byPlatform = new Map(records.map((record) => [record.platform, mapConnection(record)]));

    return supportedSocialConnectionPlatforms.map((platform) => {
      const connection = byPlatform.get(platform);

      return connection
        ? {
            platform,
            connected: true,
            displayName: connection.displayName,
            externalAccountId: connection.externalAccountId,
            connectedAt: connection.connectedAt
          }
        : {
            platform,
            connected: false
          };
    });
  },
  getAccountId: async ({ userId, platform }) => {
    const record = await prisma.socialConnection.findUnique({
      where: { userId_platform: { userId, platform } },
      select: { postPeerAccountId: true }
    });

    return record?.postPeerAccountId;
  },
  upsert: async ({ userId, platform, postPeerAccountId, displayName, externalAccountId }) => {
    const record = await prisma.socialConnection.upsert({
      where: { userId_platform: { userId, platform } },
      update: {
        postPeerAccountId,
        displayName: displayName ?? null,
        externalAccountId: externalAccountId ?? null
      },
      create: {
        userId,
        platform,
        postPeerAccountId,
        displayName: displayName ?? null,
        externalAccountId: externalAccountId ?? null
      },
      select: socialConnectionSelect
    });

    return mapConnection(record);
  },
  disconnect: async ({ userId, platform }) => {
    const result = await prisma.socialConnection.deleteMany({
      where: { userId, platform }
    });

    return result.count > 0;
  }
});
```

Create `apps/api/src/modules/socialConnections/socialConnectionStoreFactory.ts`:

```ts
import {
  type SocialConnectionStore,
  createInMemorySocialConnectionStore
} from './socialConnectionStore.js';
import {
  type PrismaSocialConnectionClient,
  createPrismaSocialConnectionRepository
} from './prismaSocialConnectionRepository.js';

export const createSocialConnectionStore = ({
  prisma
}: {
  prisma?: PrismaSocialConnectionClient;
}): SocialConnectionStore =>
  prisma
    ? createPrismaSocialConnectionRepository({ prisma })
    : createInMemorySocialConnectionStore();
```

- [ ] **Step 9: Run backend store tests and Prisma validation**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/socialConnections/socialConnectionStore.test.ts src/modules/socialConnections/prismaSocialConnectionRepository.test.ts
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npm.cmd run prisma:validate
```

Expected: tests pass and Prisma schema is valid.

- [ ] **Step 10: Commit backend store/model**

Run:

```powershell
git add apps/api/prisma/schema.prisma apps/api/prisma/migrations/20260626090000_add_social_connections/migration.sql apps/api/src/modules/socialConnections/socialConnectionStore.ts apps/api/src/modules/socialConnections/socialConnectionStore.test.ts apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.ts apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.test.ts apps/api/src/modules/socialConnections/socialConnectionStoreFactory.ts
git commit -m "Add user social connection store"
```

Expected: commit includes only the files from this task.

---

### Task 2: PostPeer Connect Config, Signed State, And Provider Client

**Files:**
- Modify: `apps/api/src/config/env.ts`
- Modify: `apps/api/src/config/env.test.ts`
- Create: `apps/api/src/modules/socialConnections/postPeerConnectState.ts`
- Create: `apps/api/src/modules/socialConnections/postPeerConnectState.test.ts`
- Create: `apps/api/src/modules/socialConnections/postPeerConnectClient.ts`
- Create: `apps/api/src/modules/socialConnections/postPeerConnectClient.test.ts`
- Modify: `apps/api/.env.example`
- Modify: `API.md`

- [ ] **Step 1: Write failing env tests**

Add this case to `apps/api/src/config/env.test.ts`:

```ts
it('reads optional PostPeer connect configuration', () => {
  const config = readServerConfig({
    POSTPEER_CONNECT_CREATE_PATH: '/v1/connect/links',
    POSTPEER_CONNECT_CALLBACK_URL: 'https://postdee-api.onrender.com/social-connections/postpeer/callback',
    POSTPEER_CONNECT_STATE_SECRET: 'state-secret',
    POSTPEER_CONNECT_CALLBACK_SECRET: 'callback-secret'
  });

  expect(config.postPeerConnectCreatePath).toBe('/v1/connect/links');
  expect(config.postPeerConnectCallbackUrl).toBe(
    'https://postdee-api.onrender.com/social-connections/postpeer/callback'
  );
  expect(config.postPeerConnectStateSecret).toBe('state-secret');
  expect(config.postPeerConnectCallbackSecret).toBe('callback-secret');
});
```

- [ ] **Step 2: Run env tests and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/config/env.test.ts
```

Expected: fail because the new config fields do not exist.

- [ ] **Step 3: Implement env fields**

In `apps/api/src/config/env.ts`, add these fields to `ServerConfig`:

```ts
  postPeerConnectCreatePath?: string;
  postPeerConnectCallbackUrl?: string;
  postPeerConnectStateSecret?: string;
  postPeerConnectCallbackSecret?: string;
```

In `readServerConfig`, add:

```ts
    postPeerConnectCreatePath: readOptional(env, 'POSTPEER_CONNECT_CREATE_PATH'),
    postPeerConnectCallbackUrl: readOptional(env, 'POSTPEER_CONNECT_CALLBACK_URL'),
    postPeerConnectStateSecret: readOptional(env, 'POSTPEER_CONNECT_STATE_SECRET'),
    postPeerConnectCallbackSecret: readOptional(env, 'POSTPEER_CONNECT_CALLBACK_SECRET'),
```

Add the same env names to `apps/api/.env.example` and the environment table in `API.md`.

- [ ] **Step 4: Run env tests and verify GREEN**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/config/env.test.ts
```

Expected: pass.

- [ ] **Step 5: Write signed-state tests**

Create `apps/api/src/modules/socialConnections/postPeerConnectState.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

import { createPostPeerConnectStateManager } from './postPeerConnectState.js';

describe('createPostPeerConnectStateManager', () => {
  it('signs and verifies user/platform state', () => {
    const manager = createPostPeerConnectStateManager({
      secret: 'state-secret',
      nowMs: () => 1_782_432_000_000,
      randomBytes: () => Buffer.from('nonce-1234567890')
    });

    const signed = manager.create({
      userId: 'seller-1',
      platform: 'TIKTOK',
      ttlSeconds: 300
    });

    expect(manager.verify(signed.token)).toMatchObject({
      userId: 'seller-1',
      platform: 'TIKTOK',
      expiresAt: '2026-06-26T09:25:00.000Z'
    });
    expect(signed.expiresAt).toBe('2026-06-26T09:25:00.000Z');
  });

  it('rejects tampered and expired state tokens', () => {
    const manager = createPostPeerConnectStateManager({
      secret: 'state-secret',
      nowMs: () => 1_782_432_000_000,
      randomBytes: () => Buffer.from('nonce-1234567890')
    });
    const signed = manager.create({
      userId: 'seller-1',
      platform: 'TIKTOK',
      ttlSeconds: 1
    });
    const expiredManager = createPostPeerConnectStateManager({
      secret: 'state-secret',
      nowMs: () => 1_782_432_002_000
    });

    expect(() => manager.verify(`${signed.token}x`)).toThrow(/Invalid PostPeer connect state/);
    expect(() => expiredManager.verify(signed.token)).toThrow(/PostPeer connect state expired/);
  });
});
```

- [ ] **Step 6: Implement signed-state manager**

Create `apps/api/src/modules/socialConnections/postPeerConnectState.ts`:

```ts
import { createHmac, randomBytes as defaultRandomBytes, timingSafeEqual } from 'node:crypto';

import type { SocialConnectionPlatform } from './socialConnectionStore.js';
import { isSocialConnectionPlatform } from './socialConnectionStore.js';

type ConnectStatePayload = {
  userId: string;
  platform: SocialConnectionPlatform;
  expiresAtMs: number;
  nonce: string;
};

export type VerifiedPostPeerConnectState = {
  userId: string;
  platform: SocialConnectionPlatform;
  expiresAt: string;
};

const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
const decode = (value: string) => JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as unknown;

const sign = (secret: string, payload: string) =>
  createHmac('sha256', secret).update(payload).digest('base64url');

const signaturesMatch = (left: string, right: string) => {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
};

export const createPostPeerConnectStateManager = ({
  secret,
  nowMs = () => Date.now(),
  randomBytes = defaultRandomBytes
}: {
  secret: string;
  nowMs?: () => number;
  randomBytes?: (size: number) => Buffer;
}) => ({
  create: ({
    userId,
    platform,
    ttlSeconds = 600
  }: {
    userId: string;
    platform: SocialConnectionPlatform;
    ttlSeconds?: number;
  }) => {
    const expiresAtMs = nowMs() + ttlSeconds * 1000;
    const payload = encode({
      userId,
      platform,
      expiresAtMs,
      nonce: randomBytes(16).toString('base64url')
    } satisfies ConnectStatePayload);
    const signature = sign(secret, payload);

    return {
      token: `${payload}.${signature}`,
      expiresAt: new Date(expiresAtMs).toISOString()
    };
  },
  verify: (token: string): VerifiedPostPeerConnectState => {
    const [payload, signature] = token.split('.');

    if (!payload || !signature || !signaturesMatch(sign(secret, payload), signature)) {
      throw new Error('Invalid PostPeer connect state');
    }

    const decoded = decode(payload) as Partial<ConnectStatePayload>;

    if (
      typeof decoded.userId !== 'string' ||
      !isSocialConnectionPlatform(decoded.platform) ||
      typeof decoded.expiresAtMs !== 'number'
    ) {
      throw new Error('Invalid PostPeer connect state');
    }

    if (decoded.expiresAtMs <= nowMs()) {
      throw new Error('PostPeer connect state expired');
    }

    return {
      userId: decoded.userId,
      platform: decoded.platform,
      expiresAt: new Date(decoded.expiresAtMs).toISOString()
    };
  }
});
```

- [ ] **Step 7: Write PostPeer connect client tests**

Create `apps/api/src/modules/socialConnections/postPeerConnectClient.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';

import {
  PostPeerConnectUnavailableError,
  createPostPeerConnectClient
} from './postPeerConnectClient.js';

describe('createPostPeerConnectClient', () => {
  it('reports unavailable when create path is not configured', async () => {
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test'
    });

    await expect(
      client.createConnectLink({
        platform: 'TIKTOK',
        state: 'signed-state',
        callbackUrl: 'https://postdee.test/social-connections/postpeer/callback'
      })
    ).rejects.toBeInstanceOf(PostPeerConnectUnavailableError);
  });

  it('posts a connect-link request and returns the authorize URL', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ connectUrl: 'https://postpeer.test/connect/abc' })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      createPath: '/v1/connect/links',
      fetchImpl
    });

    await expect(
      client.createConnectLink({
        platform: 'TIKTOK',
        state: 'signed-state',
        callbackUrl: 'https://postdee.test/social-connections/postpeer/callback'
      })
    ).resolves.toEqual({ connectUrl: 'https://postpeer.test/connect/abc' });

    expect(fetchImpl).toHaveBeenCalledWith('https://api.postpeer.test/v1/connect/links', {
      method: 'POST',
      headers: {
        'x-access-key': 'pp-key',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        platform: 'tiktok',
        state: 'signed-state',
        callbackUrl: 'https://postdee.test/social-connections/postpeer/callback'
      })
    });
  });
});
```

- [ ] **Step 8: Implement PostPeer connect client**

Create `apps/api/src/modules/socialConnections/postPeerConnectClient.ts`:

```ts
import type { SocialConnectionPlatform } from './socialConnectionStore.js';

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

const postPeerPlatform: Record<SocialConnectionPlatform, string> = {
  TIKTOK: 'tiktok',
  YOUTUBE_SHORTS: 'youtube',
  INSTAGRAM_REELS: 'instagram',
  FACEBOOK_REELS: 'facebook'
};

export class PostPeerConnectUnavailableError extends Error {
  constructor() {
    super('PostPeer account linking is not configured yet');
  }
}

export class PostPeerConnectProviderError extends Error {
  constructor(status?: number) {
    super(`PostPeer account linking failed with status ${status ?? 'unknown'}`);
  }
}

export type PostPeerConnectClient = {
  createConnectLink: (input: {
    platform: SocialConnectionPlatform;
    state: string;
    callbackUrl: string;
  }) => Promise<{ connectUrl: string }>;
};

const readConnectUrl = (payload: unknown) => {
  if (typeof payload !== 'object' || payload === null) {
    return undefined;
  }

  const body = payload as Record<string, unknown>;
  const value = body.connectUrl ?? body.url ?? body.authorizeUrl;

  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
};

export const createPostPeerConnectClient = ({
  apiKey,
  baseUrl,
  createPath,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey?: string;
  baseUrl: string;
  createPath?: string;
  fetchImpl?: FetchImpl;
}): PostPeerConnectClient => ({
  createConnectLink: async ({ platform, state, callbackUrl }) => {
    if (!apiKey || !createPath) {
      throw new PostPeerConnectUnavailableError();
    }

    const response = await fetchImpl(`${baseUrl.replace(/\/$/, '')}${createPath}`, {
      method: 'POST',
      headers: {
        'x-access-key': apiKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        platform: postPeerPlatform[platform],
        state,
        callbackUrl
      })
    });

    if (!response.ok) {
      throw new PostPeerConnectProviderError(response.status);
    }

    const connectUrl = readConnectUrl(await response.json());

    if (!connectUrl) {
      throw new PostPeerConnectProviderError(response.status);
    }

    return { connectUrl };
  }
});
```

- [ ] **Step 9: Run config/state/client tests**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/config/env.test.ts src/modules/socialConnections/postPeerConnectState.test.ts src/modules/socialConnections/postPeerConnectClient.test.ts
```

Expected: pass.

- [ ] **Step 10: Commit connect config/client**

Run:

```powershell
git add apps/api/src/config/env.ts apps/api/src/config/env.test.ts apps/api/.env.example API.md apps/api/src/modules/socialConnections/postPeerConnectState.ts apps/api/src/modules/socialConnections/postPeerConnectState.test.ts apps/api/src/modules/socialConnections/postPeerConnectClient.ts apps/api/src/modules/socialConnections/postPeerConnectClient.test.ts
git commit -m "Add PostPeer connect client"
```

Expected: commit includes only config, docs, and connect helper files.

---

### Task 3: Social Connection API Routes And App Wiring

**Files:**
- Create: `apps/api/src/modules/socialConnections/socialConnectionRoutes.ts`
- Create: `apps/api/src/modules/socialConnections/socialConnectionRoutes.test.ts`
- Modify: `apps/api/src/app.ts`
- Modify: `apps/api/src/modules/account/accountRoutes.ts`

- [ ] **Step 1: Write route tests**

Create `apps/api/src/modules/socialConnections/socialConnectionRoutes.test.ts`:

```ts
import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import type { AuthUser } from '../auth/authTypes.js';
import { createInMemorySocialConnectionStore } from './socialConnectionStore.js';
import { PostPeerConnectUnavailableError } from './postPeerConnectClient.js';
import { registerSocialConnectionRoutes } from './socialConnectionRoutes.js';

const createTestApp = ({
  authUser = { id: 'seller-1', provider: 'mock' } satisfies AuthUser,
  connectClient,
  stateManager,
  callbackSecret = 'callback-secret'
}: {
  authUser?: AuthUser;
  connectClient?: {
    createConnectLink: (input: {
      platform: 'TIKTOK' | 'YOUTUBE_SHORTS' | 'INSTAGRAM_REELS' | 'FACEBOOK_REELS';
      state: string;
      callbackUrl: string;
    }) => Promise<{ connectUrl: string }>;
  };
  stateManager?: {
    create: (input: { userId: string; platform: 'TIKTOK'; ttlSeconds?: number }) => {
      token: string;
      expiresAt: string;
    };
    verify: (token: string) => {
      userId: string;
      platform: 'TIKTOK';
      expiresAt: string;
    };
  };
  callbackSecret?: string;
} = {}) => {
  const app = express();
  const router = express.Router();
  const store = createInMemorySocialConnectionStore({
    now: () => '2026-06-26T09:00:00.000Z'
  });
  const authMiddleware: express.RequestHandler = (_request, response, next) => {
    response.locals.authUser = authUser;
    next();
  };

  app.use(express.json());
  registerSocialConnectionRoutes(router, authMiddleware, {
    store,
    connectClient:
      connectClient ??
      ({
        createConnectLink: async () => {
          throw new PostPeerConnectUnavailableError();
        }
      } as never),
    stateManager:
      stateManager ??
      ({
        create: () => ({
          token: 'signed-state',
          expiresAt: '2026-06-26T09:10:00.000Z'
        }),
        verify: () => ({
          userId: 'seller-1',
          platform: 'TIKTOK',
          expiresAt: '2026-06-26T09:10:00.000Z'
        })
      } as never),
    callbackUrl: 'https://postdee.test/social-connections/postpeer/callback',
    callbackSecret
  });
  app.use(router);

  return { app, store };
};

describe('registerSocialConnectionRoutes', () => {
  it('lists connection statuses for the authenticated user', async () => {
    const { app, store } = createTestApp();
    await store.upsert({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1',
      displayName: '@seller_one'
    });

    const response = await request(app).get('/social-connections').expect(200);

    expect(response.body.connections).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one'
        }),
        { platform: 'YOUTUBE_SHORTS', connected: false }
      ])
    );
  });

  it('returns a connect URL for a supported platform', async () => {
    const connectClient = {
      createConnectLink: vi.fn().mockResolvedValue({
        connectUrl: 'https://postpeer.test/connect/abc'
      })
    };
    const { app } = createTestApp({ connectClient: connectClient as never });

    const response = await request(app).post('/social-connections/TIKTOK/connect').expect(200);

    expect(response.body).toEqual({
      connectUrl: 'https://postpeer.test/connect/abc',
      expiresAt: '2026-06-26T09:10:00.000Z'
    });
    expect(connectClient.createConnectLink).toHaveBeenCalledWith({
      platform: 'TIKTOK',
      state: 'signed-state',
      callbackUrl: 'https://postdee.test/social-connections/postpeer/callback'
    });
  });

  it('returns 503 when PostPeer account linking is not configured', async () => {
    const { app } = createTestApp();

    const response = await request(app).post('/social-connections/TIKTOK/connect').expect(503);

    expect(response.body.message).toBe('PostPeer account linking is not configured yet');
  });

  it('stores callback results only after validating state and callback secret', async () => {
    const { app, store } = createTestApp();

    await request(app)
      .post('/social-connections/postpeer/callback')
      .set('x-postpeer-callback-secret', 'callback-secret')
      .send({
        state: 'signed-state',
        accountId: 'acct-tiktok-1',
        displayName: '@seller_one',
        externalAccountId: 'external-tiktok-1'
      })
      .expect(200);

    await expect(store.getAccountId({ userId: 'seller-1', platform: 'TIKTOK' })).resolves.toBe(
      'acct-tiktok-1'
    );
  });

  it('disconnects a user platform connection', async () => {
    const { app, store } = createTestApp();
    await store.upsert({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1'
    });

    await request(app).delete('/social-connections/TIKTOK').expect(200);
    await expect(store.getAccountId({ userId: 'seller-1', platform: 'TIKTOK' })).resolves.toBeUndefined();
  });
});
```

- [ ] **Step 2: Run route tests and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/socialConnections/socialConnectionRoutes.test.ts
```

Expected: fail because `socialConnectionRoutes.ts` does not exist.

- [ ] **Step 3: Implement social connection routes**

Create `apps/api/src/modules/socialConnections/socialConnectionRoutes.ts` with these route behaviors:

```ts
import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import {
  PostPeerConnectProviderError,
  PostPeerConnectUnavailableError,
  type PostPeerConnectClient
} from './postPeerConnectClient.js';
import type { VerifiedPostPeerConnectState } from './postPeerConnectState.js';
import {
  type SocialConnectionStore,
  isSocialConnectionPlatform
} from './socialConnectionStore.js';

type PostPeerConnectStateManager = {
  create: (input: {
    userId: string;
    platform: 'TIKTOK' | 'YOUTUBE_SHORTS' | 'INSTAGRAM_REELS' | 'FACEBOOK_REELS';
    ttlSeconds?: number;
  }) => { token: string; expiresAt: string };
  verify: (token: string) => VerifiedPostPeerConnectState;
};

const readString = (value: unknown) => (typeof value === 'string' ? value.trim() : '');

const readCallbackPayload = (request: Parameters<RequestHandler>[0]) => ({
  state: readString(request.body?.state ?? request.query.state),
  accountId: readString(
    request.body?.accountId ??
      request.body?.postPeerAccountId ??
      request.body?.integrationId ??
      request.query.accountId ??
      request.query.integrationId
  ),
  displayName: readString(request.body?.displayName ?? request.query.displayName) || undefined,
  externalAccountId:
    readString(request.body?.externalAccountId ?? request.query.externalAccountId) || undefined
});

export const registerSocialConnectionRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  {
    store,
    connectClient,
    stateManager,
    callbackUrl,
    callbackSecret
  }: {
    store: SocialConnectionStore;
    connectClient: PostPeerConnectClient;
    stateManager?: PostPeerConnectStateManager;
    callbackUrl?: string;
    callbackSecret?: string;
  }
) => {
  router.get('/social-connections', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
      return;
    }

    response.json({
      connections: await store.listForUser(authUser.id)
    });
  });

  router.post('/social-connections/:platform/connect', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    const platform = request.params.platform;

    if (!authUser) {
      response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
      return;
    }

    if (!isSocialConnectionPlatform(platform)) {
      response.status(400).json({ status: 'error', message: 'Unsupported social platform' });
      return;
    }

    if (!stateManager || !callbackUrl) {
      response.status(503).json({
        status: 'error',
        message: 'PostPeer account linking is not configured yet'
      });
      return;
    }

    const state = stateManager.create({ userId: authUser.id, platform });

    try {
      const link = await connectClient.createConnectLink({
        platform,
        state: state.token,
        callbackUrl
      });

      response.json({
        connectUrl: link.connectUrl,
        expiresAt: state.expiresAt
      });
    } catch (error) {
      if (error instanceof PostPeerConnectUnavailableError) {
        response.status(503).json({ status: 'error', message: error.message });
        return;
      }

      if (error instanceof PostPeerConnectProviderError) {
        response.status(502).json({ status: 'error', message: error.message });
        return;
      }

      throw error;
    }
  });

  const handleCallback: RequestHandler = async (request, response) => {
    if (callbackSecret) {
      const receivedSecret = readString(request.headers['x-postpeer-callback-secret']);

      if (receivedSecret !== callbackSecret) {
        response.status(401).json({ status: 'error', message: 'Invalid PostPeer callback secret' });
        return;
      }
    }

    if (!stateManager) {
      response.status(503).json({
        status: 'error',
        message: 'PostPeer account linking is not configured yet'
      });
      return;
    }

    const payload = readCallbackPayload(request);

    if (!payload.state || !payload.accountId) {
      response.status(400).json({ status: 'error', message: 'state and accountId are required' });
      return;
    }

    let verifiedState: VerifiedPostPeerConnectState;
    try {
      verifiedState = stateManager.verify(payload.state);
    } catch (error) {
      response.status(400).json({
        status: 'error',
        message: error instanceof Error ? error.message : 'Invalid PostPeer connect state'
      });
      return;
    }

    await store.upsert({
      userId: verifiedState.userId,
      platform: verifiedState.platform,
      postPeerAccountId: payload.accountId,
      displayName: payload.displayName,
      externalAccountId: payload.externalAccountId
    });

    response.json({ status: 'ok' });
  };

  router.get('/social-connections/postpeer/callback', handleCallback);
  router.post('/social-connections/postpeer/callback', handleCallback);

  router.delete('/social-connections/:platform', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    const platform = request.params.platform;

    if (!authUser) {
      response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
      return;
    }

    if (!isSocialConnectionPlatform(platform)) {
      response.status(400).json({ status: 'error', message: 'Unsupported social platform' });
      return;
    }

    await store.disconnect({ userId: authUser.id, platform });
    response.json({ status: 'ok' });
  });
};
```

- [ ] **Step 4: Wire routes and account deletion**

Modify `apps/api/src/app.ts`:

```ts
import { registerSocialConnectionRoutes } from './modules/socialConnections/socialConnectionRoutes.js';
import { createSocialConnectionStore } from './modules/socialConnections/socialConnectionStoreFactory.js';
import { createPostPeerConnectClient } from './modules/socialConnections/postPeerConnectClient.js';
import { createPostPeerConnectStateManager } from './modules/socialConnections/postPeerConnectState.js';
import type { PrismaSocialConnectionClient } from './modules/socialConnections/prismaSocialConnectionRepository.js';
```

Include `config.postStore === 'prisma'` already creates Prisma; add social connections to the Prisma condition if the code has a config-specific condition for stores. Then create:

```ts
  const socialConnectionStore = createSocialConnectionStore({
    prisma: prismaClient as unknown as PrismaSocialConnectionClient | undefined
  });
  const postPeerConnectStateManager = config.postPeerConnectStateSecret
    ? createPostPeerConnectStateManager({ secret: config.postPeerConnectStateSecret })
    : undefined;
```

Register routes before planned routes:

```ts
  registerSocialConnectionRoutes(router, authMiddleware, {
    store: socialConnectionStore,
    connectClient: createPostPeerConnectClient({
      apiKey: config.postPeerApiKey,
      baseUrl: config.postPeerApiBaseUrl,
      createPath: config.postPeerConnectCreatePath
    }),
    stateManager: postPeerConnectStateManager,
    callbackUrl: config.postPeerConnectCallbackUrl,
    callbackSecret: config.postPeerConnectCallbackSecret
  });
```

Modify `apps/api/src/modules/account/accountRoutes.ts` dependencies:

```ts
import type { SocialConnectionStore } from '../socialConnections/socialConnectionStore.js';
```

Add to `AccountRouteDependencies`:

```ts
  socialConnectionStore?: SocialConnectionStore;
```

Add to the deletion list:

```ts
      socialConnectionStore?.deleteAllForUser,
```

Pass `socialConnectionStore` from `app.ts`.

- [ ] **Step 5: Update account deletion test and run route tests**

Add a focused test to `apps/api/src/modules/account/accountRoutes.test.ts` that passes `socialConnectionStore` into `registerAccountRoutes`, creates one social connection for the deleting user, calls `DELETE /account`, and verifies the connection is removed:

```ts
const socialConnectionStore = createInMemorySocialConnectionStore();
await socialConnectionStore.upsert({
  userId: 'seller-delete',
  platform: 'TIKTOK',
  postPeerAccountId: 'acct-tiktok-delete'
});

await request(app)
  .delete('/account')
  .set('x-postdee-user-id', 'seller-delete')
  .expect(200);

await expect(
  socialConnectionStore.getAccountId({
    userId: 'seller-delete',
    platform: 'TIKTOK'
  })
).resolves.toBeUndefined();
```

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/socialConnections/socialConnectionRoutes.test.ts src/modules/account/accountRoutes.test.ts
```

Expected: pass.

- [ ] **Step 6: Commit social connection routes**

Run:

```powershell
git add apps/api/src/modules/socialConnections/socialConnectionRoutes.ts apps/api/src/modules/socialConnections/socialConnectionRoutes.test.ts apps/api/src/app.ts apps/api/src/modules/account/accountRoutes.ts apps/api/src/modules/account/accountRoutes.test.ts
git commit -m "Add social connection API routes"
```

Expected: commit includes the API route wiring and related tests.

---

### Task 4: Publish With User-Owned PostPeer Account IDs

**Files:**
- Modify: `apps/api/src/workers/publishWorker.ts`
- Modify: `apps/api/src/workers/postPeerPublisher.ts`
- Modify: `apps/api/src/workers/postPeerPublisher.test.ts`
- Modify: `apps/api/src/workers/platformPublisherFactory.ts`
- Modify: `apps/api/src/workers/publishScheduler.ts`
- Modify: `apps/api/src/workers/publishWorkerRunner.ts`
- Modify: `apps/api/src/app.ts`
- Modify: `apps/api/src/workers/publishScheduler.test.ts`
- Modify: `apps/api/src/workers/publishWorker.test.ts`

- [ ] **Step 1: Write failing PostPeer publisher tests for user account resolution**

Add tests to `apps/api/src/workers/postPeerPublisher.test.ts`:

```ts
it('resolves a PostPeer account id from the post owner before publishing', async () => {
  const calls: { body: unknown }[] = [];
  const publisher = createPostPeerPublisher({
    apiKey: 'pp-key',
    baseUrl: 'https://api.postpeer.test',
    resolveAccountId: async ({ userId, platform }) => {
      expect(userId).toBe('seller-1');
      expect(platform).toBe('TIKTOK');
      return 'acct-user-tiktok';
    },
    fetchImpl: async (_url, init) => {
      calls.push({ body: JSON.parse(String(init.body)) });
      return {
        ok: true,
        status: 200,
        json: async () => ({ id: 'postpeer-post-1' })
      };
    }
  });

  await publisher.publish({
    userId: 'seller-1',
    postId: 'post-1',
    caption: 'hello',
    videoS3Key: 'https://cdn.test/video.mp4',
    platform: 'TIKTOK'
  });

  expect(calls[0].body).toMatchObject({
    platforms: [{ platform: 'tiktok', accountId: 'acct-user-tiktok' }]
  });
});

it('does not use another user account id when resolver has none for this user', async () => {
  const publisher = createPostPeerPublisher({
    apiKey: 'pp-key',
    baseUrl: 'https://api.postpeer.test',
    accountIds: { TIKTOK: 'operator-tiktok' },
    resolveAccountId: async () => undefined,
    fetchImpl: async () => {
      throw new Error('fetch should not run when the account id is missing');
    }
  });

  await expect(
    publisher.publish({
      userId: 'seller-2',
      postId: 'post-1',
      caption: 'hello',
      videoS3Key: 'https://cdn.test/video.mp4',
      platform: 'TIKTOK'
    })
  ).rejects.toThrow(/POSTPEER_TIKTOK_ACCOUNT_ID is required/);
});
```

- [ ] **Step 2: Run PostPeer publisher tests and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/workers/postPeerPublisher.test.ts
```

Expected: fail because `PlatformPublishInput` lacks `userId` and `resolveAccountId` is not supported.

- [ ] **Step 3: Add userId to publish input and processPublishJob**

Modify `apps/api/src/workers/publishWorker.ts`:

```ts
export type PlatformPublishInput = {
  userId: string;
  postId: string;
  caption?: string;
  videoS3Key?: string;
  platform: Platform;
};
```

In `processPublishJob`, pass the owner:

```ts
        return await publisher.publish({
          userId: jobData.userId,
          postId: jobData.postId,
          caption: jobData.caption,
          videoS3Key: jobData.videoS3Key,
          platform
        });
```

Update any mock publisher tests whose fake publishers destructure input so they accept `userId`.

- [ ] **Step 4: Implement resolver-first PostPeer publisher behavior**

Modify `apps/api/src/workers/postPeerPublisher.ts`:

```ts
type ResolveAccountId = (input: {
  userId: string;
  platform: Platform;
}) => string | undefined | Promise<string | undefined>;
```

Change `readPostPeerAccountId`:

```ts
const readPostPeerAccountId = async ({
  accountIds,
  resolveAccountId,
  userId,
  platform
}: {
  accountIds: PostPeerAccountIds;
  resolveAccountId?: ResolveAccountId;
  userId: string;
  platform: Platform;
}) => {
  const resolvedAccountId = (await resolveAccountId?.({ userId, platform }))?.trim();
  const accountId = resolvedAccountId ?? accountIds[platform]?.trim();

  if (!accountId) {
    throw new Error(`${postPeerAccountIdEnv[platform]} is required to publish ${platform}`);
  }

  return accountId;
};
```

Add `resolveAccountId` to the factory parameters and call:

```ts
    const accountId = await readPostPeerAccountId({
      accountIds,
      resolveAccountId,
      userId,
      platform
    });
```

- [ ] **Step 5: Wire social connection store into publisher factory**

Modify `apps/api/src/workers/platformPublisherFactory.ts` to accept an optional store:

```ts
import type { SocialConnectionStore } from '../modules/socialConnections/socialConnectionStore.js';
import { isPublishableSocialPlatform } from '../modules/socialConnections/socialConnectionStore.js';
```

Add parameter:

```ts
  socialConnectionStore?: SocialConnectionStore;
```

Pass resolver to `createPostPeerPublisher`:

```ts
      resolveAccountId: socialConnectionStore
        ? async ({ userId, platform }) =>
            isPublishableSocialPlatform(platform)
              ? socialConnectionStore.getAccountId({ userId, platform })
              : undefined
        : undefined,
```

Wire this store in `apps/api/src/app.ts` and `apps/api/src/workers/publishWorkerRunner.ts`.

- [ ] **Step 6: Run publish tests and fix call sites**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/workers/postPeerPublisher.test.ts src/workers/publishWorker.test.ts src/workers/publishScheduler.test.ts src/workers/publishWorkerRunner.test.ts
```

Expected: tests pass after updating fake publishers and factory call sites.

- [ ] **Step 7: Add app-level regression test for user scoping**

Add a test in `apps/api/src/app.flow.test.ts` or `apps/api/src/workers/postPeerPublisher.test.ts` that creates two users with different stored connections and verifies publish for seller A sends seller A's account id. Use the in-memory `socialConnectionStore` injection when testing `createApp`.

Test assertion:

```ts
expect(postPeerCalls[0].body.platforms[0].accountId).toBe('acct-seller-a-tiktok');
```

- [ ] **Step 8: Commit user-owned publishing**

Run:

```powershell
git add apps/api/src/workers/publishWorker.ts apps/api/src/workers/postPeerPublisher.ts apps/api/src/workers/postPeerPublisher.test.ts apps/api/src/workers/platformPublisherFactory.ts apps/api/src/workers/publishScheduler.ts apps/api/src/workers/publishWorkerRunner.ts apps/api/src/app.ts apps/api/src/workers/publishScheduler.test.ts apps/api/src/workers/publishWorker.test.ts apps/api/src/app.flow.test.ts
git commit -m "Use user social connections for PostPeer publishing"
```

Expected: commit includes publish worker changes and tests only.

---

### Task 5: Mobile API Client And Profile Connection UI

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Modify: `apps/mobile/lib/core/network/postdee_api_client.dart`
- Modify: `apps/mobile/lib/features/profile/profile_screen.dart`
- Modify: `apps/mobile/test/profile_screen_test.dart`

- [ ] **Step 1: Add url_launcher dependency**

Modify `apps/mobile/pubspec.yaml`:

```yaml
  url_launcher: ^6.3.1
```

Run:

```powershell
cd apps/mobile
flutter pub get
```

Expected: dependency resolution succeeds and `pubspec.lock` updates.

- [ ] **Step 2: Add profile dependency injection for widget tests**

Modify the `ProfileScreen` constructor in `apps/mobile/lib/features/profile/profile_screen.dart` so profile widget tests can inject a fake API client and URL opener without making network calls:

```dart
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.languageController,
    required this.themeController,
    required this.onOpenTemplates,
    required this.onDeleteAccount,
    this.socialConnectionApiClient,
    this.openSocialConnectionUrl,
    super.key,
  });

  final PostDeeApiClient? socialConnectionApiClient;
  final Future<bool> Function(Uri url)? openSocialConnectionUrl;
}
```

Pass those fields into `_ConnectedPlatformsCard` from `ProfileScreen.build`.

- [ ] **Step 3: Add mobile API models and methods**

Modify `apps/mobile/lib/core/network/postdee_api_client.dart` with:

```dart
class SocialConnectionResult {
  const SocialConnectionResult({
    required this.platform,
    required this.connected,
    this.displayName,
    this.externalAccountId,
    this.connectedAt,
  });

  final String platform;
  final bool connected;
  final String? displayName;
  final String? externalAccountId;
  final DateTime? connectedAt;

  factory SocialConnectionResult.fromJson(Map<String, Object?> json) =>
      SocialConnectionResult(
        platform: json['platform'] as String,
        connected: json['connected'] as bool? ?? false,
        displayName: json['displayName'] as String?,
        externalAccountId: json['externalAccountId'] as String?,
        connectedAt: json['connectedAt'] is String
            ? DateTime.tryParse(json['connectedAt'] as String)
            : null,
      );
}

class SocialConnectLinkResult {
  const SocialConnectLinkResult({
    required this.connectUrl,
    required this.expiresAt,
  });

  final Uri connectUrl;
  final DateTime expiresAt;

  factory SocialConnectLinkResult.fromJson(Map<String, Object?> json) =>
      SocialConnectLinkResult(
        connectUrl: Uri.parse(json['connectUrl'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}
```

Add methods:

```dart
  Future<List<SocialConnectionResult>> listSocialConnections() async {
    final response = await _getJson('/social-connections');
    final connections = response['connections'];

    if (connections is! List<dynamic>) {
      throw const ApiException(
          'Social connections response is missing connections');
    }

    return connections
        .map((connection) => SocialConnectionResult.fromJson(
            connection as Map<String, Object?>))
        .toList();
  }

  Future<SocialConnectLinkResult> createSocialConnectionLink(
      String platform) async {
    final response =
        await _postJson('/social-connections/$platform/connect', {});

    return SocialConnectLinkResult.fromJson(response);
  }

  Future<void> disconnectSocialConnection(String platform) async {
    await _deleteJson('/social-connections/$platform');
  }
```

- [ ] **Step 4: Refactor profile card to accept API client and URL opener**

In `apps/mobile/lib/features/profile/profile_screen.dart`, replace the current card call with:

```dart
_ConnectedPlatformsCard(
  apiClient: socialConnectionApiClient,
  openUrl: openSocialConnectionUrl,
),
```

Make `_ConnectedPlatformsCard` stateful with:

```dart
class _ConnectedPlatformsCard extends StatefulWidget {
  const _ConnectedPlatformsCard({
    this.apiClient,
    this.openUrl,
  });

  final PostDeeApiClient? apiClient;
  final Future<bool> Function(Uri url)? openUrl;
```

Use defaults in state:

```dart
late final PostDeeApiClient _apiClient =
    widget.apiClient ?? PostDeeApiClient();

Future<bool> _openUrl(Uri url) async {
  if (widget.openUrl != null) {
    return widget.openUrl!(url);
  }

  return launchUrl(url, mode: LaunchMode.externalApplication);
}
```

Import:

```dart
import 'package:url_launcher/url_launcher.dart';
```

Load connections in `initState`, show `connectedCount/SocialPlatform.values.length`, and make each supported platform button call:

```dart
final link = await _apiClient.createSocialConnectionLink(platform.apiValue);
final opened = await _openUrl(link.connectUrl);
if (!opened) {
  throw const ApiException('ไม่สามารถเปิดหน้าต่างเชื่อมบัญชีได้');
}
```

Show a SnackBar for `ApiException` messages. After opening the URL, show a SnackBar telling the user to return and refresh.

- [ ] **Step 5: Update profile widget tests**

Modify `apps/mobile/test/profile_screen_test.dart` with a fake API client:

```dart
class FakeSocialConnectionApiClient extends PostDeeApiClient {
  FakeSocialConnectionApiClient({
    required this.connections,
    required this.connectLink,
  });

  final List<SocialConnectionResult> connections;
  final SocialConnectLinkResult connectLink;
  String? requestedPlatform;

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async =>
      connections;

  @override
  Future<SocialConnectLinkResult> createSocialConnectionLink(
      String platform) async {
    requestedPlatform = platform;
    return connectLink;
  }
}
```

Use this fake in a connected-count test:

```dart
final fakeClient = FakeSocialConnectionApiClient(
  connections: [
    const SocialConnectionResult(
      platform: 'TIKTOK',
      connected: true,
      displayName: '@seller_one',
    ),
    const SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
    const SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
    const SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
  ],
  connectLink: SocialConnectLinkResult(
    connectUrl: Uri.parse('https://postpeer.test/connect/youtube'),
    expiresAt: DateTime.utc(2026, 6, 26, 9, 10),
  ),
);
```

Expected UI assertions:

```dart
expect(find.text('1/4'), findsOneWidget);
expect(find.text('@seller_one'), findsOneWidget);
```

Add a connect-button test for a disconnected platform:

```dart
Uri? openedUrl;

await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('th'),
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: PostDeeLocalizations.supportedLocales,
    home: Scaffold(
      body: ProfileScreen(
        languageController: PostDeeLanguageController(),
        themeController: PostDeeThemeController(),
        onOpenTemplates: () {},
        onDeleteAccount: () {},
        socialConnectionApiClient: fakeClient,
        openSocialConnectionUrl: (url) async {
          openedUrl = url;
          return true;
        },
      ),
    ),
  ),
);

await tester.scrollUntilVisible(
  find.byKey(const ValueKey('profile-platform-connect-YOUTUBE_SHORTS')),
  500,
  scrollable: find.byType(Scrollable).first,
  maxScrolls: 30,
);
await tester.tap(find.byKey(const ValueKey('profile-platform-connect-YOUTUBE_SHORTS')));
await tester.pump();

expect(fakeClient.requestedPlatform, 'YOUTUBE_SHORTS');
expect(openedUrl.toString(), 'https://postpeer.test/connect/youtube');
```

- [ ] **Step 6: Run mobile tests**

Run:

```powershell
cd apps/mobile
flutter analyze
flutter test
```

Expected: analyze passes and Flutter tests pass. Primary commands are `flutter analyze` and `flutter test`; workspace fallback commands from `apps/mobile` are `..\\..\\.tools\\flutter\\bin\\flutter.bat analyze` and `..\\..\\.tools\\flutter\\bin\\flutter.bat test`.

- [ ] **Step 7: Commit mobile connection UI**

Run:

```powershell
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/lib/core/network/postdee_api_client.dart apps/mobile/lib/features/profile/profile_screen.dart apps/mobile/test/profile_screen_test.dart
git commit -m "Add mobile social connection UI"
```

Expected: commit includes only mobile API/UI/test/dependency changes.

---

### Task 6: Deployment Config, Docs, And Final Verification

**Files:**
- Modify: `render.yaml`
- Modify: `README.md`
- Modify: `API.md`
- Modify: `ARCHITECTURE.md`
- Modify: `ROADMAP.md`
- Modify: `LAUNCH_CHECKLIST.md`
- Modify: `docs/GO_LIVE.md`

- [ ] **Step 1: Update Render env placeholders**

Add secret-backed env entries to `render.yaml`:

```yaml
      - key: POSTPEER_CONNECT_CREATE_PATH
        sync: false
      - key: POSTPEER_CONNECT_CALLBACK_URL
        sync: false
      - key: POSTPEER_CONNECT_STATE_SECRET
        sync: false
      - key: POSTPEER_CONNECT_CALLBACK_SECRET
        sync: false
```

Keep `SOCIAL_PUBLISHER` unchanged until provider-level testing confirms real posting.

- [ ] **Step 2: Update docs**

Document these facts in `README.md`, `API.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `LAUNCH_CHECKLIST.md`, and `docs/GO_LIVE.md`:

```text
PostPeer social publishing now supports user-owned social connections. The old POSTPEER_*_ACCOUNT_ID env vars remain as non-production operator smoke-test fallback only. Production rejects shared env account ids and requires the /social-connections connect flow plus PostPeer connect-link configuration.
```

Add the new API routes to `API.md`:

```text
GET /social-connections
POST /social-connections/:platform/connect
GET|POST /social-connections/postpeer/callback
DELETE /social-connections/:platform
```

- [ ] **Step 3: Run full backend verification**

Run:

```powershell
cd apps/api
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npm.cmd run prisma:validate
```

Expected: tests pass, TypeScript build passes, Prisma schema is valid.

- [ ] **Step 4: Run mobile verification**

Run:

```powershell
cd apps/mobile
flutter analyze
flutter test
```

Expected: analyze passes and Flutter tests pass.

- [ ] **Step 5: Final status check**

Run:

```powershell
git status --short
```

Expected: only intentional files are modified. Do not stage unrelated existing work unless the user explicitly asks for it.

- [ ] **Step 6: Commit docs and config**

Run:

```powershell
git add render.yaml README.md API.md ARCHITECTURE.md ROADMAP.md LAUNCH_CHECKLIST.md docs/GO_LIVE.md
git commit -m "Document PostPeer user connection setup"
```

Expected: commit contains deployment/docs only.

---

## Self-Review

- Spec coverage: backend storage, authenticated routes, callback validation, publish-time account lookup, mobile profile UI, provider unavailable handling, account deletion cleanup, docs, and verification are covered by Tasks 1-6.
- Placeholder scan: this plan contains no open-ended placeholders; provider-specific uncertainty is handled as config-driven unavailable behavior with tests.
- Type consistency: platform names use `TIKTOK`, `YOUTUBE_SHORTS`, `INSTAGRAM_REELS`, and `FACEBOOK_REELS` across Prisma, backend TypeScript, and mobile Dart API values.
