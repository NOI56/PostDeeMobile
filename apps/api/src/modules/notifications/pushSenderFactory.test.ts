import { describe, expect, it } from 'vitest';

import { createPushSenderFromConfig } from './pushSenderFactory.js';

describe('push sender factory', () => {
  it('returns a no-op mock sender by default', async () => {
    const sender = createPushSenderFromConfig({
      config: { pushSender: 'mock', firebaseServiceAccountJson: undefined }
    });

    await expect(
      sender.send({ tokens: ['t1'], title: 'x', body: 'y' })
    ).resolves.toBeUndefined();
  });

  it('throws when PUSH_SENDER is firebase but no service account is set', () => {
    expect(() =>
      createPushSenderFromConfig({
        config: { pushSender: 'firebase', firebaseServiceAccountJson: undefined }
      })
    ).toThrow('FIREBASE_SERVICE_ACCOUNT_JSON is required');
  });

  it('builds a firebase sender when a service account is provided', () => {
    const sender = createPushSenderFromConfig({
      config: {
        pushSender: 'firebase',
        firebaseServiceAccountJson: '{"project_id":"demo"}'
      }
    });

    expect(typeof sender.send).toBe('function');
  });
});
