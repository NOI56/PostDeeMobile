# GO_LIVE.md — Production Integration Checklist

Most external integrations have a real adapter behind a config flag. A flag and
credentials are not proof that the full feature is production-ready: each row
below lists the remaining provider/device verification. Platform metric
ingestion, Sentry, beat/hook rendering, and AI minute top-ups still need code.

Default values keep everything in mock/local mode so the app runs without any
third-party accounts.

## Staging Gate

The repository defines an isolated Staging Blueprint/database and records a
successful API `/health` check. It also records earlier Android Debug
Firebase/Google login, RevenueCat Test Store purchase, and Restore/resync tests
through Staging. Those records are not proof that the hidden credentials or the
same E2E flows still pass for the current release candidate; recheck the Render
Dashboard without exposing values and rerun the applicable smoke tests. Project
records say the RevenueCat Play app/products/entitlements/default offering,
production Android public SDK key, and signed AAB were prepared; recheck the
provider dashboard and build artifact. Play Console app/subscriptions, internal
testing, service credentials, real Google Play purchase, lifecycle, physical
Android, R2, Gemini/ElevenLabs,
Phone Auth, and social publishing still need current-candidate tests. Hidden
Staging credentials must be confirmed in the Dashboard before those tests.
Mock push and Firebase deletion remain off,
and social publishing stays fail-closed `disabled` except during a controlled
test account run.
Complete `docs/STAGING.md` before deploying this release candidate to Production;
never point Staging at the Production database, R2 bucket, Firebase project, or
user-owned PostPeer connections.

## Status

| Area | Status | Switch |
| --- | --- | --- |
| Database (Postgres/Prisma) | ⚙️ configured in Blueprints; current Live check required | `*_STORE=prisma` + Render-managed `DATABASE_URL` |
| Scheduling worker | ⚙️ configured in-process; current Live check required | one instance with `PUBLISH_QUEUE=memory` |
| Caption from keywords (Gemini) | ⚙️ repo-ready, Live secret/function check required | Render declares `CAPTION_PROVIDER=gemini` and `GEMINI_API_KEY` as a hidden value; confirm the key in each environment and run the current release candidate |
| Social publishing (PostPeer) | blocked pending connected-account E2E | Per-user connect/refresh/disconnect, named pseudonymous profiles, async result polling, safe-only retries, and `GET /posts.platformResults` exist; configure the test key/accounts and run controlled publishing |
| Video upload (Cloudflare R2) | ⚙️ ready | `VIDEO_STORAGE=r2` + R2 creds |
| Auth (Firebase) | ⚙️ recorded Android Debug Staging Google pass; rerun current candidate; Production/iOS/Phone/physical-device tests remain | `AUTH_PROVIDER=firebase` + environment-specific project |
| Account deletion | ⚙️ Production repo-ready; current Live/device verification required | Production commits `FIREBASE_AUTH_DELETE_ENABLED=true` and therefore requires `FIREBASE_SERVICE_ACCOUNT_JSON`; Staging keeps deletion false. Confirm the Production secret, then verify R2 prefix and Firebase UID deletion on the current candidate |
| Subscriptions (RevenueCat / App Store / Play) | ⚙️ recorded Test Store purchase + Restore/resync pass and prepared Play configuration/AAB; recheck provider/build state and rerun current candidate; real-store/device tests pending | `BILLING_PROVIDER=revenuecat` + environment-specific webhook token + server REST key |
| Durable queue (Redis/BullMQ) | ⚙️ optional | `PUBLISH_QUEUE=bullmq` + `POST_STORE=prisma` + `DATABASE_URL` + `REDIS_URL` + run worker |

## 1. Gemini caption (free key — easiest)

- `CAPTION_PROVIDER=gemini` (already set)
- `GEMINI_API_KEY=...` — hidden Dashboard secret declared by both Blueprints;
  repository files cannot confirm its current value or validity
- `GEMINI_CAPTION_MODEL=gemini-2.5-flash-lite` (explicitly pinned in Production and Staging)
- The configured primary caption model retries transient failures, then falls
  back directly to the existing local template; no secondary Gemini model is
  attempted.

## 2. Social publishing — PostPeer (unlocks real posting)

- Sign up at https://postpeer.dev and connect the TikTok / YouTube / Instagram /
  Facebook accounts there.
- `SOCIAL_PUBLISHER=postpeer`
- `POSTPEER_API_KEY=...`
- Optional: `POSTPEER_API_BASE_URL` (default `https://api.postpeer.dev`)
- Do not add shared `POSTPEER_*_ACCOUNT_ID` values to production. The per-user
  connect/refresh/disconnect flow is implemented and must be verified with a
  connected test account before production publishing is enabled.
