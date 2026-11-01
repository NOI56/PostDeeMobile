import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { createSentryMonitoring } from '../../monitoring/sentryMonitoring.js';
import { createFirebasePushSender } from './firebasePushSender.js';

const firebase = vi.hoisted(() => ({
  app: { name: 'postdee-backend' },
  credential: { type: 'mock-certificate' },
  cert: vi.fn(),
  getApp: vi.fn(),
  getApps: vi.fn(),
  initializeApp: vi.fn(),
  getMessaging: vi.fn(),
  sendEachForMulticast: vi.fn()
}));

// SDK 14 exposes modular app functions at its root, without the old namespace.
// Mock every imported entry point so these tests never initialize a real SDK.
vi.mock('firebase-admin', () => {
  const modularApp = {
    cert: firebase.cert,
    getApp: firebase.getApp,
    getApps: firebase.getApps,
    initializeApp: firebase.initializeApp
  };
  return { default: modularApp, ...modularApp };
});

vi.mock('firebase-admin/app', () => ({
  cert: firebase.cert,
  getApp: firebase.getApp,
  getApps: firebase.getApps,
  initializeApp: firebase.initializeApp
}));

vi.mock('firebase-admin/messaging', () => ({
  getMessaging: firebase.getMessaging
}));

const serviceAccountJson = '{"project_id":"postdee-test"}';
const message = {
  tokens: ['device-1', 'device-2'],
  title: 'โพสต์สำเร็จ',
  body: 'คลิปพร้อมแล้ว',
  data: { postId: 'post-1', userId: 'user-1' }
};
const captureException = vi.fn();

const expectSafeDeliveryReport = () => {
  expect(captureException).toHaveBeenCalledOnce();
  const [error, context] = captureException.mock.calls[0]!;
  expect(error).toBeInstanceOf(Error);
  expect(error.message).toBe('Firebase push delivery failed');
  expect(Object.keys(error)).toEqual([]);
  expect(context).toEqual({ tags: { component: 'api', operation: 'notifications.delivery' } });
  const reported = JSON.stringify({ message: error.message, stack: error.stack, context });
  for (const privateValue of [...message.tokens, message.title, message.body,
    ...Object.values(message.data), 'private-provider-url', 'private-provider-token']) {
    expect(reported).not.toContain(privateValue);
  }
};

afterEach(async () => { await createSentryMonitoring(undefined); });

