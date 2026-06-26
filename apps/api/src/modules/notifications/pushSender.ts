export type PushMessage = {
  tokens: string[];
  title: string;
  body: string;
  data?: Record<string, string>;
};

export type PushSender = {
  send: (message: PushMessage) => Promise<void>;
};

/**
 * No-op push sender used until a real provider is configured. The real adapter
 * (e.g. firebase-admin sending to FCM) should be added behind config once a
 * service account key and a security review are in place — see LAUNCH_CHECKLIST.
 */
export const createMockPushSender = (): PushSender => ({
  send: async () => undefined
});
