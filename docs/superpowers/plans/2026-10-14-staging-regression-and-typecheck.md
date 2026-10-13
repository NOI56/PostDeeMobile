# Staging regression and test-inclusive TypeScript follow-up

Date: 2026-10-14 (Asia/Bangkok).

Status: LOCAL FOLLOW-UP. Test typing, local database concurrency verification,
native draft/clip guards and Staging R2 part transfer/recovery/abort pass.
Upload completion and real-account deletion remain unverified. No main merge,
push, deploy, new APK installation
or hosted feature activation belongs to this follow-up.

## Baseline and scope

- Verified remote main:
  `f07ee30229436a20642215d8f2d8aa3d364c2a5d`.
- Local branch: `codex/staging-regression-and-test-types`.
- Isolated checkout:
  `D:/PostDeeMobile/.tmp/security-followup-validation/route-fixture-check`.
- Preserve the original dirty worktrees, historical audit and delivery receipts.
  The original partial audit remains 0 confirmed, 19 needing validation and
  2 rejected; this focused follow-up does not replace it or run a new full audit.
- Change test fixtures, the verification script/CI step and related documentation.
  API runtime, schema, environment settings, dependencies, lockfile and mobile
  source remain identical to the baseline. No migration is required.
- Existing Staging delivery source `3481f3f` and its 17 applied migrations are
  the environment tested. Earlier delivery details remain in
  [the authorization plan](2026-10-14-account-deletion-authorization.md).
  Production remains suspended and receives no changes.

## Test typing repair and verification

The production build excludes tests, so its previous success did not detect
142 test-inclusive TypeScript errors already present on main. Align fixtures
with the actual repository, provider and queue interfaces without weakening
assertions or compiler settings.

- Baseline: the full `tsconfig.json` check reproduced 142 errors on fresh main.
- Repair 26 `.test.ts` files and add typed repository fixtures in
  `apps/api/test/repositoryFixtures.ts`. Unarranged Prisma delegates throw;
  transaction overrides and call assertions remain intact. The parameterized
  Thai punctuation cases now receive their intended fragment arrays.
- Add `npm run typecheck` (`tsc --noEmit -p tsconfig.json`) and run it in CI
  immediately after Prisma client generation. The new CI step is local and
  has not run on hosted CI yet.
- Targeted tests: 474/474 pass. Full API tests: 1,871/1,871 in 116 files pass.
- `npm.cmd run typecheck`, `npm.cmd run build`,
  `npm.cmd run prisma:validate` and `git diff --check` pass.
- Prisma seed/config helper TypeScript checking passes. Parsing the CI YAML
  and checking the Prisma generation/typecheck step order and package command
  passes locally. No hosted CI run is claimed.
- Independent review found no blocker, removed/weakened assertions, suppression
  directives, added `any` escape or relaxed strictness in the typing repair.
- Verification logs: `D:/PostDeeMobile/.tmp/staging-followup/`, including
  `types-red.log`, `types-green.log`, `types-targeted-tests.log`,
  `api-full-tests.log`, `api-typecheck-final.log`, `api-build-final.log` and
  `api-schema-final.log`, `api-prisma-helpers-final.log` and `ci-yaml-final.log`.

## Existing native Staging app

Use the retained Android package `com.postdee.postdee_mobile.staging`, installed
version code `12019`, against `https://postdee-api-staging.onrender.com` and
Firebase project `project-798caf7e-85b8-45e3-af7`. This is compatibility testing
of the existing installation; no new APK or full mobile suite is claimed here.

- The existing logged-in session survives an app restart.
- Shop `noikub` retains its two links and owner-scoped local draft. Save the
  existing draft unchanged, restart and reload it, then temporarily edit the
  shop name and restore it. The complete stored draft hash matches the original
  after restoration, including its original appearance settings.
- Do not publish the shop draft or replace it with server data: the retained
  draft already contains the user's unpublished changes.
- Select only a generated one-second H.264/AAC clip: 180 x 320 pixels, 9:16,
  30,199 bytes. The native composer renders matching metadata, accepts a manual
  test caption and reaches destination selection. Zero connected destinations
  prevents review with `เชื่อมและเลือกอย่างน้อย 1 ช่องทางก่อน`.
