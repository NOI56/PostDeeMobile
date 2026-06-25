import type { ServerConfig } from '../../config/env.js';
import {
  type S3VideoStorageClient,
  type VideoStorage,
  createMockVideoStorage,
  createR2VideoStorage,
  createS3VideoStorage
} from './videoStorage.js';
import { createCloudflareR2VideoStorageClient } from './cloudflareR2VideoStorageClient.js';

type VideoStorageConfig = Pick<
  ServerConfig,
  | 'videoStorage'
  | 'awsS3Bucket'
  | 'awsS3UploadExpiresSeconds'
  | 'cloudflareR2Bucket'
  | 'cloudflareR2AccountId'
  | 'cloudflareR2AccessKeyId'
  | 'cloudflareR2SecretAccessKey'
  | 'cloudflareR2Endpoint'
  | 'cloudflareR2UploadExpiresSeconds'
>;

const createConfiguredR2Client = (config: VideoStorageConfig): S3VideoStorageClient => {
  if (
    !config.cloudflareR2AccountId ||
    !config.cloudflareR2AccessKeyId ||
    !config.cloudflareR2SecretAccessKey
  ) {
    throw new Error(
      'CLOUDFLARE_R2_ACCOUNT_ID, CLOUDFLARE_R2_ACCESS_KEY_ID, and CLOUDFLARE_R2_SECRET_ACCESS_KEY are required when VIDEO_STORAGE is r2'
    );
  }

  return createCloudflareR2VideoStorageClient({
    accountId: config.cloudflareR2AccountId,
    accessKeyId: config.cloudflareR2AccessKeyId,
    secretAccessKey: config.cloudflareR2SecretAccessKey,
    endpoint: config.cloudflareR2Endpoint
  });
};

export const createVideoStorageFromConfig = ({
  config,
  s3Client,
  r2Client
}: {
  config: VideoStorageConfig;
  s3Client?: S3VideoStorageClient;
  r2Client?: S3VideoStorageClient;
}): VideoStorage => {
  if (config.videoStorage === 's3') {
    if (!config.awsS3Bucket) {
      throw new Error('AWS_S3_BUCKET is required when VIDEO_STORAGE is s3');
    }

    if (!s3Client) {
      throw new Error('S3 video storage requires an S3 client');
    }

    return createS3VideoStorage({
      bucket: config.awsS3Bucket,
      client: s3Client,
      uploadExpiresSeconds: config.awsS3UploadExpiresSeconds
    });
  }

  if (config.videoStorage === 'r2') {
    if (!config.cloudflareR2Bucket) {
      throw new Error('CLOUDFLARE_R2_BUCKET is required when VIDEO_STORAGE is r2');
    }

    return createR2VideoStorage({
      bucket: config.cloudflareR2Bucket,
      client: r2Client ?? createConfiguredR2Client(config),
      uploadExpiresSeconds: config.cloudflareR2UploadExpiresSeconds
    });
  }

  return createMockVideoStorage();
};
