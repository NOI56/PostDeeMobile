# GO_LIVE.md — Production Integration Checklist

Every external integration already has a real adapter wired behind a config
flag. To switch any feature from mock to real, sign up for the service, add the
listed env vars to `apps/api/.env`, then restart the API. No code changes needed.

Default values keep everything in mock/local mode so the app runs without any
third-party accounts.

## Status

| Area | Status | Switch |
| --- | --- | --- |
| Database (Postgres/Prisma) | ✅ **Live** | `*_STORE=prisma` + `DATABASE_URL` |
| Scheduling worker | ✅ **Live** (in-process, DB-backed) | none — runs with `PUBLISH_QUEUE=memory` |
| Caption from keywords (Gemini) | ⚙️ ready | Render sets `CAPTION_PROVIDER=gemini`; add `GEMINI_API_KEY` |
| Social publishing (PostPeer) | ⚙️ code ready | `SOCIAL_PUBLISHER=postpeer` + key + connected account ids |
| Video upload (Cloudflare R2) | ⚙️ ready | `VIDEO_STORAGE=r2` + R2 creds |
| Auth (Firebase) | ⚙️ ready | `AUTH_PROVIDER=firebase` + project |
| Subscriptions (RevenueCat / App Store / Play) | ⚙️ ready | `BILLING_PROVIDER=revenuecat` + webhook token |
| Durable queue (Redis/BullMQ) | ⚙️ optional | `PUBLISH_QUEUE=bullmq` + `POST_STORE=prisma` + `DATABASE_URL` + `REDIS_URL` + run worker |

## 1. Gemini caption (free key — easiest)

