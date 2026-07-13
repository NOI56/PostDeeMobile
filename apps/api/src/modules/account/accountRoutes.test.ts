import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import type { PostPeerConnectClient } from '../socialConnections/postPeerConnectClient.js';
import { createInMemorySocialConnectionStore } from '../socialConnections/socialConnectionStore.js';
import type { VideoStorage } from '../storage/videoStorage.js';

describe('account routes', () => {
  const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
    'uploads/' + encodeURIComponent(userId) + '/' + uploadId + '/' + fileName;
  const createPostAs = (app: ReturnType<typeof createApp>, userId: string) =>
    request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .send({
        caption: 'ของดีบอกต่อ',
        videoS3Key: ownedUploadKey(userId, 'demo.mp4'),
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO'
      })
      .expect(201);

  const createTemplateAs = (app: ReturnType<typeof createApp>, userId: string) =>
    request(app)
      .post('/templates')
      .set('x-postdee-user-id', userId)
      .send({ title: 'โปรโมชั่น', body: 'ลดราคาวันนี้' })
      .expect(201);

  const createFirebaseConfig = ({ deletionEnabled = true } = {}) =>
    readServerConfig({
      AUTH_PROVIDER: 'firebase',
      FIREBASE_PROJECT_ID: 'postdee-test',
      FIREBASE_AUTH_DELETE_ENABLED: String(deletionEnabled)
    });

  const createFirebaseVerifier = (userId: string) => ({
    verifyIdToken: vi.fn(async () => ({
      id: userId,
      provider: 'firebase' as const,
      authenticatedAtSeconds: Math.floor(Date.now() / 1000)
    }))
  });

  const createTemplateWithFirebase = (app: ReturnType<typeof createApp>) =>
    request(app)
      .post('/templates')
      .set('authorization', 'Bearer firebase-token')
      .send({ title: 'Firebase template', body: 'Delete retry data' })
      .expect(201);

  const createTestVideoStorage = (
    deleteAllVideosForOwner = vi.fn(async () => undefined)
  ): VideoStorage => ({
    supportsOwnerCleanup: true,
    createUpload: vi.fn(),
    createDownloadAccess: vi.fn(),
    deleteVideo: vi.fn(async () => undefined),
    deleteAllVideosForOwner
  });

  const createPostPeerCleanupClient = (
    overrides: Partial<PostPeerConnectClient> = {}
  ): PostPeerConnectClient => ({
    supportsIntegrationCleanup: true,
    createProfile: vi.fn(async () => ({ profileId: 'profile-1' })),
    createConnectUrl: vi.fn(async () => ({ connectUrl: 'https://postpeer.test/connect' })),
    listIntegrations: vi.fn(async () => []),
    disconnectIntegration: vi.fn(async () => undefined),
    ...overrides
  });

  it('permanently deletes all data for the authenticated user', async () => {
    const app = createApp();

    await createPostAs(app, 'seller-to-delete');
    await createTemplateAs(app, 'seller-to-delete');

    const postsBefore = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-to-delete')
      .expect(200);
    expect(postsBefore.body.posts).toHaveLength(1);

    const deleteResponse = await request(app)
      .delete('/account')
      .set('x-postdee-user-id', 'seller-to-delete')
      .expect(200);
    expect(deleteResponse.body).toEqual({ status: 'ok' });

    const postsAfter = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-to-delete')
      .expect(200);
    expect(postsAfter.body.posts).toEqual([]);

    const templatesAfter = await request(app)
      .get('/templates')
      .set('x-postdee-user-id', 'seller-to-delete')
      .expect(200);
    expect(templatesAfter.body.templates).toEqual([]);
  });

  it("leaves other users' data intact", async () => {
    const app = createApp();

    await createPostAs(app, 'seller-a');
    await createPostAs(app, 'seller-b');

    await request(app)
      .delete('/account')
      .set('x-postdee-user-id', 'seller-a')
      .expect(200);

    const sellerAPosts = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .expect(200);
    expect(sellerAPosts.body.posts).toEqual([]);

    const sellerBPosts = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-b')
      .expect(200);
    expect(sellerBPosts.body.posts).toHaveLength(1);
  });

  it('removes social connections when the account is deleted', async () => {
    const socialConnectionStore = createInMemorySocialConnectionStore();
    const app = createApp({ socialConnectionStore });

    await socialConnectionStore.upsert({
      userId: 'seller-social-delete',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-delete'
    });

    await request(app)
      .delete('/account')
      .set('x-postdee-user-id', 'seller-social-delete')
      .expect(200);

    await expect(
      socialConnectionStore.getAccountId({
        userId: 'seller-social-delete',
        platform: 'TIKTOK'
      })
    ).resolves.toBeUndefined();
  });

  it('does not mutate Firebase-backed accounts when identity deletion is disabled', async () => {
    const userId = 'firebase-disabled-delete';
    const app = createApp({
      config: createFirebaseConfig({ deletionEnabled: false }),
      firebaseVerifier: createFirebaseVerifier(userId)
    });

    await createTemplateWithFirebase(app);

    const response = await request(app)
      .delete('/account')
      .set('authorization', 'Bearer firebase-token')
      .expect(503);

    expect(response.body.code).toBe('ACCOUNT_DELETION_UNAVAILABLE');
    const templates = await request(app)
      .get('/templates')
      .set('authorization', 'Bearer firebase-token')
      .expect(200);
    expect(templates.body.templates).toHaveLength(1);
  });

  it('reports account deletion readiness before the mobile app revokes Apple access', async () => {
    const userId = 'firebase-ready-delete';
    const app = createApp({
      config: createFirebaseConfig(),
      firebaseVerifier: createFirebaseVerifier(userId),
      videoStorage: createTestVideoStorage(),
      accountIdentityDeleter: {
        deleteIdentity: vi.fn(async () => undefined)
      }
    });

    await request(app)
      .get('/account/deletion-readiness')
      .set('authorization', 'Bearer firebase-token')
      .expect(200, { status: 'ok', identityAlreadyDeleted: false });
  });

  it('fails readiness when a PostPeer profile exists but external cleanup is unavailable', async () => {
    const userId = 'postpeer-not-ready';
    const socialConnectionStore = createInMemorySocialConnectionStore();
    await socialConnectionStore.setProfileId({ userId, profileId: 'profile-not-ready' });
    const app = createApp({
      socialConnectionStore,
      postPeerConnectClient: createPostPeerCleanupClient({
        supportsIntegrationCleanup: false,
        disconnectIntegration: undefined
      })
    });

    const response = await request(app)
      .get('/account/deletion-readiness')
      .set('x-postdee-user-id', userId)
      .expect(503);

    expect(response.body.code).toBe('ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE');
  });

  it('disconnects every external PostPeer integration before deleting account data', async () => {
    const userId = 'postpeer-external-delete';
    const calls: string[] = [];
    const socialConnectionStore = createInMemorySocialConnectionStore();
    await socialConnectionStore.setProfileId({ userId, profileId: 'profile-delete' });
    await socialConnectionStore.upsert({
      userId,
      platform: 'TIKTOK',
      postPeerAccountId: 'int-tiktok'
    });
    const postPeerConnectClient = createPostPeerCleanupClient({
      listIntegrations: vi.fn(async () => {
        calls.push('list');
        return [
          { id: 'int-tiktok', platform: 'TIKTOK' },
          { id: 'int-future-platform' }
        ];
      }),
      disconnectIntegration: vi.fn(async ({ integrationId }) => {
        calls.push(`disconnect:${integrationId}`);
      })
    });
    const app = createApp({
      socialConnectionStore,
      postPeerConnectClient,
      videoStorage: createTestVideoStorage(
        vi.fn(async () => {
          calls.push('media');
        })
      )
    });
    await createTemplateAs(app, userId);

    await request(app).delete('/account').set('x-postdee-user-id', userId).expect(200);

    expect(calls).toEqual([
      'list',
      'disconnect:int-tiktok',
      'disconnect:int-future-platform',
      'media'
    ]);
    const templates = await request(app)
      .get('/templates')
      .set('x-postdee-user-id', userId)
      .expect(200);
    expect(templates.body.templates).toEqual([]);
  });

  it('keeps local data when PostPeer external cleanup fails', async () => {
    const userId = 'postpeer-cleanup-retry';
    const socialConnectionStore = createInMemorySocialConnectionStore();
    await socialConnectionStore.setProfileId({ userId, profileId: 'profile-retry' });
    const deleteAllVideosForOwner = vi.fn(async () => undefined);
    const disconnectAttempts: string[] = [];
    let app: ReturnType<typeof createApp>;
    const postPeerConnectClient = createPostPeerCleanupClient({
      listIntegrations: vi.fn(async () => {
        const queue = await request(app)
          .get('/queue/jobs')
          .set('x-postdee-user-id', userId)
          .expect(200);
        expect(queue.body.jobs).toEqual([]);
        return [
          { id: 'int-fails', platform: 'TIKTOK' },
          { id: 'int-still-attempted', platform: 'YOUTUBE_SHORTS' }
        ];
      }),
      disconnectIntegration: vi.fn(async ({ integrationId }) => {
        disconnectAttempts.push(integrationId);
        if (integrationId === 'int-fails') {
          throw new Error('PostPeer unavailable');
        }
      })
    });
    app = createApp({
      socialConnectionStore,
      postPeerConnectClient,
      videoStorage: createTestVideoStorage(deleteAllVideosForOwner)
    });
    await createPostAs(app, userId);
    await createTemplateAs(app, userId);

    const queueBefore = await request(app)
      .get('/queue/jobs')
      .set('x-postdee-user-id', userId)
      .expect(200);
    expect(queueBefore.body.jobs).toHaveLength(1);

    const response = await request(app)
      .delete('/account')
      .set('x-postdee-user-id', userId)
      .expect(503);

    expect(response.body.code).toBe('ACCOUNT_SOCIAL_CLEANUP_FAILED');
    expect(disconnectAttempts).toEqual(['int-fails', 'int-still-attempted']);
    expect(deleteAllVideosForOwner).not.toHaveBeenCalled();
    const posts = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', userId)
      .expect(200);
    expect(posts.body.posts).toHaveLength(1);
    const templates = await request(app)
      .get('/templates')
      .set('x-postdee-user-id', userId)
      .expect(200);
    expect(templates.body.templates).toHaveLength(1);
    await expect(socialConnectionStore.getProfileId(userId)).resolves.toBe('profile-retry');
  });

  it('does not mutate an active Firebase account without a recent sign-in', async () => {
    const userId = 'firebase-stale-auth-delete';
    const deleteAllVideosForOwner = vi.fn(async () => undefined);
    const accountIdentityDeleter = {
      deleteIdentity: vi.fn(async () => undefined)
    };
    const app = createApp({
      config: createFirebaseConfig(),
      firebaseVerifier: {
        verifyIdToken: vi.fn(async () => ({
          id: userId,
          provider: 'firebase' as const,
          authenticatedAtSeconds: Math.floor(Date.now() / 1000) - 6 * 60
        }))
      },
      videoStorage: createTestVideoStorage(deleteAllVideosForOwner),
      accountIdentityDeleter
    });
    await createTemplateWithFirebase(app);

    const response = await request(app)
      .delete('/account')
      .set('authorization', 'Bearer firebase-token')
      .expect(403);

    expect(response.body.code).toBe('ACCOUNT_REAUTHENTICATION_REQUIRED');
    expect(deleteAllVideosForOwner).not.toHaveBeenCalled();
    expect(accountIdentityDeleter.deleteIdentity).not.toHaveBeenCalled();
    const templates = await request(app)
      .get('/templates')
      .set('authorization', 'Bearer firebase-token')
      .expect(200);
    expect(templates.body.templates).toHaveLength(1);
  });

  it('lets a signed token finish cleanup after Firebase identity deletion succeeded', async () => {
    const userId = 'firebase-deleted-identity-retry';
    const accountIdentityDeleter = {
      deleteIdentity: vi.fn(async () => undefined)
    };
    const deletedIdentityVerifier = {
      verifyIdToken: vi.fn(async () => ({
        id: userId,
        provider: 'firebase' as const,
        authenticatedAtSeconds: Math.floor(Date.now() / 1000) - 30 * 60,
        identityAlreadyDeleted: true
      }))
    };
    const app = createApp({
      config: createFirebaseConfig(),
      firebaseVerifier: createFirebaseVerifier(userId),
      accountDeletionFirebaseVerifier: deletedIdentityVerifier,
      videoStorage: createTestVideoStorage(),
      accountIdentityDeleter
    });

    await request(app)
      .get('/account/deletion-readiness')
      .set('authorization', 'Bearer cached-firebase-token')
      .expect(200, { status: 'ok', identityAlreadyDeleted: true });
    await request(app)
      .delete('/account')
      .set('authorization', 'Bearer cached-firebase-token')
      .expect(200, { status: 'ok' });

    expect(accountIdentityDeleter.deleteIdentity).toHaveBeenCalledWith(
      expect.objectContaining({ id: userId, identityAlreadyDeleted: true })
    );
  });

  it('fails readiness without mutating data when owner media cleanup is unsupported', async () => {
    const userId = 'firebase-media-not-ready';
    const videoStorage = createTestVideoStorage();
    videoStorage.supportsOwnerCleanup = false;
    const app = createApp({
      config: createFirebaseConfig(),
      firebaseVerifier: createFirebaseVerifier(userId),
      videoStorage,
      accountIdentityDeleter: {
        deleteIdentity: vi.fn(async () => undefined)
      }
    });
    await createTemplateWithFirebase(app);

    const response = await request(app)
      .get('/account/deletion-readiness')
      .set('authorization', 'Bearer firebase-token')
      .expect(503);

    expect(response.body.code).toBe('ACCOUNT_MEDIA_CLEANUP_UNAVAILABLE');
    const templates = await request(app)
      .get('/templates')
      .set('authorization', 'Bearer firebase-token')
      .expect(200);
    expect(templates.body.templates).toHaveLength(1);
  });

  it('uses the authenticated user id for the production Prisma cascade', async () => {
    const deleteMany = vi.fn(async () => ({ count: 1 }));
    const app = createApp({
      prisma: { user: { deleteMany } } as never,
      socialConnectionStore: createInMemorySocialConnectionStore()
    });

    await request(app)
      .delete('/account')
      .set('x-postdee-user-id', 'prisma-delete-user')
      .expect(200);

    expect(deleteMany).toHaveBeenCalledWith({
      where: { id: 'prisma-delete-user' }
    });
  });

  it('cleans account media before deleting backend data and Firebase identity', async () => {
    const userId = 'firebase-delete-order';
    const calls: string[] = [];
    const videoStorage = createTestVideoStorage(
      vi.fn(async (ownerId) => {
        calls.push(`media:${ownerId}`);
      })
    );
    const accountIdentityDeleter = {
      deleteIdentity: vi.fn(async () => {
        calls.push('identity');
      })
    };
    const app = createApp({
      config: createFirebaseConfig(),
      firebaseVerifier: createFirebaseVerifier(userId),
      videoStorage,
      accountIdentityDeleter
    });

    await request(app)
      .delete('/account')
      .set('authorization', 'Bearer firebase-token')
      .expect(200);

    expect(calls).toEqual([`media:${userId}`, 'identity']);
    expect(accountIdentityDeleter.deleteIdentity).toHaveBeenCalledWith(
      expect.objectContaining({ id: userId, provider: 'firebase' })
    );
  });

  it('removes in-memory platform publish details owned by the deleted posts', async () => {
    const deleteAllForPosts = vi.fn(async () => undefined);
    const app = createApp({
      platformPublishStore: {
        recordResults: vi.fn(async () => []),
        deleteAllForPosts
      }
    });
    const createdPost = await createPostAs(app, 'seller-platform-details');

    await request(app)
      .delete('/account')
      .set('x-postdee-user-id', 'seller-platform-details')
      .expect(200);

    expect(deleteAllForPosts).toHaveBeenCalledWith([createdPost.body.post.id]);
  });

  it('keeps backend data when account media cleanup fails so deletion can be retried', async () => {
    const userId = 'firebase-media-retry';
    const deleteAllVideosForOwner = vi
      .fn<VideoStorage['deleteAllVideosForOwner']>()
      .mockRejectedValueOnce(new Error('R2 unavailable'))
      .mockResolvedValueOnce(undefined);
    const accountIdentityDeleter = {
      deleteIdentity: vi.fn(async () => undefined)
    };
    const app = createApp({
      config: createFirebaseConfig(),
      firebaseVerifier: createFirebaseVerifier(userId),
      videoStorage: createTestVideoStorage(deleteAllVideosForOwner),
      accountIdentityDeleter
    });
    await createTemplateWithFirebase(app);

    const failed = await request(app)
      .delete('/account')
      .set('authorization', 'Bearer firebase-token')
      .expect(503);
    expect(failed.body.code).toBe('ACCOUNT_MEDIA_CLEANUP_FAILED');
    expect(accountIdentityDeleter.deleteIdentity).not.toHaveBeenCalled();

    const templatesAfterFailure = await request(app)
      .get('/templates')
      .set('authorization', 'Bearer firebase-token')
      .expect(200);
    expect(templatesAfterFailure.body.templates).toHaveLength(1);

    await request(app)
      .delete('/account')
      .set('authorization', 'Bearer firebase-token')
      .expect(200);
    expect(accountIdentityDeleter.deleteIdentity).toHaveBeenCalledTimes(1);
  });

  it('returns a retryable error when Firebase identity deletion fails', async () => {
    const userId = 'firebase-identity-retry';
    const accountIdentityDeleter = {
      deleteIdentity: vi
        .fn()
        .mockRejectedValueOnce(new Error('Firebase unavailable'))
        .mockResolvedValueOnce(undefined)
    };
    const app = createApp({
      config: createFirebaseConfig(),
      firebaseVerifier: createFirebaseVerifier(userId),
      videoStorage: createTestVideoStorage(),
      accountIdentityDeleter
    });
    await createTemplateWithFirebase(app);

    const failed = await request(app)
      .delete('/account')
      .set('authorization', 'Bearer firebase-token')
      .expect(503);
    expect(failed.body.code).toBe('ACCOUNT_IDENTITY_DELETE_FAILED');

    const templatesAfterFailure = await request(app)
      .get('/templates')
      .set('authorization', 'Bearer firebase-token')
      .expect(200);
    expect(templatesAfterFailure.body.templates).toEqual([]);

    await request(app)
      .delete('/account')
      .set('authorization', 'Bearer firebase-token')
      .expect(200);
    expect(accountIdentityDeleter.deleteIdentity).toHaveBeenCalledTimes(2);
  });
});
