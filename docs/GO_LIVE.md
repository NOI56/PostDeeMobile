# GO_LIVE.md — Production Integration Checklist

Most external integrations have a real adapter behind a config flag. A flag and
credentials are not proof that the full feature is production-ready: each row
below lists the remaining provider/device verification. Platform metric
ingestion, Sentry, beat/hook rendering, and AI minute top-ups still need code.

Default values keep everything in mock/local mode so the app runs without any
third-party accounts.

## Staging Gate

The Staging Blueprint/database are now created on Render and the API `/health`
check passes in health-only mode. Current provider values are dummy staging-only
placeholders, not proof that authentication, uploads, AI, billing, or publishing
work. Replace them only with dedicated Staging credentials and complete
`docs/STAGING.md` before Production. Mock push and Firebase deletion remain off,
and social publishing starts in explicit fail-closed `disabled` mode; enable
PostPeer only for a controlled test account.
Complete `docs/STAGING.md` before deploying this release candidate to Production;
never point Staging at the Production database, R2 bucket, Firebase project, or
user-owned PostPeer connections.

## Status

| Area | Status | Switch |
| --- | --- | --- |
| Database (Postgres/Prisma) | ✅ **Live** | `*_STORE=prisma` + `DATABASE_URL` |
| Scheduling worker | ✅ **Live** (in-process, DB-backed) | none — runs with `PUBLISH_QUEUE=memory` |
| Caption from keywords (Gemini) | ⚙️ ready | Render sets `CAPTION_PROVIDER=gemini`; add `GEMINI_API_KEY` |
| Social publishing (PostPeer) | blocked pending provider test | Per-user connect/refresh/disconnect exists; configure the key, connect a test user, then run a controlled publish |
| Video upload (Cloudflare R2) | ⚙️ ready | `VIDEO_STORAGE=r2` + R2 creds |
| Auth (Firebase) | ⚙️ ready | `AUTH_PROVIDER=firebase` + project |
| Account deletion | ⚙️ ready, deployment test required | `FIREBASE_AUTH_DELETE_ENABLED=true` + service account; verify R2 prefix and Firebase UID deletion |
| Subscriptions (RevenueCat / App Store / Play) | ⚙️ ready | `BILLING_PROVIDER=revenuecat` + webhook token |
| Durable queue (Redis/BullMQ) | ⚙️ optional | `PUBLISH_QUEUE=bullmq` + `POST_STORE=prisma` + `DATABASE_URL` + `REDIS_URL` + run worker |

## 1. Gemini caption (free key — easiest)

