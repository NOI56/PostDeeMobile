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
Phone Auth, and the remaining provider-level social publishing paths still need current-candidate tests. Hidden
Staging credentials must be confirmed in the Dashboard before those tests.
Mock push and Firebase deletion remain off,
and social publishing stays fail-closed `disabled` except during a controlled
test account run. In this mode authenticated publishing readiness, post create,
post reschedule, and publish-now return `503 SOCIAL_PUBLISHING_UNAVAILABLE`;
post cancel stays available. Current mobile clients preflight before
watermark/upload, but this is only a configuration gate and is not proof that
PostPeer, storage, the queue/worker, or an account connection is healthy.
Complete `docs/STAGING.md` before deploying this release candidate to Production;
never point Staging at the Production database, R2 bucket, Firebase project, or
user-owned PostPeer connections.

## Status

| Area | Status | Switch |
| --- | --- | --- |
| Database (Postgres/Prisma) | ⚙️ configured in Blueprints; current Live check required | `*_STORE=prisma` + Render-managed `DATABASE_URL` |
| Scheduling worker | ⚙️ configured in-process; current Live check required | one instance with `PUBLISH_QUEUE=memory` |
| Caption from keywords (Gemini) | ⚙️ repo-ready, Live secret/function check required | Render declares `CAPTION_PROVIDER=gemini` and `GEMINI_API_KEY` as a hidden value; confirm the key in each environment and run the current release candidate |
| Social publishing (PostPeer) | earlier controlled YouTube Private E2E passed; Phase 2 release blocked | Apply the settings/outcome migration and API first, verify readiness version 1, inspect legacy backlog, then test TikTok inbox draft, YouTube compliance/visibility, Instagram, Facebook Page publish/draft, target revalidation, scheduling/recovery, and Production. TikTok direct remains off |
| Video upload (Cloudflare R2) | ⚙️ ready | `VIDEO_STORAGE=r2` + R2 creds |
| Auth (Firebase) | ⚙️ recorded Android Debug Staging Google pass; rerun current candidate; Production/iOS/Phone/physical-device tests remain | `AUTH_PROVIDER=firebase` + environment-specific project |
| Account deletion | blocked; Production disabled | The cleanup saga and durable managed-upload marker exist, but its coordinator is process-local and cannot drain another API instance or lease the worker provider call. Production and Staging keep `FIREBASE_AUTH_DELETE_ENABLED=false`; add a durable full-user-mutation barrier/drain before enabling |
| Subscriptions (RevenueCat / App Store / Play) | ⚙️ recorded Test Store purchase + Restore/resync pass and prepared Play configuration/AAB; recheck provider/build state and rerun current candidate; real-store/device tests pending | `BILLING_PROVIDER=revenuecat` + environment-specific webhook token + server REST key |
| Durable queue / publish concurrency | current single-process path only; multi-instance/separate real worker blocked | BullMQ exists, but production scale also requires a database/Redis owner lease or transactional outbox/claim-and-drain boundary across API mutation, worker provider call, and account deletion |

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
- `GET /publishing/readiness` is an authenticated config preflight. Its `200`
  response `{ "status": "ok", "acceptingPosts": true,
  "platformSettingsVersion": 1 }` means only that the API
  process is not set to `SOCIAL_PUBLISHER=disabled`; it does not probe PostPeer,
  R2/S3, the queue/worker, or user connections.
- Apply `20260811130000_add_platform_publish_configuration`, deploy the API, and
  verify version `1` before releasing Phase 2 Mobile. Current Mobile checks both
  `acceptingPosts` and version >= 1 and fails closed before upload otherwise.
- Both readiness `200` and disabled `503` responses set
  `Cache-Control: private, no-store`. Treat this as a defensive no-storage rule,
  not proof that caching caused an earlier mismatch.
- `POST /posts`, `PATCH /posts/:id`, and `POST /posts/:id/publish-now` enforce
  the same gate at the write boundary and return
  `503 SOCIAL_PUBLISHING_UNAVAILABLE` before post/quota/queue mutation.
  `DELETE /posts/:id` remains available to clear old work.
- Old clients do not preflight, and configuration can change after a new client
  preflights. An object uploaded before the authoritative `503` is not removed
  by the post route; verify temporary-object cleanup/lifecycle behavior.
