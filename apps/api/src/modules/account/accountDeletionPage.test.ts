import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';

describe('public account deletion page', () => {
  it('serves the deletion request steps without signing in', async () => {
    const app = createApp({
      config: readServerConfig({
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: 'postdee-test'
      })
    });

    const response = await request(app).get('/account-deletion').expect(200);

    expect(response.headers['content-type']).toMatch(/^text\/html/);
    expect(response.text).toContain('<html lang="th">');
    expect(response.text).toContain('PostDee');
    // In-app path uses the current Account tab and dialog labels.
    expect(response.text).toContain('บัญชี');
    expect(response.text).toContain('ลบบัญชีถาวร');
    // Web path works without reinstalling the app.
    expect(response.text).toContain('postdee.support@gmail.com');
    expect(response.text).toContain('href="mailto:postdee.support@gmail.com?subject=');
    expect(response.text).toContain('ข้อมูลที่ถูกลบ');
    expect(response.text).toContain('ข้อมูลที่อาจเก็บไว้');
    expect(response.text).toContain('30 วัน');
    expect(response.text).toContain('Delete your PostDee account');
  });

  it('locks the page down with a nonce-only style policy and no scripts', async () => {
    const response = await request(createApp()).get('/account-deletion').expect(200);

    const policy = response.headers['content-security-policy'];
    expect(policy).toContain("default-src 'none'");
    expect(policy).toContain("script-src 'none'");
    expect(policy).toContain("form-action 'none'");
    const nonce = /style-src 'nonce-([^']+)'/.exec(policy)?.[1];
    expect(nonce).toBeTruthy();
    expect(response.text).toContain(`<style nonce="${nonce}">`);
    expect(response.text).not.toContain('<script');
    expect(response.headers['cache-control']).toBe('public, max-age=300');
  });

  it('uses a fresh style nonce for every response', async () => {
    const app = createApp();
    const first = await request(app).get('/account-deletion').expect(200);
    const second = await request(app).get('/account-deletion').expect(200);

    expect(first.headers['content-security-policy'])
      .not.toBe(second.headers['content-security-policy']);
  });
});