- `CAPTION_PROVIDER=gemini` (already set)
- `GEMINI_API_KEY=...` — free from Google AI Studio (https://aistudio.google.com/apikey)
- Optional: `GEMINI_CAPTION_MODEL` (default `gemini-2.5-flash-lite`)

## 2. Social publishing — PostPeer (unlocks real posting)

- Sign up at https://postpeer.dev and connect the TikTok / YouTube / Instagram /
  Facebook accounts there.
- `SOCIAL_PUBLISHER=postpeer`
- `POSTPEER_API_KEY=...`
- Optional: `POSTPEER_API_BASE_URL` (default `https://api.postpeer.dev`)
- Do not add shared `POSTPEER_*_ACCOUNT_ID` values to production. The per-user
  connect/refresh/disconnect flow is implemented and must be verified with a
  connected test account before production publishing is enabled.
- PostPeer publishing does not currently fetch platform views/likes. Analytics
  can remain zero until a separate metrics ingestion adapter is implemented.
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
- `FIREBASE_SERVICE_ACCOUNT_JSON=...`
- `FIREBASE_AUTH_DELETE_ENABLED=true` enables Firebase UID deletion and Admin
  token revocation/user-existence checks. Keep it false until the service
  account is installed; the delete endpoint fails closed without mutating data.
- Mobile: build with `--dart-define=ENABLE_FIREBASE_AUTH=true` and add the real
  `google-services.json` / Firebase config. See `FIREBASE_SETUP.md`.
- Set an R2 lifecycle rule for `uploads/` as a race-condition safety net, then
  test that deleting one account removes only that encoded UID prefix and the
  Firebase Authentication user.
- Test that every PostPeer integration under the user's stored profile is
  disconnected across multiple list pages, and that a late RevenueCat renewal
  is ignored instead of recreating the deleted user.
- Test per-platform disconnect with a disposable connection: PostPeer deletion
  must succeed before the local row disappears, a second DELETE must remain
  successful, and refresh must not bring the connection back.
- Test the recent-login guard: a Firebase session older than five minutes must
  ask the user to sign in again, while a lost response after UID deletion must
  complete through the account-only retry path.
- On iOS/macOS, test an Apple-linked account too: readiness must pass before the
  app shows Apple reauthentication and revokes access. Keep Apple Sign-In off on
  Android/web until server-side Apple token revocation is implemented.

## 5. Subscriptions — RevenueCat

- `BILLING_PROVIDER=revenuecat`
- `REVENUECAT_WEBHOOK_AUTH_TOKEN=...`
- `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN=...` if the legacy direct Google Play notification path is enabled
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

Backend transcription is ready (`POST /ai-edits/transcribe`, Pro-gated), and the
UI-facing recipe endpoint is ready (`POST /ai-edits/prepare`, Pro-gated and
minute-metered). Local
defaults return a mock Thai transcript; the Render blueprint sets Groq providers
and needs `GROQ_API_KEY` before real transcription tests.

- `TRANSCRIPTION_PROVIDER=groq`
- `EDIT_PLAN_PROVIDER=groq`
- `GROQ_API_KEY=...`
- Optional: `GROQ_TRANSCRIPTION_MODEL` (default `whisper-large-v3`)
- Keep `VIDEO_STORAGE=r2` configured so the backend can create a signed download URL
  and pass the uploaded media bytes to Groq.

Mobile flow is wired: the Edit tab picks a real clip, can call
`/ai-edits/transcribe` for captions or `/ai-edits/prepare` for the full UI
capability recipe,
and on export burns the transcript subtitles into the real clip on-device with
FFmpeg (`subtitle_burn_video_processor.dart`) → a real subtitled MP4.

The FFmpeg export now renders trim + speed + volume + subtitle burn-in +
silence-cut into the real MP4 (`buildEditFfmpegArguments`, unit-tested). Silence
ranges are detected from validated backend word timings with transcript-segment
fallback (`findSilenceRanges` in the recipe builder); the cut subtitles stay in
sync because subtitles are burned BEFORE the silence
`select` filter, so the burned pixels travel with their frames.

The prepare recipe now supports honest pace controls. `silencePreset` uses
`natural` = 1.0 s, `balanced` = 0.6 s (default/missing), or `compact` = 0.4 s as
the minimum validated word-timing gap, with segment gaps as a conservative
fallback. The threshold also covers leading/trailing silence when duration is
valid, and overlapping timing ranges are merged before gaps are calculated.
Thai character-level Groq timings still drive gaps, but subtitle text falls back
to readable transcript segments. Groq receives the Thai language hint plus a
concise `PostDee` → `โพสต์ดี` spelling prompt; verify this against natural speech
before launch because a prompt guides rather than guarantees transcription.
`fillerWords` matches only the
normalized exact allowlist `เอ่อ`, `อ่า`, `แบบว่า`, `คือว่า`, `ประมาณว่า`; it
does not use substring matching on normal tokens. Exact `เออ` maps to `เอ่อ`,
whitespace-only provider tokens are ignored, and validated fragmented Thai
tokens are reassembled only across tight timing and verified Thai word/text
boundaries. Meaningful tokens with invalid timing still fail closed. Missing
legacy input checks all five words, while explicit `[]` (or input that sanitizes
empty) produces no filler cuts. Mobile prevents an empty selection while the
filler feature remains enabled.

Result review displays detected silence/filler counts and the merged/clamped
detected time from recipe ranges before rendering. Treat this as an analysis summary,
not an exact promise about how many seconds the exported clip will lose.

The shared/manual FFmpeg pipeline supports color presets, brightness/contrast,
and centered `drawtext` overlays. The current AI `_renderPreparedRecipe` path
applies supported visual adjustments but does not yet pass CTA, price, or
watermark text overlays into the renderer. Do not present those overlays as
applied in the AI preview until that wiring exists.

Production security gate: the mobile app now pins
[`ffmpeg_kit_flutter_new_video` 2.3.2](https://pub.dev/packages/ffmpeg_kit_flutter_new_video/changelog),
which wires the [FFmpeg 8.1.2 security fixes](https://ffmpeg.org/security.html),
including CVE-2026-8461, into Android and iOS. A signed Android release APK builds
successfully with this dependency. An Android API 34 emulator smoke test also
selected a 720×1280 clip, read its metadata, rendered the AI MP4, and played the
result preview. Do not accept untrusted user video in a store release until native
export is also smoke-tested on physical Android and iPhone devices. Internal
testing should use only team-created/trusted clips until then.

The beat-sync advanced UI now supports original audio or an owned MP3/M4A/WAV
selection with explicit rights confirmation, and carries beat intensity, music
volume, and voice-ducking settings in the prepare recipe. This is setup only:
there are no licensed catalog tracks in production yet, and the current FFmpeg
renderer does not analyze beats, mix the chosen music, or apply ducking. A
catalog track must carry verified rights for TikTok, YouTube Shorts, Instagram
Reels, Facebook Reels, Shopee Video, and Lazada Video before the app enables it.
Production builds must keep `ENABLE_EXPERIMENTAL_BEAT_SYNC` absent or `false`;
the app then locks beat sync and labels it `เร็ว ๆ นี้`. Internal QA may build
with `--dart-define=ENABLE_EXPERIMENTAL_BEAT_SYNC=true` to inspect the setup UI,
but that does not enable real beat-sync rendering. Advanced settings are shown
as a single-open accordion with no section expanded by default.

Production builds must also keep `ENABLE_EXPERIMENTAL_AI_HOOK` absent or
`false`. The 3-second opening hook has no highlight analysis/timeline renderer;
the API marks an internally requested hook as `planned` and emits no hook render
hint. Setting the flag to `true` is allowed only for internal setup-UI QA and
does not make the hook work.

A per-minute Pro quota ledger is live: `POST /ai-edits/transcribe` and
`POST /ai-edits/prepare` meter
minutes (200/month) and `GET /ai-edits/quota` reports usage; the Profile quota
card reads it. The ledger persists when `AI_EDIT_USAGE_STORE=prisma` (add it to
`.env` alongside the other `*_STORE=prisma` settings; default is memory). The
`AiEditUsage` table migration is already applied.

Still TODO for full AI editing: verify Groq Thai timing, fragmented-token
fallback, and cut quality with natural speech on physical phones; consider
FFmpeg audio silence detection if transcript timing is not accurate enough;
turn planned recipe capabilities such as beat sync, auto-reframe, audio
cleanup, SFX/music, and
translation into real processors; sticker image overlays;
music upload/storage ownership checks plus a verified cross-platform catalog;
real top-up purchase through RevenueCat; and verifying FFmpeg on real low-end devices.
Do not enable the beat-sync flag in a production build until beat analysis,
mixing, ducking, licensing, and real-device export are all verified.
Do not enable the AI-hook flag in production until highlight selection, timeline
reordering, result review, and real-device export are implemented and verified.

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
