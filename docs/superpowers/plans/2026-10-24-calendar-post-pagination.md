# Calendar post history cursor pagination

Baseline: latest verified `origin/main` at
`6afe4d6b07fe53032467031b4575aa62c9751912` (2026-10-24), ahead/behind 0/0.
Branch: `claude/security-calendar-post-pagination`. Source: audit run-2 finding
`posts/full-row-owned-history-before-bounded-use`, the part Batch 5 (PR #22)
left open: "Plain `GET /posts`, used by Calendar, still returns the full
history until the app supports pagination". This change is additive and does
not depend on PR #22.

## Problem

Calendar (`listCalendarPosts`) called plain `GET /posts`. The API read and
serialized the owner's entire retained post history in one request inside the
single shared API process. Plain `GET /posts` cannot simply be capped, because
installed app versions expect the complete list.

## Design

- **Opt-in parameters.** `GET /posts?pageSize=<1-100>[&cursor=<nextCursor>]`
  returns one page, newest created first (`createdAt desc, id desc`), and adds
  `nextCursor` (`null` on the last page).
  - The cursor is opaque base64url of `{v:1, c:createdAt, i:id}`. It is
    validated strictly: ISO round-trip, id length, 512-character cap.
  - A `cursor` without `pageSize` defaults to 50.
  - Paging combined with `limit` or `includeMedia` returns
    `400 INVALID_POST_PAGE`. `scheduled=true` combines with paging.
- **Store.** A new `PostStore.listPage({ userId, scheduledOnly?, limit, after? })`.
  - Prisma runs an owner-scoped keyset query with `take: limit + 1` on the
    existing `(userId, createdAt)` index. Ties on `createdAt` are broken by
    `id`, so no row is skipped or repeated.
  - The memory store mirrors this.
  - `PostStore.list` is untouched, which avoids conflicts with PR #22.
- **Legacy.** Plain `GET /posts` is unchanged (complete history, no
  `nextCursor`).
- **App.**
  - `listCalendarPostsPage({cursor})` and
    `listCalendarPosts({createdSince, maxPages = 20})` request pages of 100.
    Paging stops at `nextCursor: null`, after the page whose oldest post was
    created before `createdSince`, or after 20 pages. Repeated ids are dropped.
  - A non-string `nextCursor` is rejected.
  - Calendar passes `createdSince` = 31 days before the oldest period (month or
    week) the user has viewed. A post's calendar time (publish, schedule or
    creation time) is at most about 30 days after creation, because of the
    schedule window.
  - Navigating to an earlier period extends the window and reloads silently.
    Injected complete-history loaders used by tests keep their old behavior.
- **Compatibility in both directions.**
  - Old app with new API: unchanged.
  - New app with old API: the old API ignores the parameters and returns the
    full list without `nextCursor`, which the app treats as the last page.

## Reproduction before the fix

API (`postPagination.test.ts`, run against the baseline): 11 of 13 failed.

| Case | Before-fix result |
| --- | --- |
| `GET /posts?pageSize=2` pages with a cursor and no full-history read | 500: the full `store.list` history read ran (blocked by the test) |
| Scheduled-only paging | `nextCursor` missing (`undefined`), all posts returned |
| `pageSize=0/101/abc`, bad cursors, paging with `limit` or `includeMedia` (7 cases) | 200, parameters ignored |
| Prisma keyset query, no-next-page detection | `repository.listPage is not a function` |

Guards that pass before and after: the plain list stays complete without
`nextCursor`, and same-millisecond posts are neither skipped nor repeated.

Mobile (`calendar_post_pagination_test.dart`,
`calendar_history_window_test.dart`) did not compile against the baseline app:
`listCalendarPosts` had no `createdSince` or `maxPages`,
`listCalendarPostsPage` did not exist, and `CalendarScreen` had no
`loadCalendarPostsSince`. The baseline client sent plain `GET /posts`, and the
existing API test asserted an empty query. The existing test "calendar activity loads immediate and scheduled posts
without previews" now expects `pageSize=100` instead of an empty query. Its
server omits `nextCursor`, so it doubles as the new-app/old-API compatibility
test (all 53 posts from one response).

## Deploy

No schema change, migration or environment variable. Either order works. API
first is preferred so new app builds page from the start. Plain `GET /posts`
can later be capped (for example to the newest 500) once the minimum supported
app version pages; that needs an owner decision.

## Verification

- API: `npm run test`, `npm run typecheck`, `npm run build` (results in the
  pull request).
- Mobile: `flutter analyze`, `flutter test` (results in the pull request).
- Not verified: the app against Staging, and a real device.

## Residual risk

- The legacy unbounded path remains until old apps are retired.
- A user who browses back far into history makes one request per 100 posts,
  up to 20 per load. Older posts beyond 2,000 in the window are not shown.
- Calendar refreshes every 30 seconds while posts are pending. Each refresh
  re-reads pages back to the current window, usually one request.
