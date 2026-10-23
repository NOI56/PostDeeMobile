# AI editing retirement and caption media limits: security Batch 3

Baseline: latest verified `origin/main` at
`a4efd650d7a74b26fc81e11ccb8bf59d2eeaa79a` (2026-10-24), ahead/behind 0/0.
Implementation branch: `claude/security-batch3-ai-retirement`, in its own clean
worktree. Only audit run-2 Batch 3 is in scope.

## Why retirement instead of metering fixes

The audit found that `/ai-edits/*` reserved, refunded or skipped editing
minutes in ways that let a caller spend ElevenLabs and Gemini work without
paying for it. The 2026-10-05 product change already removed the mobile entry
point and every editing-minute offer, but the API still registered the routes,
so any authenticated caller could keep invoking the providers directly.
Fixing the metering would harden a feature nobody can buy. Retiring the
server routes removes the cost exposure entirely.

The real-clip caption endpoint stays in the product. It downloads the clip and
up to three frames into memory on the single shared Render instance, so it got
the media limits from the same audit batch.

## Reproduction before implementation

Ten regression cases failed against the baseline on 2026-10-24 with mock auth,
memory stores and injected fakes (14 cases in the three new files, 4 passed):

| Test | Expected | Before-fix result |
| --- | --- | --- |
| `/ai-edits/transcribe`, `/ai-edits/prepare` by default | 410, no provider call | 502 after reaching the provider fakes |
| `/ai-edits/plan` by default | 410 | 400 from the live route |
| `/ai-edits/audio/cleanup`, `/visual-proxy/cleanup`, `GET /quota` by default | 410 | 200 from the live route |
| Frame key `huge.mp4` | 400 before any download | 200, downloaded |
| Same frame key three times | Clip + one frame download | Four downloads |
| Second concurrent clip caption with a budget of one | 503 `AI_MEDIA_BUSY` | No 503; the second request also waited on media (test timed out) |
| Body without `Content-Length` above the limit | Stops before 10 chunks | Read all 1000 chunks |

These are local reproductions, not deployed or provider acceptance tests. No
live users, credentials or dashboards were used.

## Change boundaries

- `AI_EDITING_ENABLED` (`false` by default, strict `true`/`false`) gates
  `registerAiEditRoutes`. When off, `/ai-edits/*` answers `410
  AI_EDITING_RETIRED` and the edit-plan, sound-effect and visual-plan providers
  are not built. Setting it to `true` restores the previous contract unchanged.
- The transcription provider is still built for the legacy caption fallback
  (used only when no real-clip caption provider is configured), so
  `ELEVENLABS_API_KEY` and `TRANSCRIPTION_PROVIDER` stay referenced.
- The AI-edit usage store is still built so account deletion removes historical
  `AiEditUsage` rows. No schema change and no migration.
- `selectedFrameKeys` are deduplicated before the first three are taken and must
  end in `.jpg`, `.jpeg`, `.png` or `.webp` (`400 AI_CAPTION_FRAME_INVALID`).
- Frame downloads must be `image/*` (`415 AI_CAPTION_FRAME_INVALID`) and at most
  5 MiB. The clip keeps its 200 MiB limit.
- `readAiMediaResponseBytes` streams the body and cancels it once the running
  total passes the limit (`413 AI_MEDIA_TOO_LARGE`), so a missing or understated
  `Content-Length` no longer allows unbounded buffering.
- At most two clip-caption requests per instance hold media at once
  (`maxConcurrentAiMediaRequests`, default 2). Extra requests get `503
  AI_MEDIA_BUSY` with `Retry-After: 1` before any download or quota reservation.
- The vitest environment sets `AI_EDITING_ENABLED=true` so existing AI-edit
  route tests keep covering the legacy contract; the retirement tests build
  their config from an empty environment.

## Deployment notes

- Leave `AI_EDITING_ENABLED` unset on Production and Staging.
- App builds older than the 2026-10-05 navigation change still show AI editing
  and will now receive 410 from it. Current builds have no entry point.
- Existing editing-minute balances or top-ups are not refunded or migrated.
  The owner should confirm no paying customer still expects to use them.

## Verification

- `src/modules/storage/clipMediaFetch.test.ts` (frame `image/*` check, 5 MiB
  frame cap, clip limit unchanged) was added after the implementation, so it
  has no before-fix run; on the baseline the helper was not exported.
- `npm.cmd run test`: 156 files passed, 4 skipped; 2585 tests passed, 25 skipped.
- `npm.cmd run typecheck` and `npm.cmd run build`: passed.
- Mobile code is unchanged, so Flutter was not run.
- Not verified on a deployed environment.
