# Mobile motion smoothness audit

สถานะ: LOCAL AUDIT COMPLETE — final full suite 2,058/2,058 and analysis passed;
exact Staging x64 4016/8016 build/install and safe native navigation/lifecycle
checks passed with retained data. Physical-device profile-mode 60/120 FPS and
populated-content performance remain unverified; debug samples do not prove a
speedup. No new commit/push/deploy or main merge. The completed
bottom-navigation 4015/8015 receipt is separate history and is preserved in
`2026-10-12-bottom-nav-ui-motion.md`.

## Request, scope and verified baseline

ผู้ใช้ขอให้เช็กทุกหน้าว่าลูกเล่นที่เพิ่มไว้ลื่นแล้วหรือยัง ตรวจทั้งการกด/สลับหน้า
การขัดจังหวะระหว่างเคลื่อนไหว การพักแอป โหมดลดการเคลื่อนไหว การปิด ticker
และการถอดหน้าจอ พร้อมแก้ปัญหาที่มีหลักฐานจาก regression tests

Root verified a fresh remote fetch before the audit. Working checkout:
`C:\Users\stopp\.codex\worktrees\audit-system-fixes\PostDeeMobile`, branch
`codex/audit-system-fixes`, HEAD
`0e8d797bf95a7b07de8c34eed7de22e0092f66a3`; origin/main and merge-base
`c4e52201a58b556f5f47529027549a2fc16af84c`, 27 ahead/0 behind. Remote feature
matches HEAD. Preserve the completed but uncommitted bottom-navigation work and
three preexisting Windows generated-plugin changes; no reset or unrelated edit.
Canonical `D:\PostDeeMobile` remains outside the feature edits.

Installed 4015/8015 before this audit contains the completed dock feature, not
the new audit fixes. Its prior 126-lib manifest is
`27EB7DE65D9E7D3E0E04088354EB0E53C764CD5311A4CEDCA081E8296DBB820D`.
Existing server `904a3f89c3601a1fac28eedfaf8781434b19bd49` is the earlier
Shop/Account release; its Render/CI receipts do not verify these new changes.

## Findings and smallest fixes

| Area | Finding/action | Preserved behavior |
| --- | --- | --- |
| Shared press feedback | Muted/disabled/background presses could retain partial scale or replay; explicitly settle to 1, clear the held pointer, initialize/dispose the controller safely and cache the static child. | Native callback, semantics and fixed hit region; 110/160 ms scale remains finite. |
| Shared loading skeleton | Add initial lifecycle snapshot/background guard and stop/reset the sweep while blocked. | The loading state continues to reflect the existing request; no fabricated content. |
| Home hero | Replace outgoing AnimatedSwitcher content with only the current hero; settle its finite fade when interrupted. | Remove stale draft actions/semantics immediately while keeping owner/request, drafts and current callbacks. |
| Home thumbnail | Release ready or initializing decoder in background and reject late old-controller completions. | Existing cover/frame preference, tab visibility and generation guards; still never autoplay. |
| Calendar | Explicitly settle the current day fade and day/filter selection decoration under inactive/reduced/ticker/background guards. | Current-only post controls, selection/date handoff, visible polling and all scheduling/package rules. |
| Composer | Settle interrupted 160 ms color feedback, guard result transitions and video-loading feedback. Existing guarded 180 ms step entrances were audited and retained. | Four steps, caption/AI/manual-edit/save ownership and truthful publishing outcomes remain. |
| Shop/public-page preview in app | BioMotionSurface re-started 500 ms entrance on dependency refresh/resume and unrelated effects changes; start only initially or after explicit false→true entrance enable, settle to 1 when blocked, and resume ambient only when requested. | Same effects/signatures/renderers, media/fonts, all 100 templates and existing autosave/explicit publication contracts. |
| Shop manager and Account | Existing finite 220 ms entrances and passive press wrappers have lifecycle/reduced/ticker guards; Account setting/delete overlays follow the origin ticker and dispose listeners. | Native controls, owner-scoped state, settings, billing, confirmation and account callbacks. |
| Bottom navigation | Existing 8015 halo/icon/dot and press guard cases remain part of the final combined regression suite. | Five menu positions, center Create post route and previous-tab/owner state. |

