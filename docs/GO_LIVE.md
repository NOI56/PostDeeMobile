# GO_LIVE.md — Production Integration Checklist

Most external integrations have a real adapter behind a config flag. A flag and
credentials are not proof that the full feature is production-ready: each row
below lists the remaining provider/device verification. Platform metric
ingestion, Sentry, beat/hook rendering, and AI minute top-ups still need code.

Default values keep everything in mock/local mode so the app runs without any
third-party accounts.

Documentation reconciliation: 20 October 2026. Source checks and a read-only
Render infrastructure check are recorded below. Provider purchase/auth/publish
results remain earlier records, not newly repeated E2E tests.

## Staging Gate

The July Staging record reports a created Render Blueprint/database, a passing
API `/health`, and dedicated Android Debug Firebase/Google login through the
Staging API on the Emulator. RevenueCat Test Store configuration, webhook
transport/auth smoke, purchase with a Firebase UID, and true Restore/resync E2E
were recorded as passing after a backend deploy and server REST key setup.
RevenueCat Play app/products/entitlements/default offering, production Android
public SDK key, and signed AAB preparation were also recorded. The database was
listed as expiring on 14 August 2026. The 20 October read-only follow-up found
the Staging API healthy at `/health` (HTTP 200), its 18 October deploy live, and
the database available on Basic 256 MB with 1 GB storage. External SQL through
MCP is blocked by the database IP allowlist; it was not changed. No provider
configuration or functional E2E was reverified, and the local dependency/FCM fix
has not been deployed. Live uses Starter/main whereas the repository Blueprint
still says Free/temporary branch; review that drift before deploying.
Play Console app/subscriptions, internal
testing, service credentials, real Google Play purchase, lifecycle, physical
Android, R2, Gemini/Groq,
Phone Auth, and social publishing still need dedicated Staging
credentials and functional tests. The repository's Staging Blueprint keeps
`PUSH_SENDER=mock`, `FIREBASE_AUTH_DELETE_ENABLED=false`, and social publishing
fail-closed `disabled` except during a controlled test account run.
Complete `docs/STAGING.md` before deploying this release candidate to Production;
never point Staging at the Production database, R2 bucket, Firebase project, or
user-owned PostPeer connections.

The October remediation has source review and local API/Flutter regression
results as of 20 October 2026, plus an Android ARM64 debug compilation. The
initial snapshot is in `artifacts/readiness-check-20261020/summary.json`.
The dependency-remediation follow-up passes 747 API tests, typecheck, build,
Prisma checks, and dependency-tree validation on Node 22.23.3/npm 10.9.9; the
production dependency audit now reports 0 alerts. Current logs are recorded in
`artifacts/dependency-fixes-20261020/summary.json`. The FCM sender now uses
modular Firebase Admin 14 APIs with 13 mocked sender regressions.
Local suites use mocked database/provider/native clients and do not replace
real PostgreSQL/Redis race checks, an isolated security-validation runner, or
native OTP/account-switching tests on devices. Earlier provider smoke results
do not establish those conditions for the current patch.

Billing release gate: ship the additive protocol-1 purchase-readiness endpoint,
then preparation-aware mobile builds, retire/independently disable legacy builds
that skip it, then deploy read-only subscription GET. This branch bundles that
GET cutover. A missing endpoint or failed GET cannot stop those older builds
from buying. Also validate delayed User/Post/Subscription writes against real
PostgreSQL deletion and Redis timeout/retry cleanup. Cross-instance late adds,
already-admitted provider calls, OS background push and device-token detachment
remain open work; local draft isolation does not erase retained device data.

## Status

