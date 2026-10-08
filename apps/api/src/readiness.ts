import type { RequestHandler } from 'express';

type CheckStatus = 'ok' | 'unavailable';
type ReadinessOptions = {
  database: () => Promise<void>;
  queue: () => Promise<void>;
  isShuttingDown?: () => boolean;
  timeoutMs?: number;
};

// Keep one underlying probe per dependency after timeout, so repeated requests
// cannot pile up queries while a database or Redis connection is hanging.
const createProbe = (check: () => Promise<void>, timeoutMs: number) => {
  let pending: Promise<CheckStatus> | undefined;
  return async (): Promise<CheckStatus> => {
    pending ??= Promise.resolve().then(check).then(
      () => 'ok' as const,
      () => 'unavailable' as const
    ).finally(() => { pending = undefined; });
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        pending,
        new Promise<CheckStatus>((resolve) => {
          timer = setTimeout(() => resolve('unavailable'), timeoutMs);
        })
      ]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  };
};

export const createReadinessHandler = ({
  database, queue, isShuttingDown = () => false, timeoutMs = 2_000
}: ReadinessOptions): RequestHandler => {
  const probeDatabase = createProbe(database, timeoutMs);
  const probeQueue = createProbe(queue, timeoutMs);
  return async (_request, response) => {
    const [databaseStatus, queueStatus] = isShuttingDown()
      ? ['unavailable', 'unavailable'] as const
      : await Promise.all([probeDatabase(), probeQueue()]);
    const shuttingDown = isShuttingDown();
    const ready = !shuttingDown && databaseStatus === 'ok' && queueStatus === 'ok';
    response.setHeader('Cache-Control', 'no-store');
    response.status(ready ? 200 : 503).json({
      status: ready ? 'ok' : 'unavailable',
      service: 'postdee-api',
      checks: shuttingDown
        ? { database: 'unavailable', queue: 'unavailable' }
        : { database: databaseStatus, queue: queueStatus }
    });
  };
};
