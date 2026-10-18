import { describe, expect, it } from 'vitest';
import { readAdminConsoleConfig } from './adminConfig.js';

const env = { NODE_ENV: 'test', ADMIN_CONSOLE_ENABLED: 'true', TRIAL_ACCESS_ENABLED: 'true', AUTH_PROVIDER: 'firebase',
  FIREBASE_PROJECT_ID: 'fixture', ADMIN_ENVIRONMENT: 'LOCAL', ADMIN_CONSOLE_ORIGIN: 'http://localhost:4174',
  ADMIN_OWNER_UIDS: 'owner', ADMIN_VIEWER_UIDS: 'viewer',
  ADMIN_FIREBASE_WEB_CONFIG: JSON.stringify({ apiKey: 'fixture', authDomain: 'fixture.firebaseapp.com', projectId: 'fixture', appId: 'fixture' }) };
describe('administrator configuration', () => {
  it('is disabled by default without needing Firebase settings', () => expect(readAdminConsoleConfig({})).toBeUndefined());
  it('accepts explicit local roles and public Firebase configuration', () => {
    expect(readAdminConsoleConfig(env)).toMatchObject({ ownerUids: ['owner'], viewerUids: ['viewer'], environment: 'LOCAL' });
  });
  it.each([
    { AUTH_PROVIDER: 'mock' }, { TRIAL_ACCESS_ENABLED: 'false' }, { ADMIN_OWNER_UIDS: '' },
    { ADMIN_OWNER_UIDS: 'bad uid' }, { ADMIN_CONSOLE_ORIGIN: 'https://admin.example.com/path' },
    { ADMIN_CONSOLE_ORIGIN: 'http://admin.example.com' }, { NODE_ENV: 'production' },
    { ADMIN_FIREBASE_WEB_CONFIG: 'null' }, { ADMIN_FIREBASE_WEB_CONFIG: '[]' },
    { FIREBASE_PROJECT_ID: 'other' }, { ADMIN_ENVIRONMENT: '' }, { ADMIN_COST_RATES_JSON: 'null' },
    { ADMIN_COST_RATES_JSON: '{"captionRequestUsd":-1,"editMinuteUsd":0,"postUnitUsd":0}' }
  ])('fails closed for incomplete or unsafe configuration %j', override => {
    expect(() => readAdminConsoleConfig({ ...env, ...override })).toThrow();
  });
});