| Area | Status | Switch |
| --- | --- | --- |
| Database (Postgres/Prisma) | Production database is user-suspended; Staging Basic database is available in the 20 October inventory. External SQL via MCP is blocked; no network rules were changed | `*_STORE=prisma` + `DATABASE_URL` |
| Scheduling worker | Implemented in-process and configured in `render.yaml`; live timing not rechecked | `PUBLISH_QUEUE=memory` with `POST_STORE=prisma`, one API instance |
| Caption from keywords (Gemini) | ⚙️ adapter implemented; provider verification required for the release candidate | Render Blueprints set `CAPTION_PROVIDER=gemini`; add `GEMINI_API_KEY` |
| Social publishing (PostPeer) | blocked pending connected-account E2E | Per-user connect/refresh/disconnect, named pseudonymous profiles, async result polling, safe-only retries, and `GET /posts.platformResults` exist; configure the test key/accounts and run controlled publishing |
| Video upload (Cloudflare R2) | Legacy and managed multipart disposable-account production API smoke recorded as passed; full mobile-to-worker and slow-network tests remain | `VIDEO_STORAGE=r2` + R2 creds |
| Auth (Firebase) | Earlier Android Debug Staging Google path passed; Production/iOS/Phone/physical-device tests remain | `AUTH_PROVIDER=firebase` + project |
| Account deletion | Disposable-account production API/R2/Firebase smoke recorded as passed; physical-device E2E, slow-network and new lifecycle/session checks remain | Production `render.yaml` enables `FIREBASE_AUTH_DELETE_ENABLED=true`; service account required. Staging keeps deletion off |
| Subscriptions (RevenueCat / App Store / Play) | Earlier Test Store purchase + true Restore/resync E2E and RevenueCat Play config/signed AAB preparation recorded; Play Console and real-store/device tests pending | `BILLING_PROVIDER=revenuecat` + webhook token + server REST key |
| Durable queue (Redis/BullMQ) | ⚙️ optional | `PUBLISH_QUEUE=bullmq` + `POST_STORE=prisma` + `DATABASE_URL` + `REDIS_URL` + run worker |

## 1. Gemini caption (free key — easiest)

