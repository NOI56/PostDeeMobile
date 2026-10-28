# AGENTS.md

Working guide for Codex and AI assistants helping to develop the PostDee project.

## Project Goals

PostDee is a mobile app for online sellers, creators, and affiliate marketers in Thailand. The long-term goal is to upload a single vertical video, then post or schedule it to TikTok, YouTube Shorts, Instagram Reels, Facebook, Shopee Video, and Lazada Video from one place. The current PostPeer path targets TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Reels. The existing `FACEBOOK_REELS` value must always send PostPeer `platform: 'facebook'` with `platformSpecificData.contentType: 'reel'`, preserving `PUBLISH|PAGE_DRAFT` and optional `isAiGenerated`; there is no fallback to a Page feed video. Facebook Reel delivery and optional best-effort thumbnails still require real-account end-to-end verification before production claims. Shopee Video and Lazada Video remain future targets. Do not apply Facebook Page Video duration or width limits to Page Reels.

## Retired Features (do not revive)

The owner removed these from the product. Code, tests, and older dated sections of `ROADMAP.md`, `ARCHITECTURE.md`, `README.md`, and `API.md` may still describe them; treat them as retired, not as current features, launch TODOs, or review targets. Do not re-add an entry point, package benefit, or marketing copy for them unless the user explicitly asks to bring one back.

| Feature | Status | What still exists and why |
| --- | --- | --- |
| AI video editing / auto editing (editor, subtitle burn-in, music and sound effects, beat sync, editing minutes and top-ups) | Navigation entry removed 2026-10-05 (Store link took its place); API retired 2026-10-24 | Every `/ai-edits/*` request answers `410 AI_EDITING_RETIRED` unless the rollback switch `AI_EDITING_ENABLED=true` is set. `apps/api/src/modules/aiEdits` and `apps/mobile/lib/features/ai_editing` remain as compatibility code: Upload still uses `AiEditAudioExtractor` for AI-caption audio and the cover editor uses `ReviewVideoTimeline`, so the folder cannot simply be deleted. The `AiEditUsage` table stays so account deletion can clear historical rows. |
| Groq transcription/planning provider | Retired | Runtime configuration rejects Groq. Transcription uses ElevenLabs; captions use Gemini. |
| AI Clip Review | Removed | UI, `/clip-reviews` route, config, and provider code are gone; only false compatibility flags remain for older clients. |
| Analytics bottom-navigation tab | Removed from navigation | Analytics stays reachable from post details and publish results. |
| Home monthly views/likes cards | Removed from Home for now | Their analytics request was removed with them. |

Dated sections in the other docs are a history log. When they conflict with this table, this table wins. When a feature is retired or restored, update this table in the same change.

## How to work with this project

Before modifying code or creating files every time, follow these steps:

1. Summarize your understanding of the task from the user's prompt briefly in Thai.
2. Check related files or structures first. Do not guess from file names alone.
3. Briefly explain the plan: what will be done, where to modify, and why.
4. If there's not enough information, ask only strictly necessary questions.
5. If safe assumptions can be made, state those assumptions and proceed.
6. Modify only the directly related parts. Avoid unnecessary changes.
7. Maintain the project's original style, naming, and structure.
8. Do not delete or overwrite other parts without checking first.
9. After modifications, verify using appropriate methods such as test, build, lint, validate, or re-reading the flow.
10. If verification commands cannot be run, state clearly what has not been confirmed yet.
11. When changing product plans, package rules, API contracts, or architecture direction, also check and sync the related docs: `ROADMAP.md`, `README.md`, `API.md`, `ARCHITECTURE.md`, and any relevant files in `docs/superpowers/plans`.

## Mandatory Baseline and No-Regression Policy

These rules apply automatically to every bug fix, feature, refactor, and release task. The user does not need to repeat them.

Before changing code:

1. Identify the canonical integration branch, normally `main`, and verify the current branch, worktree, merge base, and ahead/behind state. If remote freshness cannot be verified, say so explicitly.
2. Do not implement on a stale branch when it would omit systems already present on `main`. Create a clean branch/worktree from the latest verified `main` and port only the intended changes. Never merge or copy an entire stale branch over newer code.
3. Preserve all uncommitted work. If the current worktree is dirty, do not reset, overwrite, or silently include unrelated changes.
4. Inspect the affected user flows, tests, feature flags, environment configuration, API contracts, database dependencies, and related documentation. Record which existing capabilities must remain working.

