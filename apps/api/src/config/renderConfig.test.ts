import { readFile } from 'node:fs/promises';

import { describe, expect, it } from 'vitest';

const readRenderConfig = async () =>
  readFile(new URL('../../../../render.yaml', import.meta.url), 'utf8');

const expectEnvValue = (source: string, key: string, value: string) => {
  expect(source).toMatch(new RegExp(`- key: ${key}\\s+value: ${value}`));
};

const expectEnvSecret = (source: string, key: string) => {
  expect(source).toMatch(new RegExp(`- key: ${key}\\s+sync: false`));
};

describe('render.yaml production config', () => {
  it('persists API quota and business stores with Prisma', async () => {
    const source = await readRenderConfig();

    expect(source).toContain('- key: DATABASE_URL');
    expectEnvValue(source, 'TEMPLATE_STORE', 'prisma');
    expectEnvValue(source, 'POST_STORE', 'prisma');
    expectEnvValue(source, 'SUBSCRIPTION_STORE', 'prisma');
    expectEnvValue(source, 'ANALYTICS_STORE', 'prisma');
    expectEnvValue(source, 'CAPTION_USAGE_STORE', 'prisma');
    expectEnvValue(source, 'AI_EDIT_USAGE_STORE', 'prisma');
  });

  it('declares required secrets for enabled real providers', async () => {
    const source = await readRenderConfig();

    expectEnvValue(source, 'CAPTION_PROVIDER', 'gemini');
    expectEnvSecret(source, 'GEMINI_API_KEY');
    expectEnvValue(source, 'TRANSCRIPTION_PROVIDER', 'groq');
    expectEnvValue(source, 'EDIT_PLAN_PROVIDER', 'groq');
    expectEnvSecret(source, 'GROQ_API_KEY');
    expectEnvValue(source, 'SOCIAL_PUBLISHER', 'mock');
    expectEnvSecret(source, 'POSTPEER_API_KEY');
    expectEnvSecret(source, 'POSTPEER_TIKTOK_ACCOUNT_ID');
    expectEnvSecret(source, 'POSTPEER_YOUTUBE_ACCOUNT_ID');
    expectEnvSecret(source, 'POSTPEER_INSTAGRAM_ACCOUNT_ID');
    expectEnvSecret(source, 'POSTPEER_FACEBOOK_ACCOUNT_ID');
  });

  it('keeps one web instance while the deploy uses the in-process memory queue', async () => {
    const source = await readRenderConfig();

    expectEnvValue(source, 'PUBLISH_QUEUE', 'memory');
    expect(source).toMatch(/numInstances: 1/);
  });
});
