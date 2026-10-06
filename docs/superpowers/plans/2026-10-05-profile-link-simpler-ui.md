# Simplify mobile profile-link UI

## Accepted scope

The user said the whole profile-link module shows too many options at once and
does not make the starting task clear. After reviewing the current UI, the user
accepted the proposed first-setup wizard and returning-profile overview with
"เริ่มได้". Preserve every customization capability and the existing explicit
draft/publication boundary; do not add automatic saving or automatic publishing.

Verified baseline: fresh origin/main
`fde4569c65a9bb4040f6681beb8149cf8921cda2`; branch
`codex/profile-link-simpler-ui` in the canonical recovery worktree. Existing
untracked artifacts and the dirty root checkout are preserved.

## Interface

- First setup: Store information -> Links -> Theme -> Review/Publish.
- Store information combines name, introduction and logo. The URL disclosure
  opens when the existing required URL is empty/invalid; no generated slug.
- Link creation starts with title and destination only in a compact sheet
  (maximum 430 px before expanding advanced options). Category, icon, font
  and individual colors remain in an optional group. A link title opens editing;
  a separate switch changes visibility. Feature/order/delete use its menu.
- Theme selection shows four visual presets and a bounded 120–150 px real preview
  that adapts to screen height to keep Additional decoration above the footer.
  Additional decoration opens a 120 px preview and four optional groups, with
  five nested text-style groups. It does not show the theme picker again.
- Review shows the real draft and the explicit publish/update action. Existing
  server profiles open a short overview with the confirmed published snapshot,
  Edit, and confirmed URL actions. Local draft edits do not replace that preview.
- Main actions stay in a footer above the keyboard and the existing capsule
  navigation. Save Draft, Refresh Status and Unpublish remain in the More menu.
- Collapsed inputs retain their values and validation; invalid hidden inputs
  reopen automatically rather than silently accepting the previous valid value.

## Visual specification and necessary differences

Two built-in Image Gen concept boards were inspected with view_image, each
1254 x 1254 with two complete mobile screens. Board 1 covers overview/store;
board 2 covers links/theme. The user-approved workflow and native code copy are
authoritative. Use existing Anuphan/Prompt fonts, green palette, 16 px gutters,
18 px corners, 24 px headings and main controls at least 52 px tall.

Retain the existing global navigation, light palette, and actual selected
profile theme/renderer. Do not implement invented decorative circles, generated
sample links as customer data, or a static image as UI. Review extends the same
preview/footer components. The required URL, loading/errors, unsaved changes,
uncertain publication and disabled controls must remain visible when relevant
even though the concept boards show the ordinary happy state.

## Compatibility and verification

The mobile UI revision changes no API, Prisma schema, dependency, package limit,
provider credential, feature flag, or external service. All packages keep one page and 20 enabled
links. Existing captions, uploading, login, calendar and billing remain intact.
The subsequent compatible backend dependency patch needed for pre-merge CI is
recorded separately below; it requires the normal backend redeploy to take effect.

Tests were added first: eight wizard regressions and nine direct decoration
regressions. The old UI failed the new tests; the new implementations pass their
respective targeted suites. Existing profile suites are adapted through real
navigation without removing their behavior assertions.

Final mobile suite: 1,124 tests passed (58 seconds); flutter analyze reports no
issues. Both new spacing regressions failed before the final patch and pass
afterward. No source/configuration changes outside the two profile UI widgets
and directly related tests/docs; no deleted files. API.md was reviewed and its
contract does not need an update. The backend and database need no new migration
or deployment for this UI revision.

Live public-browser and R2 lifecycle checks remain deferred from the previous
release; this UI task does not claim new acceptance of those routes or deploy
Production. Publishing, uncertain recovery and confirmed URL actions are covered
by the automated suites; native QA did not publish or unpublish customer data.

## Exact build and native verification

- `flutter build apk --debug --no-pub --dart-define-from-file=D:\PostDeeMobile\apps\mobile\staging.local.json`
  succeeds. Generated debug Firebase resources use
  `project-798caf7e-85b8-45e3-af7`, not the production Firebase project.