- `CAPTION_PROVIDER=gemini` (set in the repository's Render Blueprints)
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
- `FACEBOOK_REELS` retains its existing mobile/API value and always sends
  PostPeer `platform: 'facebook'` with `platformSpecificData.contentType: 'reel'`.
  It requires a video and has no fallback to a Page feed video. Verify a real
  Facebook Page Reel, its URL/id, and `GET /posts.platformResults` with a
  disposable connected account before production activation or Store claims.
  An optional signed `videoThumbnailUrl` is best effort; its display on a Reel
  still needs real-account verification, and the provider may choose the cover.
  Page Video duration limits do not establish a Reel duration limit.
- Deployment note: existing queued/scheduled posts with `FACEBOOK_REELS` also
  use the Page Reels route when the updated publisher processes them. No new
  environment variables, client fields, or database migrations are required.
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

The recorded Staging setup used Firebase project `project-798caf7e-85b8-45e3-af7` and
Android Debug application id `com.postdee.postdee_mobile.staging`. Email/Password
and Google providers were recorded as enabled; Google login, token verification, and the
authenticated Home/API response passed on the Android Emulator. The Android API
key was recorded as restricted by package + Debug SHA-1. This does not prove
current Staging availability, Production, Phone Auth, iOS, or physical-device
readiness.

- Create a Firebase project, enable Google + Apple + Phone sign-in.
- `AUTH_PROVIDER=firebase`
- `FIREBASE_PROJECT_ID=...`
- `FIREBASE_SERVICE_ACCOUNT_JSON=...`
- `FIREBASE_AUTH_DELETE_ENABLED=true` enables Firebase UID deletion and Admin
  token revocation/user-existence checks. Production `render.yaml` already sets
  it to `true`, with an installed service account and disposable-account
  API/R2/Firebase smoke recorded in the project notes. That test covered legacy
  signed upload and managed multipart, deletion readiness, owner cleanup,
  deleted-account retry, and zero leftover smoke sessions/objects. It does not
  validate the later October remediation or full physical-device E2E and
  slow-network behavior. Staging keeps it `false` until its own service account
  is installed and its separate deletion tests pass.
- Mobile: build with `--dart-define=ENABLE_FIREBASE_AUTH=true` and add the real
  `google-services.json` / Firebase config. See `FIREBASE_SETUP.md`.
- Separate temporary AI media from media awaiting a scheduled post before
  applying an R2 expiry rule. Verify the expiry cannot remove a scheduled video
  before publishing, and repeat owner-prefix/Firebase cleanup tests as needed
  for the release candidate.
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

Earlier project records report RevenueCat Test Store Starter/Pro products,
entitlements, a current offering, and an authenticated sandbox-only Staging
webhook. The dashboard transport test returned HTTP 202 and was safely ignored
because its generic `test_product` is intentionally unmapped. This proves only
webhook reachability/auth. Separately, a Test Store purchase completed end to end
on the Android Emulator with the Firebase uid and fake test price; it did not
charge real money. Restore UI/SDK also passed before true server resync was
added; a later recorded backend deploy and server key setup passed true
Restore/resync E2E. The records also report a RevenueCat Play Store app,
Starter/Pro products, entitlements, default offering, production Android public
SDK key, and prepared signed AAB. Renewal, cancel, refund, Play Console app/subscriptions,
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
- The RevenueCat-side Play Store products, entitlements, and default offering
  were recorded as prepared. Create the matching Play Console app/subscriptions after the
  developer account is verified on a physical Android device; an Emulator cannot
  complete that verification. App Store Connect setup remains separate.
- Set the RevenueCat app user id to the Firebase uid so webhook
  `event.app_user_id` matches the PostDee user id.
- Configure the RevenueCat webhook URL:
  `https://<api-host>/billing/revenuecat/webhooks`.
- Configure RevenueCat to send `Authorization: Bearer <token>` matching
  `REVENUECAT_WEBHOOK_AUTH_TOKEN`.
- An earlier Staging deploy containing `POST /billing/revenuecat/resync` and
  server REST key configuration passed user-initiated Restore:
  mobile SDK restore → authenticated backend resync →
  `GET /billing/subscription` shows the reconciled plan.
- Mobile has a `purchases_flutter` gateway behind
  `ENABLE_REVENUECAT_BILLING=true`. For local Test Store runs, pass the ignored
  `apps/mobile/revenuecat.local.json` file with
  `--dart-define-from-file=revenuecat.local.json`.
- Keep `revenuecat.local.json` for Test Store only. Production Android uses its
  RevenueCat public SDK key through the ignored production config; signed AAB
  preparation was recorded earlier. Do not commit either local config or any server secret. Configure
  the iOS platform key separately before App Store submission.
- Keep the existing `/billing/store/verify` path only as a legacy scaffold, not
  the preferred production billing path.

## 6. AI auto editing — Groq Whisper transcription

Backend transcription is ready (`POST /ai-edits/transcribe`, Pro-gated), and the
UI-facing recipe endpoint is ready (`POST /ai-edits/prepare`, Pro-gated and
minute-metered). Local
defaults return a mock Thai transcript; the Render blueprint sets Groq providers
and needs `GROQ_API_KEY` before real transcription tests.

The mobile setup no longer preselects 30 seconds. The seller must choose 30,
60, or a custom target before processing. The prepare request carries that
`targetDurationSeconds` separately from the client source-duration estimate.
The configured planner selects the strongest
spoken hook, benefit, proof, offer, and call-to-action segments within that
budget, preserves chronological order, and returns real cut ranges for the
mobile FFmpeg renderer. Treat this as transcript-based highlight selection;
visual best-moment claims remain blocked until a visual proxy is implemented
and verified.

- `TRANSCRIPTION_PROVIDER=groq`
- `EDIT_PLAN_PROVIDER=groq`
- `GROQ_API_KEY=...`
- `AI_EDIT_USAGE_STORE=prisma` for persistent production quota usage
- Optional: `GROQ_TRANSCRIPTION_MODEL` (default `whisper-large-v3`)
- Keep `VIDEO_STORAGE=r2` configured so the backend can create a signed download URL
  and pass the uploaded media bytes to Groq.

The current mobile flow extracts AAC/M4A (mono, 16 kHz, 64 kbps), uploads it as
`audio/mp4` with `purpose=ai-edit-audio`, sends `audioS3Key`, and retains the
source video locally for FFmpeg. Staging must verify the 25 MiB ceiling,
owner-scoped keys, no-audio behavior (no provider call/quota), automatic API
cleanup, explicit duplicate cleanup, and legacy `videoS3Key` compatibility.
Do not claim visual AI analysis: the 360p visual proxy is still unimplemented.

Staging must also prove planner failure behavior. With
`EDIT_PLAN_PROVIDER=openai` or `groq`, a network, HTTP, empty-content, or invalid
JSON failure must return `502 AI_EDIT_PLAN_PROVIDER_FAILED` and must never
produce `mock-rule`. A failed `/ai-edits/prepare` planning step must leave the
AI-edit minute ledger unchanged. Use `EDIT_PLAN_PROVIDER=mock` only for explicit
local/test runs, and verify that mobile labels its `mock-rule` output as test
mode.

Mobile flow is wired: the Edit tab picks a real clip, can call
`/ai-edits/transcribe` for captions or `/ai-edits/prepare` for the full UI
capability recipe,
and on export burns the transcript subtitles into the real clip on-device with
FFmpeg (`subtitle_burn_video_processor.dart`) → a real subtitled MP4.

Verify the result-review-to-Upload/Post handoff on device: it must use the
accepted local render without another metered prepare request or quota charge.
The production build must not expose a built-in manual timeline editor entry
point. Users may choose a separate external editor such as CapCut on their own,
but launch copy and QA must not claim a CapCut integration, export target, or
share handoff.

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

The mobile FFmpeg renderer supports color presets, brightness/contrast,
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

The beat-sync capability settings now support original audio or an owned MP3/M4A/WAV
selection with explicit rights confirmation, and carries beat intensity, music
volume, and voice-ducking settings in the prepare recipe. This is setup only:
there are no licensed catalog tracks in production yet, and the current FFmpeg
renderer does not analyze beats, mix the chosen music, or apply ducking. A
catalog track must carry verified rights for TikTok, YouTube Shorts, Instagram
Reels, Facebook Page Reels, Shopee Video,
and Lazada Video before the app enables it.
Production builds must keep `ENABLE_EXPERIMENTAL_BEAT_SYNC` absent or `false`;
the app then locks beat sync and labels it `เร็ว ๆ นี้`. Internal QA may build
with `--dart-define=ENABLE_EXPERIMENTAL_BEAT_SYNC=true` to inspect the setup UI,
but that does not enable real beat-sync rendering. The AI setup has no global
advanced-mode switch: each available capability exposes its settings directly,
the Preset card is immediately available, and panels use a single-open
accordion with no section expanded by default.

Production builds must also keep `ENABLE_EXPERIMENTAL_AI_HOOK` absent or
`false`. The 3-second opening hook has no highlight analysis/timeline renderer;
the API marks an internally requested hook as `planned` and emits no hook render
hint. Setting the flag to `true` is allowed only for internal setup-UI QA and
does not make the hook work.

A per-minute Pro quota ledger is implemented: `POST /ai-edits/transcribe` and
`POST /ai-edits/prepare` meter
minutes (200/month) and `GET /ai-edits/quota` reports usage; the Profile quota
card reads it. The ledger persists when `AI_EDIT_USAGE_STORE=prisma` (add it to
`.env` alongside the other `*_STORE=prisma` settings; default is memory). The
`AiEditUsage` table migration was previously recorded as applied; verify it for
the target deployment. Prepare reserves usage only
after its planner and recipe succeed; a `502 AI_EDIT_PLAN_PROVIDER_FAILED`
response must not change used minutes.

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

The repository's `render.yaml` currently uses one API instance with
`PUBLISH_QUEUE=memory` and `POST_STORE=prisma`. API startup runs an in-process
scheduler that reads due posts from PostgreSQL. This source/configuration check
does not verify live uptime, publish timing, or recovery behavior.

BullMQ is an optional move to an external Redis queue and separate worker when
operational or scaling needs justify it. Both paths restrict provider retries
to explicitly safe pre-accept failures; uncertain outcomes must not be posted
again automatically. A separate worker is required only after selecting BullMQ.

- `PUBLISH_QUEUE=bullmq`
- `POST_STORE=prisma`
- `DATABASE_URL=...` (shared PostgreSQL used by the API and worker)
- `REDIS_URL=...` (Upstash)
- Run the worker: `node dist/workers/publishWorkerRunner.js` as a second service.

## Highest-leverage order

1. **Gemini key** — instant, free.
2. **R2** — needed before PostPeer (real video URL).
3. **PostPeer** — controlled real posting; analytics ingestion is separate.
4. **Firebase** — auth, Apple Sign-In, OTP, push (4 features).
5. **RevenueCat billing** — paid subscriptions.
