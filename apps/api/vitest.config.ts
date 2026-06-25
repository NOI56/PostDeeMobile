import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    env: {
      ANALYTICS_STORE: 'memory',
      AUTH_PROVIDER: 'mock',
      BILLING_PROVIDER: 'mock',
      CAPTION_PROVIDER: 'mock',
      CAPTION_USAGE_STORE: 'memory',
      EDIT_PLAN_PROVIDER: 'mock',
      POST_STORE: 'memory',
      PUBLISH_QUEUE: 'memory',
      SOCIAL_PUBLISHER: 'mock',
      SUBSCRIPTION_STORE: 'memory',
      TEMPLATE_STORE: 'memory',
      TRANSCRIPTION_PROVIDER: 'mock',
      VIDEO_STORAGE: 'mock'
    },
    environment: 'node',
    globals: true
  }
});
