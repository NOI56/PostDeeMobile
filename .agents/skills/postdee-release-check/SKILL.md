---
name: postdee-release-check
description: Produce an evidence-based go/no-go report for a PostDee release candidate before the Production API deploy, a Google Play upload, or an App Store build. Use when the owner asks whether PostDee is ready to launch or release; it checks and reports, it does not deploy or upload.
---

# PostDee release check

The output is a report, not a release. Resuming or deploying Production, uploading to a store, changing Production environment variables, or dropping `[skip render]` from a `main` commit each need the owner's explicit approval for that action.

Start by fixing the candidate: one exact commit SHA on `main`, and the targets (Production API, Android Play track, iOS). Every check below is about that SHA. Evidence from an older SHA, an old CI run, or a dated doc entry does not count; record it only as history.

## Gates

### 1. Source and CI

- The SHA is on `origin/main`, and `.github/workflows/ci.yml` (jobs "Backend API" and "Flutter Mobile") passed for that exact SHA. For Mobile changes, `build_ios.yml` also passed.
- Local full suites per `AGENTS.md` on the same SHA, plus `npm.cmd run typecheck`. Opt-in database tests need their own run (see `postdee-api-schema-change`).

### 2. API configuration

- `apps/api/src/config/env.ts` refuses to boot in production with mock `AUTH_PROVIDER`, `BILLING_PROVIDER`, `SOCIAL_PUBLISHER`, `VIDEO_STORAGE`, or `SUPPORT_BOT_PROVIDER`, or with shared `POSTPEER_*_ACCOUNT_ID`. Confirm no change weakened these guards.
- `render.yaml` (Production) and `render.staging.yaml` are pinned by `src/config/renderConfig.test.ts` and `renderStagingConfig.test.ts`; CI config by `githubCiConfig.test.ts`. A Blueprint change must update those tests in the same commit.
- Production runs one instance because `PUBLISH_QUEUE=memory` uses an in-process scheduler. More instances would publish the same post twice.
- Hidden values (`sync: false`) live only in the Render Dashboard. Confirm they are set for the right environment without printing them.
- Read the Status table in `docs/GO_LIVE.md` for switches that must stay off until their own acceptance (for example account-deletion Firebase cleanup). A release does not flip them.

### 3. Database and compatibility

- List migrations added since the last Production deploy. Render's `preDeployCommand` runs `prisma migrate deploy` before the new code starts; a failed migration blocks the deploy.
- Installed Mobile builds keep calling the API. The API must accept the requests of every Mobile build still in use; deploy API before Mobile. Note any Mobile build that the new API will refuse (for example `426` upgrade responses).

### 4. Staging acceptance

- The same SHA is Live on Staging (see `postdee-staging-deploy`) and the checklist in `docs/STAGING.md` → "Smoke test ก่อนอนุญาตให้ deploy Production" has current-candidate evidence for every item touched by this release. Unchecked items are blockers or explicit owner-accepted risks, never silent passes.
- Real publishing claims need `postdee-publish-e2e` evidence. Facebook Page Reels delivery is not yet proven on a real account.

### 5. Android release build

- Built with `apps/mobile/tool/postdee-production.ps1 -Command build-appbundle`, which reads the ignored `production.local.json` and rejects Test Store (`test_`) and placeholder RevenueCat keys; Android requires `REVENUECAT_ANDROID_API_KEY`. Output: `apps/mobile/build/app/outputs/bundle/release/app-release.aab`.
- Signed with the release key from the ignored `android/key.properties` (see `docs/ANDROID_SIGNING_KEYS.md`). Never print or commit signing material.
- Release package is `com.postdee.postdee_mobile` (Debug/Staging is `.staging`). Play needs a higher version code than the last uploaded bundle; check the build number in `apps/mobile/pubspec.yaml` `version` before building.
- Smoke-test the release build against Production config only with the owner's approval.

### 6. iOS build

- `build_ios.yml` produces an unsigned IPA on `main` pushes that touch `apps/mobile/**`.
- Minimum iOS 15.0 must match in `apps/mobile/ios/Podfile` (`platform :ios`) and all three `IPHONEOS_DEPLOYMENT_TARGET` entries in `Runner.xcodeproj/project.pbxproj`.
- All `firebase_*` plugins must resolve to the same Firebase iOS SDK; mismatched FlutterFire versions break Swift Package resolution.

### 7. Store listing and policy

- `docs/PLAY_STORE_LISTING.md` separates claims allowed after final AAB checks from integrations that must not be advertised yet. Retired features (`AGENTS.md`) never appear in listing text or screenshots.
- Data safety and `docs/PRIVACY_POLICY.md` must name every processor the release actually sends data to, and Android permissions must match the manifest.

### 8. Production service state

Read the Production service's current state with the Render tools: suspended or running, auto-deploy setting, deployed commit. Do not rely on a remembered state. The Production service auto-deploys from `main`, which is why merges carry `[skip render]`.

## Report

| Gate | Result | Evidence | Level |
| --- | --- | --- | --- |
| e.g. CI | pass / fail / not run / blocked | SHA, run link, command output | local / CI / Staging / device / Production |

End with a verdict, **Ready** or **Not ready**, and the blockers in priority order. Anything not run is a gap to name, not a pass.
