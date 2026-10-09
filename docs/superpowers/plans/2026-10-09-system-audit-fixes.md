# System audit fixes — 2026-10-09

## Scope and baseline

The user authorized the five-round plan after a read-only page audit. Start from
remote-verified main `c4e52201a58b556f5f47529027549a2fc16af84c` in an isolated
`codex/audit-system-fixes` worktree. Preserve all unrelated work, the five-tab
dock, full-screen composer, 100 profile templates, captions, current entitlement
windows and owner mutation/deletion barriers. Real posts, payments, OTP,
connections and shop publication are outside the read-only test authorization.
The initial local implementation had no push, merge, deployment or database
mutation. The user subsequently authorized push/deploy to Staging; its receipt
is recorded below. Real customer-content writes remain outside the test scope.

## Fixes

1. Publishing: streamed stable source/cover/watermark identity, optional persisted
   Post fingerprint, saved upload receipt before create, reuse after lost reply,
   and conflict/retained draft when accepted media changes. Never rotate an
   uncertain request id automatically. Home gets all-post navigation, active
   entitlement refresh and visible stale-load errors; Calendar stays current.
2. Auth/notifications: run UI before bounded session restoration, ignore changed
   sessions and late timeout results, rebind device registration per UID and
   unregister only the caller's token. Push data includes owner/post id; cold
   taps and list taps can open the owned post. All routes above the shell close
   on UID transition; same-owner token refresh preserves the route. Post details
   also guard their own owner directly. Local profile drafts use UID keys with
   strict matching-email legacy migration. Phone verification refreshes
   credentials/entitlement; login legal and supported email self-service work.
3. Shop: serialized local autosave with saved/pending/error states; publish stays
   explicit. Protect added image references before committing local changes and
   only then replace old device references. Category/rhythm and outline contrast
   agree with HTML, and inactive previews stop animation callbacks. Unsupported
   protection routes (404/405) report feature unavailability; other failures use
   the existing error mapper instead of always claiming an internet failure.
4. Billing/captions/templates: use actual store prices, bound store waiting while
   retaining the same in-flight operation, and recheck without buying again.
   Identify provider fallback and release only its exact usage reservation;
   release failure is reported as charged. Keep new text typed while a prior
   template save finishes and block conflicting list/save operations.

## Migration and compatibility

Apply `20261009090000_add_post_media_content_fingerprint` and
`20261009114000_protect_link_in_bio_draft_images` using the normal Prisma deploy
procedure, then generate/build and deploy API, then distribute the mobile APK.
Both migrations are additive; old rows are retained. Caption refunds reuse the
existing usage-row id and need no additional schema. Device unregistration is
authenticated `DELETE /devices` with a JSON token, not a token in the access-log
URL. New push payloads need server `userId` before the stricter mobile receiver.

An old accepted Post with no fingerprint can replay only with identical video
and cover keys. A pre-upgrade uncertain local draft lacking upload receipts
cannot safely infer its previous media after reupload. It remains saved and
needs checking the existing/destination post before explicit new-attempt action.

Existing/old-client image uploads have `legacyRetention=true`: the server cannot
know which offline drafts refer to them. New-client managed uploads pin up to
three owned keys per versioned device draft reference. The mobile persists a
monotonic owner-scoped revision before sending any protection request; an older
delayed replace only removes references from that device at its own revision or
earlier. Other devices and newer revisions remain protected. All local managers
serialize protection, disk commit and release, rereading the shared confirmation
cache inside the owner queue. The migration temporarily permits
20 retained legacy plus 20 managed images (each at most 512 KiB). Explicit
legacy-image cleanup remains future work. Unknown refs are never deleted to
free space automatically. Prune claims prevent new pins from attaching during
object removal; an interrupted storage delete or metadata deletion keeps the
claim closed rather than exposing potentially missing bytes. Such claimed rows
need verified operational reconciliation and occupy a slot until repaired.
There is no automatic unclaim after an uncertain remote delete.

Publication adds a unique durable guard before validating/committing image
references. Successful publication releases that guard after persistence;
uncertain writes retain it and failed guard cleanup does not turn an accepted
publication into a failure response. Prisma prune also atomically excludes any
current saved profile image. Interrupted publication guards need verified
operational reconciliation; retained references stay bounded at 32 per image.
After a successful prune claim, a fresh profile read runs before any object
delete to cover a concurrent profile commit outside the claim statement's
snapshot. A confirmed current reference cancels the claim at that point only;
a failed read leaves the claim closed and does not delete storage bytes.

Process-local owner/deletion coordination and memory scheduling still require
one API instance. No horizontal scaling, Redis activation or provider activation
is part of this fix. Auth/photo/store SDK flows are covered with injected fakes
until authorized native/service E2E acceptance.

SDK token rotation must succeed before a new owner registers a token. If the
SDK/network cannot delete the previous token, OS notifications may still show
previous payloads until retry succeeds; the in-app UID filter remains strict.
Real background delivery and two-account device tests remain acceptance gates.

## Verification and delivery

Regression tests are added before implementation for the audited failures.
Targeted checks run during development; final full Flutter/API suites, analysis,
API build, Prisma validation/generation, generated-helper type checks and exact
Staging APK verification must be recorded before declaring the patch ready.
During local verification, Staging was the prior release with social publishing
disabled. The authorized rollout below preserves that setting. A
health/readiness success is not proof of social-provider acceptance or paid-store
checkout. Native update must preserve the existing account/data and may be
limited by emulator storage; do not uninstall or wipe it to bypass that limit.

Final local checks on the combined branch:

- API full suite: 108 files / 1,647 tests passed. Production TypeScript build,
  Prisma generation/validation and seed/config type checks passed.
- Final Flutter full suite after the error-copy patch: 1,683 tests passed;
  full analysis reports no issues.
- Profile template catalog parity and all 22 generator tests passed; the 100
  original templates and platform logo assets are preserved.
