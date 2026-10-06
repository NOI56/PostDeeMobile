# Internal mobile link manager

## Scope and baseline

The user selected the mobile Linktree Links-manager reference on
[Pinterest](https://www.pinterest.com/pin/993325261536292041/) for PostDee's
internal Store link screen. Replace the setup wizard and returning-profile
overview with a direct link manager; preserve the public page and its renderer.
The earlier `2026-10-05-profile-link-simpler-ui.md` remains historical evidence.

Freshly fetched baseline: `HEAD = origin/main`,
`bcd7153f196cd381a786b333b9b61a67dbe95ca3`, 0 ahead / 0 behind, on
`codex/pinterest-mobile-ui` in the canonical recovery worktree. Existing dirty
bottom-navigation changes and unrelated untracked artifacts are preserved.
No push, merge or deployment is authorized in this task.

## Interface and visual specification

- Every profile state opens the manager, with shop identity and three explicit
  actions: `ข้อมูลร้าน`, `ตกแต่ง`, `ดูตัวอย่าง`.
- Place the primary `เพิ่มลิงก์` action above the list. Cards expose editing,
  visibility and drag ordering. Preserve the menu's move up/down, featured
  promotion and delete actions. Use stable link IDs for card identity.
- Store information, theme customization and review are separate views. Retain
  all advanced link and appearance settings, their values and validation.
- Show Save draft in the footer and an explicit route to review. Publish/Update
  remains an explicit action in review; confirmed success returns to the manager.
  Copy/open remains available only for the server-confirmed public URL.
- Use existing Anuphan/Prompt fonts, pale green/gray surfaces, white cards,
  green primary controls at least 52 dp high, 18 dp card corners and the existing
  light/dark palette. Preserve the current bottom dock and 116 dp clearance.

The two-state ImageGen concept (filled and empty manager) was inspected with
`view_image` at
`C:\Users\stopp\.codex\generated_images\01a105f6-2943-7ae3-9df1-447070022cb2\exec-7bc4eeae-a9d9-483b-b015-9153c9f00934.png`.
It is a preview reference and is not shipped in the app. Intentional native
adaptations use practical spacing for 411 x 914 dp, actual shop data and the
existing Material icon family; no reference sample links or invented Shopee/LINE
logos become customer data. The existing dock is retained. The final native
comparison below confirms this direction in the inspected states.

## Preserved behavior

Draft saving stays explicit and local to the signed-in owner; edits and view
navigation do not save or publish automatically. Keep the 20-link total draft
limit, disabled links, array ordering, enabled-ID set, stable link IDs, category,
icon, font, per-link colors and the complete appearance/media snapshot.
Disabling or deleting a featured link clears its reference. Publish sends only
enabled links in order and merges normalized results by ID, retaining disabled
links. A successful server publication remains confirmed even if the subsequent
local save fails.

Keep local-draft precedence, edit-version protection from late cloud loads,
account-change state reset and late-result owner checks. Unknown publish or
unpublish outcomes require refresh before another publication action or sharing;
public URL actions never use an edited but unconfirmed slug. Preserve slug-change
warnings, hidden-field validation, loading/errors and image upload/reload behavior.

README.md, ROADMAP.md and ARCHITECTURE.md track the new interface. API.md was
reviewed: its link-array order, enabled-only publication and owner/media contracts
are unchanged, so it needs no contract edit. No API, Prisma schema, dependency,
credential, package rule, feature flag or environment configuration changes are
required. This UI revision needs no migration or backend deployment.

## Verification status

Regression tests were added first. The old UI failed
`empty manager opens directly with Add Link and no setup wizard`; evidence is
`link-manager-red.log`. The initial implementation also exposed a Flutter
Material diagnostic. Using a Material surface for the screen and link cards
fixes the ancestor requirement and preserves visible ink feedback.

Targeted manager checks: 12 passed, including a real incremental drag followed
by save/reload and a modal Save action above the keyboard. The initial combined
link/Home run passed 143 of 145 checks. Two test assumptions needed adjustment:
use the intended 393 x 873 viewport for sliver visibility, and scope the More-menu
Save draft label now that the same action is also visible in the footer. The
affected publish/Home suites then passed all 42 checks. Existing data-behavior
assertions remain; these targeted results do not substitute for a full run.

The local Flutter SDK's `onReorderItem` already adjusts the removed-item index;
the manager passes it directly to the existing reorder method. Section Done
validates information/theme input and returns to links; publication retains its
existing validation and error handling.

The complete Flutter suite passed 1,132 of 1,132 tests in approximately 64 seconds
(`link-manager-full-tests.log`). Flutter analyze reports no issues
(`link-manager-analyze.log`), and the exact Staging debug APK build passed
(`link-manager-build.log`). No source changes followed the full test run.
Root verification logs use the `link-manager` prefix in
`C:\Users\stopp\.codex\visualizations\2026\10\04\01a105f6-2943-7ae3-9df1-447070022cb2`.

The APK was installed with `adb install -r`, retaining application data and the
signed-in account. Local APK and installed `base.apk` SHA-256 match:

`4AADE658845CCDB5AD6902AFA25B52FE37B706D3E80580632440D0B7AB2F3E4D`.

Delivery environment: Android emulator `emulator-5554`, API 34, 1080 x 2400
physical pixels at 420 dpi (approximately 411 x 914 dp). The app uses the
existing Staging API and Firebase authentication with project
`project-798caf7e-85b8-45e3-af7`; mock, RevenueCat and experimental flags are false.
The app targets SDK 36, but native API 36 has not been tested in this revision.
HEAD and origin/main remain at the verified `bcd7153` baseline, 0 ahead / 0 behind.

## Native interaction and data preservation

Native QA passed on the same installed APK in light mode. The real saved
`noikub` draft opened directly in the manager at 0/20. Two temporary links,
`QA-Shop` and `QA-Contact`, were added through the sheet while the keyboard was
open. Shop was edited to `QA-Shop-Edited`, toggled off with the `ซ่อนอยู่` state,
and a real ADB drag moved Contact before Shop. Shop information's Done action
remained above the keyboard and returned to the manager. Selecting the Shop
theme then Done preserved the links; review and full preview showed only the
enabled Contact link. Returning preserved both cards, order and hidden state.

No draft Save, publish or unpublish was performed during native QA. Force-stop
and relaunch discarded the temporary in-memory state. The final manager shows
the original `noikub`, `postdee-demo-20261005` and 0/20, and remains open for
review. The baseline, pre-restart and post-restart `FlutterSharedPreferences.xml`
SHA-256 are identical:

`948dbf65ea1ccf2f720989c79f064143087322a290de0134b4b1fdabbb9f8b82`.

The current app process log scan contains no matches for fatal errors, Unhandled
Exception, RenderFlex, EXCEPTION CAUGHT or E/flutter. No source changes followed
the verified test/build. Independent read-only review found no blocker; final
diff checking passes. The earlier navigation changes and unrelated artifacts
remain intact. No push, merge, server deployment or migration was performed.

## Native visual comparison

All evidence below is in the visualization folder recorded above. Screenshots
were inspected, with no clipping seen in the tested states. This is native
Flutter Android UI, so emulator screenshots and interactions verify the changed
surface; no browser frontend was changed.

| Comparison | Inspected evidence and result |
| --- | --- |
| Direct empty/filled manager | `link-manager-empty.png`, `link-manager-populated-before-drag.png` and `link-manager-populated.png` show shop identity, three grouped actions, a full-width green Add action and white link cards. No setup wizard or inline public-page preview occupies the manager. |
| Card actions and ordering | The populated images show native edit controls, switches, drag handles and hidden state; the before/after sequence confirms the native drag. Actual data and Material icons replace generated sample content/logos. |
| Keyboard and footer | `link-manager-keyboard.png` and `link-manager-info-keyboard.png` show usable modal/info actions above the keyboard. Practical 411 dp spacing preserves the existing dock and content clearance. |
| Separate preview and restoration | `link-manager-preview.png` and `link-manager-full-preview.png` show the enabled draft link in review/full preview. `link-manager-final.png` and `link-manager-final.xml` confirm the original empty saved draft after restart. |

The implementation matches the selected manager workflow and native visual
specification in these inspected states. Intentional differences from the
generated concept are practical phone spacing, actual shop content, existing
fonts/Material icons, state-dependent messages and the preserved PostDee dock.

Native coverage is light mode at approximately 411 dp. Widget regressions cover
320/393 dp and enlarged text, including dark-theme manager layouts. Native dark
mode, physical Android, iOS and API 36 were not tested in this revision; native
long-list drag auto-scroll was not exercised. Real server publication was
intentionally not performed. Public browser/R2 lifecycle checks remain deferred
from the earlier release and are not implied by mobile UI verification.

## Follow-up: fill an empty button title from its URL (2026-10-06)

The user requested fewer inputs when adding a link: entering a URL should fill
the button title if the user has not supplied one. The same freshly fetched
`bcd7153f196cd381a786b333b9b61a67dbe95ca3` baseline, 0 ahead / 0 behind, and
`codex/pinterest-mobile-ui` worktree apply; existing UI changes are preserved.
The preceding test/build/native evidence records the manager before this
follow-up and does not verify the additional title behavior.

A valid URL suggests Shopee, Lazada, LINE, TikTok, YouTube, Instagram or Facebook
using the existing domain rules. Other destinations use the lowercase hostname
without a leading `www.`, capped at the existing 80-character title limit.
The title follows URL changes while empty or generated. Once the user writes a
custom title, URL changes retain it; titles on existing saved links are also
treated as user-owned. Clearing a title does not immediately refill it while
typing, but a later URL edit or Save can supply the suggestion again. Invalid
URLs still fail the existing validator and do not receive a suggested title.

`link_in_bio_link_defaults.dart` supplies the pure URL/platform helper shared by
title suggestions and automatic icon selection. The recognized domains and icon
rules remain unchanged. Only the modal title field changes; there is no metadata
fetch, AI call, automatic draft saving or publication, API/schema change,
dependency, credential or environment change. API.md's required title and URL
validation contract remains applicable without modification.

Twelve regressions were added before implementation; the old UI failed the
Shopee suggestion expectation with an empty title. The 12 new regressions and
two preview tests pass (14/14). The complete Flutter suite passes 1,144/1,144 in
62 seconds (`auto-link-title-full-tests.log`), analyze reports no issues in
9.7 seconds (`auto-link-title-analyze.log`), and the Staging debug build succeeds
in 17.5 seconds (`auto-link-title-build.log`). Logs use the visualization folder
recorded above. No source changes followed these checks; read-only review found
no issues.

The follow-up APK was installed with `adb install -r` on the same API 34 emulator.
Its local and installed SHA-256 match:
`2985C2BB1801230A665733FE8B1FB6F85CA549962DC71C61E7750CEFC3395617`.
Staging configuration is unchanged: API
`https://postdee-api-staging.onrender.com`, Firebase authentication enabled with
project `project-798caf7e-85b8-45e3-af7`, and mock/RevenueCat/experimental flags
false.

Native follow-up QA passed on that APK: a blank title plus a Shopee URL rendered
`Shopee`, changing the URL to `youtu.be` rendered `YouTube`, and entering
`QA-Custom` then changing to a TikTok URL retained the custom title. Sheet Save
returned the matching card in memory. Inspected `auto-link-title-filled.png` and
`auto-link-title-custom.png`, with matching XML, record these checks. No local
draft Save, publish or unpublish was performed.

Force-stop/relaunch discarded the QA state and loaded the confirmed published
`noikub` profile with its original `youtube` link and 1/20 count. The earlier 0/20
display was in-memory state, not the persisted profile. This round's preferences
SHA-256 before installation, before cleanup and after restart is identical:
`cb389d8a372a8a71b5c89efb03bf1d97485d83c402ade442dd3de6e13bd8f055`.
`auto-link-title-restored.xml` confirms the original link and absence of QA data.
The final blank Add form is open; inspected `auto-link-title-ready.png` shows
the form and Save action clearly.

The restarted process log (`auto-link-title-runtime.log`) contains no matching
Flutter/fatal runtime errors; the earlier native-test process was not captured.
Final diff checking passes, with no API/pubspec changes and no source changes
after tests/build. Native coverage is light mode on API 34 only. Clear-title then
Save is covered by widget regression, not a native check; physical devices, iOS,
native dark mode and API 36 remain untested. No push or deployment was performed.
