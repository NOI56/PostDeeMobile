---
name: postdee-staging-deploy
description: Deploy an exact main commit of the PostDee API to the Render Staging service, change Staging environment variables, and prove the deploy is healthy. Use when the owner asks to put a change on Staging or check what Staging runs; Production changes are out of scope.
---

# PostDee Staging deploy

## Services

| Service (Render name) | Blueprint | Branch | Deploys |
| --- | --- | --- | --- |
| `postdee-api-staging` | `render.staging.yaml` | `main` | Manual only (`autoDeployTrigger: "off"`) |
| `postdee-api` (Production) | `render.yaml` | `main` | Automatically on commits to `main`, unless the message contains `[skip render]` |

Find services by name with the Render tools (`list_services`, `get_service`) every time; do not reuse a remembered service ID or state. Production is out of scope here: never trigger, resume, or change it from this workflow, and keep `[skip render]` on commits to `main`.

Staging has its own database (`postdee-postgres-staging`), R2 bucket, Firebase project, and RevenueCat sandbox. Never point Staging at Production resources or at users' real PostPeer connections.

## Authorization

A Staging deploy changes what testers and the owner's installed Staging app talk to. Deploy only a commit the owner approved for Staging, and only after it is on `origin/main` with CI green for that SHA. An environment-variable change also needs approval for the exact key and value; never print secret values.

## Deploy

1. Record the intended SHA (`git rev-parse origin/main`) and the currently Live Staging deploy and commit (`list_deploys`), so you can report the change and roll back.
2. Trigger the deploy (`trigger_deploy`) and follow it (`get_deploy`) until it is Live or fails. `preDeployCommand` runs `prisma migrate deploy` first; a failed migration cancels the deploy and the previous instance keeps serving.
3. Confirm the Live deploy's commit equals the intended SHA. A Live deploy of a different commit is a failed delivery.

## Environment variables

- Render's update merges by key, but **replaces a key's whole value**, and it triggers a deploy. For list-valued keys such as `ADMIN_OWNER_UIDS` and `ADMIN_VIEWER_UIDS`, read the current value and append; never overwrite with only the new entry.
- If the service does not see a value the owner says they added, check that it was added to `postdee-api-staging` itself and not to another service or environment group before retrying.
- A failed start after a variable change keeps the old instance serving. Read the deploy logs, revert the change if needed, and report.

## Verify

- `GET https://postdee-api-staging.onrender.com/health` returns 200.
- `GET /ready` returns 200 with database and queue `ok`, and `Cache-Control: no-store`.
- An unauthenticated `GET /posts` returns 401.
- Logs for the deploy window (`list_logs`) show migrations applied and no application errors.

Health is not feature proof. Publishing, billing, and push still need their own checks (`postdee-publish-e2e`, device tests via `postdee-android-build`).

## Record

Add a newest-first section to `docs/STAGING.md` in its existing style (Thai, dated heading): deploy ID with dashboard link, source SHA, Live time in Thai time and UTC, migrations, the checks above with results, and what was not done (for example no APK distributed, Production untouched). Commit that note with `[skip render]` in the message.