- Package `com.postdee.postdee_mobile.staging`; API base
  `https://postdee-api-staging.onrender.com`; Firebase auth enabled, RevenueCat
  billing and experimental AI Hook/Beat Sync disabled. Configuration is unchanged.
- Built and installed APK SHA256:
  `2882A8FEF7AA0B9F1627AA5C067E3B11E470C5248F018210D5FFB9E21E2FB656`.
  ADB checksum of installed base.apk matches the local delivery APK exactly.
- Android emulator `emulator-5554`, 1080 x 2400 physical pixels, density 420 dpi
  (approximately 411 x 914 logical pixels). Screenshots were inspected with
  view_image. Additional regression viewports cover 393 x 873 with fixed capsule
  footer, and 320 x 640 with keyboard visible. Light and dark themed test flows pass.
- Native path checked: existing signed-in Free account -> profile overview ->
  edit store -> next -> add link title/URL -> expand/collapse extras with values
  retained -> theme -> decoration -> nested font groups -> review -> full preview.
  Main theme decoration button is fully visible above the footer without scrolling.
  Current-process Flutter/AndroidRuntime error logs contain no errors.
- Installed with `adb install -r`; no app-data clearing, uninstall or account
  deletion. Test link existed only in unsaved widget state. Original shared
  preferences restored from private in-app backup and byte comparison passed;
  existing Google/Firebase account remains signed in. The editor is reopened with
  the original draft for the user.
- On 2026-10-05 the user authorized committing and pushing this verified UI
  revision to `codex/profile-link-simpler-ui`. No merge or server deploy is part
  of this push; the existing Staging backend remains unchanged.

Evidence folder:
`C:\Users\stopp\.codex\visualizations\2026\10\04\01a105f6-2943-7ae3-9df1-447070022cb2`.
Final files: `profile-ui-info-final.png`, `profile-ui-overview-final.png`,
`profile-ui-add-link-final.png`, `profile-ui-theme-final.png`,
`profile-ui-decoration-final.png`, `profile-ui-review-final.png`,
`profile-ui-full-tests-final-spacing.log`, `profile-ui-analyze-final.log`,
`profile-ui-staging-build-final.log`, `profile-link-simpler-staging.apk`.

## Visual fidelity ledger

Accepted references (preview-only; not shipped as raster UI):
`C:\Users\stopp\.codex\generated_images\01a10c57-3736-7882-941f-0edc425600cf\exec-92238f3b-41c0-49b5-a154-11f5f92146a6.png`
and
`C:\Users\stopp\.codex\generated_images\01a10c57-3736-7882-941f-0edc425600cf\exec-725d16f0-aefb-4195-9c4e-9460178e32bd.png`.
Both boards and the latest native implementation screenshots were inspected with
view_image in the final QA pass. The edited surface is Flutter Android, so native
ADB screenshots and UI hierarchy interaction replace browser/IAB/Playwright;
there is no edited browser frontend in this task. Saved browser domain blocks
were respected.

| Comparison point | Reference evidence | Native evidence / resolution |
| --- | --- | --- |
| Task order and copy | Board 1 store, board 2 links/theme use the four named steps and one primary task | Final info/theme/review show the same order, headings and current-step emphasis; required states remain visible |
| Information density | Board 1 store shows name/introduction/logo and collapsed URL | Final info starts with these controls only; valid loaded URL collapses; link sheet starts with two fields and collapsed extras |
| Theme controls | Board 2 has four presets in a 2 x 2 grid and separate decoration entry | Final theme uses four visual palette samples, selected border/check, and separate decoration; actual theme colors are preserved |
| Spacing and actions | Boards reserve distinct content, action and navigation zones | Final theme decoration bottom y=1832, Next top y=1896 physical px: about 24 dp clear gap. Fixed 52 dp primary actions and 16 dp gutters preserved. Clipped decoration and oversized default link sheet were repaired |
| Typography and icons | Boards use large Thai task headings and familiar link/tune/image metaphors | Existing Anuphan/Prompt typography, 24 dp headings and Material icon family retained; no generated text/icons shipped |
| Palette and asset treatment | Boards suggest green native chrome around a profile preview | Existing dark/light palette and native capsule remain. Public appearance uses actual cream/store/pastel/dark presets, original images and contract; no invented circles/sample links become customer data |
| Responsive and state behavior | Boards show ordinary phone happy states | Phone screenshots, narrow keyboard and embedded footer regressions pass; hidden validation opens the relevant section, draft survives back navigation, and published overview remains server-confirmed |

