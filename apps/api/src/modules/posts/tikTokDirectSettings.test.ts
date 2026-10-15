import { describe, expect, it } from 'vitest';

import { buildTikTokConnectionRevision, validateTikTokDirectCaption, validateTikTokDirectSettings } from './tikTokDirectSettings.js';
import { arePlatformSettingsEqual, normalizePersistedPlatformSettings, readPlatformSettings } from './platformSettings.js';

const settings = {
  publishMode: 'DIRECT_POST' as const, privacyLevel: 'PUBLIC_TO_EVERYONE' as const,
  disableComment: false, disableDuet: true, disableStitch: false,
  brandContentToggle: false, brandOrganicToggle: false, isAigc: false,
  videoDurationSeconds: 10, musicUsageConfirmed: true as const,
  brandedContentPolicyConfirmed: false, creatorInfoRevision: 'a'.repeat(64)
};
const info = {
  creatorAvatarUrl: 'https://cdn.tiktok.test/avatar.jpg',
  creatorUsername: 'seller', creatorNickname: 'Seller',
  privacyLevelOptions: ['PUBLIC_TO_EVERYONE', 'SELF_ONLY'] as const,
  commentDisabled: false, duetDisabled: true, stitchDisabled: false,
  maxVideoPostDurationSec: 60
};

describe('explicit TikTok Direct Post settings', () => {
  it.each([undefined, '', 'a'.repeat(2200), '😀'.repeat(1100)])('allows a caption within 2200 UTF-16 units', (caption) => {
    expect(() => validateTikTokDirectCaption(caption)).not.toThrow();
  });

  it.each(['a'.repeat(2201), '😀'.repeat(1101)])('rejects a caption exceeding 2200 UTF-16 units', (caption) => {
    expect(() => validateTikTokDirectCaption(caption)).toThrow(expect.objectContaining({
      code: 'TIKTOK_CAPTION_TOO_LONG', statusCode: 400
    }));
  });

  it('parses and persists the complete immutable choice', () => {
    expect(readPlatformSettings({ TIKTOK: settings }, ['TIKTOK'])).toEqual({
      ok: true, value: { TIKTOK: settings }
    });
    expect(normalizePersistedPlatformSettings({ TIKTOK: settings }, ['TIKTOK'])).toEqual({ TIKTOK: settings });
    expect(() => validateTikTokDirectSettings(info, settings)).not.toThrow();
  });

  for (const [field, value] of [
    ['privacyLevel', 'UNKNOWN'], ['disableComment', undefined], ['disableDuet', 'true'],
    ['disableStitch', null], ['brandContentToggle', 1], ['brandOrganicToggle', undefined],
    ['isAigc', 'false'], ['videoDurationSeconds', 0], ['videoDurationSeconds', Infinity],
    ['videoDurationSeconds', NaN], ['musicUsageConfirmed', false],
    ['brandedContentPolicyConfirmed', undefined], ['unknownField', true],
    ['creatorInfoRevision', undefined], ['creatorInfoRevision', 'bad-revision']
  ] as const) {
    it(`rejects incomplete or invalid ${field}=${String(value)}`, () => {
      expect(readPlatformSettings({ TIKTOK: { ...settings, [field]: value } }, ['TIKTOK'])).toEqual({ ok: false });
    });
  }

  it('requires branded-content agreement and forbids private branded content', () => {
    for (const candidate of [
      { ...settings, brandContentToggle: true },
      { ...settings, privacyLevel: 'SELF_ONLY', brandContentToggle: true, brandedContentPolicyConfirmed: true }
    ]) {
      expect(readPlatformSettings({ TIKTOK: candidate }, ['TIKTOK'])).toEqual({ ok: false });
    }
  });

  for (const [field, value] of [
    ['privacyLevel', 'SELF_ONLY'], ['disableComment', true], ['disableDuet', false],
    ['disableStitch', true], ['brandContentToggle', true], ['brandOrganicToggle', true],
    ['isAigc', true], ['videoDurationSeconds', 11], ['brandedContentPolicyConfirmed', true],
    ['creatorInfoRevision', 'b'.repeat(64)]
  ] as const) {
    it(`compares immutable ${field} when checking an idempotent intent`, () => {
      expect(arePlatformSettingsEqual(
        { TIKTOK: settings },
        { TIKTOK: { ...settings, [field]: value, ...(field === 'brandContentToggle' ? { brandedContentPolicyConfirmed: true } : {}) } },
        ['TIKTOK']
      )).toBe(false);
    });
  }

  it('rejects unavailable privacy, interactions, and excessive duration', () => {
    for (const candidate of [
      { ...settings, privacyLevel: 'MUTUAL_FOLLOW_FRIENDS' as const },
      { ...settings, disableDuet: false },
      { ...settings, videoDurationSeconds: 61 }
    ]) {
      expect(() => validateTikTokDirectSettings(info, candidate)).toThrow();
    }
    expect(() => validateTikTokDirectSettings({ ...info, commentDisabled: true }, settings)).toThrow();
    expect(() => validateTikTokDirectSettings({ ...info, stitchDisabled: true }, settings)).toThrow();
    expect(() => validateTikTokDirectSettings({ ...info, maxVideoPostDurationSec: 3600 }, {
      ...settings, videoDurationSeconds: 601
    })).toThrow();
    expect(() => validateTikTokDirectSettings({ ...info, maxVideoPostDurationSec: 3600 }, {
      ...settings, videoDurationSeconds: 600
    })).not.toThrow();
  });

  it('binds the creator review to owner and target revision, including reconnects', () => {
    const target = { accountId: 'account-one', externalAccountId: 'creator-one', connectedAt: '2026-10-15T10:00:00.000Z' };
    const revision = buildTikTokConnectionRevision({ userId: 'seller', target });
    expect(revision).toMatch(/^[a-f0-9]{64}$/);
    expect(buildTikTokConnectionRevision({ userId: 'seller', target: { ...target, displayName: 'Renamed' } })).toBe(revision);
    expect(buildTikTokConnectionRevision({ userId: 'other', target })).not.toBe(revision);
    expect(buildTikTokConnectionRevision({ userId: 'seller', target: { ...target, accountId: 'account-two' } })).not.toBe(revision);
    expect(buildTikTokConnectionRevision({ userId: 'seller', target: { ...target, externalAccountId: 'creator-two' } })).not.toBe(revision);
  });
});