describe('Firebase push sender', () => {
  beforeEach(async () => {
    vi.resetAllMocks();
    await createSentryMonitoring({
      dsn: 'https://public123@o123.ingest.us.sentry.io/123456',
      environment: 'staging'
    }, { initialize: async () => ({ captureException, flush: async () => true }) });
    firebase.cert.mockReturnValue(firebase.credential);
    firebase.getApps.mockReturnValue([]);
    firebase.initializeApp.mockReturnValue(firebase.app);
    firebase.getMessaging.mockReturnValue({
      sendEachForMulticast: firebase.sendEachForMulticast
    });
    firebase.sendEachForMulticast.mockResolvedValue({
      successCount: 2,
      failureCount: 0,
      responses: []
    });
  });

  it('does not initialize Firebase during construction or an empty-token send', async () => {
    const sender = createFirebasePushSender({ serviceAccountJson: 'not-json' });

    expect(firebase.getApps).not.toHaveBeenCalled();
    await expect(sender.send({ ...message, tokens: [] })).resolves.toEqual({ invalidTokens: [] });

    expect(firebase.cert).not.toHaveBeenCalled();
    expect(firebase.initializeApp).not.toHaveBeenCalled();
    expect(firebase.getMessaging).not.toHaveBeenCalled();
    expect(firebase.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it('initializes the named app with a certificate and preserves the multicast payload', async () => {
    const sender = createFirebasePushSender({ serviceAccountJson });

    await sender.send(message);

    expect(firebase.cert).toHaveBeenCalledWith({ project_id: 'postdee-test' });
    expect(firebase.initializeApp).toHaveBeenCalledWith(
      { credential: firebase.credential },
      'postdee-backend'
    );
    expect(firebase.getMessaging).toHaveBeenCalledWith(firebase.app);
    expect(firebase.sendEachForMulticast).toHaveBeenCalledWith({
      tokens: message.tokens,
      notification: { title: message.title, body: message.body },
      data: message.data
    });
  });

  it('reuses the named auth app without requiring a default app', async () => {
    firebase.getApps.mockReturnValue([{ name: 'unrelated-app' }, firebase.app]);
    firebase.getApp.mockImplementation(() => {
      throw new Error('No default app');
    });
    const sender = createFirebasePushSender({ serviceAccountJson });

    await sender.send(message);

    expect(firebase.getApp).not.toHaveBeenCalled();
    expect(firebase.initializeApp).not.toHaveBeenCalled();
    expect(firebase.cert).not.toHaveBeenCalled();
    expect(firebase.getMessaging).toHaveBeenCalledWith(firebase.app);
  });

  it('shares initialization across repeated and concurrent sends from one sender', async () => {
    const sender = createFirebasePushSender({ serviceAccountJson });

    await Promise.all([sender.send(message), sender.send(message)]);
    await sender.send(message);

    expect(firebase.initializeApp).toHaveBeenCalledTimes(1);
    expect(firebase.getMessaging).toHaveBeenCalledTimes(1);
    expect(firebase.sendEachForMulticast).toHaveBeenCalledTimes(3);
  });

  it('keeps the messaging cache scoped to each sender', async () => {
    firebase.getApps.mockReturnValue([firebase.app]);
    const firstSend = vi.fn(async () => ({ successCount: 2, failureCount: 0, responses: [] }));
    const secondSend = vi.fn(async () => ({ successCount: 2, failureCount: 0, responses: [] }));
    firebase.getMessaging
      .mockReturnValueOnce({ sendEachForMulticast: firstSend })
      .mockReturnValueOnce({ sendEachForMulticast: secondSend });
    const firstSender = createFirebasePushSender({ serviceAccountJson });
    const secondSender = createFirebasePushSender({ serviceAccountJson });

    await firstSender.send(message);
    await secondSender.send(message);

    expect(firebase.getMessaging).toHaveBeenCalledTimes(2);
    expect(firstSend).toHaveBeenCalledTimes(1);
    expect(secondSend).toHaveBeenCalledTimes(1);
  });

  it('rejects malformed service-account JSON before initialization', async () => {
    const sender = createFirebasePushSender({ serviceAccountJson: 'not-json' });

    await expect(sender.send(message)).rejects.toThrow(
      'FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON'
    );
    expect(firebase.cert).not.toHaveBeenCalled();
    expect(firebase.initializeApp).not.toHaveBeenCalled();
    expect(firebase.getMessaging).not.toHaveBeenCalled();
  });

  it.each(['null', '[]', '"text"', '123', 'true'])(
    'rejects a non-object service account: %s',
    async (invalidServiceAccount) => {
      const sender = createFirebasePushSender({
        serviceAccountJson: invalidServiceAccount
      });

      await expect(sender.send(message)).rejects.toThrow(
        'FIREBASE_SERVICE_ACCOUNT_JSON must be a JSON object'
      );
      expect(firebase.cert).not.toHaveBeenCalled();
      expect(firebase.initializeApp).not.toHaveBeenCalled();
      expect(firebase.getMessaging).not.toHaveBeenCalled();
    }
  );

  it('reports tokens FCM no longer accepts and keeps other failures', async () => {
    firebase.sendEachForMulticast.mockResolvedValueOnce({
      successCount: 1,
      failureCount: 3,
      responses: [
        { success: true, messageId: 'm1' },
        { success: false, error: { code: 'messaging/registration-token-not-registered' } },
        { success: false, error: { code: 'messaging/invalid-registration-token' } },
        { success: false, error: { code: 'messaging/internal-error' } }
      ]
    });
    const sender = createFirebasePushSender({ serviceAccountJson });

    await expect(
      sender.send({ ...message, tokens: ['ok', 'unregistered', 'invalid', 'flaky'] })
    ).resolves.toEqual({ invalidTokens: ['unregistered', 'invalid'] });
    expectSafeDeliveryReport();
  });

  it.each([
    'messaging/mismatched-credential',
    'messaging/internal-error',
    'messaging/message-rate-exceeded',
    'private-provider-token'
  ])('reports a non-invalid FCM rejection safely: %s', async (code) => {
    firebase.sendEachForMulticast.mockResolvedValueOnce({
      successCount: 1,
      failureCount: 1,
      responses: [
        { success: false, error: { code, message: 'private-provider-url private-provider-token' } },
        { success: true, messageId: 'private-provider-token' }
      ]
    });
    const sender = createFirebasePushSender({ serviceAccountJson });

    await expect(sender.send(message)).resolves.toEqual({ invalidTokens: [] });

    expectSafeDeliveryReport();
    expect(firebase.sendEachForMulticast).toHaveBeenCalledOnce();
  });

  it('returns only dead tokens without reporting expected uninstall failures', async () => {
    firebase.sendEachForMulticast.mockResolvedValueOnce({
      successCount: 0,
      failureCount: 2,
      responses: [
        { success: false, error: { code: 'messaging/registration-token-not-registered' } },
        { success: false, error: { code: 'messaging/invalid-registration-token' } }
      ]
    });
    const sender = createFirebasePushSender({ serviceAccountJson });

    await expect(sender.send(message)).resolves.toEqual({ invalidTokens: message.tokens });

    expect(captureException).not.toHaveBeenCalled();
  });

  it('reports once for a batch with several delivery failures and a dead token', async () => {
    firebase.sendEachForMulticast.mockResolvedValueOnce({
      successCount: 0,
      failureCount: 3,
      responses: [
        { success: false, error: { code: 'messaging/mismatched-credential' } },
        { success: false, error: { code: 'messaging/registration-token-not-registered' } },
        { success: false }
      ]
    });
    const sender = createFirebasePushSender({ serviceAccountJson });

    await expect(sender.send({ ...message, tokens: ['device-1', 'device-2', 'device-3'] }))
      .resolves.toEqual({ invalidTokens: ['device-2'] });

    expectSafeDeliveryReport();
  });

  it('does not report successful or empty sends', async () => {
    const sender = createFirebasePushSender({ serviceAccountJson });

    await sender.send({ ...message, tokens: [] });
    await sender.send(message);

    expect(captureException).not.toHaveBeenCalled();
  });

  it.each(['throw', 'reject'])('keeps delivery best-effort when monitoring fails: %s', async (failure) => {
    if (failure === 'throw') {
      captureException.mockImplementationOnce(() => { throw new Error('private-provider-token'); });
    } else {
      captureException.mockRejectedValueOnce(new Error('private-provider-token'));
    }
    firebase.sendEachForMulticast.mockResolvedValueOnce({
      successCount: 0,
      failureCount: 2,
      responses: [
        { success: false, error: { code: 'messaging/mismatched-credential' } },
        { success: false, error: { code: 'messaging/invalid-registration-token' } }
      ]
    });
    const sender = createFirebasePushSender({ serviceAccountJson });

    await expect(sender.send(message)).resolves.toEqual({ invalidTokens: ['device-2'] });
    await Promise.resolve();

    expectSafeDeliveryReport();
  });

  it('surfaces provider failures and retains the initialized sender for retry', async () => {
    const providerError = new Error('FCM unavailable');
    firebase.sendEachForMulticast.mockRejectedValueOnce(providerError);
    const sender = createFirebasePushSender({ serviceAccountJson });

    await expect(sender.send(message)).rejects.toBe(providerError);
    expectSafeDeliveryReport();
    await expect(sender.send(message)).resolves.toEqual({ invalidTokens: [] });

    expect(firebase.getMessaging).toHaveBeenCalledTimes(1);
    expect(firebase.sendEachForMulticast).toHaveBeenCalledTimes(2);
  });

  it('surfaces initialization failures and allows another attempt', async () => {
    const initializationError = new Error('Firebase initialization failed');
    firebase.initializeApp.mockImplementationOnce(() => {
      throw initializationError;
    });
    const sender = createFirebasePushSender({ serviceAccountJson });

    await expect(sender.send(message)).rejects.toBe(initializationError);
    expectSafeDeliveryReport();
    await expect(sender.send(message)).resolves.toEqual({ invalidTokens: [] });

    expect(firebase.initializeApp).toHaveBeenCalledTimes(2);
    expect(firebase.sendEachForMulticast).toHaveBeenCalledTimes(1);
  });
});