- Compiled local HTTP smoke passes post replay/conflict/owner separation,
  device reassignment/scoped unregister, image upload/reference owner checks
  and both caption fallback refunds. All adapters are local mocks/memory, with
  no external provider requests or live user writes.
- Production dependency audit passes the high-severity gate; four existing
  moderate advisories remain. Dependency versions were not changed here.
- Validated Staging debug APK build passes with Flutter 3.44.1/Dart 3.12.1 and
  `--target-platform=android-x64` for emulator verification. APK size is
  196,657,846 bytes; SHA-256 is
  `3f16f9b237f8c8d127d0f1506e5c9dee01edc9adcbaf6d77f191da1dde999388`.
  Package is `com.postdee.postdee_mobile.staging`, version `0.1.0-staging`,
  min SDK 24 / target SDK 36. The debug certificate matches the installed app
  (`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`).
  The helper validates the Staging API URL, Firebase project/OAuth client,
  Firebase auth enabled, local mock auth disabled, Staging marker, experimental
  flags disabled and RevenueCat Test Store overlay; it does not print the key.

Before rollout, an isolated PGlite 0.5.8 PostgreSQL 18.3 engine applied all 16
migration files, including seeded pre-upgrade rows, and executed the exact raw
SQL templates with bound parameters 72 times across ten protection scenarios.
This supplements the test doubles; it does not certify multi-connection MVCC,
the Prisma TCP driver or R2 bytes. The Render migration engine also applied both
new migrations during the authorized rollout below.
R2 delete/upload, real purchase/restore/acknowledgement,
OTP/email delivery, two-account/background FCM delivery and real platform
publication are still service acceptance gates. The emulator screen checks below
ran against the prior Staging API. The new API is now Live as recorded below;
authenticated new write-contract acceptance remains unverified.

Native screen receipt on Android 14/API 34, `PostDee_Pixel:5556`:

- The first APK (`8cf06bc807ce5d8c278bb28cbc5946336234c318d6445871e6578a82aea799b6`)
  was installed with `adb install -r` and its installed bytes matched that hash.
  The existing signed-in account, one local post draft and two shop links were
  retained. Home, current-month Calendar, composer, shop/preview and Account
  opened. Composer stayed on step one with Thai validation when Next was pressed
  without a clip. The package page read Test Store prices. No manual draft save,
  edits, upload, publication, purchase, OTP or connection change was performed.
- Opening the shop can perform background image-protection/bookkeeping requests
  for existing drafts; it is not a read-only operation against a new API. Live
  Staging is still the old API, and the protection feature was unavailable. The
  misleading connectivity warning prompted the final error-copy patch above.
- The final APK was rebuilt after that patch, passed package/certificate checks
  and was installed with `adb install -r` successfully. The user stopped Computer
  Use with physical Escape before the final APK screen check. No further native
  input was issued. Final-artifact native smoke remains incomplete; prior screen
  results do not certify the final APK or the new API write contracts.

## Authorized push and Staging deployment

The user requested `push/deploy` after the local fix summary. A fresh fetch
confirmed `origin/main` still at baseline `c4e5220`. All 95 related source, tests,
migrations and documentation files were committed and pushed on
`codex/audit-system-fixes` as
`85ef2a9e8e48bdce19354bc6fb8952010def2396`. Windows generated files with no
semantic diff were excluded; private configuration and artifacts were not staged.
`main` was not changed. Render's specific-commit dialog accepts any branch and
selected this exact SHA; branch/Auto-Deploy/compute/environment settings were
not modified.

