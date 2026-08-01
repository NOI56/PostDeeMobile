# Render Environment Keys

Repository configuration reviewed: 2026-08-01. The only recorded Render API
snapshot in this file is from 2026-07-03; it is historical evidence, not proof
of the current Dashboard state.

This file is the shared checklist for PostDee Render environment variables.
Do not paste real secret values into this file. Store real values only in the
Render Dashboard or another approved secret manager.

Production uses `render.yaml`. Staging uses `render.staging.yaml` with separate
resource names and separate provider credentials; see `docs/STAGING.md`. Never
copy `DATABASE_URL`, R2 bucket credentials, Firebase service-account JSON,
RevenueCat webhook/REST secrets, or PostPeer user connections between
environments.

## What Was Checked

- `render.yaml`
- `render.staging.yaml`
- `apps/api/.env.example`
- `apps/api/src/config/env.ts`
- `apps/api/src/config/renderConfig.test.ts`
- `docs/GO_LIVE.md`
- `API.md`

Important limit: this repo can confirm what the Render blueprint expects. It
cannot prove which hidden secret values are already present in the live Render
Dashboard unless someone checks the dashboard or provides safe read-only Render
access. Treat every `sync: false` key below as "must confirm in Render".

Dependency boundary: CI installs optional native build/test packages, then
audits the runtime dependency set with optional packages excluded. Both Render
blueprints keep those build packages through Prisma migration and run
`npm prune --omit=dev --omit=optional` before starting the API. PostDee uses
`firebase-admin` Auth/FCM only, so its optional Firestore and Google Cloud
Storage clients are intentionally absent from the running service. Cloudflare
R2 remains the video storage provider.

## Status Legend

- `Blueprint value`: committed in `render.yaml`; Render should set it from the
  blueprint.
- `Render-managed`: supplied by Render, such as a PostgreSQL connection string.
- `Dashboard secret`: declared as `sync: false`; the name is in the blueprint,
  but the real value must be manually entered in Render.
- `Default in code`: not required in Render unless you want to override the
  backend default.
- `Do not set`: unsafe or forbidden in production.

## Production Blueprint Values Already Declared

These are present in `render.yaml` with fixed values or a Render-managed source.

| Key | Status | Current blueprint value | Notes |
| --- | --- | --- | --- |
| `NODE_ENV` | Blueprint value | `production` | Enables production safety guards. |
| `DATABASE_URL` | Render-managed | `postdee-postgres.connectionString` | Required because Prisma stores are enabled. |
| `TEMPLATE_STORE` | Blueprint value | `prisma` | Uses PostgreSQL. |
| `POST_STORE` | Blueprint value | `prisma` | Uses PostgreSQL. |
| `SUBSCRIPTION_STORE` | Blueprint value | `prisma` | Uses PostgreSQL. |
| `ANALYTICS_STORE` | Blueprint value | `prisma` | Uses PostgreSQL. |
| `CAPTION_USAGE_STORE` | Blueprint value | `prisma` | Persists paid AI caption quota. |
| `AI_EDIT_USAGE_STORE` | Blueprint value | `prisma` | Persists AI editing minute quota. |
| `PUBLISH_QUEUE` | Blueprint value | `memory` | Intentional for one Render web instance. |
| `VIDEO_STORAGE` | Blueprint value | `r2` | Requires Cloudflare R2 keys below. |
| `CAPTION_PROVIDER` | Blueprint value | `gemini` | Requires `GEMINI_API_KEY`. |
| `TRANSCRIPTION_PROVIDER` | Blueprint value | `elevenlabs` | Requires `ELEVENLABS_API_KEY`. |
| `EDIT_PLAN_PROVIDER` | Blueprint value | `gemini` | Uses `GEMINI_API_KEY`; PostDee rules are the final fallback. |
| `SOCIAL_PUBLISHER` | Blueprint value | `postpeer` | Requires `POSTPEER_API_KEY`. |
| `AUTH_PROVIDER` | Blueprint value | `firebase` | Requires `FIREBASE_PROJECT_ID`. |
| `FIREBASE_AUTH_DELETE_ENABLED` | Blueprint value | `true` | Keeps Firebase UID deletion and revoked-token checks enabled; requires `FIREBASE_SERVICE_ACCOUNT_JSON`. |
| `PUSH_SENDER` | Blueprint value | `mock` | Safe until Firebase service account push is ready. |
| `BILLING_PROVIDER` | Blueprint value | `revenuecat` | Requires the webhook token; current Restore also needs the server REST key below. |
| `REVENUECAT_STARTER_ENTITLEMENT_ID` | Blueprint value | `starter` | Maps RevenueCat entitlement to Starter. |
| `REVENUECAT_PRO_ENTITLEMENT_ID` | Blueprint value | `pro` | Maps RevenueCat entitlement to Pro. |
| `REVENUECAT_STARTER_PRODUCT_ID` | Blueprint value | `postdee_starter_monthly` | Maps RevenueCat product to Starter. |
| `REVENUECAT_PRO_PRODUCT_ID` | Blueprint value | `postdee_pro_monthly` | Maps RevenueCat product to Pro. |

