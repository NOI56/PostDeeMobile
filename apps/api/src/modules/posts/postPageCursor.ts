// Opaque keyset cursor for GET /posts pages, ordered by createdAt desc, id desc.
// It names a position inside the caller's own posts; every page query is
// owner-scoped, so a forged cursor cannot reach another owner's rows.
export type PostPageCursor = { createdAt: string; id: string };

export const defaultPostPageSize = 50;
export const maxPostPageSize = 100;

export const encodePostPageCursor = ({ createdAt, id }: PostPageCursor) =>
  Buffer.from(JSON.stringify({ v: 1, c: createdAt, i: id })).toString('base64url');

const decodePostPageCursor = (value: string): PostPageCursor | undefined => {
  if (value.length === 0 || value.length > 512 || !/^[A-Za-z0-9_-]+$/.test(value)) return undefined;
  try {
    const parsed: unknown = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
    if (typeof parsed !== 'object' || parsed === null) return undefined;
    const { v, c, i } = parsed as Record<string, unknown>;
    if (v !== 1 || typeof c !== 'string' || typeof i !== 'string' || i.length === 0 || i.length > 200) {
      return undefined;
    }
    const createdAt = new Date(c);
    return Number.isFinite(createdAt.getTime()) && createdAt.toISOString() === c
      ? { createdAt: c, id: i }
      : undefined;
  } catch {
    return undefined;
  }
};

export type PostPageRequest = { pageSize: number; after?: PostPageCursor; activeSince?: string };

const readActiveSince = (value: unknown) => {
  if (typeof value !== 'string' || value.length > 40) return undefined;
  const time = new Date(value);
  return Number.isFinite(time.getTime()) ? time.toISOString() : undefined;
};

// Undefined when the request asks for no page (the legacy complete list).
// `activeSince` keeps posts created, scheduled or published at/after that time.
export const readPostPageRequest = (query: {
  pageSize?: unknown;
  cursor?: unknown;
  activeSince?: unknown;
}): PostPageRequest | 'invalid' | undefined => {
  const { pageSize: rawPageSize, cursor: rawCursor, activeSince: rawActiveSince } = query;
  if (rawPageSize === undefined && rawCursor === undefined) {
    return rawActiveSince === undefined ? undefined : 'invalid';
  }
  const activeSince = rawActiveSince === undefined ? undefined : readActiveSince(rawActiveSince);
  if (rawActiveSince !== undefined && !activeSince) return 'invalid';
  const filter = activeSince ? { activeSince } : {};

  let pageSize = defaultPostPageSize;
  if (rawPageSize !== undefined) {
    if (typeof rawPageSize !== 'string' || !/^\d{1,3}$/.test(rawPageSize)) return 'invalid';
    pageSize = Number(rawPageSize);
    if (pageSize < 1 || pageSize > maxPostPageSize) return 'invalid';
  }

  if (rawCursor === undefined) return { pageSize, ...filter };
  const after = typeof rawCursor === 'string' ? decodePostPageCursor(rawCursor) : undefined;
  return after ? { pageSize, after, ...filter } : 'invalid';
};