Above-the-fold copy diff: step names, main task headings, decoration and action
copy match the workflow reference. Intentional differences are the real store
name/slug/content, current publication status, link count/limit, existing preview
brand/fallback copy, validation/loading/error notices, and the unchanged global
navigation. Validity-dependent required URL visibility is intentional. Native
controls keep established rounded shapes; preview uses a bounded scrollable real
renderer instead of a generated/scaled static mockup. Palette sample cards do
not invent decorative assets. These differences preserve current data/contracts
and are part of the accepted native specification. No other copy was introduced.

The implementation was faithfully verified against the accepted workflow and
native visual specification with the documented necessary differences. No
material unaddressed mismatch remains in the inspected states.

## Files changed

UI: `apps/mobile/lib/features/link_in_bio/link_in_bio_screen.dart` and
`link_in_bio_appearance_editor.dart` in the same directory. Tests: new wizard,
direct appearance and navigation helper suites; adapted existing profile screen,
publish/customization and Home integration tests. Docs: README.md, ROADMAP.md,
ARCHITECTURE.md and this plan. The follow-up backend lock/test changes below add
no API, schema, or configuration changes; no migration required.

## Pre-merge dependency patch (2026-10-06)

The user authorized merging the branch into main. Main is still the verified
baseline `fde4569c65a9bb4040f6681beb8149cf8921cda2`; PR #17 is mergeable without
conflicts. The initial PR CI passed Flutter, 1,158 backend tests, build and
Prisma validation but failed the existing production dependency audit gate.

The blocker is the critical `proxy-addr` advisory
[GHSA-jqcg-44mw-7w3h](https://github.com/advisories/GHSA-jqcg-44mw-7w3h), published
to GitHub's reviewed database on 2026-10-05. Only the package-lock entry changes
from `2.0.7` to the published compatible fix `2.0.8`; its tarball and integrity
were verified against npm metadata and by a fresh npm ci install. Dependencies
`forwarded=0.2.0` and `ipaddr.js=1.9.1` are unchanged, as are Express `5.2.1`,
package.json and the single-hop `trust proxy = 1` setting.

Tests were added before the lock patch. New
`apps/api/src/config/proxyAddrSecurity.test.ts` reproduced the mapped-IPv6 CIDR
case on `2.0.7`: an unrelated socket peer was replaced by forged forwarded data.
It fails on the old dependency and passes on `2.0.8`. The new
`apps/api/src/app.rateLimit.test.ts` integration case confirms that varying the
left forwarded prefix with the same rightmost client shares the global limit
bucket, while a different rightmost client has its own bucket. Existing 429
payload, health exemption and normal traffic assertions remain.

Verification after exact installation: all five targeted tests passed; 96 files
and 1,160 full backend tests passed; build, Prisma schema validation and Prisma
seed/config type-check passed. `npm audit --omit=dev --omit=optional
--audit-level=high` exits successfully with zero high/critical findings. Four
moderate findings remain in `@fastify/busboy`, `ip-address`, `morgan` and `qs`;
this focused patch does not claim a clean audit or broad IP-spoofing protection
for every custom limiter. Existing API contracts, provider credentials and
database schema remain unchanged. API.md was checked and needs no contract edit.

Follow-up changes: the API lockfile, the two test files above, and related
README/ROADMAP/ARCHITECTURE/plan documentation. No security gate was relaxed.
Backend patch deployment uses the normal existing main/CI deployment policy;
there is no migration, secret change, or manual Production deployment in this task.
Local evidence: `artifacts/profile-ui-premerge-api-tests-20261006.log` and
`artifacts/profile-ui-premerge-api-audit-20261006.json` (kept outside Git).
