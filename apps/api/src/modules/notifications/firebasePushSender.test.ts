import { beforeEach, describe, expect, it, vi } from 'vitest';

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

describe('Firebase push sender', () => {
  beforeEach(() => {
    vi.resetAllMocks();
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
    await expect(sender.send({ ...message, tokens: [] })).resolves.toBeUndefined();

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
    const firstSend = vi.fn(async () => undefined);
    const secondSend = vi.fn(async () => undefined);
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

  it('surfaces provider failures and retains the initialized sender for retry', async () => {
    const providerError = new Error('FCM unavailable');
    firebase.sendEachForMulticast.mockRejectedValueOnce(providerError);
    const sender = createFirebasePushSender({ serviceAccountJson });

    await expect(sender.send(message)).rejects.toBe(providerError);
    await expect(sender.send(message)).resolves.toBeUndefined();

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
    await expect(sender.send(message)).resolves.toBeUndefined();

    expect(firebase.initializeApp).toHaveBeenCalledTimes(2);
    expect(firebase.sendEachForMulticast).toHaveBeenCalledTimes(1);
  });
});
