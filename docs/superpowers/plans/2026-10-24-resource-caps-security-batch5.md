# Per-owner resource caps: security Batch 5

Baseline: latest verified `origin/main` at
`a4efd650d7a74b26fc81e11ccb8bf59d2eeaa79a` (2026-10-24), ahead/behind 0/0.
Implementation branch: `claude/security-batch5-resource-caps`, in its own clean
worktree. Only audit run-2 Batch 5 is in scope; it does not depend on the open
Batch 2, 3 or 4 pull requests.

## Reproduction before implementation

Seventeen regression cases failed against the baseline on 2026-10-24 with mock
auth, memory stores and Prisma-shaped fakes (19 cases in four new test files;
2 guards passed):

| Area | Expected | Before-fix result |
| --- | --- | --- |
| Template title 121 / body 5001 chars | 400 `TEMPLATE_FIELD_TOO_LONG` | 201 |
| 201st template for one owner | 409 `TEMPLATE_LIMIT_REACHED` | 201 |
| Template count and bounded Prisma list | `count`, `take: 200` | Not available |
| Device token of 4097 chars or with spaces | 400 `DEVICE_TOKEN_INVALID` | 200 |
| 12 tokens for one owner | Newest 10 kept | All 12 kept |
| Prisma device register/list | Prune past 10, `take: 10` | Unbounded |
| `PATCH /posts/:id`, `publish-now` | No history list | Listed history (500 when list fails) |
| `GET /posts?limit=3` | Store asked for 3 | Full history read |
| Memory/Prisma limited list | Newest first, `take` | Unbounded |
| TikTok-only or shared caption > 63206 | `CAPTION_TOO_LONG` | Accepted |
| File name of 256 chars, `video/x-anything`, `image/svg+xml` | Rejected | Accepted |
| 11th unexpired upload session | `UPLOAD_SESSION_LIMIT_REACHED` | Created |

Guards that pass before and after: expired sessions do not count, and a
63206-character TikTok Inbox caption is accepted. The Prisma upload-cap case was
added after implementation. These are local reproductions, not deployed tests.

## Change boundaries

- Templates: title at most 120 and body at most 5000 characters after
  trimming. At most 200 per owner, using a non-transactional count, so a
  concurrent burst can overshoot slightly. The list is newest first, capped
  at 200.
- Device tokens: 1-4096 characters of `A-Za-z0-9:_.-`. Each register keeps
  the 10 newest tokens by `updatedAt` and deletes the rest. `listForUser`
  takes 10. FCM chunking is unnecessary at this cap. Pruning tokens FCM
  reports as unregistered waits until the real push sender is enabled.
- Posts:
  - Limited or media `GET /posts` passes `limit` to the store, which orders
    by `createdAt desc` and uses `take`. The route still sorts and slices
    defensively.
  - `PATCH` and `publish-now` use `findOwned`.
  - The Prisma `list` throws without `userId`. The interface stays optional
    because many tests call the memory store unscoped.
  - New posts reject any shared or per-platform caption above 63206 UTF-16
    units (`CAPTION_TOO_LONG`). Only the create route checks this.
    `readPlatformCaptionIssue` and the publisher are unchanged, so posts
    already queued are not re-checked.
- Uploads:
  - `fileName` is at most 255 characters for every purpose.
  - General uploads accept exactly `video/mp4`, `video/quicktime`,
    `image/jpeg`, `image/png` and `image/webp`. The app sends only `video/mp4`
    and `image/jpeg`.
  - An owner may hold at most 10 unexpired `UPLOADING` sessions. In Postgres
    this is counted inside the serializable create transaction. The rejected
    request's R2 multipart upload is aborted by the existing error path.

## Deliberately not done here

- The TikTok 2200 cap stays Direct-only. The app does not preflight 2200 for
  Inbox drafts, so a server-only 2200 rule would reject posts with no warning
  in the app. The 63206 ceiling bounds storage without changing valid posts.
- Plain `GET /posts` (Calendar) still returns the full history; bounding it
  needs app pagination first.
- No sweeper yet retires expired upload sessions or aborts abandoned R2
  multipart uploads. This needs scheduler integration plus an R2 lifecycle
  rule decision.
- BullMQ owner/post job indexing: BullMQ is not deployed.

## Compatibility and deployment notes

- No schema change, migration, env var or `render.yaml` change; no mobile
  change.
- Owners who already have more than 200 templates or 10 device tokens keep
  their rows. The list shows the newest 200, and the next device registration
  prunes tokens to 10.
- Owner check (read-only SQL on Production before merge): count templates
  per owner and device tokens per owner to confirm no real account exceeds
  the caps.

## Verification

- `npm.cmd run test`: 156 files passed, 4 skipped; 2586 tests passed, 25 skipped.
- `npm.cmd run typecheck` and `npm.cmd run build`: passed.
- Mobile code is unchanged, so Flutter was not run.
- Not verified on a deployed environment or against real Postgres.
