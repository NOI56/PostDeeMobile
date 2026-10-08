import type { PlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import type { PostStore } from '../modules/posts/postStore.js';

// Run only before the single-process scheduler starts claiming work. Recovery
// uses saved terminal receipts; it never calls a provider or requeues a post.
export const reconcileInterruptedPublishes = async ({
  postStore, platformPublishStore
}: { postStore: PostStore; platformPublishStore: PlatformPublishStore }) => {
  const posts = await postStore.listPublishing();
  let recovered = 0;
  let requiresReconciliation = 0;
  for (let offset = 0; offset < posts.length; offset += 100) {
    const batch = posts.slice(offset, offset + 100);
    const records = await platformPublishStore.listForPostIds?.(batch.map((post) => post.id)) ?? [];
    for (const post of batch) {
      const platforms = [...new Set(post.platforms)];
      const results = platforms.map((platform) => records.find((record) => record.postId === post.id && record.platform === platform));
      const complete = results.length > 0 && results.every((record) => record && (
        record.status === 'FAILED' || (record.status === 'PUBLISHED' &&
          (record.providerPostId || record.externalPostId) && record.deliveryOutcome &&
          record.publishedAt && Number.isFinite(Date.parse(record.publishedAt)))
      ));
      if (!complete) {
        requiresReconciliation += 1;
        continue;
      }
      const published = results.filter((record) => record?.status === 'PUBLISHED');
      const status = published.length === results.length ? 'PUBLISHED'
        : published.length > 0 ? 'PARTIAL_PUBLISHED' : 'FAILED';
      const publishedAt = published.map((record) => record!.publishedAt!).sort().at(-1);
      if (await postStore.finalizeInterruptedPublish({
        postId: post.id, status, ...(publishedAt ? { publishedAt } : {})
      })) {
        recovered += 1;
      }
    }
  }
  return { recovered, requiresReconciliation };
};
