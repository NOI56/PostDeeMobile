# Support chat room — 2026-10-28

Status: review candidate on branch `claude/support-chat`, stacked on
`claude/service-status` (phase 1, PR NOI56/PostDeeMobile#38, still open when this
was cut). Not merged or deployed. Phase 2 of the support chat plan
(`ROADMAP.md`, "Support chat with an AI helper").

## 2026-10-29 admin alert follow-up (local candidate)

The earlier status and verification entries below describe the phase 2
snapshot. This follow-up adds administrator alerts without changing the
member message API, Dot switches or team-reply notification behavior.

- `GET /admin/api/support/pending-count` returns `{count, checkedAt}` only to
  authenticated owners/viewers, private/no-store. It counts `WAITING_TEAM`
  conversations across all pages/filters, not unread messages. Opening a
  thread does not clear it; existing status changes determine the count.
- The admin navigation badge polls independently every 30 seconds while
  visible, on login/resume and after reply/close. It displays `99+`, marks
  stale reads and preserves open conversations, filters and drafts. Reads
  stop while hidden/logged out; late responses cannot cross sessions.
- Only actually created member messages trigger a best-effort generic Firebase
  push to deduplicated configured owner/viewer UIDs with registered Mobile
  devices. Same-id retries do not retrigger. Payload data uses the recipient
  administrator's `userId` and `type: support_new_message`; no member identity
  or message body appears. Handoff-only requests update the count without
  another push.
- Reuses `PUSH_SENDER=firebase`, existing messaging credentials and Mobile
  device registration. Administrators must sign into Mobile in the same
  Firebase project and opt in to notifications. No new environment key,
  schema migration, Mobile build or browser notification permission.
- Tapping an administrator push opens Mobile, not the admin web inbox.
  Delivery is best effort; the pending count is the outstanding-work source.

Acceptance still needs recorded evidence for member send -> administrator
device alert and web count -> reply/close -> count update, including same-id
retry and an administrator who has no registered device. Local unit/route
checks alone do not establish real Firebase delivery or production readiness.

Local candidate validation on 2026-10-29 used the verified `db353719` baseline
and Node 22.23.3, matching the Render runtime. The full API suite passed 2,952
tests (66 skipped); typecheck, build, Prisma validation and Prisma helper
typechecking passed. A fresh isolated PostgreSQL 18.1 fixture applied all 28
migrations and passed all 34 tests in the five administrator/support/status
database suites. The fixture was stopped after verification; application
databases were not used. Browser fixture checks verified the waiting count at
desktop size and 390px width without horizontal page overflow or application
console errors. Real staging workflows and Firebase device delivery remain
pending and must be recorded separately.

## Goal

A member can ask the PostDee team for help from inside the app, and the team
answers from the admin console. Phase 3 adds an AI helper that answers first
from the phase 1 service notices; this phase is human-only.

## Decisions

- One continuous conversation per member (like a shop chat). A member message
  reopens a closed conversation.
- Owners and viewers can both reply and close (agreed in the plan review);
  service notices stay owner-only.
- Members never see which administrator replied ("ทีมงาน PostDee"); the admin
  console marks the caller's own replies as "คุณ".
- Polling, not sockets: Mobile polls every 5 seconds while the chat is open
  and the app is in the foreground; the admin conversation polls every 10
  seconds and repaints only the message log so a reply being typed survives.
- Every message has a client-made UUID; a retry with the same id returns the
  stored message, so lost responses never duplicate messages or pushes.
- Close needs the id of the last message the administrator saw, so a member
  message that arrives meanwhile is never hidden by a close.
- Limits: 1–1000 characters, text only, 100 member messages per rolling 24
  hours, 20 sends per minute per client.
- The reply push is generic ("ทีมงาน PostDee ตอบกลับแล้ว") so conversation
  text never shows on a lock screen.
- Account deletion: both tables cascade from `User`; the memory store is
  cleared by the deletion saga. Prisma writes take the active-owner lock.

## Changes

- API: `apps/api/src/modules/supportChat` (types, validation, memory and
  Prisma stores, member routes), `supportReplyNotifier`, admin `support` view
  and `support/thread|reply|close`, app and account-deletion wiring, local
  admin preview fixture.
- Database: migration `20261028020000_support_chat` with CHECK constraints for
  status, sender, author and length.
- Admin console: "แชทช่วยเหลือ" tab with status filter and search, chat drawer
  with reply, retry-safe send and close.
- Mobile: `loadSupportChat` / `sendSupportMessage`, `SupportChatScreen`,
  "แชทกับทีมงาน" row under Account help, help text points to the chat.

## Verification