- A fresh authenticated user is ensured in the local User store before the
  PostPeer profile is saved. The provider profile gets a stable pseudonymous
  required name, not the Firebase UID, email, phone, or display name.
- If one older 40-bit PostPeer profile lost its local mapping, configure both
  `POSTPEER_LEGACY_RECOVERY_FINGERPRINT` (the 64-hex
  `HMAC-SHA256(POSTPEER_API_KEY, "postdee-legacy-recovery:<firebase-user-id>")`)
  and `POSTPEER_LEGACY_RECOVERY_PROFILE_ID`, refresh that signed-in user once,
  verify the connection, then remove both variables. Never leave partial
  values configured or use the short legacy profile name as ownership proof.
- PostPeer publishing does not currently fetch platform views/likes. Analytics
  can remain zero until a separate metrics ingestion adapter is implemented.
- The backend calls `POST /v1/posts` with the `x-access-key` header, sends
  `content`, `platforms`, `mediaItems`, and `publishNow`, and resolves uploaded
  video keys to signed R2/S3 download URLs before calling PostPeer.
- A `202 pending/publishing` response is polled through
  `GET /v1/posts/{postId}` for roughly two minutes. The worker accepts success
  only with a real platform URL/id and never creates a fake external id.
- Controlled-first requests use YouTube visibility `private` and TikTok
  `SELF_ONLY` with `draft: false`. Add explicit user privacy controls before a
  public rollout.
- `FACEBOOK_REELS` is retained internally for compatibility, but PostPeer
  currently publishes Facebook Page Video, not Facebook Reels. Store copy and
  screenshots must use the real capability.
- Only errors explicitly proving that a provider post was not accepted may be
  retried. For an unknown network/polling outcome, check PostPeer and the social
  account before retrying manually. `GET /posts` exposes the persisted,
  user-scoped `platformResults` used for that check.
- Real connected-account publishing has not passed E2E yet. Use disposable
  test accounts and verify the final provider URL/status on every advertised
  capability before changing the status table above.

## 3. Video upload — Cloudflare R2

- Create an R2 bucket + S3 API token in the Cloudflare dashboard.
- `VIDEO_STORAGE=r2`
- `CLOUDFLARE_R2_BUCKET`, `CLOUDFLARE_R2_ACCOUNT_ID`,
  `CLOUDFLARE_R2_ACCESS_KEY_ID`, `CLOUDFLARE_R2_SECRET_ACCESS_KEY`,
  `CLOUDFLARE_R2_ENDPOINT`

## 4. Auth — Firebase (unlocks Apple Sign-In, phone OTP, push)

The recorded Staging setup used Firebase project
`project-798caf7e-85b8-45e3-af7` and Android Debug application id
`com.postdee.postdee_mobile.staging`. It records Email/Password and Google as
enabled plus an Emulator login/token/API pass. Confirm the current hidden
`FIREBASE_PROJECT_ID`, provider state, and API-key restrictions before rerunning;
the historical result does not prove Production, Phone Auth, iOS, or
physical-device readiness.

- Create a Firebase project, enable Google + Apple + Phone sign-in.
- `AUTH_PROVIDER=firebase`
- `FIREBASE_PROJECT_ID=...`
- Production: `FIREBASE_SERVICE_ACCOUNT_JSON=...` must be present because
  `render.yaml` commits `FIREBASE_AUTH_DELETE_ENABLED=true`. Confirm presence in
  the Production Dashboard without copying the value.
- Staging: `render.staging.yaml` commits `FIREBASE_AUTH_DELETE_ENABLED=false`
  and does not declare the service-account secret.
- `FIREBASE_AUTH_DELETE_ENABLED=true` enables Firebase UID deletion and Admin
  token revocation/user-existence checks. Never enable it in an environment
  before that environment's service account is installed. Production already
  commits it as true, so the secret is a deploy prerequisite; Staging remains
  false. The delete endpoint fails closed without mutating data.
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

Project records say RevenueCat Test Store Starter/Pro products, entitlements, a
current offering, and an authenticated sandbox-only Staging webhook were set up.
They also record an HTTP 202 transport test, an Emulator Test Store purchase,
and a later true Restore/resync run with a Firebase uid. Treat these as dated
evidence: confirm the current Dashboard configuration and rerun the current
release candidate. The same records say the Play Store app, products,
entitlements, default offering, production Android public SDK key, and signed
AAB were prepared. Renewal, cancel, refund, Play Console app/subscriptions,
internal testing, Google service credentials, real Google Play purchase, and
physical Android remain unverified.

- `BILLING_PROVIDER=revenuecat`
- `REVENUECAT_WEBHOOK_AUTH_TOKEN=...`
- `REVENUECAT_REST_API_V1_KEY=...` (server-only subscriber read key; never put it
  in Flutter and do not reuse the Test Store mobile SDK key)