## Production Dashboard Secrets To Confirm In Render

These keys are declared with `sync: false` in `render.yaml`. Their names are in
the blueprint, but the real values are hidden and must be confirmed in the
Render Dashboard.

| Key | Needed for | Required now? | Notes |
| --- | --- | --- | --- |
| `CLOUDFLARE_R2_BUCKET` | R2 video storage | Yes | Bucket name; not a password, but kept out of git. |
| `CLOUDFLARE_R2_ACCOUNT_ID` | R2 video storage | Yes | Cloudflare account id. |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 video storage | Yes | R2 S3-compatible access key id. |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 video storage | Yes | Secret key. |
| `CLOUDFLARE_R2_ENDPOINT` | R2 video storage | Usually optional | Override endpoint when needed. If blank, backend can use the default account endpoint. |
| `GEMINI_API_KEY` | AI caption and edit planning from real clip | Yes | Required because `CAPTION_PROVIDER=gemini` and `EDIT_PLAN_PROVIDER=gemini`. |
| `ELEVENLABS_API_KEY` | Scribe v2 transcription | Yes | Server-only. Required because `TRANSCRIPTION_PROVIDER=elevenlabs`. |
| `POSTPEER_API_KEY` | Social publishing | Yes | Required because `SOCIAL_PUBLISHER=postpeer`. |
| `FIREBASE_PROJECT_ID` | Firebase Auth token verification | Yes | Project id, not a private key. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Firebase account deletion and future push sender | Yes | Required by the committed Production configuration because `FIREBASE_AUTH_DELETE_ENABLED=true`. The repository cannot confirm whether the hidden value is currently present. Keep it secret and verify it in Render before deploy. |
| `REVENUECAT_WEBHOOK_AUTH_TOKEN` | RevenueCat webhook auth | Yes | Production startup fails without this when `BILLING_PROVIDER=revenuecat`. |
| `REVENUECAT_REST_API_V1_KEY` | RevenueCat subscriber lookup after user Restore | Before enabling Restore | Server-only secret. Never use the mobile/Test Store SDK key here and never expose it to Flutter. Without it, `POST /billing/revenuecat/resync` returns `501 REVENUECAT_RESYNC_NOT_CONFIGURED`. |
| `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN` | Legacy Google Play RTDN endpoint | Only if that endpoint is used | Blueprint declares it; RevenueCat is still the preferred billing path. |

## Staging Blueprint Differences

`render.staging.yaml` deliberately does not use every Production value. Keep
these differences when syncing the Staging Blueprint:

| Key | Staging blueprint value | Difference from Production |
| --- | --- | --- |
| `DATABASE_URL` | `postdee-postgres-staging.connectionString` | Uses the isolated Staging database. |
| `SOCIAL_PUBLISHER` | `disabled` | Fails closed unless an operator intentionally enables a controlled PostPeer test. No `POSTPEER_API_KEY` is declared by the Staging Blueprint. |
| `FIREBASE_AUTH_DELETE_ENABLED` | `false` | Prevents Staging account deletion from requiring Firebase Admin credentials. |
| `PUSH_SENDER` | `mock` | Does not send real push notifications. |

The Staging Blueprint declares its own `sync: false` entries for R2,
`GEMINI_API_KEY`, `ELEVENLABS_API_KEY`, `FIREBASE_PROJECT_ID`, and the two
RevenueCat server secrets. Their values must belong to Staging and must be
confirmed in the Staging service Dashboard. It intentionally does not declare
`FIREBASE_SERVICE_ACCOUNT_JSON` or `POSTPEER_API_KEY` while deletion is off and
social publishing is disabled.