While changing code:

5. Add or update regression tests first, then make the smallest related patch. Do not replace a complete file with a version from an older branch.
6. Resolve merge conflicts by understanding and preserving the behavior from both sides. Never choose one side wholesale merely to make the conflict disappear.
7. For schema, API, configuration, entitlement, or external-service changes, keep backward compatibility and document the required migration/deployment order.

Before declaring the task complete:

8. Run targeted tests and the relevant full test, build, lint, type-check, and schema validation suites. A targeted test alone is not sufficient for a cross-cutting change.
9. Compare the final diff with the verified baseline. Check for unexpected deleted files, large unrelated rewrites, missing imports/routes/assets, changed feature flags, and lost capability wiring.
10. Build and smoke-test the exact branch and environment intended for delivery. Verify the app package, API base URL, Firebase project, feature flags, account/entitlement state, and database migration state so an environment mismatch is not mistaken for a missing feature.
11. Treat any unexplained regression, unexpected deletion, or unverified critical flow as incomplete work. Stop and report it instead of handing off or deploying.
12. Summarize the baseline used, capabilities preserved, tests run, environment tested, migrations required, residual risks, and whether anything was not verified. Do not merge, push, or deploy without the user's authorization.

## Language and Explanations

- Explain simply for the user to understand, as the user might not have a coding background.
- Use Thai as the primary language.
- Do not explain theories unnecessarily long. Focus on actual actions and impacts.
- If there are risks to data, security, or existing systems, inform the user before proceeding.

## Main Structure

```text
apps/
  mobile/  Flutter mobile app scaffold
  api/     Express + TypeScript + Prisma backend scaffold
```

## File Modification Rules

- Use `apply_patch` for manual file modifications or creation.
- Use `rg` or `rg --files` first when searching for files or text.
- Do not use destructive commands like `git reset --hard`, `git checkout --`, or recursive delete unless explicitly instructed by the user.
- This project might not be a git repo yet, so do not rely solely on `git diff` to verify work.
- If you find files that already have changes, assume they might be the user's work and do not revert them yourself.

## Backend

Location: `apps/api`

Current Stack:

- Node.js
- Express
- TypeScript
- Prisma
- PostgreSQL schema
- Redis + BullMQ queue adapters
- Mock, Cloudflare R2, and legacy S3 video storage adapters
- Off/mock/OpenAI support-chat helper (Dot), off by default and switched on by an owner in the admin console
- Mock and Gemini caption adapters, ElevenLabs transcription, and legacy OpenAI adapters; Groq is intentionally rejected by current runtime configuration. Gemini edit-planning adapters belong to retired AI editing and are built only when `AI_EDITING_ENABLED=true`
- Mock/Firebase auth plus Firebase Admin push adapter
- Memory/Prisma stores, PostPeer publisher, and RevenueCat billing adapters

Main verification commands:

```powershell
cd apps/api
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npm.cmd run prisma:validate
```

To verify Prisma helper files:

```powershell
cd apps/api
npx.cmd tsc --noEmit --target ES2022 --module NodeNext --moduleResolution NodeNext --esModuleInterop --skipLibCheck prisma\seed.ts prisma.config.ts
```

## Mobile

Location: `apps/mobile`

Current Stack:

- Flutter mobile app with light/dark themes (light is the default)
- Bottom navigation: Home, Calendar, Create post, Store link, and Account
- Full-screen create-post flow with AI captions and saved caption templates,
  plus publishing, notifications, billing, and analytics reached from post
  details and publish results
- AI video editing is retired; see Retired Features above

Note: In the current environment, Flutter might not be in `PATH` yet. Do not claim `flutter analyze` or `flutter test` passed if they haven't been actually run.

Commands when Flutter is ready:

```powershell
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

## Guidelines for Adding Features

- Start with tests first for new behaviors or bug fixes.
- Implement the smallest possible code that makes the tests pass.
- Do not add real integration with Stripe, OpenAI, S3, Firebase, or social platforms without credentials and a security plan.
- For mock adapters, state clearly that it is a scaffold, not production.
- For user-related routes, always be careful with user scope.

## Summary Upon Completion

Every time a task is finished, summarize in Thai:

- The cause of the problem or reason for the action
- What was modified
- Which files were changed
- What has been verified
- Are there any remaining risks or next steps to take
