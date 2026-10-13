export type RunWithActiveOwner = <T>(ownerId: string, operation: () => Promise<T>) => Promise<T>;

export class OwnerOperationBusyError extends Error {
  readonly code = 'ACCOUNT_WRITE_DRAIN_FAILED';
  constructor() {
    super('Active account work has not finished. Please retry shortly.');
    this.name = 'OwnerOperationBusyError';
  }
}

// Independent from the HTTP mutation/deletion coordinator: a route that
// already holds its shared HTTP admission never acquires that lock exclusively.
export const createOwnerOperationQueue = ({ maxWaitMs = 5000 }: { maxWaitMs?: number } = {}) => {
  const pendingByOwner = new Map<string, Promise<void>>();
  return async <T>(ownerId: string, operation: () => Promise<T>): Promise<T> => {
    const previous = pendingByOwner.get(ownerId) ?? Promise.resolve();
    let started = false;
    let expired = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const result = previous.then(() => {
      if (expired) throw new OwnerOperationBusyError();
      started = true;
      if (timer) clearTimeout(timer);
      return operation();
    });
    const admission = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => {
        if (!started) { expired = true; reject(new OwnerOperationBusyError()); }
      }, maxWaitMs);
    });
    const tail = result.then(() => undefined, () => undefined);
    pendingByOwner.set(ownerId, tail);
    void tail.then(() => {
      if (pendingByOwner.get(ownerId) === tail) pendingByOwner.delete(ownerId);
    });
    try {
      return await Promise.race([result, admission]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  };
};
