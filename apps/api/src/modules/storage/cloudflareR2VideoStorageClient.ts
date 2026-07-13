import {
  DeleteObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import type { S3VideoStorageClient } from './videoStorage.js';

const buildR2Endpoint = (accountId: string) =>
  `https://${accountId}.r2.cloudflarestorage.com`;

export const createCloudflareR2VideoStorageClient = ({
  accountId,
  accessKeyId,
  secretAccessKey,
  endpoint,
  s3Client
}: {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  endpoint?: string;
  s3Client?: S3Client;
}): S3VideoStorageClient => {
  const client =
    s3Client ??
    new S3Client({
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
    listObjectKeysByPrefix: async ({ bucket, prefix }) => {
      const keys: string[] = [];
      let continuationToken: string | undefined;

      do {
        const page = await client.send(
          new ListObjectsV2Command({
            Bucket: bucket,
            Prefix: prefix,
            ContinuationToken: continuationToken
          })
        );

        for (const object of page.Contents ?? []) {
          if (object.Key) {
            keys.push(object.Key);
          }
        }

        if (page.IsTruncated && !page.NextContinuationToken) {
          throw new Error('R2 object listing was truncated without a continuation token');
        }

        continuationToken = page.IsTruncated
          ? page.NextContinuationToken
          : undefined;
      } while (continuationToken);

      return keys;
    },
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
