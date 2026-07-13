import type { S3Client } from '@aws-sdk/client-s3';
import { describe, expect, it, vi } from 'vitest';

import { createCloudflareR2VideoStorageClient } from './cloudflareR2VideoStorageClient.js';

describe('createCloudflareR2VideoStorageClient', () => {
  it('lists every owner object across paginated R2 responses', async () => {
    const send = vi
      .fn()
      .mockResolvedValueOnce({
        Contents: [{ Key: 'uploads/seller-a/first.mp4' }],
        IsTruncated: true,
        NextContinuationToken: 'next-page'
      })
      .mockResolvedValueOnce({
        Contents: [
          { Key: 'uploads/seller-a/second.mp4' },
          { Key: undefined }
        ],
        IsTruncated: false
      });
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: { send } as unknown as S3Client
    });

    await expect(
      client.listObjectKeysByPrefix?.({
        bucket: 'postdee-r2',
        prefix: 'uploads/seller-a/'
      })
    ).resolves.toEqual([
      'uploads/seller-a/first.mp4',
      'uploads/seller-a/second.mp4'
    ]);

    expect(send).toHaveBeenCalledTimes(2);
    expect(send.mock.calls[0]?.[0].input).toMatchObject({
      Bucket: 'postdee-r2',
      Prefix: 'uploads/seller-a/',
      ContinuationToken: undefined
    });
    expect(send.mock.calls[1]?.[0].input).toMatchObject({
      ContinuationToken: 'next-page'
    });
  });

  it('rejects a truncated response that cannot be continued', async () => {
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: {
        send: vi.fn(async () => ({ IsTruncated: true }))
      } as unknown as S3Client
    });

    await expect(
      client.listObjectKeysByPrefix?.({
        bucket: 'postdee-r2',
        prefix: 'uploads/seller-a/'
      })
    ).rejects.toThrow('without a continuation token');
  });
});