The template chooser still mounts only its current 20 candidates; samples use
`staticPreview: true`, disabled tickers and repaint boundaries. Requested ambient
effects on the full preview remain available. The whole preview builder still
rebuilds per ambient frame; this is a potential profiling target, not a proven
cause of jank. Do not introduce a renderer/cache refactor without stronger data.

## Data, API and native verification boundary

No business API, quota/price/package/schedule rule, persistence trigger, provider,
configuration, dependency, backend or schema change; no migration is required.
Preserve API owner/request scope, all local drafts, media/link data, subscription
and connection refreshes, AI/manual-edit guards and real result/retry behavior.
Keep Staging API/Firebase/auth/badge configuration and disabled social publishing
with the memory queue unchanged.

Native testing uses the retained account and read/navigation/scroll/open/close
only. Do not Save, Apply a theme, purchase, call AI/OAuth, publish/unpublish,
delete, change settings or sign out. Positive caption/results/video/loading and
mutation outcomes use controlled fixtures; do not represent those as native
business success. The retained account has no posts, so real native populated
post/video states need separate authorized data later.

## Tests-first receipts

| Suite | Before runtime | After runtime | Evidence |
| --- | --- | --- | --- |
| Shared primitives | 11 passed / 13 failed, exit1 | 24/24 passed, exit0 | `D:\Temp\postdee-motion-audit-shared-{red,green}-20261012.log` |
| Composer/video/results, 18 new cases | 0 passed / 18 failed, exit1 | Combined relevant suite 50/50 passed, exit0 | `D:\Temp\postdee-motion-audit-composer-{red,green}-20261012.log` |
| Watermark fixture follow-up | Existing selected-video case 0 passed / 1 failed, exit1 | Combined 4-file composer/watermark suite 52/52 passed, 9 s, exit0 | `D:\Temp\postdee-motion-audit-composer-watermark-{red,green}-20261012.log` |
| Home/Calendar, 24 new cases | Final RED 4 passed / 20 failed, exit1 | Frozen relevant suite 112/112 passed, exit0 | `D:\Temp\postdee-motion-audit-home-calendar-{red,green}-20261012.log` |
| BioMotionSurface, 18 new cases | Final RED 5 passed / 13 failed, exit1 | New suite 18/18; combined 6-file preview/theme/UI suite 176/176, exit0 | `D:\Temp\postdee-motion-audit-preview-{red,green}-20261012.log` |

The final preview RED corrects initial MaterialApp fixture frame settling; runtime
was still unchanged when the 13 product regressions were demonstrated. Tests cover
initial/explicit entrance enable, equal-valued effects, unrelated-effect changes,
interruptions/resume with/without ambient, paused creation and safe disposal.
The 176-case suite also preserves all 100 templates at 320 px with large text,
existing preview/new-theme behavior and manager/category/drag data guards.

The watermark test now holds the existing create-post fixture with a Completer:
verify posting before completion, complete the result, verify done afterward and
verify the outgoing posting controls are absent. It no longer relies on a
finished posting view being retained by AnimatedSwitcher. All watermark bytes,
upload/create calls, temporary cleanup and draft-delete assertions are retained;
no production business behavior changed for this fixture correction.

Final-source verification and exact-build receipts:

- First full Flutter run: **2,057 passed / 1 failed, 2 m 18 s**. The watermark
  fixture at `uploader_watermark_flow_test.dart:425` expects an outgoing posting view
  after fast completion. The deterministic fixture correction above passes its
  targeted suite. Final combined rerun: **2,058/2,058 passed, 2 m 08 s**, exit0,
  `D:\Temp\postdee-motion-audit-full-final-20261012.log`.
- First `flutter analyze` reported an unnecessary null assertion at
  `uploader_screen.dart:4222`; the assertion is removed. Final analysis:
  **No issues, 8.6 s**, exit0,
  `D:\Temp\postdee-motion-audit-analyze-final-20261012.log`.
- Final intended-file/diff/no-deletion comparison passes. No unexpected deleted
  files or API/configuration/dependency/backend change. The preexisting Windows
  generated-plugin changes remain excluded; previous dock work remains preserved.
  Root's fresh remote fetch at **19:24 GMT+7 after QA** confirms the unchanged
  HEAD/origin-main/merge-base above and **27 ahead/0 behind**. Deleted files: **0**;
  protected API source/pubspec/Android/tool/configuration diff: **0**.
