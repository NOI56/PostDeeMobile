# Dot, the AI support helper — 2026-10-28

Status: review candidate on branch `claude/support-bot`, opened as a pull
request stacked on `claude/support-chat` (phase 2, PR NOI56/PostDeeMobile#39),
which is stacked on `claude/service-status` (phase 1, #38). Neither earlier PR
was merged when this was cut. Not merged or deployed. Phase 3 of the support chat plan
(`ROADMAP.md`, "Support chat with an AI helper").

## Goal

Members get an immediate, grounded answer in the support chat. The team is
currently one person, so Dot answers most chats itself, including what is
broken right now (service notices and Sentry signals), and flags a chat for
a person only when someone has to act.

## Safety and security plan

- **Off by default, twice.** `SUPPORT_BOT_PROVIDER` defaults to `off`, and even
  when it is `openai` nothing answers until an owner turns the global switch
  on in the admin console (no row = off). The console asks the owner to confirm
  that the privacy policy covers sending chat text to OpenAI.
- **No actions.** Dot has no tools. It can only write text; it cannot read or
  change the account, refund, grant credits, change plans or retry posts.
- **Grounded context only.** Open service notices, FAQ facts built from the
  enforced plan-limit constants, the member's plan, and the last five posts'
  statuses with failure reasons translated through the fixed admin mapping.
  No email, name, phone, account id, caption text or raw provider error is
  sent.
- **Scrubbing.** Emails, phone numbers and long digit runs in the conversation
  are replaced before the request; only the last 20 messages are sent.
- **Handoff.** Dot sets `handoff` only when a person must act: an explicit
  request, a payment/refund/billing problem that needs the account checked,
  or an account problem nothing in its data explains. It still gives general
  steps. A handoff or the member's "ขอคุยกับทีมงาน" sets `teamRequested`
  (thread stays `WAITING_TEAM`); Dot keeps answering and is told the team
  already knows. A team reply clears the flag; only the admin per-thread
  switch silences Dot.
- **Sentry signals.** With `SENTRY_SIGNALS_TOKEN` (read-only, `event:read`),
  one issue search per area over the safe Sentry tags, cached 2 minutes,
  5-second timeout. Dot sees only a fixed Thai area label and last-seen time
  and must say errors were detected, without naming a cause, a fix time or
  that someone is working on it unless a notice says so. Issue titles and
  links are shown only to administrators. The token never leaves the server
  and is never logged.
- **Failure and cost bounds.** A model error, timeout (20 s) or malformed reply
  becomes a fixed handoff message. At most 20 Dot replies per member per
  rolling 24 hours; after that the thread goes straight to the team without a
  model call. Replies are capped at 500 tokens and 1000 characters.
- **No stale or duplicate replies.** Dot stores its reply only if the message
  it answered is still the newest and the thread's bot is on, inside the same
  owner-locked transaction as member writes. A per-member scheduler runs one
  reply at a time and re-runs once for messages sent meanwhile.
- **Account deletion.** The reply write runs inside the member's owner
  lifetime, so nothing lands for a deleted or deleting account; the model call
  itself never holds deletion up.
- **Labeling.** Members see "Dot · ผู้ช่วย AI" and "ตอบโดย AI" on every Dot
  reply and a note that AI can be wrong; administrators see "Dot (AI)".
- **Production guard.** `SUPPORT_BOT_PROVIDER=mock` refuses to boot when
  `NODE_ENV=production`.

## Changes

- API: `apps/api/src/modules/supportBot` (engine, scheduler, global switch with
  memory/Prisma stores and a 10-second read cache, knowledge/prompt, OpenAI and
  mock providers), chat store support for `BOT`, per-thread `botEnabled`,
  conditional bot replies, member handoff, member route
  `POST /support/chat/handoff`, admin `support/bot-settings` (owner) and
  `support/thread-bot`, config `SUPPORT_BOT_PROVIDER` and
  `OPENAI_SUPPORT_BOT_MODEL` (default `gpt-4o-mini`), Sentry signal source
  (`SENTRY_SIGNALS_TOKEN`, optional `SENTRY_SIGNALS_PROJECT_IDS`,
  `SENTRY_SIGNALS_WINDOW_MINUTES`).
- Database: migration `20261028030000_support_bot` (additive: `botEnabled`
  and `teamRequested` columns, `SupportBotSetting` single-row table, `BOT` allowed in the sender
  checks).
- Admin console: Dot card with on/off in the chat tab, Dot bubbles, per-chat
  switch, team-requested marker; Sentry signals with draft-a-notice in the
  status tab.
- Mobile: Dot bubbles, intro note while Dot is on, "Dot กำลังพิมพ์…",
  "ขอคุยกับทีมงาน" button.

## Deployment order

1. Merge #38, then #39, then this PR.
2. Update the privacy policy so it says support chat text is processed by
   OpenAI (not done here; legal text needs the owner's review).
3. On Staging set `SUPPORT_BOT_PROVIDER=openai` (the existing `OPENAI_API_KEY`
   is reused) and deploy manually; the migration runs on deploy.
4. An owner turns Dot on in `/admin` › แชทช่วยเหลือ and tests with a test
   account: a question covered by an open notice, a refund question (should
   hand off), and "ขอคุยกับทีมงาน".
5. Ship the Mobile build.

## Not verified yet

- A real OpenAI call and a real Sentry search (only mocked HTTP responses were
  tested; the Sentry tag-filter queries follow Sentry's documented search
  syntax), answer quality in Thai, Staging, and the app on a device.
