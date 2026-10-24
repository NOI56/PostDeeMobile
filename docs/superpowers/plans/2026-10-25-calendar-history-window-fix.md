# Calendar history window fixes from the Codex review

Baseline: `origin/main` at `f29c701e` (2026-10-25). Branch:
`claude/fix-calendar-history-window`. Source: a Codex review of PR #28 on
2026-10-25. Both findings were confirmed against the code.

## Findings

1. **Rescheduled posts could be missed.** The app stopped paging after the page
   that reached 31 days before the oldest viewed period, by creation time. But
   `PATCH /posts/:id` measures the 14- or 30-day window from the reschedule
   request, not the creation time. A post created on 1 August and rescheduled a
   few times into October could sit on a page the app never read.
2. **The week→month switch did not widen the window.** Only `_selectDay`
   extended the history start, and the view toggles only flipped
   `_isWeekView`. After browsing back to the week of 28 September and switching
   to month view, posts created early in August that show in early September
   stayed missing, even after a refresh.

## Fix

- API:
  - `GET /posts` paging accepts `activeSince` (RFC 3339, paging only). The
    page keeps posts whose `createdAt`, `scheduledAt` or `publishedAt` is at or
    after it.
  - Prisma adds `AND: [{ OR: [...] }]` beside the keyset `OR`, and the memory
    store mirrors it.
  - A malformed `activeSince`, or `activeSince` without paging, returns
    `400 INVALID_POST_PAGE`.
  - The Calendar time is one of those three fields, so the filter returns every
    post the window can show.
- App:
  - `listCalendarPosts({ activeSince })` sends the parameter on every page and
    pages until `nextCursor: null` (or 20 pages). The creation-time early stop
    is removed.
  - Calendar passes the start of the oldest viewed period, without the 31-day
    margin.
  - `_extendHistoryToVisiblePeriod()` now also runs after either view toggle.
- Compatibility:
  - Old apps don't send the parameter, so they are unaffected.
  - Against an API without `activeSince` (main before this change), the app
    simply pages through the history up to 20 pages.
- Docs: `API.md` (new `activeSince` row; the cursor wording now says cursors are
  not signed but stay owner-scoped, as Codex noted), `ARCHITECTURE.md`,
  `README.md`.

## Reproduction before the fix

API: `postPaginationActiveSince.test.ts` ran against `f29c701e`, and all 4
failed:
- The August-only published post was returned with the October ones (no filter).
- `activeSince=yesterday` and `activeSince` without paging returned 200.
- Prisma got no `activeSince` filter.

App: commit `c4d66783` (the API fix plus the updated app tests, without the app
fix) is the CI before-fix run on PR #34. CI Flutter Mobile failed at
`flutter analyze`, because the named parameter `activeSince` isn't defined: the
old client has no way to ask for the window. Because analysis stopped first,
the updated `calendar_history_window_test.dart` did not run in that commit. It
expects the window start (1 October, then 1 September) instead of the old
31-day margin, and a reload after the week→month switch.

## Verification

See the pull request: the full API suite, typecheck, build, and CI Flutter
Mobile (`flutter analyze` + full `flutter test`) on the fix commit. Local
Flutter was blocked by another session's long-running `flutter test`.
