export type OwnerMutationLock = {
  acquire: (ownerId: string) => Promise<() => void>;
};

export type OwnerMutationCoordinator = OwnerMutationLock & {
  // Shared side of the owner barrier: normal mutations may run concurrently,
  // while a queued account deletion prevents later mutations from entering.
  acquireMutation: (ownerId: string) => Promise<() => void>;
  isActive: (ownerId: string) => boolean;
  markDeleting: (ownerId: string) => void;
  markDeleted: (ownerId: string) => void;
  // Diagnostics for regression tests/metrics; contains no owner identifiers.
  debugStateSize: () => number;
};

/**
 * Serializes account deletion with the final durable publish-write boundary.
 * One instance is shared by every route registered on an app process.
 */
export const createOwnerMutationLock = (): OwnerMutationCoordinator => {
  type Waiter = {
    kind: 'mutation' | 'deletion';
    resolve: (release: () => void) => void;
  };
  type OwnerState = {
    activeMutations: number;
    deletionActive: boolean;
    waiters: Waiter[];
  };
  const stateByOwner = new Map<string, OwnerState>();
  const inactiveOwners = new Map<string, 'DELETING' | 'DELETED'>();

  const readState = (ownerId: string) => {
    const existing = stateByOwner.get(ownerId);
    if (existing) {
      return existing;
    }
    const created: OwnerState = {
      activeMutations: 0,
      deletionActive: false,
      waiters: []
    };
    stateByOwner.set(ownerId, created);
    return created;
  };

  const deleteStateIfIdle = (ownerId: string, state: OwnerState) => {
    if (
      state.activeMutations === 0 &&
      !state.deletionActive &&
      state.waiters.length === 0 &&
      stateByOwner.get(ownerId) === state
    ) {
      stateByOwner.delete(ownerId);
    }
  };

  const drain = (ownerId: string) => {
    const state = stateByOwner.get(ownerId);
    if (!state) {
      return;
    }
    if (state.deletionActive) {
      return;
    }
    if (state.waiters.length === 0) {
      deleteStateIfIdle(ownerId, state);
      return;
    }

    if (state.waiters[0].kind === 'deletion') {
      if (state.activeMutations > 0) {
        return;
      }
      const waiter = state.waiters.shift() as Waiter;
      state.deletionActive = true;
      let released = false;
      waiter.resolve(() => {
        if (released) {
          return;
        }
        released = true;
        state.deletionActive = false;
        drain(ownerId);
      });
      return;
    }

    while (state.waiters[0]?.kind === 'mutation') {
      const waiter = state.waiters.shift() as Waiter;
      state.activeMutations += 1;
      let released = false;
      waiter.resolve(() => {
        if (released) {
          return;
        }
        released = true;
        state.activeMutations -= 1;
        drain(ownerId);
      });
    }
  };

  const enqueue = (ownerId: string, kind: Waiter['kind']) =>
    new Promise<() => void>((resolve) => {
      readState(ownerId).waiters.push({ kind, resolve });
      drain(ownerId);
    });

  return {
    acquire: (ownerId) => enqueue(ownerId, 'deletion'),
    acquireMutation: (ownerId) => enqueue(ownerId, 'mutation'),
    isActive: (ownerId) => !inactiveOwners.has(ownerId),
    markDeleting: (ownerId) => {
      if (inactiveOwners.get(ownerId) !== 'DELETED') {
        inactiveOwners.set(ownerId, 'DELETING');
      }
    },
    markDeleted: (ownerId) => {
      inactiveOwners.set(ownerId, 'DELETED');
    },
    debugStateSize: () => stateByOwner.size
  };
};
