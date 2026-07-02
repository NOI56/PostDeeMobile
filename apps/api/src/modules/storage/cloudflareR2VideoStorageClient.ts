import { DeleteObjectCommand, GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import type { S3VideoStorageClient } from './videoStorage.js';

const buildR2Endpoint = (accountId: string) =>
  `https://${accountId}.r2.cloudflarestorage.com`;

export const createCloudflareR2VideoStorageClient = ({
  accountId,
  accessKeyId,
  secretAccessKey,
  endpoint
}: {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  endpoint?: string;
}): S3VideoStorageClient => {
  const client = new S3Client({
    region: 'auto',
    endpoint: endpoint ?? buildR2Endpoint(accountId),
    credentials: {
      accessKeyId,
      secretAccessKey
    }
  });

  return {
    createPresignedUploadUrl: async ({
      bucket,
      key,
      contentType,
      sizeBytes,
      expiresInSeconds
    }) =>
      getSignedUrl(
        client,
        new PutObjectCommand({
          Bucket: bucket,
          Key: key,
          ContentType: contentType,
          ContentLength: sizeBytes
        }),
        {
          expiresIn: expiresInSeconds,
          signableHeaders: new Set(['content-length', 'content-type'])
        }
      ),
    createPresignedDownloadUrl: async ({ bucket, key, expiresInSeconds }) =>
      getSignedUrl(
        client,
        new GetObjectCommand({
          Bucket: bucket,
          Key: key
        }),
        {
          expiresIn: expiresInSeconds
        }
      ),
    deleteObject: async ({ bucket, key }) => {
      await client.send(
        new DeleteObjectCommand({
          Bucket: bucket,
          Key: key
        })
      );
    }
  };
};