- `CAPTION_PROVIDER=gemini` (already set)
- `GEMINI_API_KEY=...` — free from Google AI Studio (https://aistudio.google.com/apikey)
- Optional: `GEMINI_CAPTION_MODEL` (default `gemini-2.5-flash-lite`)

## 2. Social publishing — PostPeer (unlocks real posting + real analytics)

- Sign up at https://postpeer.dev and connect the TikTok / YouTube / Instagram /
  Facebook accounts there.
- `SOCIAL_PUBLISHER=postpeer`
- `POSTPEER_API_KEY=...`
- Optional: `POSTPEER_API_BASE_URL` (default `https://api.postpeer.dev`)
- Add the connected account integration ids from PostPeer:
  `POSTPEER_TIKTOK_ACCOUNT_ID`, `POSTPEER_YOUTUBE_ACCOUNT_ID`,
  `POSTPEER_INSTAGRAM_ACCOUNT_ID`, and `POSTPEER_FACEBOOK_ACCOUNT_ID`.
  These are PostPeer integration ids from `/v1/connect/integrations`, not the
  public social usernames.
- The backend calls `POST /v1/posts` with the `x-access-key` header, sends
  `content`, `platforms`, `mediaItems`, and `publishNow`, and resolves uploaded
  video keys to signed R2/S3 download URLs before calling PostPeer.

## 3. Video upload — Cloudflare R2

- Create an R2 bucket + S3 API token in the Cloudflare dashboard.
- `VIDEO_STORAGE=r2`
- `CLOUDFLARE_R2_BUCKET`, `CLOUDFLARE_R2_ACCOUNT_ID`,
  `CLOUDFLARE_R2_ACCESS_KEY_ID`, `CLOUDFLARE_R2_SECRET_ACCESS_KEY`,
  `CLOUDFLARE_R2_ENDPOINT`

## 4. Auth — Firebase (unlocks Apple Sign-In, phone OTP, push)

- Create a Firebase project, enable Google + Apple + Phone sign-in.
- `AUTH_PROVIDER=firebase`
- `FIREBASE_PROJECT_ID=...`
- Mobile: build with `--dart-define=ENABLE_FIREBASE_AUTH=true` and add the real
  `google-services.json` / Firebase config. See `FIREBASE_SETUP.md`.

## 5. Subscriptions — RevenueCat

- `BILLING_PROVIDER=revenuecat`
- `REVENUECAT_WEBHOOK_AUTH_TOKEN=...`
- `REVENUECAT_STARTER_ENTITLEMENT_ID=starter`
- `REVENUECAT_PRO_ENTITLEMENT_ID=pro`
- `REVENUECAT_STARTER_PRODUCT_ID=postdee_starter_monthly`
- `REVENUECAT_PRO_PRODUCT_ID=postdee_pro_monthly`
- Create the matching App Store Connect and Play Console subscription products,
  then connect them to RevenueCat offerings and entitlements.
- Set the RevenueCat app user id to the Firebase uid so webhook
  `event.app_user_id` matches the PostDee user id.
- Configure the RevenueCat webhook URL:
  `https://<api-host>/billing/revenuecat/webhooks`.
- Configure RevenueCat to send `Authorization: Bearer <token>` matching
  `REVENUECAT_WEBHOOK_AUTH_TOKEN`.
- Mobile has a `purchases_flutter` gateway behind
  `ENABLE_REVENUECAT_BILLING=true`. For local Test Store runs, pass the ignored
  `apps/mobile/revenuecat.local.json` file with
  `--dart-define-from-file=revenuecat.local.json`.
- The current local SDK key is a RevenueCat Test Store key. Replace it with
  real platform RevenueCat SDK keys before submitting to App Store or Google
  Play.
- Keep the existing `/billing/store/verify` path only as a legacy scaffold, not
  the preferred production billing path.

## 6. AI auto editing — Groq Whisper transcription

Backend transcription is ready (`POST /ai-edits/transcribe`, Pro-gated). Local
defaults return a mock Thai transcript; the Render blueprint sets Groq providers
and needs `GROQ_API_KEY` before real transcription tests.

- `TRANSCRIPTION_PROVIDER=groq`
- `EDIT_PLAN_PROVIDER=groq`
- `GROQ_API_KEY=...`
- Optional: `GROQ_TRANSCRIPTION_MODEL` (default `whisper-large-v3`)
- Keep `VIDEO_STORAGE=r2` configured so the backend can create a signed download URL
  and pass the uploaded media bytes to Groq.

Mobile flow is wired: the Edit tab picks a real clip, calls `/ai-edits/transcribe`,
and on export burns the transcript subtitles into the real clip on-device with
FFmpeg (`subtitle_burn_video_processor.dart`) → a real subtitled MP4.

The FFmpeg export now renders trim + speed + volume + subtitle burn-in +
silence-cut into the real MP4 (`buildEditFfmpegArguments`, unit-tested). Silence
ranges are detected from transcript segment gaps (`detectSilenceRanges`); the
cut subtitles stay in sync because subtitles are burned BEFORE the silence
`select` filter, so the burned pixels travel with their frames.

The render now also applies color presets + brightness/contrast (`eq`,
`colorbalance`, `hue`) and centered text overlays (`drawtext` with the bundled
Prompt font). Color grade is applied before subtitles so captions stay crisp.

A per-minute Pro quota ledger is live: `POST /ai-edits/transcribe` meters
minutes (200/month) and `GET /ai-edits/quota` reports usage; the Profile quota
card reads it. The ledger persists when `AI_EDIT_USAGE_STORE=prisma` (add it to
`.env` alongside the other `*_STORE=prisma` settings; default is memory). The
`AiEditUsage` table migration is already applied.

Still TODO for full AI editing: finer silence detection from Groq word
timing (segment gaps are the conservative first pass); sticker image overlays;
real top-up purchase through RevenueCat; and verifying FFmpeg on real low-end devices.

## 7. Durable queue — Upstash Redis + BullMQ (optional)

Only needed to run publishing in a separate worker process / get retry
semantics. The in-process scheduler already publishes due posts reliably from
the database.

- `PUBLISH_QUEUE=bullmq`
- `POST_STORE=prisma`
- `DATABASE_URL=...` (shared PostgreSQL used by the API and worker)
- `REDIS_URL=...` (Upstash)
- Run the worker: `node dist/workers/publishWorkerRunner.js` as a second service.

## Highest-leverage order

1. **Gemini key** — instant, free.
2. **R2** — needed before PostPeer (real video URL).
3. **PostPeer** — real posting + analytics.
4. **Firebase** — auth, Apple Sign-In, OTP, push (4 features).
5. **RevenueCat billing** — paid subscriptions.