## Model Defaults and Explicit Blueprint Pins

Production and Staging explicitly pin both Gemini model values in their
blueprints. `gemini-3.5-flash-lite` edit requests keep structured JSON output
and omit `generationConfig.temperature`. The configured `gemini-2.5-flash-lite`
caption primary retries transient failures, then falls back directly to the
existing local template; no secondary Gemini model is attempted.

| Key | Default | Notes |
| --- | --- | --- |
| `GEMINI_CAPTION_MODEL` | `gemini-2.5-flash-lite` | Explicit Production and Staging caption-model pin. |
| `GEMINI_EDIT_PLAN_MODEL` | `gemini-3.5-flash-lite` | Explicit Production and Staging visual/transcript edit-planning-model pin. |
| `ELEVENLABS_TRANSCRIPTION_MODEL` | `scribe_v2` | AI editing batch transcription model. |
| `ELEVENLABS_TRANSCRIPTION_KEYTERMS` | empty | Optional brand terms. Keep blank until measured because keyterm prompting adds provider cost. |
| `POSTPEER_API_BASE_URL` | `https://api.postpeer.dev` | PostPeer API host. |
| `CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS` | `300` | Five-minute signed upload URL lifetime; mobile retries once only when the URL explicitly expires. |
| `UPLOAD_PROTOCOL_MODE` | `legacy` | Use `dual` during the mobile rollout; use `multipart` only after old app versions are blocked. |
| `MULTIPART_UPLOAD_PART_SIZE_BYTES` | `16777216` | Uniform 16 MiB R2 parts; the final part may be smaller. |
| `MULTIPART_UPLOAD_SESSION_EXPIRES_SECONDS` | `3600` | One-hour server-managed upload session lifetime. |
| `UPLOAD_MAX_SIZE_BYTES` | `524288000` | 500 MiB upload metadata limit. |
| `RATE_LIMIT_WINDOW_MS` | `60000` | Global rate limit window. |
| `RATE_LIMIT_MAX_REQUESTS` | `300` | Global rate limit max requests. |
| `REDIS_URL` | `redis://localhost:6379` | Not used while `PUBLISH_QUEUE=memory`; required if switching to BullMQ. |

## Do Not Set In Production

These values either fail startup in production or are intentionally not in
`render.yaml`.

| Key or value | Why |
| --- | --- |
| `AUTH_PROVIDER=mock` | Production startup rejects mock auth. |
| `BILLING_PROVIDER=mock` | Production startup rejects mock billing. |
| `VIDEO_STORAGE=mock` | Production startup rejects mock storage. |
| `SOCIAL_PUBLISHER=mock` | Production startup rejects mock publishing. |
| `SOCIAL_PUBLISHER=disabled` | Explicit fail-closed mode for initial Staging or maintenance; it never reports fake publish success. Production launch still requires `postpeer`. |
| `POSTPEER_TIKTOK_ACCOUNT_ID` | Shared operator account ids are forbidden in production. |
| `POSTPEER_YOUTUBE_ACCOUNT_ID` | Shared operator account ids are forbidden in production. |
| `POSTPEER_INSTAGRAM_ACCOUNT_ID` | Shared operator account ids are forbidden in production. |
| `POSTPEER_FACEBOOK_ACCOUNT_ID` | Shared operator account ids are forbidden in production. |

## How To Check The Live Render Dashboard

1. Open Render Dashboard.
2. Open service `postdee-api`.
3. Go to Environment.
4. Confirm every key in "Dashboard Secrets To Confirm In Render" exists.
5. Do not reveal or copy the secret values into chat; only confirm present or
   missing.
6. Confirm forbidden `POSTPEER_*_ACCOUNT_ID` values are not present.
7. Deploy and open logs. These startup errors tell you exactly what is missing:
   - `DATABASE_URL is required when any Prisma-backed store is enabled`
   - `REVENUECAT_WEBHOOK_AUTH_TOKEN is required when BILLING_PROVIDER=revenuecat in production`
   - `AUTH_PROVIDER=mock is not allowed when NODE_ENV=production`
   - `BILLING_PROVIDER=mock is not allowed when NODE_ENV=production`
   - `VIDEO_STORAGE=mock is not allowed when NODE_ENV=production`
   - `SOCIAL_PUBLISHER=mock is not allowed when NODE_ENV=production`
   - `POSTPEER_*_ACCOUNT_ID cannot be used in production`
