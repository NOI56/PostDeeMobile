// Six attempts spread a same-owner startup burst without retrying indefinitely.
// Positive jitter waits 25–49, 50–99, 100–199, 200–399, then 200–399ms
// outside failed transactions (at most 1,145ms of added backoff).
// Only wrap database transactions: a failed admission must never replay the
// caller's provider request, queue acknowledgement, or other external action.
export const retryOwnerSerializationConflict = async <T>(operation: () => Promise<T>): Promise<T> => {
  for (let attempt = 0; ; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      const conflict = typeof error === 'object' && error !== null && 'code' in error && error.code === 'P2034';
      if (!conflict || attempt === 5) throw error;
      const delayMs = Math.min(200, 25 * 2 ** attempt);
      await new Promise((resolve) => setTimeout(resolve, delayMs + Math.floor(Math.random() * delayMs)));
    }
  }
};
