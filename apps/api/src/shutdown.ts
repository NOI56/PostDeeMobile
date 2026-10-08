type ShutdownOptions = {
  markUnavailable: () => void;
  stopScheduling: () => void;
  stopAcceptingRequests: () => Promise<void>;
  drainPublishing: () => Promise<void>;
  closeResources: () => Promise<void>;
  timeoutMs?: number;
};

export const createGracefulShutdown = ({
  markUnavailable, stopScheduling, stopAcceptingRequests,
  drainPublishing, closeResources, timeoutMs = 30_000
}: ShutdownOptions) => {
  let pending: Promise<void> | undefined;
  return (): Promise<void> => {
    if (pending) return pending;
    markUnavailable();
    stopScheduling();
    const drain = (async () => {
      try {
        await Promise.all([stopAcceptingRequests(), drainPublishing()]);
        await closeResources();
      } catch {
        throw new Error('Graceful shutdown failed');
      }
    })();
    let timer: ReturnType<typeof setTimeout>;
    pending = Promise.race([
      drain,
      new Promise<never>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error('Graceful shutdown timed out')), timeoutMs);
      })
    ]).finally(() => { clearTimeout(timer); });
    return pending;
  };
};
