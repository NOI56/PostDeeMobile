import type { ServerConfig } from '../../config/env.js';
import { createFirebasePushSender } from './firebasePushSender.js';
import { type PushSender, createMockPushSender } from './pushSender.js';

type PushSenderConfig = Pick<
  ServerConfig,
  'pushSender' | 'firebaseServiceAccountJson'
>;

// Returns the real firebase-admin sender when PUSH_SENDER=firebase (with a
// service account key), and the no-op mock sender otherwise.
export const createPushSenderFromConfig = ({
  config
}: {
  config: PushSenderConfig;
}): PushSender => {
  if (config.pushSender === 'firebase') {
    if (!config.firebaseServiceAccountJson) {
      throw new Error(
        'FIREBASE_SERVICE_ACCOUNT_JSON is required when PUSH_SENDER is firebase'
      );
    }

    return createFirebasePushSender({
      serviceAccountJson: config.firebaseServiceAccountJson
    });
  }

  return createMockPushSender();
};