- Discard only this new unsaved composer input; its saved-draft count stays zero.
  The original shop draft and owner hashes still match after all native checks.
- Local native evidence: `D:/PostDeeMobile/.tmp/staging-followup/native/`.
  Keep tokens, email addresses, UID values and signed URLs out of tracked docs.

## Authenticated Staging upload probe

Use the retained app's normal `currentIdToken()` Firebase refresher through its
debug VM service. Keep credentials and the VM/signed URL tokens in memory only;
remove the temporary ADB forward afterwards. Verify the token's project and
same owner as the original native shop draft before any upload request.

- `/auth/me`: HTTP 200, same owner.
- Deletion readiness: HTTP 503, `ACCOUNT_DELETION_UNAVAILABLE`.
- Publishing readiness: HTTP 503, `SOCIAL_PUBLISHING_UNAVAILABLE`.
- Create one managed multipart session in the `postdee-staging` R2 bucket.
  Upload its only part: HTTP 200, all 30,199 synthetic bytes transferred and
  the ETag matches their MD5. Recover the session as `UPLOADING`.
- Abort that session: HTTP 200, then read `ABORTED`. Preparing another part
  returns HTTP 409 and reusing its old signed R2 part URL returns HTTP 404.
- Result: `PASS`. No upload completion or completed video object, AI request,
  social post, purchase, shop publication or account deletion is performed.
- Three preparatory upload sessions also received HTTP 200 on abort after the
  probe's URL/status assumptions failed. Earlier VM inspection/refresh attempts
  failed before creating sessions. These probe failures are not recorded as
  application defects.

Receipt: `D:/PostDeeMobile/.tmp/staging-followup/staging-upload-receipt.json`.
SHA256: `15F711421B601F93D42CD28F3BCE8DD9910DB018CBDF134812E8A8104B77CB61`.
This verifies a part transfer and cancellation against real Staging R2, not
complete-upload acceptance or end-to-end social publishing.

## Two-process database verification

Run an isolated PostgreSQL 18.1 database on `127.0.0.1:55443` with all 17 actual
migrations and two independent Node processes/Prisma engines. This is separate
from the earlier two-client check. No live database, Redis, Firebase or provider
is used; source is unchanged. Its seven checks are:

1. Own loopback PostgreSQL database with all 17 migrations.
2. Two independent Node processes and Prisma engines.
3. An admitted final SQL User write commits before a separate process authorizes
   deletion. PostgreSQL shows that deletion waiting on `Lock/transactionid`.
4. A `DELETED` owner rejects User/Post/Subscription recreation and new remote
   operation admission from the other process.
5. A `DELETING` owner likewise rejects late durable writes and new remote
   admission with `ACCOUNT_DELETION_IN_PROGRESS`.
6. Concurrent authorization preserves one committed first proof and UID
   isolation.
7. An IPC simulation confirms the enablement gap: an already-admitted non-SQL
   operation can finish after another process has marked its owner `DELETED`.

Result: `PASS_WITH_ENABLEMENT_GAP`. The final case is a controlled IPC simulation,
not a real Redis/provider test or proof of a live exploit. All test processes
and the owned PostgreSQL server were stopped; the port is free and local evidence
is retained.

Receipt:
`D:/PostDeeMobile/.tmp/staging-followup/concurrency-20c4bb5b-df50-463e-899b-a8bccbb7ecd8/concurrency-receipt.json`.

SHA256:
`83D0055E2EF259105AB220D0BA598A58F337C951C282E2F0129A1E527AEAAA20`.

## Prepare a disposable Staging account

The user has no disposable account and requested preparation only. No account
is created, signed out, deleted or reconfigured in this task. These are future
execution steps, after the user authorizes account creation:

### ขั้นตอนในแอปสำหรับผู้ใช้ (เตรียมไว้ ยังไม่ได้สร้างบัญชี)

1. ใช้ Emulator แยก เปิดแอปที่มีป้าย **STAGING** และตรวจระบบตามข้อกำหนดด้านล่าง
   ไม่ออกจากบัญชีในแอปปัจจุบัน
