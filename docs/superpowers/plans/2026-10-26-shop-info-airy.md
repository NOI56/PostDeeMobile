# Shop information airy layout — 2026-10-26

Status: locally verified implementation of the user's selected mockup variant 1,
installed on the test Emulator, with the main push authorized by the user.
There is no Store, Production or real-user acceptance claim. The verified baseline is
`origin/main` at `401eeed2e80e7917977be4c9aa5319559b57aed4`, with branch
`codex/shop-info-airy` initially clean and 0 ahead / 0 behind.

## Scope

Improve the information section of the existing Flutter shop-link editor in
`apps/mobile/lib/features/link_in_bio/link_in_bio_screen.dart`. Reduce competing
labels and separate photo, shop text and URL settings into readable groups.
Keep the manager, decoration gallery, advanced customization, full-screen
preview and explicit publication review unchanged.

## Layout and interactions

- Put the existing logo preview and add/change/remove photo actions before the
  text fields. Keep the current gallery, crop, upload and ownership flow.
- Put the shop name and description in a separate quiet card. Show labels above
  the inputs, mark the description optional, and keep helpful hints with the
  existing limits and validation: shop name 1–80 characters and description at
  most 280.
- Show character counters while their input has focus and reserve their space
  while unfocused, so focusing a field does not move the following content.
  Keep system text scaling, multiline input and keyboard interaction usable.
- Present URL settings in their own card with a link icon and an explicit
  `แก้ไข` / `ย่อ` action. A collapsed summary remains readable. An invalid or
  missing slug still opens the settings automatically, including when the
  existing finish validation finds an invalid value. Retain the 3–40-character
  slug rule, normalization and error messages.
- For the information section only, move the local draft-save status from the
  shared header to the footer near the existing `เสร็จสิ้น` action. Include a
  concise hint that saving the draft still requires explicit publication to
  update the live website. Keep saving, unsaved and failed-save states visible;
  the other sections retain their existing status placement and actions.

## Behavior to preserve

- Owner-scoped serialized autosave, draft signatures, pending-save handling,
  save failures and leave guards. Finishing validates, saves and returns to the
  manager; it never publishes implicitly.
- Existing field controllers and stable test keys. Keep entered text and media
  through focus changes, collapsing URL settings and validation errors.
- Actual configured API base URL, normalized slug and confirmed public URL
  behavior. Copy/open must still use only the confirmed published URL; changing
  the draft slug must not silently replace the published address.
- Logo crop confirmation/cancellation, image bytes, draft/public media
  separation and account/session guards against stale asynchronous results.
- Basic/free 2, Starter 7 and Pro 20 link limits, fresh entitlement checks,
  enabled-link publication counting and preservation of legacy over-limit
  drafts/published pages. This layout change does not revise package policy.
- Existing publication uncertainty, status refresh and unpublish behavior.

No API, schema, migration, dependency, provider or feature-flag change is
required. The user subsequently authorized pushing this UI work to main;
an API deployment is not needed for this layout-only change.
An update of the existing test Emulator may be used for local verification;
record the exact build and preserved package/data state below when performed.

## Acceptance checklist

- Add regression tests before the UI patch for group order, labels, optional
  description, focus-only counters with stable reserved space, URL expansion
  and information-only footer placement.
- Check valid finish/save/return without publication; invalid name/slug and
  failed-save retention; logo crop cancel/confirm and existing draft reload.
- Check 320px width with larger text, ordinary phone width, light/dark themes
  and keyboard-visible scrolling. Distinguish rendered fixtures or Emulator
  checks from physical-device and real-user acceptance.
- Run the relevant targeted tests, full Flutter suite, analysis and the exact
  intended app build/smoke checks. Compare the final diff with the verified
  baseline and record actual commands, results and environment separately.

## Local verification receipt

- Baseline was refreshed again after implementation: `origin/main` remains
  `401eeed2e80e7917977be4c9aa5319559b57aed4`, with HEAD at that base (0/0).
  The local diff contains only the screen, its new regression test, this plan
  and the mobile README note. No deleted files or API/schema/dependency/config
  changes were found; `git diff --check` passed.
- Files changed: `apps/mobile/lib/features/link_in_bio/link_in_bio_screen.dart`,
  `apps/mobile/test/link_in_bio_info_layout_test.dart`, `apps/mobile/README.md`
  and this record.
- Tests were added before the UI patch and failed for the missing layout.
  The final **9/9 new regression tests passed**, including 320px layouts with
  1x/2x text in light/dark themes, focus-only counters with stable space,
  autosave without publication, logo removal preserving other draft data,
  invalid-finish expansion and reopening a manually collapsed invalid URL
  after leaving and re-entering information settings.
- Final `flutter test --no-pub --reporter expanded`: **3,160 passed / 6 skipped**.
  This final run includes the invalid-URL re-entry fix and all nine new tests.
  Existing media/crop, manager, decoration, fullscreen preview, publication,
  subscription and session regressions passed in that suite.
- Final `flutter analyze --no-pub`: **No issues found**. Staging Android x64
  debug build passed using `tool/postdee-staging.ps1 -Command build-apk --no-pub
  --target-platform android-x64 --build-number 12061`. Existing third-party
  plugins still emit a future Kotlin migration warning; no dependency was
  changed for this UI task.
- Exact environment: package `com.postdee.postdee_mobile.staging`, version
  `0.1.0-staging` / **12061**, API
  `https://postdee-api-staging.onrender.com`, Firebase project
  `project-798caf7e-85b8-45e3-af7`, Firebase auth enabled and local mock auth
  disabled. The helper validated the existing ignored RevenueCat Test Store
  overlay without exposing or committing its SDK key.
- APK SHA-256:
  `FC1E3CD6AEF47F53D3D7229F68B167609F9A88FFB84DA9E39741085F9E9BA2F8`.
  Existing debug signer SHA-256:
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  The safe update preserved package UID **10197** and the internal volume,
  updating 12060 to 12061 with no uninstall or data clear.
- Native Pixel_8 Emulator smoke retained the signed-in Free account, saved
  clip draft, connected-channel count, published shop `noikub`, original logo,
  exact saved slug and **2/2** shop links. Information settings show the chosen
  logo-first layout, white field card, optional description and separate URL
  card. `แก้ไข` opens the unchanged URL; `ย่อ` collapses it; scrolling exposes
  the saved-draft status and explicit-publish hint without overlap. No shop
  text, image, published page, purchase or account state was edited during
  native smoke. The new information screen is left open.
- Local evidence logs in the user's Temp directory:
  `postdee-info-layout-nine-final-20261026.log`,
  `postdee-info-airy-mobile-full-final-20261026.log`,
  `postdee-info-airy-analyze-final-20261026.log` and
  `postdee-info-airy-mobile-apk-final-20261026.log`.

No API deployment or database migration is needed for this layout-only change.
The API, schema, package limits, flags, provider configuration and dependencies
are byte-unchanged from the baseline, so backend suites were not rerun for this
UI patch. Physical devices, iOS, app-store distribution and Production were not
tested or released. At the local verification checkpoint, the source was not
yet pushed or merged. The user then requested the main push; release review
confirmed only the four intended files against freshly verified `401eeed2`,
with the existing full-suite, analysis, build and native-smoke evidence above.
