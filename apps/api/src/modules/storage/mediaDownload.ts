export const aiMediaDownloadMaxBytes = 200 * 1024 * 1024;
export const aiEditAudioDownloadMaxBytes = 25 * 1024 * 1024;
// Caption frames are small JPEG stills extracted by the app.
export const aiCaptionFrameMaxBytes = 5 * 1024 * 1024;

export type AiMediaFetchOptions = { kind: 'frame'; maxBytes: number };

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

// Reads the body chunk by chunk so a missing or understated Content-Length
// cannot make the shared process buffer more than maxBytes.
const readBodyWithinLimit = async (body: ReadableStream<Uint8Array>, maxBytes: number) => {
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  for (;;) {
    const { done, value } = await reader.read();

    if (done) {
      break;
    }

    total += value.byteLength;

    if (total > maxBytes) {
      await reader.cancel().catch(() => undefined);
      throw createTooLargeError();
    }

    chunks.push(value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;

  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return bytes;
};

export const readAiMediaResponseBytes = async (
  response: Pick<Response, 'arrayBuffer' | 'headers'> & { body?: ReadableStream<Uint8Array> | null },
  maxBytes = aiMediaDownloadMaxBytes
) => {
  const contentLength = readContentLength(response.headers);

  if (contentLength !== undefined && contentLength > maxBytes) {
    throw createTooLargeError();
  }

  if (response.body) {
    return readBodyWithinLimit(response.body, maxBytes);
  }

  const buffer = await response.arrayBuffer();

  if (buffer.byteLength > maxBytes) {
    throw createTooLargeError();
  }

  return new Uint8Array(buffer);
};