- Before switching Staging to `postpeer`, inspect and cancel every old `QUEUED`
  or scheduled record. The current single-instance in-process scheduler polls
  Prisma for due posts, so old work can be submitted shortly after the switch.
- Keep Staging `SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG=true`. A guarded PostPeer
  deploy starts only when one atomic global aggregate count with status in
  `QUEUED` or `PUBLISHING` is zero; future schedules are included. A query failure
  also blocks startup before the scheduler and HTTP listener; the check returns
  no post/user/media details. This guard is for `PUBLISH_QUEUE=memory` only and
  is not added to the Production Blueprint.
- Startup reads config once and passes the same object to the app and scheduler
  diagnostics. Capture the non-secret `mode`, `publisher`, and
  `emptyBacklogGuard` startup line. Count activation as passed only when the
  separate guard-pass line appears after scheduler startup; a Live deploy or
  generic scheduler/listener log is insufficient.
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
- Phase 2 exact intent is TikTok `INBOX_DRAFT`; YouTube title,
  Private/Unlisted/Public, made-for-kids, realistic synthetic-media answer, and
  community-guidelines certification; Instagram share-to-feed; and Facebook
  Page Video `PUBLISH|PAGE_DRAFT`. TikTok `DIRECT_POST/SELF_ONLY` remains only
  for legacy persisted work and must stay unavailable to new users until current
  creator-info, privacy/interaction choices, consent, and TikTok audit pass.
- Use empty disposable accounts: Instagram has no per-post Private mode, and
  YouTube may keep requested Unlisted/Public uploads Private until API audit.
- `FACEBOOK_REELS` is retained internally for compatibility, but PostPeer
  currently publishes Facebook Page Video, not Facebook Reels. Store copy and
  screenshots must use the real capability.
- Mobile publish drafts are app-owned Application Support files scoped by the
  stable authenticated user ID. Saving one must not create an API post, upload to R2,
  contact the provider, enqueue work, or consume post quota; the backend has no
  `DRAFT` post status. They do not sync between devices, OS backup may include
  them, queue acceptance deletes the active draft, and a failure before queue
  acceptance retains it. Verify all of those statements on the release candidate and reconcile
  Android/iOS backup rules with Privacy/Data Safety before launch.
- TikTok inbox and Facebook Page drafts are provider drafts, not the local store:
  pressing Post uploads, queues, calls PostPeer, and consumes one unit per
  destination. Run provider E2E and verify explicit final draft evidence.
- Connected destinations must start unselected. Review must show TikTok
  inbox draft, the completed YouTube visibility/compliance choice, Instagram
  share-to-feed, and Facebook Page publish/page-draft before confirmation.
  Details appear only after selecting a row and opening its platform sheet;
  every row also names its connected account/channel/page. A missing display
  name/external account id, unknown outcome, or incomplete setting stays blocked
  and requires refresh/reconnect or correction. Create/reschedule accepts only
  future times within 30 days; scheduled post detail uses the owner-scoped
  publish-now command rather than rescheduling to the current time.
- The post result must preserve the returned lifecycle: queued is not published,
  publishing is not complete, partial is not full success, and an unknown status
  must retain the draft and block a success view. A replay must be labelled as
  the existing item.
- Each local draft persists one stable `clientRequestId`. The API commits one
  deterministic owner-scoped post before enqueue: first success returns `201`,
  a matching retry returns `200 idempotentReplay: true` and repairs a missing
  `QUEUED` job, while recognized intent mismatch or terminal failed replay
  returns `409`. Legacy no-key calls remain compatible but are new attempts with
  no deduplication guarantee. Verify this with Prisma, queue failure, app/API
  restart, lost response, and exactly-once post-unit evidence.
- New posts persist explicit settings and an internal target snapshot, recheck
  the connection before commit, and revalidate it again before the provider
  call. `platformTargets` and `providerPostId` must never appear in public
  post/queue/result responses. `deliveryOutcome` is the public truth
  (`LIVE|PRIVATE|UNLISTED|DRAFT`); internal `PUBLISHED` means requested delivery
  completed, not necessarily public visibility. Inspect/drain legacy-null
  queued posts because they have no immutable target snapshot.
- This idempotency does not cover remote objects. Mobile does not persist
  completed remote video/cover keys in the draft, so a lost response can cause
  replacement uploads before the existing post is recovered. Production needs
  key reuse or superseded-object cleanup plus verified R2 lifecycle evidence.
