# Support chat room — 2026-10-28

Status: review candidate on branch `claude/support-chat`, stacked on
`claude/service-status` (phase 1, PR NOI56/PostDeeMobile#38, still open when this
was cut). Not merged or deployed. Phase 2 of the support chat plan
(`ROADMAP.md`, "Support chat with an AI helper").

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
- Administrators get no alert for new chats yet (phase 4).

## Not verified yet

- Staging deploy, real Firebase push delivery, and the chat on a device.
