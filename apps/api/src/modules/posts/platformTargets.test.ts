import { describe, expect, it } from 'vitest';

import {
  buildPlatformTarget,
  isSamePlatformTarget,
  normalizePersistedPlatformTargets
} from './platformTargets.js';

describe('platform target snapshots', () => {
  it('keeps the provider account and non-secret identity evidence needed for a stable target', () => {
    expect(
      buildPlatformTarget({
        userId: 'seller-1',
        platform: 'YOUTUBE_SHORTS',
        postPeerAccountId: 'postpeer-youtube-old',
        displayName: 'Original channel',
        externalAccountId: 'youtube-channel-123',
        connectedAt: '2026-08-01T10:00:00.000Z',
        updatedAt: '2026-08-02T10:00:00.000Z'
      })
    ).toEqual({
      accountId: 'postpeer-youtube-old',
      displayName: 'Original channel',
      externalAccountId: 'youtube-channel-123',
      connectedAt: '2026-08-01T10:00:00.000Z'
    });
  });

  it('fails closed on a partial or malformed persisted target snapshot', () => {
    expect(() =>
      normalizePersistedPlatformTargets(
        {
          YOUTUBE_SHORTS: {
            accountId: '',
            connectedAt: 'not-a-date'
          }
        },
        ['YOUTUBE_SHORTS']
      )
    ).toThrow(/Persisted platform targets are invalid/);

    expect(() =>
      normalizePersistedPlatformTargets(
        {
          YOUTUBE_SHORTS: {
            accountId: 'youtube-1',
            connectedAt: '2026-08-01T10:00:00.000Z'
          }
        },
        ['YOUTUBE_SHORTS', 'TIKTOK']
      )
    ).toThrow(/Persisted platform targets are invalid/);
  });

  it('keeps legacy null snapshots eligible for live account resolution', () => {
    expect(normalizePersistedPlatformTargets(null, ['TIKTOK'])).toBeUndefined();
  });

  it('uses stable identity fields while allowing display-name and metadata enrichment', () => {
    const original = {
      accountId: 'postpeer-youtube-1',
      displayName: 'Old channel name',
      connectedAt: '2026-08-01T10:00:00.000Z'
    };

    expect(
      isSamePlatformTarget(original, {
        ...original,
        displayName: 'Renamed channel',
        externalAccountId: 'channel-1'
      })
    ).toBe(true);
    expect(
      isSamePlatformTarget(original, {
        ...original,
        accountId: 'postpeer-youtube-2'
      })
    ).toBe(false);
    expect(
      isSamePlatformTarget(original, {
        ...original,
        connectedAt: '2026-08-02T10:00:00.000Z'
      })
    ).toBe(false);
  });
});
