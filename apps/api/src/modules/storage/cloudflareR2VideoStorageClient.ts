import {
  AbortMultipartUploadCommand,
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListMultipartUploadsCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
  UploadPartCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import type {
  MultipartVideoUpload,
  S3VideoStorageClient
} from './videoStorage.js';

const buildR2Endpoint = (accountId: string) =>
  `https://${accountId}.r2.cloudflarestorage.com`;

const isNoSuchUploadError = (error: unknown) => {
  if (!error || typeof error !== 'object') {
    return false;
  }

  const candidate = error as {
    name?: unknown;
    code?: unknown;
    Code?: unknown;
  };

  return [candidate.name, candidate.code, candidate.Code].includes('NoSuchUpload');
};

const isObjectNotFoundError = (error: unknown) => {
  if (!error || typeof error !== 'object') {
    return false;
  }

  const candidate = error as {
    name?: unknown;
    code?: unknown;
    Code?: unknown;
    status?: unknown;
    statusCode?: unknown;
    httpStatusCode?: unknown;
    $metadata?: { httpStatusCode?: unknown };
  };

  return (
    [candidate.name, candidate.code, candidate.Code].some((value) =>
      ['NotFound', 'NoSuchKey'].includes(String(value))
    ) ||
    [
      candidate.status,
      candidate.statusCode,
      candidate.httpStatusCode,
      candidate.$metadata?.httpStatusCode
    ].includes(404)
  );
};

const unknownMultipartUploadCreatedAt = new Date(0).toISOString();

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
    multipart: {
      createUpload: async ({ bucket, key, contentType }) => {
        const response = await client.send(
          new CreateMultipartUploadCommand({
            Bucket: bucket,
            Key: key,
            ContentType: contentType
          })
        );

        if (!response.UploadId) {
          throw new Error('R2 did not return an ID for the multipart upload');
        }

        return { storageUploadId: response.UploadId };
      },
      createPartUpload: async ({
        bucket,
        key,
        storageUploadId,
        partNumber,
        sizeBytes,
        expiresInSeconds
      }) =>
        getSignedUrl(
          client,
          new UploadPartCommand({
            Bucket: bucket,
            Key: key,
            UploadId: storageUploadId,
            PartNumber: partNumber,
            ContentLength: sizeBytes
          }),
          {
            expiresIn: expiresInSeconds,
            signableHeaders: new Set(['content-length'])
          }
        ),
      completeUpload: async ({
        bucket,
        key,
        storageUploadId,
        parts
      }) => {
        await client.send(
          new CompleteMultipartUploadCommand({
            Bucket: bucket,
            Key: key,
            UploadId: storageUploadId,
            MultipartUpload: {
              Parts: [...parts]
                .sort((left, right) => left.partNumber - right.partNumber)
                .map(({ partNumber, eTag }) => ({
                  ETag: eTag,
                  PartNumber: partNumber
                }))
            }
          })
        );
      },
      abortUpload: async ({ bucket, key, storageUploadId }) => {
        try {
          await client.send(
            new AbortMultipartUploadCommand({
              Bucket: bucket,
              Key: key,
              UploadId: storageUploadId
            })
          );
        } catch (error) {
          if (!isNoSuchUploadError(error)) {
            throw error;
          }
        }
      },
      getObjectSize: async ({ bucket, key }) => {
        try {
          const response = await client.send(
            new HeadObjectCommand({
              Bucket: bucket,
              Key: key
            })
          );

          if (
            typeof response.ContentLength !== 'number' ||
            !Number.isSafeInteger(response.ContentLength) ||
            response.ContentLength < 0
          ) {
            throw new Error('R2 did not return the completed object size');
          }

          return response.ContentLength;
        } catch (error) {
          if (isObjectNotFoundError(error)) {
            return undefined;
          }

          throw error;
        }
      },
      listUploadsByPrefix: async ({ bucket, prefix }) => {
        const uploads: MultipartVideoUpload[] = [];
        let keyMarker: string | undefined;
        let uploadIdMarker: string | undefined;

        do {
          const page = await client.send(
            new ListMultipartUploadsCommand({
              Bucket: bucket,
              Prefix: prefix,
              KeyMarker: keyMarker,
              UploadIdMarker: uploadIdMarker
            })
          );

          for (const upload of page.Uploads ?? []) {
            if (upload.Key && upload.UploadId) {
              uploads.push({
                storageUploadId: upload.UploadId,
                videoS3Key: upload.Key,
                createdAt:
                  upload.Initiated?.toISOString() ?? unknownMultipartUploadCreatedAt
              });
            }
          }

          if (page.IsTruncated && !page.NextKeyMarker) {
            throw new Error(
              'R2 multipart upload listing was truncated without a key marker'
            );
          }

          if (
            page.IsTruncated &&
            page.NextKeyMarker === keyMarker &&
            page.NextUploadIdMarker === uploadIdMarker
          ) {
            throw new Error(
              'R2 multipart upload listing returned the same pagination markers'
            );
          }

          keyMarker = page.IsTruncated ? page.NextKeyMarker : undefined;
          uploadIdMarker = page.IsTruncated
            ? page.NextUploadIdMarker
            : undefined;
        } while (keyMarker);

        return uploads;
      }
    },
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
