export const aiMediaDownloadMaxBytes = 200 * 1024 * 1024;

export class MediaDownloadError extends Error {
  constructor(
    message: string,
    readonly statusCode: number,
    readonly code: string
  ) {
    super(message);
  }
}

const readContentLength = (headers: Headers) => {
  const rawValue = headers.get('content-length');

  if (!rawValue) {
    return undefined;
  }

  const value = Number(rawValue);
  return Number.isFinite(value) && value >= 0 ? value : undefined;
};

const createTooLargeError = () =>
  new MediaDownloadError(
    'Selected media is too large for AI processing',
    413,
    'AI_MEDIA_TOO_LARGE'
  );

export const readAiMediaResponseBytes = async (
  response: Pick<Response, 'arrayBuffer' | 'headers'>,
  maxBytes = aiMediaDownloadMaxBytes
) => {
  const contentLength = readContentLength(response.headers);

  if (contentLength !== undefined && contentLength > maxBytes) {
    throw createTooLargeError();
  }

  const buffer = await response.arrayBuffer();

  if (buffer.byteLength > maxBytes) {
    throw createTooLargeError();
  }

  return new Uint8Array(buffer);
};