- The current owner/post locks are process-local and the worker does not hold
  them across the provider call. They cover authenticated route mutations and
  RevenueCat webhook application only inside one API process; a mutation already
  running in another instance can pass the durable-marker check before deletion
  and commit afterward. Do not enable
  production account deletion, multiple API instances, or a separate real
  publisher worker until a durable repository owner barrier/lease or equivalent
  transactional outbox/claim-and-drain protocol rejects new writes and drains
  every in-flight user mutation. Test same- and separate-process races.
- Only errors explicitly proving that a provider post was not accepted may be
  retried. For an unknown network/polling outcome, check PostPeer and the social
  account before retrying manually. `GET /posts` exposes the persisted,
  user-scoped `platformResults` used for that check.
- On 2026-08-10, exact Staging SHA
  `208b4e580ddd2291a7a32e718c2519d785730895` logged `postpeer` mode and a
  successful empty-backlog guard before one separately authorized YouTube
  Shorts Private immediate post. One submit reached terminal post/platform
  `PUBLISHED`, returned a real non-mock external reference, and the destination
  reported Private. Fresh post units changed exactly once from `249/250` to
  `248/250`; there was no retry. Staging was then restored to `disabled` with
  exact disabled-mode/listener/health evidence. The first restoration deploy
  incorrectly remained enabled and is retained in the result chronology rather
  than hidden. See
  `docs/testing/results/2026-08-10-social-publishing-pixel8.md`.
- This is one controlled Staging capability pass, not launch approval. Use
  disposable test accounts and verify the final provider URL/status separately
  for TikTok, Instagram, Facebook, scheduling, and failure recovery. Direct
  authenticated post-rollback readiness/header evidence remains open.

Configuration risk: `render.yaml` currently commits
`SOCIAL_PUBLISHER=postpeer` for Production while only the controlled Staging
YouTube Private path has passed. The repository cannot confirm the currently deployed Render
value or secret. This publishing-safety change does not alter that Blueprint;
resolve the Production fail-closed policy and verify the Dashboard before any
public rollout. Do not treat `acceptingPosts: true` as launch approval.

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
- Production and Staging keep `FIREBASE_AUTH_DELETE_ENABLED=false`; account
  deletion is temporarily unavailable until the durable mutation barrier/drain
  and remaining device/slow-network cleanup gates are complete. Verify the live
  Dashboard value remains false before release.
- Staging does not declare the service-account secret.
- `FIREBASE_AUTH_DELETE_ENABLED=true` enables Firebase UID deletion and Admin
  token revocation/user-existence checks. Never enable it in an environment
  before that environment's service account is installed and the durable
  mutation-drain design has passed same-process and cross-process race tests.
  The delete endpoint fails closed without mutating data while disabled.
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

Mobile flow is wired. Every optional capability starts off and the seller-facing
setup currently lets the user explicitly enable subtitle, silence, or
repeated-speech; target-only shortening remains valid with all three off. The
older colour renderer remains available only for internal/legacy verification,
while the seller-facing colour and audio-cleanup cards are hidden. The screen calls
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

The shared FFmpeg pipeline supports color presets, brightness/contrast,
centered `drawtext` overlays, and up to eight bundled procedural sound effects.
The seller does not place sounds manually: a dedicated AI analysis may return
only a validated PostDee sound ID and trusted source timestamp. Mobile fixes the
volume, maps anchors through final cuts, delays and mixes the surviving effects
with source audio, limits the result, encodes AAC, and reuses the same recipe
across preview/review/export. Provider/timing/parse failure must stay fail closed
and an unavailable-only request must not be metered. Physical Android/iPhone
listening, level, and A/V-sync evidence is still pending, so do not mark AI SFX
release-accepted until that matrix passes. The current AI `_renderPreparedRecipe`
path applies supported visual adjustments but does not yet pass CTA, price, or
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
fresh APK/fixture hashes are recorded, and candidate/deployed Staging SHA
`6695e5f1d6050e0656c2bfd591fbbad745d80963` plus health evidence match. The
Pixel 8 `color-local` passed device/render checks without a quota change, but
direct zero-upload/prepare log evidence remains pending. `target-30` is blocked
after a new 30-day, Speech-to-Text-only Staging key was installed and an
environment-only deploy went live on the unchanged SHA. Health returned HTTP
200, but the 21:57 ICT rerun still failed closed with upstream HTTP `401`, no
output, and no PostDee quota change. ElevenLabs showed 9,994/10,000 workspace
credits used (6 remaining), so provider-side quota exhaustion is the leading
diagnosis; the upstream response detail was not captured to prove the exact
cause. No payment, plan upgrade, or key revocation was performed. Wait for or
restore provider quota only with separate approval, then rerun `target-30` once.
This partial evidence does not authorize Production deployment.