8. After deploy, check `/health` on the Render service URL.

## How To Check With The Render API

Use `scripts/check-render-env.ps1` when you have a Render API key. The script
prints only environment variable names and status. It does not print secret
values.

In PowerShell:

```powershell
$env:RENDER_API_KEY='paste-render-api-key-here'
.\scripts\check-render-env.ps1
```

If the service name is not `postdee-api`, pass the name:

```powershell
.\scripts\check-render-env.ps1 -ServiceName 'your-service-name'
```

If multiple services share the same name, set the service id:

```powershell
$env:RENDER_SERVICE_ID='srv_xxxxxxxxxxxxx'
.\scripts\check-render-env.ps1
```

After checking, close that terminal or clear the token:

```powershell
Remove-Item Env:\RENDER_API_KEY
Remove-Item Env:\RENDER_SERVICE_ID
```

Notes:

- Do not commit or paste the real Render API key into chat or repo files.
- The Render API endpoint used by the script returns variables directly on the
  service. It does not include variables from linked environment groups.
- Render API docs:
  <https://api-docs.render.com/reference/list-services> and
  <https://api-docs.render.com/reference/get-env-vars-for-service>.

## Historical Live Render Check

Recorded Render API check: 2026-07-03. Do not use this snapshot to infer which
secrets are present now; the committed Blueprint requirements have changed
since it was captured.

Service: `postdee-api`
Service id: `srv-d8uf2sbtqb8s73b6ptmg`

Result at that time: the keys required by the backend configuration then in use
were present. No secret values were copied into this file. The snapshot did not
check `REVENUECAT_REST_API_V1_KEY` and predates the current Production setting
`FIREBASE_AUTH_DELETE_ENABLED=true`.

Confirmed present only in that historical snapshot:

- `CLOUDFLARE_R2_BUCKET`
- `CLOUDFLARE_R2_ACCOUNT_ID`
- `CLOUDFLARE_R2_ACCESS_KEY_ID`
- `CLOUDFLARE_R2_SECRET_ACCESS_KEY`
- `GEMINI_API_KEY`
- `ELEVENLABS_API_KEY`
- `POSTPEER_API_KEY`
- `FIREBASE_PROJECT_ID`
- `REVENUECAT_WEBHOOK_AUTH_TOKEN`

Historical missing/unconfirmed keys:

- `CLOUDFLARE_R2_ENDPOINT` is present.
- `FIREBASE_SERVICE_ACCOUNT_JSON` was missing in the 2026-07-03 snapshot. That
  was acceptable for the configuration used then, but is **not** sufficient for
  the current committed Production Blueprint because account deletion is now
  enabled. Recheck it before the next Production deploy.
- `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN` is missing, which is acceptable while
  RevenueCat is the main billing path.
- `REVENUECAT_REST_API_V1_KEY` was not confirmed in the dated snapshot. Recorded
  Staging tests say Restore/resync was configured later, but current Staging and
  Production presence must still be checked independently in Render.

Forbidden production keys confirmed absent:

- `POSTPEER_TIKTOK_ACCOUNT_ID`
- `POSTPEER_YOUTUBE_ACCOUNT_ID`
- `POSTPEER_INSTAGRAM_ACCOUNT_ID`
- `POSTPEER_FACEBOOK_ACCOUNT_ID`

Important security note: the Render API key used for this check was shared in
chat. Revoke or rotate that API key in Render before relying on it again.

## Current Repo-Based Conclusion

From `render.yaml`, the production blueprint already declares the correct key
names for database persistence, R2 video storage, Gemini captions/edit planning,
ElevenLabs transcription, PostPeer publishing, Firebase auth, RevenueCat billing, and AI edit
usage persistence.

Both blueprints declare `REVENUECAT_REST_API_V1_KEY` as `sync: false`. The
historical Render API snapshot does not prove the current value of that key or
`FIREBASE_SERVICE_ACCOUNT_JSON`. Recheck `postdee-api-staging` and
`postdee-api` independently without printing any value, and record the check
date rather than replacing repository requirements with an unverified Live
claim.
