import type { UploadMetadata } from '../storage/videoStorage.js';

export const aiEditAudioUploadPurpose = 'ai-edit-audio' as const;
export const aiEditAudioUploadMaxBytes = 25 * 1024 * 1024;
export const aiEditAudioUploadInvalidCode = 'UPLOAD_AI_EDIT_AUDIO_INVALID' as const;
export const aiEditVisualProxyUploadPurpose = 'ai-edit-visual-proxy' as const;
export const aiEditVisualProxyUploadMaxBytes = 50 * 1024 * 1024;
export const aiEditVisualProxyUploadInvalidCode =
  'UPLOAD_AI_EDIT_VISUAL_PROXY_INVALID' as const;

const isPositiveNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value) && value > 0;

const readOptionalPositiveNumber = (value: unknown) => (isPositiveNumber(value) ? value : undefined);

type ReadUploadMetadataOptions = {
  maxSizeBytes: number;
};

const isVerticalNineBySixteen = ({ width, height }: { width: number; height: number }) => {
  if (height <= width) {
    return false;
  }

  const expectedHeight = (width * 16) / 9;
  const tolerance = expectedHeight * 0.02;

  return Math.abs(height - expectedHeight) <= tolerance;
};

export const readUploadMetadata = (body: unknown, { maxSizeBytes }: ReadUploadMetadataOptions) => {
  const payload = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const fileName = typeof payload.fileName === 'string' ? payload.fileName.trim() : '';
  const contentType = typeof payload.contentType === 'string' ? payload.contentType.trim() : '';
  const sizeBytes = payload.sizeBytes;
  const width = readOptionalPositiveNumber(payload.width);
  const height = readOptionalPositiveNumber(payload.height);

  if (payload.purpose === aiEditAudioUploadPurpose) {
    const hasDimensions = payload.width !== undefined || payload.height !== undefined;
    const audioSizeLimit = Math.min(maxSizeBytes, aiEditAudioUploadMaxBytes);
    const isValidAiEditAudio =
      fileName.toLowerCase().endsWith('.m4a') &&
      contentType === 'audio/mp4' &&
      isPositiveNumber(sizeBytes) &&
      sizeBytes <= audioSizeLimit &&
      !hasDimensions;

    if (!isValidAiEditAudio) {
      return {
        ok: false as const,
        code: aiEditAudioUploadInvalidCode,
        message: 'AI edit audio must be an M4A audio/mp4 file no larger than 25 MiB.'
      };
    }

    return {
      ok: true as const,
      metadata: {
        fileName,
        contentType,
        sizeBytes,
        width,
        height
      }
    };
  }

  if (payload.purpose === aiEditVisualProxyUploadPurpose) {
    const hasDimensions = payload.width !== undefined || payload.height !== undefined;
    const proxySizeLimit = Math.min(maxSizeBytes, aiEditVisualProxyUploadMaxBytes);
    const isValidVisualProxy =
      fileName.toLowerCase().endsWith('.mp4') &&
      contentType === 'video/mp4' &&
      isPositiveNumber(sizeBytes) &&
      sizeBytes <= proxySizeLimit &&
      !hasDimensions;

    if (!isValidVisualProxy) {
      return {
        ok: false as const,
        code: aiEditVisualProxyUploadInvalidCode,
        message: 'AI edit visual proxy must be an MP4 video/mp4 file no larger than 50 MiB.'
      };
    }

    return {
      ok: true as const,
      metadata: {
        fileName,
        contentType,
        sizeBytes,
        width,
        height
      }
    };
  }

  // Videos are the main upload; images are accepted too for AI-caption frames.
  const isSupportedContentType =
    contentType.startsWith('video/') || contentType.startsWith('image/');

  if (!fileName || !isSupportedContentType || !isPositiveNumber(sizeBytes)) {
    return {
      ok: false as const,
      message: 'fileName, a video or image contentType, and positive sizeBytes are required'
    };
  }

  if (sizeBytes > maxSizeBytes) {
    return {
      ok: false as const,
      message: `File is larger than the configured upload limit of ${maxSizeBytes} bytes.`
    };
  }

  if (width !== undefined && height !== undefined && !isVerticalNineBySixteen({ width, height })) {
    return {
      ok: false as const,
      message: 'Use a vertical 9:16 video, such as 1080x1920.'
    };
  }

  return {
    ok: true as const,
    metadata: {
      fileName,
      contentType,
      sizeBytes,
      width,
      height
    }
  };
};