- [Exact-source CI 37889287192](https://github.com/NOI56/PostDeeMobile/actions/runs/37889287192)
  passed Backend API and Flutter Mobile. Logs confirm 1,647 API tests, 1,683
  Flutter tests and no analysis issues. The dispatch did not build another APK.
- [Render deploy dep-db47shbbc2fs73au8e90](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db47shbbc2fs73au8e90)
  on `srv-d9bb72ojs32c739osa5g` shows `Deploy succeeded | Live` for exact source
  `85ef2a9`. Build generated Prisma 6.19.3 and compiled the API. Runtime Node is
  26.11.1; CI used Node 22.
- Instance `55gww` connects to database `postdee_staging` at the previously
  verified Staging database host. Logs found 16 migrations and applied
  `20261009090000_add_post_media_content_fingerprint` and
  `20261009114000_protect_link_in_bio_draft_images`, ending with
  `All migrations have been successfully applied` at 12:41:25 GMT+7.
- After dependency pruning, the API started at 12:42:13 GMT+7 on port 10000 and
  Render reported Live at 12:42:15. Social publishing remains disabled;
  `PUBLISH_QUEUE=memory` and one-instance operation are preserved. The production
  dependency subset still reports four moderate advisories.
- The attempted direct browser `/ready` check was blocked by client access
  settings. No alternate request path was used to bypass the block. Render's
  deployment/startup/internal health evidence is verified; direct `/ready`,
  authenticated `/posts`, live protection writes, schema introspection and
  public-page rendering remain unverified. No customer post, purchase, OTP,
  image upload, pin/unpin test or shop publication was triggered by this rollout.
- Local proof: `.tmp/render-audit-fixes-live.png` and
  `.tmp/pglite-validation/receipt.json`; neither contains credentials. The
  screenshot shows Live and the selected SHA. Documentation-only delivery
  updates have the same application runtime as the deployed feature SHA.

Deployment completion is distinct from full product acceptance. Native smoke
and the external-service acceptance gates above remain open. Production has
not been deployed in this run.

## Follow-up: Account and Home package display

The installed audit APK hash matched the final artifact above. Native inspection
reproduced cached Account `Pro / 250` while a fresh Home tab load and a newly
opened Paywall both reported `BASIC / 0`. Account did not refresh on tab entry;
neither Account nor Home refreshed its package when the app resumed. This is
display evidence, not proof of the purchase's expiration/refund history. The
validated APK uses RevenueCat Test Store; test billing is not a production
purchase acceptance test. No repeat purchase, restore or resync was performed.

Account now reloads on tab entry. Home and Account reload on app resume only
when their tab and root route are visible. The shell passes the same optional
subscription loader to Home, Account and Account's Paywall; production still
uses authenticated `GET /billing/subscription`. Existing generation guards
ignore older responses, including a late Pro response after a newer Basic read.
No package rules, billing verification, API contract, server configuration or
database schema changed.

Two behavioral regression tests failed before the patch (one load instead of
two). Five added regressions cover upgrade, expiration, hidden-tab resume,
late-response ordering and Home/Account/Paywall integration. Full Flutter tests
pass 1,688/1,688; full analysis reports no issues. The validated Staging debug
APK builds, keeps the same package and debug certificate, and has SHA-256
`1b7b577ab4c5dce527465641be14bbc6332ea9da88bfe09a70f6647e240fbe98`.
It was installed with `adb install -r --streaming`; installed bytes match.
Native Home and Account display the current Free `0 / 3` status with the same
signed-in account retained. A live new purchase/restore and this account's
provider transaction history have not been re-tested or confirmed.

## Follow-up: AI captions blocked by clip aspect ratio

Fresh `git fetch origin` retained main baseline
`c4e52201a58b556f5f47529027549a2fc16af84c`; this follow-up starts from the
already-pushed audit branch `80fa9b6` (three commits ahead, none behind main).
Unrelated generated Windows line-ending changes and the dirty original
workspace are preserved and excluded from delivery.

Local metadata inspection of the selected `1000000096.mp4` on the Staging
emulator returned actual `1080x2400` dimensions (9:20), rather than 9:16.
The composer stopped before uploading it for AI. No rotation change, crop,
remote user upload, provider generation or quota-consuming action was performed.

Caption uploads now identify `purpose: "ai-caption-video"` and retain complete
source dimensions at any aspect ratio. When legacy draft metadata knows only
one dimension, mobile omits both instead of fabricating the missing value.
The API requires `.mp4` / `video/mp4`, the existing maximum upload size and
either absent or positive finite integer dimension pairs. Existing ownership,
authentication, paid-plan and AI quota gates remain. AI upload receipts remain
separate from the posting cache; generic uploads and mobile posting retain the
9:16 rule. This is not a new server-side `/posts` aspect-ratio guarantee.

The AI panel maps paid access, exhausted monthly quota and invalid upload errors
to Thai, uses the shared safe API error mapper for other errors, and retains the
user's caption on failure. Paid-plan copy uses package names without embedding
store prices. The related four root documents are synchronized. No database
migration or configuration change is required; deploy API before mobile.

Backend regression tests failed before the patch (30 failures) and pass 63/63
targeted; full API tests pass 1,684/1,684 across 108 files. API build, Prisma
schema validation and Prisma helper type checks pass. Mobile aspect tests fail
with the old guard (three cases); partial-dimension regressions also fail before
normalization (two cases). The final targeted AI tests pass 14/14, full Flutter
tests pass 1,697/1,697, and full analysis reports no issues.

The final Staging debug APK builds with the validated Staging/Firebase and
RevenueCat Test Store configuration, unchanged package
`com.postdee.postdee_mobile.staging` and debug certificate
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
It is 196,657,846 bytes with SHA-256
`0b6183303c95a5a034fe154276e3ed61869a7f0f16cceeb48c62418a2f204232`.
It has not yet replaced the installed APK: the user currently has an unsaved
selected clip open, and the earlier test scope forbids saving a draft for them.
That interim APK was not installed. The user's later instruction to start the
social-connect return rollout authorized restarting/installing the combined
build below, without saving their draft. Live provider generation remains
unverified.

## Follow-up: Android social-connect return

Fresh remote verification again retained main `c4e5220`, with audit HEAD
`80fa9b6` three commits ahead and none behind. The existing provider callback
showed JSON because the connect link omitted the optional PostPeer `redirectUri`.
New authenticated connect requests accept only fixed `returnTarget` values:
`android` maps to `postdee://social-connect/return`, and `android-staging` to
`postdee-staging://social-connect/return`. Legacy clients omit the field and
keep their existing behavior. Invalid targets fail before provider/profile
work; arbitrary caller redirect/profile/owner fields are never forwarded.

Android debug builds use the Staging target, matching the existing package
suffix independently of the UI's Staging badge. A transient native return
activity validates the exact package/scheme/authority/path and reuses
MainActivity. It does not forward callback metadata, tokens or success claims.
The connection screen reconciles the signed-in owner through authenticated
refresh, coalesces early resume/launcher completion and ignores work from a
previous owner. iOS and web retain the legacy flow. Existing billing deep links,
Google/email authentication, publishing destinations and AI plan/quota gates
are preserved. No schema, environment or permission change is required.

Tests-first social regressions failed before implementation. Final combined
API tests pass 1,708/1,708 across 108 files; API build, Prisma schema validation
and Prisma helper type checks pass. Flutter passes 1,707/1,707, full analysis
reports no issues, and Android's five JVM URI regressions pass. Both validated
Staging debug and x86_64 split builds succeed with the existing Firebase/API
and RevenueCat Test Store configuration.

The emulator lacked space for the universal artifact. Regenerable caches and
PostDee dexopt artifacts were reclaimed without clearing app data, uninstalling
or deleting user media. The delivered x86_64 split APK is 127,485,886 bytes,
version code 4001, package `com.postdee.postdee_mobile.staging`, SHA-256
`5262c27323f593bc0932ff9526ec8ebde3d31c9629eb91522c69434cc48e289e`.
Its certificate is unchanged from the previous receipt. Installation used
`adb install -r --streaming`; pulled installed bytes match that exact hash.
The first launch was slow during emulator I/O/GC work, then Home and Account
loaded with the signed-in account and existing TikTok connection retained.

Developer VIEW-intent smoke resolves the Staging URI to the new return activity
and preserves the same MainActivity record and task (`38a5398`, task 105).
Native inspection still shows the original connection screen and existing
1/4 connected status, with no duplicate screen. The production URI has no
handler in this Staging-only install. No real new OAuth grant, account
disconnect, customer upload, AI generation, purchase or post was performed.
A local browser-fixture launch command was rejected by automatic policy;
its test server was stopped. This does not verify actual provider/browser
handoff, browser Open App confirmation or cold-start authentication. These
remain explicit acceptance gates; old already-open links cannot acquire the
new redirect setting. Staging API deployment of the combined contract is
recorded below; new customer links must use the updated API.

### Combined Staging delivery receipt

Authorized source `9f0b72904d610c7161c8fca863e7d21f0ff1a1f6` was pushed to
`codex/audit-system-fixes` and manually deployed on the existing Staging service
`srv-d9bb72ojs32c739osa5g`, deploy `dep-db498ejl550s73b0qu20`. Render checked out
the exact SHA, completed npm/Prisma/TypeScript build and reported Live at
14:16:00 GMT+7 on 2026-10-09 (duration 1m58s). Runtime instance `qv9d4` found
16 migrations with none pending, pruned development/optional dependencies and
started the API on port 10000 at 14:15:58. Logs retain publishing disabled and
`PUBLISH_QUEUE=memory`; service topology/configuration was not changed. The
production dependency subset still reports four moderate advisories.

The installed x86_64 APK receipt above uses the same frozen runtime source.
Proof `.tmp/render-social-return-live.png` shows source SHA and startup/Live
logs. Public Staging browser access remains blocked; no alternate HTTP, shell
or URL was used to bypass that block. Render deployment/internal health is
verified; direct `/ready`, a new provider authorization/return and a real
AI-caption upload/generation remain unverified. Production and main were not
deployed/merged in this run. GitHub CI run `37897827978` passed both Backend API
and Flutter Mobile jobs at exact source `9f0b729`, including production dependency
audit and shared-template checks. Documentation-only receipt updates do not
alter the tested/deployed runtime source.

## Follow-up: caption evidence and publishing text

This follow-up starts from audit branch `084a507`, with remote main still
`c4e5220` (five commits ahead, none behind). The earlier Staging/API/APK receipt
above does not certify this new quality patch. The initial local implementation
did not perform customer uploads, generation, posts, paid-state changes,
installation or deployment. Later provider probes and the local APK delivery
are recorded below; they do not replace a deployed API or authenticated caption
screen acceptance test.

The Gemini prompt asks for an evidence-specific natural opening hook in the
primary caption, grounded in speech, visible actions and legible text. Silent
clips must not invent speech, tutorial steps or unsupported product claims;
the prompt requests `detectedSpokenLanguage: "und"` for them. Incidental
identifiers must not become marketing content. Thai is the prompt default unless
actual speech or dominant meaningful text across the clip clearly establishes
another language; brands, account names, dates and numbers do not override it.
Captions use creator voice rather than an analysis summary, in one or two short
sentences. Silent menu navigation previews only menus/data actually visible,
without inferred store creation, business setup or promotional benefits; the
same evidence boundary applies to options, hooks and metadata. Visible buttons,
plan or link labels alone
do not establish setup, editing, purchase, scheduling or integrations. Real-clip
generation temperature decreases from 0.8 to 0.4 to reduce speculation.
These prompt instructions
cannot guarantee factual accuracy. Hooks remain a separate response field; the
parser does not prepend hooks or rewrite the primary caption. Gemini hashtags
and SEO keywords are normalized/deduplicated up to five valid items each; missing,
empty or invalid metadata stays empty instead of adding generic defaults.

Mobile inserts the caption and deduplicated hashtags, omitting the literal
`SEO:` paragraph. Search keywords appear only in the collapsed current-screen
`คำค้นที่ AI แนะนำ` area and clear on source change, draft restoration and owner
reset. Actual path replacement preserves all caption/guidance and marks
nonempty caption text for review. Applied fallback AI also requires review.
Cancelled or same-path selection does not add a flag. The general review notice
has an explicit `ตรวจแล้ว` action; ordinary edits do not acknowledge it. Only
that acknowledgement or an applied non-fallback AI result clears the flag.
The optional local boolean `captionNeedsReview` uses existing manifest version
3, defaults to false when absent and persists across saved-draft restoration.

Both Gemini modes already receive the whole MP4; `AUDIO_ONLY` is a historical
enum, not isolated-audio transport. Pro adds at most three selected frames.
Existing models, retries, network fields, media/owner checks, paid access,
quotas, four-platform posting and SDK remain unchanged. No API field, database
migration or configuration change is required. The four root documents are
synchronized. Final automated verification passes 1,716/1,716 API tests across
108 files (`--maxWorkers=2`), 45/45 targeted caption tests and API build. Earlier
Prisma validation/helper type checks pass with schema unchanged. Flutter passes
1,717/1,717 and analysis reports no issues.

### Caption-quality provider and local APK receipt

The final provider source SHA-256 is
`c8bb8a53a38be2476e6e47da90064a155e18c9e92ec1f91b2c5d6acef8a8edb9`.
Six direct Gemini calls completed across refinements: the first three English
results and one Thai Pro tutorial claim were unsuitable. The final Pro primary
caption, `มาดูกันว่าในหน้า ลิงก์ร้านค้า มีอะไรให้เราจัดการบ้างนะ`, matches the
observed menu preview. Its single call took 25.148 seconds using the unchanged
Gemini 2.5 Flash-Lite model at temperature 0.4 with three Pro frames. Receipt:
`.tmp/caption-quality-live-menu-preview-pro-20261009.json`. This is a limited
improvement, not a general quality benchmark or a claim that all semantic checks
pass. Gemini still returned `detectedSpokenLanguage: "th"` despite ffprobe finding
no audio stream. The prompt's `und` request is not guaranteed detection; Mobile
only echoes this context metadata and does not use it for caption selection,
routing or entitlements. Direct provider probes do not verify deployed Staging
API routes or quota behavior.

The exact Staging x86_64 debug APK built and installed with `-r`; built and pulled
installed bytes match SHA-256
`CAF3349CFBA3A17AA6266827F9C0C5943416B74ECF04E7D474692115B6E8DC68`,
149,683,019 bytes, package `com.postdee.postdee_mobile.staging`, version code
4001 / `0.1.0-staging`. Certificate remains
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
The validated helper uses Staging API, real Firebase auth project
`project-798caf7e-85b8-45e3-af7`, RevenueCat Test Store, mock auth off and
experimental features off.

The user authorized installation without preserving the unsaved composer form.
No app-data clearing, uninstall, draft save, post or purchase was performed.
The installed app opened login; the user chose code/tests only instead of
authentication. Authenticated caption UI smoke therefore remains pending at
that choice. No commit, push or deployment was performed for this caption patch;
the earlier historical Staging delivery receipt remains unchanged.

### Native caption UI acceptance follow-up (2026-10-09, about 16:04 GMT+7)

After the user requested native testing, inspection used the unchanged Staging
APK with SHA-256
`CAF3349CFBA3A17AA6266827F9C0C5943416B74ECF04E7D474692115B6E8DC68`.
The user was already signed in; the composer opened at step 2 with
`1000000099.mp4` and an existing AI caption. That result was present before
inspection: this test did not generate it or establish its network/quota history.

Three native caption behaviors pass within visual inspection limits:

- `คำค้นที่ AI แนะนำ` expands separate keyword text; the visible primary caption
  has no `SEO:` paragraph, and `#TikTok`, `#Reels` and `#Facebook` are not visibly
  duplicated.
- Cancelling the Android photo picker retains clip 99 and its caption without
  adding a review notice.
- Replacing clip 99 with `1000000096.mp4` (10 seconds) visibly retains the
  caption, clears the previous SEO suggestions and shows
  `กรุณาตรวจว่าแคปชั่นตรงกับคลิปที่เลือกก่อนใช้` plus `ตรวจแล้ว`. Acknowledging
  hides the notice without changing visible text. Selecting clip 99 again
  preserves the caption and adds the notice again for the changed source path;
  ephemeral SEO suggestions remain cleared.

The local draft sheet was inspected read-only with two items visible; no draft
was restored, saved or deleted. Fresh inspection at 16:05 GMT+7 confirms the
sheet closed, composer step 2 on clip 99, visibly unchanged caption, review
notice visible and no SEO suggestions. No Generate AI, channel, post, purchase, logout,
permission or authentication control was used, and no upload/generation action
was initiated. This visual test cannot assert byte-for-byte text identity.
The existing 1,717 passing Flutter tests cover exact text preservation, saved
review-state persistence, fallback results and legacy draft compatibility.

The deployed Staging backend still uses the earlier source; this native smoke
does not verify the final prompt through the app or deployed API/quota behavior.
Earlier direct Gemini probes cover one clip only, with the known incorrect
silent-language metadata. No commit, push or deployment was performed.

### Caption-quality Staging delivery and bounded app smoke (2026-10-09)

The user subsequently authorized deployment. Source
`f6bf0f9b60a229448aa04dfd5920e24884c577fc` was pushed to
`codex/audit-system-fixes`; exact-source CI `37909530347` completed successfully
for both Backend API and Flutter Mobile. Render deployed that exact source as
`dep-db4b0t3tqb8s73emmb40`: the UI lists 16:14:28 GMT+7, logs report Live at
16:16:20 GMT+7, duration 1m52s. Build succeeded, all 16 migrations were found
with none pending, and the API listened on port 10000. The memory queue and
disabled social publishing remain unchanged. Proof:
`.tmp/render-caption-quality-live-20261009.png`. Main and Production were not
deployed. The installed APK remains SHA-256
`CAF3349CFBA3A17AA6266827F9C0C5943416B74ECF04E7D474692115B6E8DC68`.

One normal app Generate AI action was attempted at 09:20:07 UTC (16:20:07 GMT+7)
in a new unsaved composer, with blank caption/guidance and `1000000099.mp4`.
This silent whole MP4 lasts 3.875111 seconds and has SHA-256
`F0775992DF8AB5DD2558790C6C1301FEAA2F5CFA95F358EBCD63C6233D7F8F9F`,
distinct from the earlier 10-second clip 96. About six seconds later, the UI
showed `AI แคปชั่นใช้ได้ในแพ็กเกจ Starter หรือ Pro กรุณาตรวจสอบแพ็กเกจของคุณ`.
No caption result, retry, draft save, post or purchase occurred.

Home's visible Pro 250/250 is cached post-unit information, not observed AI
quota or proof of a current backend entitlement. AI reloads `/billing/subscription`
and checks `canUseAiCaptions`; the server rechecks the same subscription store.
The displayed message can arise from the fresh mobile gate before upload or
the server paid gate after media upload. The screenshot does not establish the
exact stage, current entitlement/expiry, upload activity or cost. Both known
paid gates reject before provider execution/quota reservation, but the UI alone
does not prove the request path taken. Local Test Store Pro alone does not grant
backend access; it needs the existing resync/webhook confirmation. Pro AI's
120/month limit is unchanged and its actual usage was not observed.

Deployment and CI passed; end-to-end app AI remains blocked at entitlement and
has not passed. No generated-caption quality or provider failure is inferred.
Existing package policies and guards remain unchanged. Earlier no-push/deploy
statements above describe their respective historical runs.

### Pro display versus AI entitlement investigation (2026-10-09)

Read-only native inspection of the original installed app closed the tester's
blank composer without saving: Home showed cached Pro, Account loaded Free,
then Home refreshed to Free. No draft save, post, purchase, Restore/resync,
mobile logout or authentication action was performed in this inspection.

After the user logged in, RevenueCat Dashboard inspection confirmed the current
Firebase UID matched the observed customer; only the sanitized equality result
was retained. The latest
Pro purchase used Test Store Sandbox, starting about 15:55 and expiring at
16:20:43.503 GMT+7 on 2026-10-09. Relevant provider history, all in GMT+7:

| Event | Period purchase | Period expiry | Event timestamp | Webhook sent |
| --- | --- | --- | --- | --- |
| Previous renewal | 16:10:43.503 | 16:15:43.503 | 16:14:34.666 | 16:14 |
| Latest renewal | 16:15:43.503 | 16:20:43.503 | 16:21:42.380 | 16:22 |
| Expired | — | 16:20:43.503 | 16:21:42.396 | 16:22 |

Late provider delivery is confirmed, and current Sandbox Free is confirmed.
The original AI action at 16:20:07.708 and its error about six seconds later
preceded the latest expiry by about 30 seconds; current expiration therefore
does not fully explain that earlier denial. A backend still holding the prior
period end is consistent with the delayed renewal, but remains an inference:
the database row and exact request stage were not read. Render's actual
`SUBSCRIPTION_STORE=prisma` was verified read-only and masked again, ruling out
the proposed memory-store reset explanation. Privacy-cropped evidence:
`D:\PostDeeMobile\.tmp\caption-subscription-20261009\revenuecat-expiry-20261009.png`.

Mobile commit `2800742cfa34df4888281c2cc2728e6c1f9cfaef` changes only
`postdee_shell.dart` and its tests: Home/Profile become inactive while the
composer is open and refresh when it closes, preserving state and existing
same-owner route guards. Three new regressions first produced two failures
and one pass, then passed; all 45 shell tests pass. Full analysis reports no
issues and the full Flutter suite passes 1,720/1,720 with `--concurrency=2`.
An initial run was interrupted by memory/resource pressure after 1,715 passes
with five incomplete cases; the completed rerun supplies acceptance evidence.
Per-command temporary storage used D:, and only the tester's prior APK receipt
was moved to
`D:\PostDeeMobile\.tmp\caption-subscription-20261009\caption-quality-installed-20261009.apk`,
retaining the earlier `CAF3349…E8DC68` hash.

The exact detached `2800742` checkout built successfully through the checked-in
Staging helper with temporary storage on D: (Gradle 92.3 seconds). The x86_64
debug APK is 127,488,978 bytes, SHA-256
`13ECE089A7756125AB6DA18BDFF81E40F2FD4762B739E0D7384BC2C23B462859`,
package `com.postdee.postdee_mobile.staging`, version code 4001 / `0.1.0-staging`.
API/Firebase configuration and validated RevenueCat Test Store settings match
the prior build; the certificate remains
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
Build artifact:
`D:\PostDeeMobile\.tmp\caption-subscription-20261009\verify-worktree\apps\mobile\build\app\outputs\flutter-apk\app-x86_64-debug.apk`.
Installation with `adb install -r` succeeded; the pulled installed base APK at
`D:\PostDeeMobile\.tmp\caption-subscription-20261009\package-refresh-installed-20261009.apk`
matches the same hash and byte size.

Native launch showed PostDee, Splash, then Staging Login. The session did not
restore to authenticated UI, and no authentication control was pressed. The
new Home/composer refresh smoke and paid AI remain unverified; the original
app's Pro-to-Free observation above is separate evidence. No app-data clearing,
uninstall, mobile logout, draft save, post, purchase or live resync was performed.
The app was left at Login. This fix is installed locally and has not been
pushed/deployed.

The backend remains Live at `f6bf0f9`; no new push/deployment or package/API
policy change was made. A possible follow-up is one existing authenticated
server resync when AI preflight sees Basic with RevenueCat enabled, followed by
a fresh subscription GET while retaining the paid gate. This was not
implemented: it would not invoke SDK Restore/purchase or remove the gate.

### Follow-up: bounded AI entitlement reconciliation (automated checks pass)

The user's subsequent instruction to continue authorized this mobile follow-up
from audit HEAD `6f6e018`. The earlier recommendation-only receipt above remains
historical. After a successful initial subscription GET reports AI access
disabled, and only with RevenueCat enabled, the implemented preflight calls the
existing authenticated server resync once per Generate action, then fetches subscription
again. It ignores the resync reply's plan; the second GET controls the unchanged
paid gate and Pro-frame choice. Paid users, disabled RevenueCat and a failed
initial GET add no resync. There is no automatic retry loop or reconciliation
of a later caption `402` after upload; the AI provider is not retried.

Resync or fresh-read failure stops before AI media/generation and reports Thai
rights-verification unavailability with user-triggered retry. It preserves the
current caption and owner/generation/source guards. No SDK Restore, purchase,
free grant, quota, package, API route/response, schema or key-handling change is
introduced. The server subscriber lookup remains bounded to 8 seconds, ordinary
client JSON requests retain their 20-second deadline per request, and resync
shares the existing per-IP 10-requests-per-10-minutes limit per API instance.

The five related product/API/architecture/package documents are synchronized.
The new 24 regressions first produced eight passes and 16 failures, then all
24 passed. Together with 75 existing targeted cases, 99 pass. The unchanged
backend RevenueCat contract passes its 21 targeted tests. Full Flutter analysis
reports no issues (20.1 seconds); the serialized full suite passes 1,744/1,744
with `--concurrency=1`, exit 0, in 4m40s. An initial concurrency-2 run alongside
analysis hit Windows VM memory pressure with two worker-load interruptions and
was cancelled; no semantic assertion failure is inferred from that resource
interruption. The completed serial run supplies acceptance evidence. Logs:
`D:\PostDeeMobile\.tmp\caption-subscription-20261009\flutter-resync-full-test-serial-20261009.log`
and `flutter-resync-analyze-20261009.log` in that same directory.

The prior Login and signed-in Account Pro observations are historical. Fresh
pre-install inspection showed cached Account Pro, then Home loaded Free 0/3,
then Account loaded Free 0/3. No login, purchase or draft save was performed.
This display does not establish the new resync end-to-end result. No
push/deployment occurred in this task; no API, schema, credential or
configuration flag changed. Live entitlement reconciliation and native paid
end-to-end checks remain pending.

### Exact-source resync APK receipt

Local source commit `24266aa218d63646eea26989f636b4452e50e823`, tree
`2c90f54fa3bd000183bae8c1f1c926eea9be5b50`, uploader blob
`2ceffcf59b9b1e24f9b5ce4277dd1504605a381e` built from a fresh detached
`verify-resync-worktree` on D: through the checked-in Staging helper. The x86_64
split debug build took 72.1 seconds and exited 0. Log:
`D:\PostDeeMobile\.tmp\caption-subscription-20261009\resync-apk-build-20261009-172231.log`.
The APK is 127,489,846 bytes, SHA-256
`51D074EB6940F41C7F1A324158552B51939672283103A9390DF1C61EE9BA8D5F`,
package `com.postdee.postdee_mobile.staging`, version code 4001 /
`0.1.0-staging`. Its certificate remains
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
Staging API/Firebase configuration matches project
`project-798caf7e-85b8-45e3-af7`, mock auth/plan are off, RevenueCat is enabled
through the existing validated Test Store overlay, and experimental features
remain off.

`adb install -r` succeeded without app-data clearing. The pulled installed APK
at `D:\PostDeeMobile\.tmp\caption-subscription-20261009\revenuecat-resync-installed-20261009.apk`
has the identical hash. Package metadata reports last update
`2026-10-09 10:25:10 UTC`; first install remains `2026-10-05 06:30:36 UTC`.
The new launch reached Splash and then signed-in Home, as recorded below.
Active-paid AI reconciliation/generation remains unverified. The existing
Staging `/health` returned 200/ok but exposes
no source commit, so it is not a version proof. No backend change, migration,
new key, global configuration change, cache deletion, push or deployment was
performed in this follow-up.

### Native denied-rights smoke on the resync APK (2026-10-09)

The verified `24266aa` APK launched Splash then signed-in Home displaying Free
0/3, preserving the existing account without a login action. A blank composer
showed the unchanged count of two existing drafts. The original clip 96 was
not found in Recent, so the tester selected the pre-existing owned QA video
`postdee-nav-motion-final.mp4` through Android Files. No new QA media was
generated or draft saved.

At caption step 2, Generate AI was pressed exactly once at about 17:30 GMT+7.
The final UI showed
`AI แคปชั่นใช้ได้ในแพ็กเกจ Starter หรือ Pro กรุณาตรวจสอบแพ็กเกจของคุณ`;
the caption stayed blank, the button was enabled and the spinner was gone.
No verification-unavailable message appeared. This verifies native Free/denied
gating and button usability, not active-paid reconciliation or AI generation.

Automated tests assert GET1 → resync → GET2, and the production wiring plus
RevenueCat-enabled build configuration were reviewed. No live HTTP request
trace was captured: this native observation does not establish that network
sequence, current RevenueCat expiry/customer identity, upload activity or a
provider call. No caption was generated. The tester closed this owned blank QA
form with X and explicitly chose `ออกโดยไม่บันทึก`. Home displayed Free 0/3
with no posts; fresh Account also displayed Free 0/3, then Home again showed
Free 0/3 and was left open. Two saved drafts were visible before/during the QA
form; the draft count was not rechecked after exit. No save, login, purchase,
Restore or social-publish action was performed.
Active-paid reconciliation/generation end-to-end remains pending with the
current fresh Free display; no paid access is granted by this smoke test.

### Authorized Home/AI entitlement Staging delivery (2026-10-09)

The user's subsequent authorization delivered audit-branch source
`c8e463d2a82ab69e4c952b4da5f77d05e9a1684f` to
`codex/audit-system-fixes`. Earlier no-push/deployment statements describe
their respective local runs. Remote `main` remains `c4e5220`; there is no main
merge or Production delivery. API, Render and workflow files are unchanged
from `f6bf0f9`; no new migration, environment, credential or package policy
change accompanies this delivery.

Exact-source CI `37918977276` completed successfully in both jobs: 1,716 API
tests plus 22 generator tests, 1,744 Flutter tests and clean Flutter analysis.
CI APK building was disabled; this does not replace the validated local APK.

[Render deploy `dep-db4ccku0tbcc73dtlasg`](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db4ccku0tbcc73dtlasg)
is Deploy succeeded / Live at the exact source above. The UI deployed timestamp
is 2026-10-09 17:47:47 GMT+7 and duration is 1m51s. Logs show build success at
17:48:25, 16 migrations with none pending at 17:48:45, API port 10000 with the
memory scheduler and social publishing disabled at 17:49:31, and service Live
at 17:49:38. Local proof:
`D:\PostDeeMobile\.tmp\caption-subscription-20261009\revenuecat-resync-render-live-20261009.png`.

The installed APK remains the exact `24266aa` artifact, SHA-256
`51D074EB6940F41C7F1A324158552B51939672283103A9390DF1C61EE9BA8D5F`.
The `24266aa` to `c8e463d` diff contains only the six related documentation
files, so the installed mobile runtime is identical. Its native Free/denied
gate, button usability and final Home/Account consistency evidence above
remain valid; this deployment does not add active-paid reconciliation or
generation acceptance. Public Staging browser checks remain skipped under
the existing block: no new health/readiness result or live HTTP sequence is
claimed. Active-paid AI end-to-end and live HTTP tracing remain unverified.

### Follow-up: caption presets and remembered human edits (local checks/APK pass; native pending)

The user selected caption-style presets plus remembering human edits. Work
starts from audit HEAD `a1384d2`; freshly fetched `origin/main` remains
`c4e5220`, with the audit branch 12 ahead / zero behind. This follow-up is
separate from the delivered `c8e463d` receipt above and has no push/deploy
authorization yet.

The additive optional `writingStyle` object accepts tone
`auto/friendly/playful/direct_review/soft_sell`, length `auto/short/medium`,
emoji `auto/none/light`, and at most three trimmed nonempty example strings,
each at most 500 UTF-16 code units. Missing fields default to auto/empty;
omitted style preserves legacy behavior. Invalid supplied style returns 400
within the existing paid flow, before media/quota work; unknown extra fields
are ignored. The prompt requests 1–2 sentences for auto/short, 3–4 for medium,
with no fact padding. Presets outrank examples; examples are untrusted writing
form, not instructions, clip facts or language overrides. Local fallback is
unchanged/labeled. No live style-compliance or instruction-isolation guarantee
is claimed, and no training or additional model call is added.

Mobile retains a version-1, stable-UID-scoped SharedPreferences profile for
selected settings and up to three latest unique human-edited examples. Local
normalization trims/bounds stored examples to 500 UTF-16 code units without
splitting a surrogate pair. Remember-edits defaults on with a visible switch;
off sends no examples and learns none. Clear memory preserves manual presets.
Learn only when an accepted non-fallback AI baseline is edited, same owner and
source with review cleared, then Next moves caption to platforms. Progress
jumps, saves, cancellation, unchanged AI and fallback do not learn. The profile
is device-local, but settings/examples accompany manually requested generation
to the configured AI; there is no cloud profile or social-history import.

After successful backend DELETE, Shell clears the UID captured before awaiting
deletion, even when auth is already gone. Store deletion invalidates pending
work; other owners' keys remain. Remote deletion failure retains local style.
The incomplete-cleanup warning now names local data rather than only drafts.
Shell's targeted TDD was one pass/two failures before implementation, then
three passes; its scoped diff check passes. Final targeted coverage passes:
128 UI cases (23 new and 105 existing), 15 store cases and three Shell cases.
Backend checks pass:
110 targeted, 1,781 full API tests across 109 files, build, Prisma validation
and helper TypeScript checks. API files are unchanged from the verified feature
source; the API checks were captured as tool outputs, not a separate log file.

The final runtime source is `089dcb52ff00590972759c736cc254d3f2e98457`:
feature commit `111819d` plus braces-only lint fixes on six guards. A fresh fetch
still shows `origin/main` at `c4e52201a58b556f5f47529027549a2fc16af84c`,
with this source 14 ahead / zero behind. Final-source Flutter passes
1,783/1,783, exit 0, in 4m43s; analysis reports no issues, exit 0, in 11.3s.
Logs:
`D:\PostDeeMobile\.tmp\caption-writing-style-20261009\flutter-test-final-source.log`
and `flutter-analyze-final.log` in the same directory. The first full run on
`111819d` had 1,782 passes and one Windows errno 32 temporary-file deletion
failure in the unchanged deadline test. Its isolated eight deadline cases
passed, then the full `111819d` suite passed 1,783, followed by the final-source
full pass above. No test suppression or deadline patch was used.

The exact-source `089dcb52` Staging APK build passed, exit 0, in 110.3s through
the checked-in helper
with `--no-pub --split-per-abi --target-platform android-x64 --build-number 4002`,
TEMP/TMP on `D:\Temp`, Gradle cache on D: and the existing SDK on C:.
Artifact:
`D:\PostDeeMobile\.tmp\caption-writing-style-20261009\verify-worktree\apps\mobile\build\app\outputs\flutter-apk\app-x86_64-debug.apk`,
SHA-256 `19E4916D6A7F0FF58F4D60601815946E5B7CD0A481E645A244020E51672ED438`.
`aapt` verifies package `com.postdee.postdee_mobile.staging`, version name
`0.1.0-staging` and version code 8002: the x86_64 split adds 4000 to build number
4002. Minimum SDK is 24, target/compile SDK is 36, and the launch activity is
`com.postdee.postdee_mobile.MainActivity`. `apksigner` verification passes;
new and existing APK certificates share SHA-256
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
The helper validates the example configuration and existing common RevenueCat
test overlay without recording its key. Its API is
`https://postdee-api-staging.onrender.com`, with Firebase project
`project-798caf7e-85b8-45e3-af7`, real Firebase enabled, local mock disabled,
and RevenueCat using that validated test overlay. Existing Kotlin Gradle Plugin,
Java 8 and deprecation warnings remain; there is no compile failure or plugin
upgrade. The required local profile-template generator tests also pass 22/22,
exit 0, on `089dcb52`; log `profile-template-generator-test.log` is in the same
receipt directory. This is local verification, not a new CI delivery.

Native installation/acceptance remain pending. At the read-only `native-before.png`
observation, the emulator had a clip/caption form open; whether its latest edits
were saved was not confirmed. Installed version 4001 remains in place;
read-only ADB hashing confirms its APK SHA-256
`51D074EB6940F41C7F1A324158552B51939672283103A9390DF1C61EE9BA8D5F`.

Native acceptance, real paid AI/style-quality, live HTTP tracing and deployment
remain pending. Deploy the supporting API before installing/shipping this
mobile feature; older servers ignore `writingStyle`. No price, paid gate,
quota, model/retry/provider, route, schema, environment or credential change is
introduced. Prior limited caption-quality probes and active-paid AI/HTTP-trace
gates remain unchanged. This feature has not been pushed/deployed. No customer
write, real provider call, purchase, social import/channel read, account deletion
or AI training was performed for this follow-up.
