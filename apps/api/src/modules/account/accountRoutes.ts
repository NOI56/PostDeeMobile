import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { AnalyticsStore } from '../analytics/analyticsStore.js';
import type { AiEditUsageStore } from '../aiEdits/aiEditUsageStore.js';
import type { RealClipCaptionUsageStore } from '../captions/captionUsageStore.js';
import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
import type { PostStore } from '../posts/postStore.js';
import type { PublishQueue } from '../queue/publishQueue.js';
import type { SocialConnectionStore } from '../socialConnections/socialConnectionStore.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { TemplateStore } from '../templates/templateStore.js';
import type { UserStore } from '../users/userStore.js';

/**
 * Minimal Prisma surface needed to hard-delete an account. Removing the User row
 * cascades to posts, templates, subscription, and usage rows via the schema's
 * `onDelete: Cascade` relations, so a single deleteMany clears everything.
 */
export type PrismaAccountClient = {
  user: {
    deleteMany: (args: { where: { id: string } }) => Promise<{ count: number }>;
  };
};

export type AccountRouteDependencies = {
  postStore: PostStore;
  templateStore: TemplateStore;
  subscriptionStore: SubscriptionStore;
  analyticsStore: AnalyticsStore;
  realClipCaptionUsageStore: RealClipCaptionUsageStore;
  aiEditUsageStore: AiEditUsageStore;
  deviceTokenStore: DeviceTokenStore;
  socialConnectionStore?: SocialConnectionStore;
  userStore: UserStore;
  publishQueue: PublishQueue;
  prisma?: PrismaAccountClient;
};

/**
 * Registers `DELETE /account`, the store-compliance account deletion endpoint.
 * It permanently removes every piece of data owned by the authenticated user.
 */
export const registerAccountRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  dependencies: AccountRouteDependencies
) => {
  const {
    postStore,
    templateStore,
    subscriptionStore,
    analyticsStore,
    realClipCaptionUsageStore,
    aiEditUsageStore,
    deviceTokenStore,
    socialConnectionStore,
    userStore,
    publishQueue,
    prisma
  } = dependencies;

  router.delete('/account', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const userId = authUser.id;

    // Cancel any queued/scheduled publish jobs before the posts disappear, so a
    // worker never tries to publish for a deleted account.
    const posts = await postStore.list({ userId });
    for (const post of posts) {
      try {
        await publishQueue.remove(post.id);
      } catch {
        // Best-effort: a missing or already-processed job must not block deletion.
      }
    }

    // Memory-backed stores remove their own user-scoped data. Prisma-backed
    // stores leave these undefined and are cleared by the User cascade below.
    const deleters = [
      postStore.deleteAllForUser,
      templateStore.deleteAllForUser,
      subscriptionStore.deleteAllForUser,
      analyticsStore.deleteAllForUser,
      realClipCaptionUsageStore.deleteAllForUser,
      aiEditUsageStore.deleteAllForUser,
      deviceTokenStore.deleteAllForUser,
      socialConnectionStore?.deleteAllForUser,
      userStore.deleteAllForUser
    ];

    for (const deleter of deleters) {
      if (deleter) {
        await deleter(userId);
      }
    }

    // Prisma-backed stores: deleting the User row cascades to every child table.
    if (prisma) {
      await prisma.user.deleteMany({ where: { id: userId } });
    }

    response.json({ status: 'ok' });
  });
};
