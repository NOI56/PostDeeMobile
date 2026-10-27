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
  it('pins the Render package runtime to the Node version used for release checks', async () => {
    const packageJson = JSON.parse(
      await readFile(new URL('../../package.json', import.meta.url), 'utf8'),
    );

    expect(packageJson.engines.node).toBe('22.23.3');
  });

  it('matches the paid staging resources and keeps deployment manual', async () => {
    const source = await readStagingConfig();

    expect(source).toMatch(/name: postdee-api-staging/);
    expect(source).toMatch(/name: postdee-postgres-staging/);
    expect(source).toMatch(/databaseName: postdee_staging/);
    expect(source).toMatch(/user: postdee_staging/);
    const [services, databases] = source.split('\ndatabases:');
    expect(services).toMatch(/plan: starter\s/);
    expect(databases).toMatch(/plan: basic-256mb\s/);
    expect(databases).toMatch(/diskSizeGB: 1\s/);
    expect(databases).toMatch(/postgresMajorVersion: "18"/);
    expect(source).not.toMatch(/^\s+plan: free\s*$/m);
    expect(source).toContain('branch: main');
    expect(source).toContain('autoDeployTrigger: "off"');
    expect(source).not.toMatch(/name: postdee-(?:api|postgres)\s/);
    expect(source).not.toContain('preDeployCommand:');
    expect(source).toContain('startCommand: npm run prisma:migrate:deploy');
    expect(source).toMatch(/ipAllowList:\s*\[\]/);
  });

  it('keeps native build tools through migration and prunes unused runtime modules before start', async () => {
    const source = await readStagingConfig();

    expect(source).toContain(
      'buildCommand: npm ci --include=dev && npm run prisma:generate && npm run build',
    );
    expect(source).toContain(
      'startCommand: npm run prisma:migrate:deploy && npm prune --omit=dev --omit=optional && npm run start',
    );
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
      'ELEVENLABS_API_KEY',
      'FIREBASE_PROJECT_ID',
      // Staging's own service account, so revoked or disabled users are
      // rejected. Deletion and push stay off via FIREBASE_AUTH_DELETE_ENABLED
      // and PUSH_SENDER.
      'FIREBASE_SERVICE_ACCOUNT_JSON',
      'REVENUECAT_WEBHOOK_AUTH_TOKEN',
      'REVENUECAT_REST_API_V1_KEY',
    ]) {
      expectEnvSecret(source, key);
    }

    expectEnvValue(source, 'ELEVENLABS_TRANSCRIPTION_MODEL', 'scribe_v2');
    expectEnvValue(source, 'ELEVENLABS_TRANSCRIPTION_KEYTERMS', '""');
    expectEnvValue(source, 'TRANSCRIPTION_PROVIDER', 'elevenlabs');
    expectEnvValue(source, 'GEMINI_CAPTION_MODEL', 'gemini-2.5-flash-lite');
    expectEnvValue(source, 'EDIT_PLAN_PROVIDER', 'gemini');
    expectEnvValue(source, 'GEMINI_EDIT_PLAN_MODEL', 'gemini-3.5-flash-lite');
    expect(source).not.toContain('GROQ_');
    expect(source).not.toContain('POSTPEER_TIKTOK_ACCOUNT_ID');
    expect(source).not.toContain('POSTPEER_YOUTUBE_ACCOUNT_ID');
    expect(source).not.toContain('POSTPEER_INSTAGRAM_ACCOUNT_ID');
    expect(source).not.toContain('POSTPEER_FACEBOOK_ACCOUNT_ID');
    expect(source).not.toContain('POSTPEER_API_KEY');
    expect(source).not.toContain('GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN');
    expect(source).not.toContain('fromGroup:');
    expect(source).not.toContain('envVarGroups:');
  });

  it('keeps destructive and outbound staging actions disabled initially', async () => {
    const source = await readStagingConfig();

    expectEnvValue(source, 'PUSH_SENDER', 'mock');
    expectEnvValue(source, 'FIREBASE_AUTH_DELETE_ENABLED', '"false"');
    expectEnvValue(source, 'SOCIAL_PUBLISHER', 'disabled');
    expectEnvValue(source, 'SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG', '"true"');
    expectEnvValue(source, 'PUBLISH_QUEUE', 'memory');
    expect(source).toMatch(/numInstances: 1/);
  });
});