2. กด **เข้าสู่ระบบด้วยอีเมล** แล้ว **ยังไม่มีบัญชี? สร้างบัญชีใหม่**
3. ในหน้า **สร้างบัญชีด้วยอีเมล** กรอกอีเมลทดสอบที่คุณควบคุมและรหัสผ่านใหม่
   ที่คาดเดายาก แล้วกด **สร้างบัญชี** ไม่ใช้อีเมลร้านหรือบัญชีที่มีข้อมูลสำคัญ
4. หากต้องยืนยันอีเมล ไปหน้า **บัญชี** กด **ส่งอีเมลยืนยัน** เปิดลิงก์ในอีเมล
   แล้วกลับมากด **ตรวจสอบการยืนยัน**
5. ตรวจว่าบัญชีใหม่ว่าง ไม่มีโพสต์ การซื้อหรือข้อมูลสำคัญ แล้วหยุดไว้ก่อน
   ยังไม่เชื่อมร้านจริงหรือกดลบบัญชี

ชื่อปุ่มตรวจจากโค้ดหน้าล็อกอินปัจจุบัน ยังไม่ได้เปิดหน้าสมัครบนบัญชีจริง
และยังไม่ได้ยืนยันว่า Firebase Staging เปิด Email/Password provider อยู่
หากไม่รองรับ ให้บันทึกข้อผิดพลาดไว้ก่อน อีกทางที่โค้ดรองรับคือ
**เข้าสู่ระบบด้วย Google** โดยใช้ Google ทดสอบที่เพิ่มไว้บน Emulator แยก
ยังไม่ต้องเปลี่ยนการตั้งค่า Firebase เพื่อทดสอบนี้

### Environment and isolation checks

1. Use a separate emulator/device for the Staging app so the retained current
   account, drafts and uploads stay intact. Confirm the package suffix
   `.staging`, visible STAGING banner, API URL and Firebase project above before
   signing in. Stop if any setting identifies Production or another project.
2. Use a new dedicated test identity the user controls through an already
   enabled Firebase sign-in provider. Keep its credentials in the user's
   credential manager; never put a password, ID token or service-account key
   into a plan, repository, screenshot or test log.
3. Confirm the new account is separate from the current owner and has no
   valuable posts, shop data, local drafts, purchases or active subscription.
   Record a redacted baseline of owner status/proof, owned row counts,
   queue jobs and managed-upload sessions/prefix; retain exact identifiers only
   in private local evidence needed for cleanup.
4. Seed only explicitly identified synthetic fixtures if later authorized:
   a short generated video, test draft and disposable shop content. Connect a
   disposable social identity only if provider cleanup is part of the approved
   test; never connect a seller's real account or buy a subscription.
5. Keep a second disposable owner as the isolation control when later authorized.
   Compare its protected data before/after; denied cross-owner operations must
   not create authorization, remove rows/media or invoke cleanup for that owner.
6. Stop after account preparation and readiness checks. With current settings,
   deletion readiness must remain unavailable; do not turn a failed readiness
   response into a deletion attempt or enable a flag as a workaround.

## Gates before real deletion or multi-process enablement

Keep `FIREBASE_AUTH_DELETE_ENABLED=false`, `SOCIAL_PUBLISHER=disabled` and the
existing single-instance memory queue. No shared lease/drain implementation is
included. The API/architecture contracts are unchanged and still describe the
process-local limitation.

1. Design and implement shared operation lifetime coordination for remote work
   admitted before deletion, including workers, late queue admission and crash
   recovery. Rejecting new work through an owner marker alone does not drain
   a provider call already running elsewhere. Cover remaining mutation stores
   and managed-upload admission at the same required boundary.
2. Test actual Redis/BullMQ with separate API/worker processes, delayed provider
   responses, process crashes and cleanup retry. Establish that work cannot add
   data or remote effects after the deletion cleanup boundary, or is reconciled
   before deletion reports success.
3. Use the prepared empty Staging account only after explicit authorization for
   feature enablement and destructive deletion. Verify recent authentication,
   stored same-UID proof, provider/R2/queue/database cleanup, Firebase identity
   deletion last, authorized retry and the unaffected isolation owner. Do not
   manually stamp a missing proof or backfill legacy tombstones.
4. Record exact app/API source, flags, migration state and redacted counts;
   verify cleanup and restore approved Staging settings. Physical-device,
   slow-network and provider-specific acceptance remain required before
   Production. None of these checks resumes Production.
