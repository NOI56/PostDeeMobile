# AI caption output language — 2026-11-04

Status: isolated candidate; no merge, deployment or device update.

## Request and baseline

The owner requested an output-language choice on the AI caption screen, first
checking the Gemini model and the evidence for audio language support.

GitHub `main` was verified with `git ls-remote` as
`16fe77425e268fd0929f729d4be579c354417dc2`. Branch
`codex/caption-output-language` starts there in a separate checkout. The existing
`D:\PostDeeMobile` checkout has a different branch and unrelated uncommitted work;
none of those edits are included. Open GitHub PR/issue lists were empty at the
initial check. Codex desktop task/worktree metadata calls did not return, so
local Git worktree reads and GitHub CLI reads were used for the initial baseline
and task checks. The connected GitHub tools were subsequently available and the
open-PR list was checked again.

## Model and language evidence

- `apps/api/src/config/env.ts`, `.env.example`, `render.yaml` and
  `render.staging.yaml` configure `gemini-2.5-flash-lite` for captions. This is
  source/configuration evidence, not a fresh inspection of hosted runtime values.
- Mobile extracts audio for the clip-caption request. Starter uses audio; Pro
  can also send still frames. The Gemini provider calls `generateContent` in
  evidence, writing and grounding-audit passes. The source language is detected
  from evidence. ElevenLabs belongs to the legacy transcription fallback and
  retired editing paths, not the primary Gemini caption-audio pass.
- Google's [exact model card](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite)
  documents audio input and text output. Its [audio understanding guide](https://ai.google.dev/gemini-api/docs/audio)
  covers transcription, summarization and translation but publishes no fixed
  spoken-language list/count for this path. Live API/TTS language counts cannot
  be substituted. No per-language accuracy claim is made.
- The [Firebase general-use language documentation](https://firebase.google.com/docs/ai-logic/models#supported-languages)
  describes understanding/responding in over 100 languages with text examples;
  that is not a certified audio-language count for this integration.

## Contract and behavior

Add optional `captionLanguage` with `auto` plus `th`, `en`, `zh`, `ja`, `ko`,
`vi`, `id`, `ms`, `lo`, `km`, `my`, `es`, `fr`, `de`, `pt`, `ar`, `hi`.
These seventeen explicit options are product output choices. Omission/auto
preserve the previous speech-first decision. Explicit choice takes precedence
over source speech and writing-style examples while preserving names, facts,
negation and uncertainty. Source transcript/detected speech remain independent.
The preference covers all caption/metadata/platform fields and is included in
the audit. Wrong-language metadata must not be accepted as a paid success.

Explicit selections also receive an obvious script-mismatch check for each
output family. Bounded source-brand labels can keep their original spelling.
This is not language identification: languages sharing Latin or Han scripts
still depend on the model's audit, and real clip quality must be evaluated
separately. A detected mismatch uses the existing failed-generation refund path.

Mobile provides localized Thai/English controls with native language names,
stores the preference with drafts, and guards busy/obsolete generation state.
Existing manual captions, previews, style learning, platform settings, quota and
fallback handling remain intact.

No server persistence or schema migration. API rollout must precede Mobile
because an older API can ignore an unrecognized output preference. No merge,
deployment, social publication or existing-device installation is included.

## Validation

Completed local checks:

- API full suite: `npm.cmd run test -- --maxWorkers=2` — 205 files passed,
  3,825 tests passed; 15 files / 80 tests skipped (including opt-in database
  fixtures). No persistence or schema behavior changed; real-PostgreSQL suites
  were not enabled.
- `npm.cmd run typecheck`, `npm.cmd run build`, `prisma:generate`,
  `prisma:validate`, and the dedicated Prisma seed/config TypeScript check passed.
  The database URL was only a local fixture value for validation; no hosted
  database was contacted. Local Node is 24.11.0, whereas the repository pins
  22.23.3; GitHub CI uses Node 22.
- Flutter SDK from the root checkout: 3.44.1 / Dart 3.12.1. Offline package
  resolution used the existing package cache. `flutter analyze --no-pub` passed
  and `flutter build web --debug --no-pub` compiled the complete candidate.
- Focused Mobile suites passed 95 existing regression cases and 12 new language
  cases. Four widget screenshots at 360dp cover Thai/English and light/dark;
  the new control/helper fit without overflow. Those captures use a test harness,
  not an installed app; pre-existing top-action glyph placeholders in that
  harness are outside the changed panel.
- Full Mobile suite: `flutter test --no-pub --concurrency=2` — 5,221 tests
  passed, 10 skipped, completed in 10m32s. App smoke tests and the existing
  uploader/publishing/draft regressions ran in this suite.
- Independent code review checked the source/output distinction, draft/account
  state, stale results, platform captions and language mismatch/refund behavior.
- One repeated full API run hit the existing `app.test.ts:58` support-chat
  ordering assertion (3,824 passed / 1 failed / 80 skipped); the isolated
  `app.test.ts` rerun passed all 18. Independent reproduction showed that equal
  millisecond message times are sorted by random UUID, so the final array item
  can be MEMBER even after the BOT job drained. The support files/test are
  unchanged from `origin/main`; this work does not alter that unrelated behavior.

Provider tests use controlled responses; real Gemini multilingual audio and
translation quality, Android/iOS package builds, device installation and hosted
runtime configuration remain unverified.
