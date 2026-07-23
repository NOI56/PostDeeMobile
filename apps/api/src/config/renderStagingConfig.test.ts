import { readFile } from 'node:fs/promises';

import { describe, expect, it } from 'vitest';

const readStagingConfig = async () =>
  readFile(new URL('../../../../render.staging.yaml', import.meta.url), 'utf8');

const expectEnvValue = (source: string, key: string, value: string) => {
  expect(source).toMatch(new RegExp(`- key: ${key}\\s+value: ${value}`));
};

const expectEnvSecret = (source: string, key: string) => {
  expect(source).toMatch(new RegExp(`- key: ${key}\\s+sync: false`));
};

describe('render.staging.yaml isolated staging config', () => {
  it('uses separate free Render resources', async () => {
    const source = await readStagingConfig();

    expect(source).toMatch(/name: postdee-api-staging/);
    expect(source).toMatch(/name: postdee-postgres-staging/);
    expect(source).toMatch(/databaseName: postdee_staging/);
    expect(source).toMatch(/user: postdee_staging/);
    expect(source.match(/plan: free/g)).toHaveLength(2);
    expect(source).toContain('branch: main');
    expect(source).toContain('autoDeployTrigger: checksPass');
    expect(source).not.toContain('preDeployCommand:');
    expect(source).toContain(
      'startCommand: npm run prisma:migrate:deploy && npm run start',
    );
    expect(source).toMatch(/ipAllowList:\s*\[\]/);
  });

  it('keeps production safety guards and Prisma stores enabled', async () => {
    const source = await readStagingConfig();

    expectEnvValue(source, 'NODE_ENV', 'production');
    expect(source).toMatch(
      /fromDatabase:\s+name: postdee-postgres-staging\s+property: connectionString/,
    );
    expectEnvValue(source, 'TEMPLATE_STORE', 'prisma');
    expectEnvValue(source, 'POST_STORE', 'prisma');
    expectEnvValue(source, 'SUBSCRIPTION_STORE', 'prisma');
    expectEnvValue(source, 'ANALYTICS_STORE', 'prisma');
    expectEnvValue(source, 'CAPTION_USAGE_STORE', 'prisma');
    expectEnvValue(source, 'AI_EDIT_USAGE_STORE', 'prisma');
  });

  it('requires separate provider credentials without committing values', async () => {
    const source = await readStagingConfig();

    for (const key of [
      'CLOUDFLARE_R2_BUCKET',
      'CLOUDFLARE_R2_ACCOUNT_ID',
      'CLOUDFLARE_R2_ACCESS_KEY_ID',
      'CLOUDFLARE_R2_SECRET_ACCESS_KEY',
      'CLOUDFLARE_R2_ENDPOINT',
      'GEMINI_API_KEY',
      'GROQ_API_KEY',
      'ELEVENLABS_API_KEY',
      'FIREBASE_PROJECT_ID',
      'REVENUECAT_WEBHOOK_AUTH_TOKEN',
      'REVENUECAT_REST_API_V1_KEY',
    ]) {
      expectEnvSecret(source, key);
    }

    expectEnvValue(source, 'TRANSCRIPTION_PROVIDER', 'groq');
    expectEnvValue(source, 'ELEVENLABS_TRANSCRIPTION_MODEL', 'scribe_v2');
    expect(source).not.toContain('POSTPEER_TIKTOK_ACCOUNT_ID');
    expect(source).not.toContain('POSTPEER_YOUTUBE_ACCOUNT_ID');
    expect(source).not.toContain('POSTPEER_INSTAGRAM_ACCOUNT_ID');
    expect(source).not.toContain('POSTPEER_FACEBOOK_ACCOUNT_ID');
    expect(source).not.toContain('POSTPEER_API_KEY');
    expect(source).not.toContain('FIREBASE_SERVICE_ACCOUNT_JSON');
    expect(source).not.toContain('GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN');
    expect(source).not.toContain('fromGroup:');
    expect(source).not.toContain('envVarGroups:');
  });

  it('keeps destructive and outbound staging actions disabled initially', async () => {
    const source = await readStagingConfig();

    expectEnvValue(source, 'PUSH_SENDER', 'mock');
    expectEnvValue(source, 'FIREBASE_AUTH_DELETE_ENABLED', '"false"');
    expectEnvValue(source, 'SOCIAL_PUBLISHER', 'disabled');
    expectEnvValue(source, 'PUBLISH_QUEUE', 'memory');
    expect(source).toMatch(/numInstances: 1/);
  });
});