- `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN=...` if the legacy direct Google Play notification path is enabled
- `REVENUECAT_STARTER_ENTITLEMENT_ID=starter`
- `REVENUECAT_PRO_ENTITLEMENT_ID=pro`
- `REVENUECAT_STARTER_PRODUCT_ID=postdee_starter_monthly`
- `REVENUECAT_PRO_PRODUCT_ID=postdee_pro_monthly`
- The RevenueCat-side Play Store products, entitlements, and default offering are
  already prepared. Create the matching Play Console app/subscriptions after the
  developer account is verified on a physical Android device; an Emulator cannot
  complete that verification. App Store Connect setup remains separate.
- Set the RevenueCat app user id to the Firebase uid so webhook
  `event.app_user_id` matches the PostDee user id.
- Configure the RevenueCat webhook URL:
  `https://<api-host>/billing/revenuecat/webhooks`.
- Configure RevenueCat to send `Authorization: Bearer <token>` matching
  `REVENUECAT_WEBHOOK_AUTH_TOKEN`.
- A recorded Staging run passed mobile SDK restore → authenticated
  `POST /billing/revenuecat/resync` → `GET /billing/subscription`. Before
  Production, confirm `REVENUECAT_REST_API_V1_KEY` is still present in the
  intended environment and rerun that flow on the current release candidate.
  Do not treat an SDK-only callback or the historical run as sufficient proof.
- Mobile has a `purchases_flutter` gateway behind
  `ENABLE_REVENUECAT_BILLING=true`. For local Test Store runs, pass the ignored
  `apps/mobile/revenuecat.local.json` file with
  `--dart-define-from-file=revenuecat.local.json`.
- Keep `revenuecat.local.json` for Test Store only. Production Android uses its
  RevenueCat public SDK key through the ignored production config, and the signed
  AAB is ready; do not commit either local config or any server secret. Configure
  the iOS platform key separately before App Store submission.
- Keep the existing `/billing/store/verify` path only as a legacy scaffold, not
  the preferred production billing path.

## 6. AI auto editing — ElevenLabs transcription + Gemini planning

Backend transcription is ready (`POST /ai-edits/transcribe`, Pro-gated), and the
UI-facing recipe endpoint is ready (`POST /ai-edits/prepare`, Pro-gated with
outcome-based minute metering). Local defaults return a mock Thai transcript;
the Render blueprint uses ElevenLabs Scribe v2 for timed transcription and
Gemini for both visual and transcript planning.

- `TRANSCRIPTION_PROVIDER=elevenlabs`
- `EDIT_PLAN_PROVIDER=gemini`
- `ELEVENLABS_API_KEY=...`
- `GEMINI_API_KEY=...`
- `GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite` (explicitly pinned in Production and Staging)
- Optional: `ELEVENLABS_TRANSCRIPTION_MODEL` (default `scribe_v2`)
- Keep `VIDEO_STORAGE=r2` configured so the backend can create signed download
  URLs for the bounded temporary M4A chunks sent to ElevenLabs and the visual
  proxy sent to Gemini. The original video remains on the phone for preview and
  final export.
- Gemini 3.5 transcript and visual requests keep structured JSON output and
  use provider-default sampling: omit `generationConfig.temperature`.

Mobile flow is wired. Every optional capability starts off and the user must
explicitly enable subtitle, silence, repeated-speech, or colour; target-only
shortening remains valid with all four off. The screen calls
`/ai-edits/prepare` when target planning or an audio-dependent capability is
needed. `/ai-edits/transcribe` remains an authenticated backend/compatibility
endpoint and API-client method; it is not a separate user-facing path.

Color-only edits at original duration render locally for Pro users and do not
consume AI editing minutes. This route builds a cut-free full-duration recipe
without extracting audio, uploading media, or calling `/ai-edits/prepare`.
Colour plus shortening remains on the normal prepare path, while an unknown
enabled capability fails closed before either route starts side effects. The
phone uses `_subtitled.mp4` only when real subtitle content is rendered;
otherwise it uses `_edited.mp4`.

The FFmpeg export renders trim + speed + volume + optional subtitle burn-in and
verified silence/repeated-speech cuts into the real MP4
(`buildEditFfmpegArguments`, unit-tested). Transcript gaps are silence
candidates only. The Android/iOS client confirms each candidate against the
source waveform before rendering; failed or ambiguous verification keeps the
original audio. Mobile uses FFmpeg `silencedetect`, safety padding, protected
speech, and source-edge checks, then forwards only verified intersections to
preview, review update, subtitle re-render, and export. A successful empty probe
is distinct from failure; retry repeats only the local verifier/renderer and
does not extract, upload, prepare, or charge again. Subtitles are burned before
the video `select` filter, so accepted subtitle pixels stay with their frames.