- API unit/route tests; Prisma store tests on a throwaway PostgreSQL 18 fixture
  cluster (`ADMIN_TEST_DATABASE_URL`, 127.0.0.1:55439): concurrent duplicate
  sends, daily cap, cursor polling, close-only-what-was-seen, writes refused
  during account deletion, cascade on user delete, database constraints.
- Admin console exercised in the local preview (list, open, reply, close).
- Mobile widget tests (load, send, same-id retry, discard, polling with
  lifecycle pause, daily limit, load retry, profile entry) and real-font light
  and dark large-text captures.

## Deployment order

1. Merge phase 1 (#38) first, then this branch.
2. Deploy the API (Staging deploys are manual); the migration runs on deploy.
3. Smoke-test on Staging: send a message from a test account, answer and close
   it in `/admin`, confirm the push arrives when `PUSH_SENDER=firebase`.
4. Ship a Mobile build for the chat entry.

## Follow-ups

- Tapping the reply push opens the app but not the chat yet.
- The privacy policy should mention that support messages are stored and
  deleted with the account (and, in phase 3, processed by the AI provider).
- Administrator alerts are covered by the 2026-10-29 candidate above; real
  device delivery and staging acceptance must be recorded separately.

## Not verified yet

- Staging deploy, real Firebase push delivery, and the chat on a device.

## 2026-10-29 staging validation checkpoint

This checkpoint updates the earlier phase 2/local-candidate entries above;
it is not a final production acceptance receipt.

- Baseline: branch `codex/admin-support-alerts` starts from verified
  `origin/main` commit `db353719143d2e5c288a05b15b78e9912d1b288e`.
  Runtime commit `7b8ac533af7b2989a85627ad0dd20440924e5a31` was pushed and
  deployed to staging with the user's explicit authorization. The change is
  under [draft PR #41](https://github.com/NOI56/PostDeeMobile/pull/41); it has
  not been merged to `main`, and production was not changed.
- Render deploy `dep-dbh3i8ec6qcc73cg35c0` became Live on 2026-10-29 at
  01:05:38 GMT+7. Before deployment, the existing `PUSH_SENDER` value changed
  from `mock` to `firebase` using **Save only**. All 60 environment keys were
  retained and no other environment value changed. This alert change adds no
  migration; startup found all 28 existing migrations applied with none
  pending. `/health` and `/ready` returned 200 with database and queue healthy.
  `/admin/config` identified `STAGING` and Firebase project
  `project-798caf7e-85b8-45e3-af7`.
- Mobile validation used Flutter 3.44.1 / Dart 3.12.1: the full suite passed
  3,194 tests, with 6 skipped and 0 failures, and `flutter analyze` passed.
  The lockfile stayed unchanged and there is no diff under `apps/mobile/lib`
  against the baseline. The exact-branch debug APK built successfully with
  version code `12079`, package `com.postdee.postdee_mobile.staging`, and
  packaged Firebase project `project-798caf7e-85b8-45e3-af7`. The build used
  the staging API define file, `POSTDEE_STAGING_BUILD=true`, and the existing
  RevenueCat Test Store overlay. APK SHA-256:
  `949337E29471FEBDEED2DE0A76F55F42C52F4FDAC82D3675A346DA3F84388492`.
  Installation on the member test device preserved its existing package UID
  and storage volume. Mobile acceptance remains pending its Google sign-in;
  a successful build and installation do not establish device smoke results.
- GitHub's Backend API and Flutter Mobile checks succeeded for runtime commit
  `7b8ac533af7b2989a85627ad0dd20440924e5a31`. A subsequent fetch still found
  `origin/main` at the verified baseline above.
- Browser fixture checks passed at desktop and 390px widths, including
  preservation of an open reply draft during badge refreshes.
- On staging, only the designated test member received a Pro trial: a 7-day
  grant at 01:19 GMT+7 on October 29 ended November 5 at 01:19, a 7-day
  extension moved the end to November 12 at 01:19, and revocation at 01:23
  showed **ยกเลิกแล้ว** in the admin UI. The purchased plan remained `BASIC`;
  displayed selected-channel usage stayed at 15 units and AI-caption usage
  at 13. The filtered admin audit trail contains the three new UAT actions
  with the expected before/after dates and cancellation state; the older
  historical grant remains present. Propagation of the trial changes into
  Mobile has not been verified.
- CSV: the user reported that the report downloaded, but tooling observed no
  download event and had not located the saved file. Actual file contents
  remain unverified; CSV acceptance is not marked passed.
- Real push/chat acceptance remains pending. The administrator's Android
  notification permission was disabled at the pre-test check. A Google-only
  test-member login on the test Android virtual device was still pending
  manual Google account setup. No chat messages or service incidents had
  been created for this validation at this checkpoint, and actual Firebase delivery to an
  administrator device has not been established.
