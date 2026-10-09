# System audit fixes — 2026-10-09

## Scope and baseline

The user authorized the five-round plan after a read-only page audit. Start from
remote-verified main `c4e52201a58b556f5f47529027549a2fc16af84c` in an isolated
`codex/audit-system-fixes` worktree. Preserve all unrelated work, the five-tab
dock, full-screen composer, 100 profile templates, captions, current entitlement
windows and owner mutation/deletion barriers. Real posts, payments, OTP,
connections and shop publication are outside the read-only test authorization.
There is no push, merge, deployment or database mutation in this implementation.

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
Live Staging remains the prior release with social publishing disabled. A
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

New migrations and raw SQL were validated/covered with test doubles, not run
against real PostgreSQL. R2 delete/upload, real purchase/restore/acknowledgement,
OTP/email delivery, two-account/background FCM delivery and real platform
publication are still service acceptance gates. The new API is not deployed.
The emulator APK is for local read-only screen checks against the existing
Staging service; new write contracts require the API rollout above.

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