The prepare recipe now supports honest pace controls. `silencePreset` uses
`natural` = 1.0 s, `balanced` = 0.6 s (default/missing), or `compact` = 0.4 s as
the minimum validated word-timing gap, with segment gaps as a conservative
fallback. Leading and trailing gaps are excluded, and overlapping timing ranges
are merged before internal candidates are calculated.
Provider word timings drive gaps, while subtitle text falls back to readable
transcript segments when word coverage is incomplete. ElevenLabs receives only
the bounded audio and optional approved keyterms.

`recipe.transcript.boundarySegments` is separate from visible subtitle cues and
lets Mobile align target-only cuts while subtitles are off. Unsafe or missing
boundary evidence keeps the planner cut and shows a warning; Mobile never
substitutes raw transcript segments. Thai fragments used for repeated-speech
timing must match exact NFC text in raw provider order, remain inside one
reliable segment, and stay within the allowed internal gap. Unprovable evidence
fails closed instead of becoming a cut.
Current mobile offers `AI เลือกให้` and `เลือกเอง`; both send
`speechReductionMode: auto` and do not show fixed word chips. The backend may
recommend removing only adjacent repeated Thai words or
one-to-three-word phrases backed by complete trusted timing. It keeps the last
occurrence, reports distributed frequent words without cutting them, and fails
closed for negation, `ๆ`, numbers/prices, sentence boundaries, fragmented
tokens, or unsafe timing. Legacy `fillerWords` remains accepted only for older
clients.
AI mode starts with safe recommendations selected. Manual mode starts empty,
ignores legacy-only filler ranges, and waits for explicit user selection.
Mobile then lets the user keep/remove every safe occurrence. It fits the AI story
window first, removes the same selected word from source-timeline subtitles,
and unions validated silence/repetition cuts afterward. Do not restore or
shrink any cleanup range merely to reach the selected duration. If a subtitle
word cannot be mapped safely, reject that media cut too; a slightly shorter
result is expected and truthful.

Result review displays waveform-verified silence counts, selected/sanitized
repeated-speech occurrences, and their merged/clamped time before rendering. Raw
silence candidates from the recipe are never counted as approved cuts. Treat this
as an analysis summary, not an exact promise about how many seconds the exported
clip will lose.

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
Reels, Facebook Page Video (and any future Reels integration), Shopee Video,
and Lazada Video before the app enables it.
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
`POST /ai-edits/prepare` can meter minutes (200/month) and
`GET /ai-edits/quota` reports usage; the Profile quota card reads it. Prepare
reserves minutes only when at least one requested outcome succeeds. An
unavailable-only repeat/subtitle/silence result is unmetered; safe silence
analysis that succeeds with zero candidates remains metered. Explicit empty or
colour-only API requests stop before provider work, the local colour route is
unmetered, and legacy requests that omit capabilities keep their prior metered
behaviour. The ledger persists when `AI_EDIT_USAGE_STORE=prisma` (add it to
`.env` alongside the other `*_STORE=prisma` settings; default is memory). The
`AiEditUsage` table migration is already applied.

Current Task 9 preparation is recorded in
`docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md`: the verified
implementation is in local commit `43fa6e0`, automated API/mobile checks pass,
and fresh APK/fixture hashes are recorded. Candidate/deployed Staging SHA,
health evidence, and every Pixel 8 matrix row remain `PENDING`; none of this
preflight evidence authorizes Production deployment.

Still TODO for full AI editing: verify ElevenLabs Thai timing, fragmented-token
fallback, Gemini cut quality, and the PostDee-rule fallback with natural speech
on physical phones; record fresh output codec, FPS, file size, audio peak, and
A/V sync evidence from the Task 9 Pixel 8 matrix (none of those acceptance
checks is claimed fixed yet);
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

1. **Reconfirm Staging secrets and rerun AI/R2 tests** — use the current release
   candidate and the Thai real-clip rubric; do not copy secrets into logs.
2. **Play Console and RevenueCat real-store testing** — complete physical-device
   account verification, Internal Testing purchase/restore, and lifecycle events.
3. **PostPeer controlled publishing** — connect disposable per-user accounts and
   verify provider results before enabling social publishing.
4. **Firebase production/device completion** — test Google, Apple, Phone Auth,
   FCM/APNs, and account deletion on supported physical devices.
5. **R2 isolation and cleanup** — verify environment-specific buckets, temporary
   object cleanup, and safe lifecycle prefixes.
6. **BullMQ/Redis only when needed** — move scheduling to a separate worker before
   multi-instance scaling or when independent queue operations become necessary.
