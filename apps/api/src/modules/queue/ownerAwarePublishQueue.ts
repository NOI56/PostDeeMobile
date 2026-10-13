import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import type { QueuedPost } from '../posts/postStore.js';
import type { PublishQueue } from './publishQueue.js';

// Redis effects stay outside SQL transactions. Preserve the underlying queue's
// acknowledgement/error semantics: a new timeout would let route rollback run
// before an actual reschedule settles. Only owner admission/drain is bounded.
export const createOwnerAwarePublishQueue = (
  queue: PublishQueue,
  runWithActiveOwner: RunWithActiveOwner
): PublishQueue => ({
    ...queue,
    enqueue: (post: QueuedPost) => runWithActiveOwner(post.userId, () => queue.enqueue(post)),
    ensureEnqueued: (post: QueuedPost) => runWithActiveOwner(post.userId, () => queue.ensureEnqueued(post)),
    reschedule: (post: QueuedPost) => runWithActiveOwner(post.userId, () => queue.reschedule(post))
});