- First frozen 126-lib source manifest:
  `AC47826C2ABD4DFDD83671E71E96B36B473491654377F0D1718EAB0FF5DA2908`.
  This is the first-run history before the analyzer correction. Latest frozen
  126-lib manifest:
  `25C2A34C47F07C1B38F5B407C6948594BF6252C43E9949024E102547A92545F8`.
  This manifest is identical before and after build: **126 files, 0 changed**.
- Exact Staging helper debug x64 build-number4016/versionCode8016 succeeded,
  Gradle **25.2 s**, `D:\Temp\postdee-motion-audit-build-8016-20261012.log`.
  APK `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk` SHA256:
  `E8752265AE390DABC329917B5C118B060A82823C5BA5F7024770EE980B7ACE89`.
  Package `com.postdee.postdee_mobile.staging`, versionName`0.1.0-staging`,
  SDK24/36, x86_64 only; unchanged signer SHA256:
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  Staging API/FirebaseAuthtrue/localmockfalse/Staging badge are verified;
  Firebase debug project `project-798caf7e-85b8-45e3-af7` remains unchanged.
  The helper validates the canonical ignored public RevenueCat TestStore overlay;
  its key is hidden and unchanged, with no credential copied or config changed.
- `adb install -r` succeeded without downgrade/data clear. Installed8016,
  lastUpdateTime`2026-10-12 12:18:01` device UTC (**19:18:01 GMT+7**);
  firstInstallTime`2026-10-05 06:30:36` remains unchanged. Retained login:
  Home/Account Free0/3, connections0/4, no posts, original noikub2-links shop.
- Final native 8016 and measured-frame receipts are below. Recent PID17571 log
  has **0 critical hits / 140 lines** at **19:22:55 GMT+7**.

## Baseline native and backend availability receipts

Before installing the new audit source, read-only native checks on installed
**8015** cover Home; Calendar day/month; Shop/review/full-preview open/close;
Account/edit-profile open/back, appearance-settings sheet open/close and package
view/back; and an empty composer open/close. This is existing-build navigation
and presentation evidence, not post-fix 8016 verification. No Save, purchase, AI,
publishing, OAuth or data modification was performed.

The unchanged backend returned `/health` HTTP200 at **19:10:15 GMT+7** and `/ready`
HTTP200 at **19:10:16 GMT+7**, with database/queue healthy. This establishes
availability only, not new source deployment or a migration run. The external
Staging source remains the prior `904a3f8` release; 8016 build/install/final native
checks are recorded separately below.

## Final retained-data native checks (8016)

Read-only checks passed on the exact installed audit build:

- Home warm/scroll; Calendar week→month/day15/TikTok filter shows the current
  selected day15 content only.
- Shop manager→review→full-preview modal; use the native Home gesture to
  background the app, then open PostDee through its native icon. The same preview
  stays open on resume and closes correctly; no late navigation occurs.
- Account open/scroll; center Create post opens one empty composer, close returns
  to Account, then Home. The retained Free0/3, connections0/4, no-post state and
  noikub's two original links remain unchanged.
- No Save, theme Apply, purchase, AI, OAuth, post/external publication or settings
  change. Native populated videos/results and real AI/publication were not
  executed; those states and business assertions use controlled fixtures.

Raw final native screenshot outside the repository:
`C:/Users/stopp/.codex/visualizations/2026/10/12/01a12dc1-f51c-7ec2-9a95-f89a5069c32c/mobile-motion-final-8016.jpg`.

## Measured baseline and limits

Root collected real `Flutter.Frame` extension events from the installed **debug
x64 Android emulator 8015 before audit fixes**, through read-only VM monitoring.
Raw diagnostic artifact outside the repository:
`C:/Users/stopp/.codex/visualizations/2026/10/12/01a12dc1-f51c-7ec2-9a95-f89a5069c32c/mobile-motion-baseline-8015.json`.
Its summary totals **431 frame events**; **32 build** and **136 raster** samples
exceed 16.67 ms, with possible overlap between the two counts.

| Observation label | Frames | Build P95 ms | Raster P95 ms |
| --- | ---: | ---: | ---: |
| idle | 1 | 2.376 | 8.454 |
| home-warm | 185 | 14.554 | 23.209 |
| home-scroll | 25 | 8.369 | 21.656 |
| calendar-open | 29 | 23.517 | 19.619 |
| calendar-month | 25 | 13.997 | 21.640 |
| calendar-day | 21 | 17.723 | 38.693 |
| shop-open | 23 | 27.123 | 19.932 |
| shop-preview | 13 | 14.483 | 19.759 |
| shop-full-preview | 18 | 17.677 | 21.054 |
| shop-preview-close | 15 | 26.154 | 23.712 |
| account-open | 76 | 18.620 | 24.289 |

