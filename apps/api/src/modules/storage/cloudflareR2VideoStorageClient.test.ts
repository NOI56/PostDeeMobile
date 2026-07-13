import type { S3Client } from '@aws-sdk/client-s3';
import { describe, expect, it, vi } from 'vitest';

import { createCloudflareR2VideoStorageClient } from './cloudflareR2VideoStorageClient.js';

describe('createCloudflareR2VideoStorageClient', () => {
  it('creates, completes, and aborts multipart uploads with R2 commands', async () => {
    const send = vi
      .fn()
      .mockResolvedValueOnce({ UploadId: 'r2-upload-1' })
      .mockResolvedValueOnce({})
      .mockResolvedValueOnce({});
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: { send } as unknown as S3Client
    });

    await expect(
      client.multipart?.createUpload({
        bucket: 'postdee-r2',
        key: 'uploads/seller-a/video.mp4',
        contentType: 'video/mp4'
      })
    ).resolves.toEqual({ storageUploadId: 'r2-upload-1' });
    await client.multipart?.completeUpload({
      bucket: 'postdee-r2',
      key: 'uploads/seller-a/video.mp4',
      storageUploadId: 'r2-upload-1',
      parts: [
        { partNumber: 2, eTag: 'etag-2' },
        { partNumber: 1, eTag: 'etag-1' }
      ]
    });
    await client.multipart?.abortUpload({
      bucket: 'postdee-r2',
      key: 'uploads/seller-a/video.mp4',
      storageUploadId: 'r2-upload-1'
    });

    expect(send.mock.calls[0]?.[0].input).toEqual({
      Bucket: 'postdee-r2',
      Key: 'uploads/seller-a/video.mp4',
      ContentType: 'video/mp4'
    });
    expect(send.mock.calls[1]?.[0].input).toEqual({
      Bucket: 'postdee-r2',
      Key: 'uploads/seller-a/video.mp4',
      UploadId: 'r2-upload-1',
      MultipartUpload: {
        Parts: [
          { ETag: 'etag-1', PartNumber: 1 },
          { ETag: 'etag-2', PartNumber: 2 }
        ]
      }
    });
    expect(send.mock.calls[2]?.[0].input).toEqual({
      Bucket: 'postdee-r2',
      Key: 'uploads/seller-a/video.mp4',
      UploadId: 'r2-upload-1'
    });
  });

  it('reads the completed object size with an R2 HEAD request', async () => {
    const send = vi.fn().mockResolvedValue({ ContentLength: 20_000_000 });
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: { send } as unknown as S3Client
    });

    await expect(
      client.multipart?.getObjectSize({
        bucket: 'postdee-r2',
        key: 'uploads/seller-a/video.mp4'
      })
    ).resolves.toBe(20_000_000);
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0].input).toEqual({
      Bucket: 'postdee-r2',
      Key: 'uploads/seller-a/video.mp4'
    });
  });

  it.each([
    Object.assign(new Error('not found'), { name: 'NotFound' }),
    Object.assign(new Error('no such key'), { Code: 'NoSuchKey' }),
    Object.assign(new Error('missing'), {
      $metadata: { httpStatusCode: 404 }
    })
  ])('returns no completed size when R2 reports a missing object', async (error) => {
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: {
        send: vi.fn().mockRejectedValue(error)
      } as unknown as S3Client
    });

    await expect(
      client.multipart?.getObjectSize({
        bucket: 'postdee-r2',
        key: 'uploads/seller-a/missing.mp4'
      })
    ).resolves.toBeUndefined();
  });

  it('does not hide unexpected completed object lookup failures', async () => {
    const failure = new Error('R2 is unavailable');
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: {
        send: vi.fn().mockRejectedValue(failure)
      } as unknown as S3Client
    });

    await expect(
      client.multipart?.getObjectSize({
        bucket: 'postdee-r2',
        key: 'uploads/seller-a/video.mp4'
      })
    ).rejects.toBe(failure);
  });

  it('rejects an R2 HEAD response without a completed object size', async () => {
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: {
        send: vi.fn().mockResolvedValue({})
      } as unknown as S3Client
    });

    await expect(
      client.multipart?.getObjectSize({
        bucket: 'postdee-r2',
        key: 'uploads/seller-a/video.mp4'
      })
    ).rejects.toThrow('did not return the completed object size');
  });

  it('presigns multipart parts with their exact content length', async () => {
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key'
    });

    const uploadUrl = await client.multipart?.createPartUpload({
      bucket: 'postdee-r2',
      key: 'uploads/seller-a/video.mp4',
      storageUploadId: 'r2-upload-1',
      partNumber: 3,
      sizeBytes: 8_388_608,
      expiresInSeconds: 1500
    });

    const signedUrl = new URL(uploadUrl ?? '');
    expect(signedUrl.pathname).toContain('/uploads/seller-a/video.mp4');
    expect(signedUrl.searchParams.get('partNumber')).toBe('3');
    expect(signedUrl.searchParams.get('uploadId')).toBe('r2-upload-1');
    expect(signedUrl.searchParams.get('X-Amz-Expires')).toBe('1500');
    expect(signedUrl.searchParams.get('X-Amz-SignedHeaders')).toContain(
      'content-length'
    );
  });

  it('treats NoSuchUpload as an idempotent multipart abort result', async () => {
    const noSuchUpload = Object.assign(new Error('upload is already gone'), {
      name: 'NoSuchUpload'
    });
    const send = vi.fn().mockRejectedValue(noSuchUpload);
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: { send } as unknown as S3Client
    });

    await expect(
      client.multipart?.abortUpload({
        bucket: 'postdee-r2',
        key: 'uploads/seller-a/video.mp4',
        storageUploadId: 'r2-upload-missing'
      })
    ).resolves.toBeUndefined();
  });

  it('does not hide unexpected multipart abort failures', async () => {
    const failure = new Error('R2 is unavailable');
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: {
        send: vi.fn().mockRejectedValue(failure)
      } as unknown as S3Client
    });

    await expect(
      client.multipart?.abortUpload({
        bucket: 'postdee-r2',
        key: 'uploads/seller-a/video.mp4',
        storageUploadId: 'r2-upload-1'
      })
    ).rejects.toBe(failure);
  });

  it('lists every multipart upload across paginated R2 responses', async () => {
    const send = vi
      .fn()
      .mockResolvedValueOnce({
        Uploads: [
          {
            Key: 'uploads/seller-a/first.mp4',
            UploadId: 'upload-1',
            Initiated: new Date('2026-07-13T01:00:00.000Z')
          }
        ],
        IsTruncated: true,
        NextKeyMarker: 'uploads/seller-a/first.mp4',
        NextUploadIdMarker: 'upload-1'
      })
      .mockResolvedValueOnce({
        Uploads: [
          {
            Key: 'uploads/seller-a/second.mp4',
            UploadId: 'upload-2',
            Initiated: new Date('2026-07-13T02:00:00.000Z')
          },
          { Key: undefined, UploadId: 'ignored' }
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
      client.multipart?.listUploadsByPrefix({
        bucket: 'postdee-r2',
        prefix: 'uploads/seller-a/'
      })
    ).resolves.toEqual([
      {
        storageUploadId: 'upload-1',
        videoS3Key: 'uploads/seller-a/first.mp4',
        createdAt: '2026-07-13T01:00:00.000Z'
      },
      {
        storageUploadId: 'upload-2',
        videoS3Key: 'uploads/seller-a/second.mp4',
        createdAt: '2026-07-13T02:00:00.000Z'
      }
    ]);

    expect(send).toHaveBeenCalledTimes(2);
    expect(send.mock.calls[0]?.[0].input).toMatchObject({
      Bucket: 'postdee-r2',
      Prefix: 'uploads/seller-a/',
      KeyMarker: undefined,
      UploadIdMarker: undefined
    });
    expect(send.mock.calls[1]?.[0].input).toMatchObject({
      KeyMarker: 'uploads/seller-a/first.mp4',
      UploadIdMarker: 'upload-1'
    });
  });

  it('rejects a truncated multipart response that cannot be continued', async () => {
    const client = createCloudflareR2VideoStorageClient({
      accountId: 'account-id',
      accessKeyId: 'access-key',
      secretAccessKey: 'secret-key',
      s3Client: {
        send: vi.fn(async () => ({ IsTruncated: true }))
      } as unknown as S3Client
    });

    await expect(
      client.multipart?.listUploadsByPrefix({
        bucket: 'postdee-r2',
        prefix: 'uploads/seller-a/'
      })
    ).rejects.toThrow('without a key marker');
  });

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
