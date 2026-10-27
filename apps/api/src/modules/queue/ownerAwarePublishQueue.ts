import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import type { PublishJob, PublishQueue } from './publishQueue.js';
import type { QueuedPost } from '../posts/postStore.js';

class QueueAdmissionTimeoutError extends Error {
  constructor() {
    super('Publish queue admission timed out');
    this.name = 'QueueAdmissionTimeoutError';
  }
}

/** Drain acknowledged queue writes before same-process account cleanup starts. */
export const createOwnerAwarePublishQueue = (
  queue: PublishQueue,
  runWithActiveOwner: RunWithActiveOwner,
  { operationTimeoutMs = 10000 }: { operationTimeoutMs?: number } = {}
): PublishQueue => {
  const admitOperation = async (post: QueuedPost, operation: () => Promise<PublishJob>): Promise<PublishJob> => {
    let expired = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => { expired = true; reject(new QueueAdmissionTimeoutError()); }, operationTimeoutMs);
    });
    // Keep the owner gate held after the HTTP timeout until the actual Redis
    // operation settles and a late acknowledged job is removed. Deletion then
    // fails with a bounded retry response rather than passing unfinished work.
    const admitted = runWithActiveOwner(post.userId, async () => {
      if (expired) throw new QueueAdmissionTimeoutError();
      const result = await operation();
      if (expired) {
        await queue.remove(post.id);
        throw new QueueAdmissionTimeoutError();
      }
      return result;
    });
    try {
      return await Promise.race([admitted, timeout]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  };
  return {
    ...queue,
    enqueue: (post) => admitOperation(post, () => queue.enqueue(post)),
    reschedule: (post) => admitOperation(post, () => queue.reschedule(post))
  };
};
