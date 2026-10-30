# Historical work reconciliation — 2026-10-30

Status: local implementation and validation passed. This record does not
claim a new main merge, push, hosted deployment or app-store publication.

## Baseline and preservation

- Canonical integration branch: `origin/main`, verified by fetch at
  `59ad8f00a39d4cf6fc16c5b467432b7c7f1cc903`, merge base equal, ahead/behind 0/0.
- Reuse the clean English delivery worktree on the new branch
  `codex/pending-work-reconcile-20261030`; do not implement on an old branch.
- Preserve all 43 historical worktrees, three local-only backup branches and
  four stashes. Whole-file differences on a stale baseline do not establish a
  missing feature. No old file or branch is copied wholesale.
- Keep current publishing, Facebook Page Reels routing, auth/owner lifecycle,
  billing, per-channel caption credits/add-ons, drafts, English UI and flags.
  AI editing, Groq and other retired features remain retired.

## Selected caption fixes

1. Recognize `503 AI_MEDIA_BUSY` as a rejection before provider work in the
   owner-operation router. Release that operation ticket so ordinary capacity
   rejection does not leave a private deletion blocker. Continue retaining
   unknown and provider-error outcomes exactly as before.
2. Apply the existing per-app two-request media budget to legacy caption
   transcription as well as Gemini. The legacy case matters when no real-clip
   provider is configured but a transcription provider is available; this is
   not a claim about the current hosted provider selection. Acquire before any
   reservation/provider await and release in `finally` on every exit.
3. Atomically reserve Gemini caption credits before downloading media. A
   preliminary quota read can race, so a rejected reservation must not fetch
   media. Preserve the existing 1–4 channel cost, add-on batch semantics,
   media-error refund and local-template fallback/refund behavior.

The changes add no schema migration, environment variable, feature flag,
provider integration, media-size limit or entitlement rule. A credit is held
while media downloads; process interruption or a failed usage-store refund can
leave it reserved under the existing best-effort refund design. This patch
does not promise reconciliation while the database is unavailable.

## Classification of historical work

| Group | Result and source evidence |
| --- | --- |
| Shop logo | Delivered via `1bf125c2`, disposal/export fix `3481f3fc`, English `32c1e0c0`; preserve newer crop normalization and route guards. |
| Composer wizard | All 19 dirty/new Dart and test files match main ancestor `11778457`; six old documentation versions are superseded. |
| Profile compositions / running dot | All 13 content blobs occur in main history, including `a764d81c`, `81f0b9ff`, `8aa84443`; removed Home metrics stay removed. |
| OAuth refresh | Current owner-bound lifecycle observer, pending-return drain and launcher-failure handling supersede the old patch; current regression tests cover early return and owner changes. |
| Analytics verify | 8/8 content files match delivered `704bae09`; current detail analytics remain, retired Home cards do not return. |
| Calendar verify | 2/2 files match `a2a63489`; current supported-platform filtering uses the newer responsive layout. |
| Notifications verify | 2/2 files match `2b3813da`; current permission-on-demand has newer owner and timeout guards. |
| Profile/auth verify | 16/16 files match `3b804823`; preserve later UID-scoped drafts and auth changes. |
| Publish verify | 8/8 files match `2d476069`; current connected destinations, progress and queued outcomes remain. |
| Brand verify | 34/38 paths equal current main; four historical blobs were delivered then updated. Duplicate icon removal in `2183cc63` is intentional. |
| Billing red-confirmation tests | Transfer test equals main; environment test is an older subset of current coverage, including later promotional-entitlement regression cases. |
| AI retirement | Main covers retired endpoints in `aiEditRetirement.test.ts`; frame/stream/admission safeguards already exist. Select only the active caption fixes above. |
| Account-delete backup `4e878afb` | Core safeguards delivered in `a00364c8`, with later persisted authorization, owner drain and profile cleanup. No missing active invariant identified. |
| Publish-draft WIP `5aa8a216` | Core idempotent publishing and local drafts delivered as `95e76dc9` and `843c2e87`, with the migration present. This is not a semantic certification of all 111 old files; retain the backup. |
| Subtitle backup | Active-word subtitles are retired. Duration is equivalent to `9f63ea9a`, OAuth refresh is superseded, and explicit Staging flags replace the old debug-mode inference. |
| Preview stashes 1/2 | Intent delivered as `fc1ddd38` with later immersive UI and English; preserve current volume/mute, owner and lifecycle guards. |

Do not port old editing-minute metering, `audioDuration.ts`, Gemini Files API
transport or the former 200 MiB Gemini envelope. Active captions deliberately
use the newer 15 MB inline clip budget/audio extraction. Aggregate clip/frame
overhead remains the documented fallback limitation from the October 27
delivery, not a new contract in this patch.

## Android launcher and remaining UX candidate

- Android launcher: implement the `-OpenOnly` and strict named-AVD intent from
  stashes 0/3 without applying the old documentation blindly. Default to
  `Pixel_8`; verify the exact AVD during selection and boot, then recheck its
  cached serial before install, force-stop and launch. An unknown, ambiguous,
  changed or missing device fails closed. `OpenOnly` requires an installed
  Staging package and performs no build, install or force-stop; it opens the
  existing APK without certifying that APK as the newest source. Preserve the
  canonical-main resolver, launcher mutex and existing UID/storage guards.
- App-first OAuth: an old native-launcher UX patch is absent from main and was
  explicitly excluded from the historical scoped delivery. Current browser
  routing and lifecycle refresh work. Preserve this separate feature candidate;
  it still needs real-provider/device acceptance before delivery claims.

## Verification

- Tests added first: three failures / 27 passes against unchanged production
  source in the two targeted files. The failures reproduce retained busy
  tickets, media download after a lost reservation, and unbounded legacy
  transcription admission.
- After the smallest patch: five caption/account test files passed, 119 tests.
- Full API suite: 188 files passed / 11 skipped; 2,964 tests passed / 67 skipped.
  The existing media-failure test now asserts that four reserved credits are
  refunded while a previous usage remains, rather than asserting no reservation
  ever occurred. The first full run exposed this obsolete ordering assertion;
  the final complete run passed after preserving its no-charge invariant.
- API build, type-check, Prisma schema validation and the documented Prisma
  seed/config helper type-check passed using the existing portable Node 22.23.3.
  A placeholder loopback database URL was used; opt-in database suites stayed
  skipped and no shared database was migrated.
- Compiled API smoke passed on isolated loopback with injected mock providers:
  health/readiness 200, busy legacy request 503 with Retry-After, next request
  admitted after completion, and retired editing 410. The smoke starts/stops
  the in-memory scheduler as the actual server startup does.
- Launcher regressions: initial 1 pass / 16 failures, then 17 passes / 5 new
  serial-reuse failures before the final guards; final 22/22 passed on Windows
  PowerShell 5.1 and PowerShell 7. Existing storage guard tests passed 64/64.
- Real `ResolveOnly` selected canonical main at `D:/PostDeeMobile` with the
  expected SDK/defines. Real `OpenOnly` passed on Pixel_8 / emulator-5554:
  version 12093, UID 10197, internal volume, installed APK hash, Flutter
  preferences and all three draft manifests were unchanged before/after.
  No install/build/force-stop, permission change or account action was used.
- Independent source review accepted caption accounting/owner boundaries and
  the launcher guards after fixing the serial-reuse case. `git diff --check`
  passed; no deleted file, schema, feature flag or runtime mobile UI change.
- Flutter runtime source is unchanged by the caption patch; no new mobile
  runtime acceptance is claimed here.
