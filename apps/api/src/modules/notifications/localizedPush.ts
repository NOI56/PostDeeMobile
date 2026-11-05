import type { DeviceToken, DeviceTokenStore } from '../devices/deviceTokenStore.js';
import type { AppLanguage } from '../shared/appLanguage.js';
import type { PushSender } from './pushSender.js';

/** Isolate each language's delivery and cleanup so pushes remain best-effort. */
export const sendLocalizedPush = async ({
  userId, deviceTokenStore, pushSender, messageForLanguage, data
}: {
  userId: string;
  deviceTokenStore: DeviceTokenStore;
  pushSender: PushSender;
  messageForLanguage: (language: AppLanguage) => { title: string; body: string };
  data: Record<string, string>;
}): Promise<void> => {
  let devices: DeviceToken[];
  try {
    devices = await deviceTokenStore.listForUser(userId);
  } catch {
    return;
  }
  const groups = new Map<AppLanguage, string[]>();
  for (const device of devices) {
    // Old clients registered without a language and always used Thai.
    const language = device.language === 'en' ? 'en' : 'th';
    const tokens = groups.get(language) ?? [];
    tokens.push(device.token);
    groups.set(language, tokens);
  }
  await Promise.allSettled([...groups].map(async ([language, tokens]) => {
    const result = await pushSender.send({ tokens, ...messageForLanguage(language), data });
    await Promise.allSettled((result?.invalidTokens ?? [])
      .filter(token => tokens.includes(token))
      .map(token => deviceTokenStore.unregister({ userId, token })));
  }));
};
