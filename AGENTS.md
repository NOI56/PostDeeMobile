# AGENTS.md

Working guide for Codex and AI assistants helping to develop the PostDee project.

## Project Goals

PostDee is a mobile app for online sellers, creators, and affiliate marketers in Thailand. The long-term goal is to upload a single vertical video, then post or schedule it to TikTok, YouTube Shorts, Instagram Reels, Facebook, Shopee Video, and Lazada Video from one place. The current PostPeer production path covers TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Video. Do not advertise Facebook Reels, Shopee Video, or Lazada Video as working destinations until their provider mappings and end-to-end tests pass.

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
- Mock and Gemini planning/caption adapters, ElevenLabs transcription, and legacy OpenAI adapters; Groq is intentionally rejected by current runtime configuration
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
- Home, uploader, AI editing/review, calendar, caption assistant, templates,
  analytics, profile, billing, and publishing flows

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
