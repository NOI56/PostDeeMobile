# Mobile and CI hardening: security Batch 6

Baseline: latest verified `origin/main` at
`a4efd650d7a74b26fc81e11ccb8bf59d2eeaa79a` (2026-10-24), ahead/behind 0/0.
Implementation branch: `claude/security-batch6-mobile-ci`, in its own clean
worktree. Only audit run-2 Batch 6 is in scope; no API change.

## Reproduction before implementation

Twelve Flutter cases failed against the baseline on 2026-10-24:

- Ten were behavioral assertions:
  - The Android manifest lacks `allowBackup="false"` and data extraction
    rules.
  - The manifest still declares `postdee://billing`.
  - `build_ios.yml` has no `API_BASE_URL` define.
  - Neither workflow has `permissions: contents: read`.
  - Actions use tags such as `actions/checkout@v4`.
  - No checkout sets `persist-credentials: false`.
  - `ci.yml` does not verify `apk_source_ref`.
- Two failed to compile because the hooks did not exist yet:
  `PostDeeApiClient(releaseMode:, enableFirebaseAuth:)` and
  `buildClipFrameArguments`.

## Change boundaries

- **Android:**
  - `android:allowBackup="false"` plus `res/xml/data_extraction_rules.xml`,
    which excludes every domain from both `<cloud-backup>` and
    `<device-transfer>`. Android 12+ ignores `allowBackup` for device
    transfer.
  - None of the 19 plugin manifests declares backup attributes, so the
    manifest merge has no conflict to resolve.
  - The unused `postdee://billing` intent filter on `MainActivity` is
    removed. No Dart, Kotlin or API code handled it. The Kotlin
    `SocialConnectReturnTest` only checks URL matching and does not read the
    manifest. It was not run here.
- **iOS/release:**
  - `build_ios.yml` adds `--dart-define=API_BASE_URL=https://postdee-api.onrender.com`.
  - `AppConfig.isReleaseBuild` (`dart.vm.product`) and `PostDeeApiClient`
    refuse a non-HTTPS base URL when both release mode and Firebase auth are
    on. The request fails with `ApiException` code `INSECURE_API_BASE_URL`
    before auth headers load. Debug, profile and mock-auth builds keep
    local HTTP.
- **FFmpeg:**
  - `buildClipFrameArguments` builds the argument list, and the extractor
    calls `FFmpegKit.executeWithArguments`. A quote in a clip path can no
    longer split into extra options.
- **Workflows:**
  - Both workflows get top-level `permissions: contents: read` and
    `persist-credentials: false` on every checkout.
  - All actions are pinned by commit SHA, with the version in a comment:
    - checkout v4.4.0
    - setup-java v4.9.1
    - flutter-action v2.23.0
    - setup-node v4.4.0
    - upload-artifact v4.6.2
  - When `apk_source_ref` is set, the mobile job fetches all branches and
    fails unless `git for-each-ref --contains HEAD refs/remotes/origin`
    finds a branch of this repository. Fork pull-request refs are stored
    under `refs/remotes/pull/*` and do not pass.

## Compatibility and deployment notes

- After installing this build, Android users whose data comes from a backup
  restore or phone transfer must sign in again. Local drafts are not carried
  over either.
- `subosito/flutter-action` and other pinned actions need manual SHA bumps;
  Dependabot for GitHub Actions can automate this later.
- The iOS workflow change affects the next push to `main` touching
  `apps/mobile/**`; the IPA remains unsigned.

## Verification

- Targeted Flutter tests (25) and `flutter analyze`: passed.
- Full `flutter test`: the first local run reported no failures but exited
  early with code 127 after 2782 tests, without a summary. A second run of
  the 150 test files it had not reached passed: 2284 passed, 6 skipped,
  0 failed.
- Not verified:
  - a real Android build or the backup/transfer behavior on a device;
  - the iOS IPA build;
  - the workflows on GitHub (they run on the PR).