Still TODO for full AI editing: verify ElevenLabs Thai timing, fragmented-token
fallback, Gemini cut quality, and the PostDee-rule fallback with natural speech
on physical phones; record fresh output codec, FPS, file size, audio peak, and
A/V sync evidence from the Task 9 Pixel 8 matrix (none of those acceptance
checks is claimed fixed yet);
turn planned recipe capabilities such as beat sync, auto-reframe, audio
cleanup, music selection, and
translation into real processors; sticker image overlays;
music upload/storage ownership checks plus a verified cross-platform catalog;
real top-up purchase through RevenueCat; and verifying FFmpeg on real low-end devices.
Do not enable the beat-sync flag in a production build until beat analysis,
mixing, ducking, licensing, and real-device export are all verified.
Do not enable the AI-hook flag in production until highlight selection, timeline
reordering, result review, and real-device export are implemented and verified.

## 7. Durable queue and multi-process coordination — Upstash Redis + BullMQ

BullMQ is needed when publishing moves to a separate worker, but enabling it is
not by itself sufficient for a safe production scale-out. The current in-process
scheduler can recover due posts from Prisma in a strictly one-instance setup;
its route/account locks are still local memory, and the worker does not hold one
through the external provider call. The API locks cannot drain a mutation already
running in another instance, so this remains an account-deletion release blocker
and a scaling concern.

- `PUBLISH_QUEUE=bullmq`
- `POST_STORE=prisma`
- `DATABASE_URL=...` (shared PostgreSQL used by the API and worker)
- `REDIS_URL=...` (Upstash)
- Run the worker: `node dist/workers/publishWorkerRunner.js` as a second service.

Before actually running multiple API instances or the separate real publisher
worker—or enabling production account deletion—add a durable repository owner
barrier/lease or equivalent transactional outbox/claim-and-drain protocol. It
must span every user mutation family, worker claim/provider call, and deletion;
atomically stop new writes, drain in-flight work, then take the cleanup snapshot.
Prove same-process, separate-process, and crash/restart behavior.

## Highest-leverage order

1. **Reconfirm Staging secrets and rerun AI/R2 tests** — use the current release
   candidate and the Thai real-clip rubric; do not copy secrets into logs.
2. **Play Console and RevenueCat real-store testing** — complete physical-device
   account verification, Internal Testing purchase/restore, and lifecycle events.
3. **Verify local drafts and scheduling safety** — capture real-device
   save/restore/account-isolation/backup behavior, zero publish-side effects
   while saving, progressive per-platform settings, exact-account review plus
   missing-identity/unknown-outcome blocking, local-versus-provider draft wording,
   future/+30-day boundaries, and publish-now compensation on the release candidate.
4. **Finish PostPeer controlled publishing** — keep Staging disabled by default.
   Apply/verify the migration and readiness version first; inspect legacy
   backlog. The earlier YouTube Private path passed, but now test TikTok inbox
   draft, YouTube compliance/visibility, Instagram, Facebook Page publish/draft,
   target change/redaction, scheduling, and recovery with explicit authorization.
5. **Firebase production/device completion** — test Google, Apple, Phone Auth,
   and FCM/APNs on supported devices. Keep account deletion disabled until the
   durable full-mutation barrier/drain is implemented, then run route-family,
   worker, slow-network, and physical-device deletion races.
6. **R2 isolation and cleanup** — verify environment-specific buckets, temporary
   object cleanup, and safe lifecycle prefixes.
7. **Close publish concurrency and orphan-media gates** — add the durable
   owner/outbox boundary before multi-instance/separate-worker rollout, verify
   stable-request replay across process restarts, and prove that response-lost
   replacement uploads are reused or cleaned from R2.
8. **Finalize legal/store privacy copy** — replace the in-app Privacy Policy and
   Terms working drafts with reviewed hosted text, then reconcile Android/iOS
   backup, Data Safety, and App Privacy disclosures with local draft media.
