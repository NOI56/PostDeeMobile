# Profile-link publication status dot

Status: VERIFIED FOR MAIN — full tests, analysis, status renders and Staging APK
passed; the user authorized main/push. No API deployment or device installation
is part of this delivery. The current app/form is preserved.

## Request and baseline

ผู้ใช้ต้องการจุดสีแดงเมื่อหน้าลิงก์ร้านยังไม่ได้เผยแพร่ และสีเขียวเมื่อเผยแพร่อยู่
ทั้งการ์ดลิงก์หน้าโปรไฟล์บน Home และสถานะใต้หัวข้อในหน้าลิงก์ร้าน

- Freshly fetched `main`/`origin/main` and the clean reused attached worktree
  match `e4dc01a04010cf48608c6000766d84811fbb374d`, zero ahead/behind.
- Branch: `codex/profile-publication-status-dot`, in the existing attached
  `platform-consent-preserve/PostDeeMobile` worktree. Preserve canonical main's
  pre-existing Windows generated-file changes/artifacts and the stale D: checkout.
- Preserve the Home publishing-card feedback, full-screen publishing motion,
  selective TikTok confirmations, remembered platform defaults and current API
  dependencies/configuration. No stale feature branch is merged or copied.

## Scoped changes

- A shared static 8px decorative dot and publication resolver are used by the
  Home shortcut and LinkInBio header. Adjacent text remains available to screen
  readers; narrow layouts wrap/ellipsize text without losing the dot.
- Green requires current-owner confirmed `isPublished` and a public URL. Red
  requires a confirmed unpublished profile or a confirmed missing page. Loading,
  read failure, missing URL on a published flag, uncertain mutation outcomes or
  an account/session change use gray, avoiding a false published/unpublished claim.
- Home keeps its existing loader lifecycle, owner/generation guards, refresh
  deduplication and navigation. A refresh that retains content may retain its
  last confirmed status while pending, then becomes gray if the read fails.
- LinkInBio tracks status-read failure separately from local draft errors. A
  failed refresh hides a stale green claim; successful load/publish/unpublish
  restores confirmation. Existing session/mutation guards are unchanged.
- Local draft edits, link toggles, validation and disk-save failures do not
  unpublish the live page or turn a confirmed live website red. Actual publish
  and unpublish requests, confirmation dialogs and retry semantics are unchanged.
- API/contracts, schema, dependencies, feature flags, billing, publication
  endpoints, images, local draft formats and scheduling are unchanged. `API.md`,
  root README/ROADMAP/ARCHITECTURE checked; no contract/architecture/roadmap update
  or backend deploy/migration is required. Mobile README documents the UI rule.

## Verification

- Tests first on baseline runtime: **10 passed / 20 expected failures**, 13.4
  seconds, reproducing the absent dot and new confirmation/read-failure display.
- Home cases cover confirmed green/red, missing page/URL, pending reads, retry,
  refresh failure after green and late old-owner completion, preserving loader
  counts. Link-manager cases cover publication/unpublication, initial/refresh
  failure, unknown result/recovery, account change, local draft edits/save failure,
  screen-reader status and 320px at 200% text in light/dark palettes.
- Evidence/tooling: `D:\PostDeeMobile\artifacts\profile-publication-status-dot-20261020`.
- Nine-file focused suite: **163 passed**, 46 seconds. The initial GREEN attempt
  found only two new-test semantics-handle cleanup errors; explicit disposal
  before test completion fixed them. No runtime regression was identified.
- Opt-in render fixture uses real bundled fonts, production Home/LinkInBio
  widgets, local loaders/memory drafts and no publish/unpublish calls. It captures
  green/red in light/dark and neutral pending status for both screens.
- Complete Flutter suite: **2,524 passed / five optional previews skipped**,
  209.4 seconds. Opt-in fixture explicitly passed **1/1**, 5.6 seconds, with ten
  final captures in `preview-final/`: Home/shop, green/red, light/dark and pending
  gray. The changed status regions were visually inspected. Unrelated footer
  text can use the widget-test default font; native font rendering is not claimed
  and no product font/theme was changed.
- `flutter analyze --no-pub`: **no issues**, final 7.4 seconds (9.0 seconds with
  startup). Original delivery analysis also passed, 14.0 seconds. The final
  runtime, regression tests and opt-in fixture all match the full-suite/build
  input hashes; all **653** source/snapshot inputs match before this record update.
- Staging Android x86_64 debug APK **12031** built successfully in 107.4 seconds
  using Flutter 3.44.1 / Dart 3.12.1 and the existing constrained D: snapshot/cache.
  Package `com.postdee.postdee_mobile.staging`, version `0.1.0-staging`;
  **197,049,886 bytes**, SHA-256
  `a9a6b62987c59bb95b366a4b93ded25c50a72db6309d6b9bfa8aa9ac528e6b01`.
- APK inspection confirms the expected debug signer/signature, 16KiB alignment,
  x86_64 engine, Staging API `https://postdee-api-staging.onrender.com`, Firebase
  project `project-798caf7e-85b8-45e3-af7` and existing Google client/public billing
  configuration. Existing Firebase auth and billing are enabled; mock auth and
  experimental AI hook/beat sync remain disabled. No environment changes.
- Compiled kernel includes the publication dot/resolver/read-failure handling,
  existing Home sending rail/results, selective TikTok confirmation reset,
  remembered defaults and full-screen progress. Keep verified APK12030 separately;
  preserve APK12031 under the evidence folder with `apk-verification-12031.json`.
- Independent read-only review found no blocker in the current-owner guards,
  shared classifier, read-failure isolation or preserved publishing/draft behavior.
- Final diff review: eight related files, no deletions/unrelated rewrites, API,
  config, dependency, workflow or migration changes. Only this completion record
  changes after the immutable verification manifests.
- Native installation, real publication/unpublication and native rendering/FPS
  are not part of this task and have not been performed.

## Main/push delivery

- The user explicitly authorized `main/push` after local verification. A fresh
  fetch confirms `origin/main` is still
  `e4dc01a04010cf48608c6000766d84811fbb374d`; verified feature
  `8722e1a8455faa1519d89cdd550cef642a7e3098` is one ahead and zero behind.
- Integrate the eight related files into canonical `main` by fast-forward.
  Preserve its three pre-existing generated Windows file changes and untracked
  artifacts; do not include stale checkout content.
- This documentation-only delivery commit includes `[skip render]`. No API,
  Render Blueprint, configuration, dependencies, migrations or workflows change.
  Normal push workflows remain enabled; no extra dispatch, native update or
  publication/unpublication is required for main/push.
- Runtime, regression tests and the opt-in fixture remain identical to verified
  APK12031 inputs. This completion/delivery record is the sole later source change.
- Exact pushed SHA, remote equality and workflow snapshots are saved separately
  under `D:\PostDeeMobile\artifacts\main-push-20261020` to keep source immutable.

## Files changed

- `apps/mobile/lib/features/link_in_bio/link_in_bio_publication_status.dart`
- `apps/mobile/lib/features/link_in_bio/link_in_bio_screen.dart`
- `apps/mobile/lib/features/home/home_screen.dart`
- `apps/mobile/test/home_dashboard_test.dart`
- `apps/mobile/test/link_in_bio_publish_screen_test.dart`
- `apps/mobile/test/link_in_bio_publication_preview_test.dart`
- `apps/mobile/README.md`, this record.