Labels describe observation windows, not exact per-gesture attribution: VM events
can arrive in batches. These are debug/JIT/emulator samples with small and uneven
windows, including warm-up and data/render work. They are not comparable physical
profile-mode benchmarks and do not certify 60/120 FPS or prove a specific widget
caused a slow frame. Unit/widget tests prove guard/flow correctness; retained-data
native QA and final debug diagnostics provide separate evidence. A physical
profile-mode benchmark with representative populated content is still needed to
make a production smoothness claim.

## Final diagnostic frame sample (8016)

Root collected **345 real Flutter.Frame events** from the installed debug x64
Android emulator after the fixes, with no concurrent Flutter test/build.
**41 build** and **87 raster** samples exceed 16.67 ms, with possible overlap;
aggregate Build P95 is **38.499 ms**, Raster P95 **28.116 ms**. Raw artifact:
`C:/Users/stopp/.codex/visualizations/2026/10/12/01a12dc1-f51c-7ec2-9a95-f89a5069c32c/mobile-motion-final-8016.json`.

| Observation label | Frames | Build P95 ms | Raster P95 ms |
| --- | ---: | ---: | ---: |
| home-scroll | 19 | 22.075 | 62.986 |
| calendar-open | 52 | 18.643 | 24.944 |
| calendar-month | 23 | 11.781 | 18.895 |
| calendar-day | 28 | 13.185 | 18.289 |
| calendar-filter | 27 | 11.877 | 21.255 |
| shop-open | 9 | 165.556 | 32.271 |
| shop-preview | 15 | 27.658 | 24.798 |
| shop-full-preview | 18 | 27.660 | 21.555 |
| preview-background-gesture | 1 | 252.064 | 8.816 |
| preview-resume | 3 | 35.712 | 73.729 |
| preview-close | 9 | 9.321 | 19.785 |
| account-open | 42 | 11.542 | 19.685 |
| composer-open | 11 | 38.845 | 28.116 |
| composer-close | 44 | 16.407 | 19.367 |
| account-scroll | 24 | 8.511 | 23.406 |
| home-return | 20 | 19.493 | 26.939 |

The VM collector is closed and its exact forwarding rule removed. Do not compare
the two runs as a controlled speed benchmark: label windows/content/event batches,
JIT warm-up, cold-tab/render work and device conditions differ. They do not prove
a speedup or certify universal 60/120 FPS. The existing Staging helper does not
allow a profile build; it was not bypassed. Physical profile-mode measurement
with representative populated content remains the performance recommendation;
whole-preview per-frame builder cost remains an unproven optimization target.
ADB inventory is **one emulator / zero physical devices**, so physical smoothness
was not measured in this audit.

## Changed-file inventory

Audit runtime (nine files):
`apps/mobile/lib/features/shared/postdee_press_feedback.dart`,
`apps/mobile/lib/features/shared/postdee_skeleton.dart`,
`apps/mobile/lib/features/home/home_activity_section.dart`,
`apps/mobile/lib/features/home/home_screen.dart`,
`apps/mobile/lib/features/calendar/calendar_screen.dart`,
`apps/mobile/lib/features/uploader/uploader_screen.dart`,
`apps/mobile/lib/features/uploader/publish_flow_screen.dart`,
`apps/mobile/lib/features/uploader/post_video_preview_screen.dart`, and
`apps/mobile/lib/features/link_in_bio/link_in_bio_motion.dart`.

Audit tests (nine files): `home_motion_primitives_test.dart`,
`home_activity_section_test.dart`, `home_screen_test.dart`,
`calendar_motion_test.dart`, `uploader_interaction_feedback_test.dart`,
`publish_flow_screen_test.dart`, `post_video_preview_screen_test.dart`,
`uploader_watermark_flow_test.dart`, and new
`link_in_bio_motion_surface_test.dart`, all under `apps/mobile/test/`.

Audit docs: `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`,
`apps/mobile/README.md` and this report. The prior uncommitted dock runtime/test/
plan remain preserved; their completed 8015 receipts are not replaced by this
audit. Preexisting Windows generated-plugin changes remain excluded.
