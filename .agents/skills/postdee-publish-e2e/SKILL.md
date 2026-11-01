---
name: postdee-publish-e2e
description: Run and record a controlled real-account PostDee publishing test through PostPeer on Staging for TikTok, YouTube Shorts, Instagram Reels, or Facebook Page Reels. Use when the owner asks to prove that posting actually works; mock or unit-test checks do not need this.
---

# PostDee real publishing test

A real post reaches a real social account and may be visible to the public. Treat every step that uploads, posts, or deletes as an outward action.

## Get authorization first

Before any upload, have the owner confirm in chat:

- the environment (Staging only; Production is out of scope),
- the exact accounts, channel, and Page to use,
- which platforms and which modes (below),
- whether a public post is allowed at all.

If Staging has `SOCIAL_PUBLISHER=disabled`, publishing routes answer `503 SOCIAL_PUBLISHING_UNAVAILABLE`. Switching it on is a Staging variable change with its own approval (see `postdee-staging-deploy`); switch it back afterwards if the owner asks.

## Prefer the least public mode

| Platform | Least public first | Public |
| --- | --- | --- |
| TikTok | `INBOX_DRAFT` (lands in the creator's inbox) | `DIRECT_POST` stays off until creator-info, consent, and audit checks pass |
| YouTube Shorts | `private`, then `unlisted` | `public` |
| Facebook Page Reels | `PAGE_DRAFT` | `PUBLISH` |
| Instagram Reels | none; every Reel is published (share-to-feed is optional) | always |

Check the current modes in `apps/api/src/modules/posts/platformSettings.ts`. Facebook always goes as a Reel (`contentType: 'reel'`); a Page feed video is never a fallback.

## Run

1. **Baseline:** the deployed Staging SHA, the app build installed (APK hash; see `postdee-android-build`), the account's plan and remaining post quota, and the connected accounts shown in Connections.
2. **Readiness without side effects:** `GET /social-connections/publishing-readiness` and `GET /publishing/readiness` with the user's token. Reading readiness must not create PostPeer profiles or repair connections.
3. **Fixture:** a short 9:16 test video whose SHA-256 you record. The caption starts with an identifiable tag such as `[STAGING TEST] PostDee <date>`.
4. **Submit once** from the app, selecting only the approved platforms and modes. Do not tap again on a slow response; the stable `clientRequestId` makes a replay return the same post, and you should verify that instead of creating a second post.
5. **Evidence:** the post's status through `GET /posts/:id` (`QUEUED` → `PUBLISHING` → `PUBLISHED` / `PARTIAL_PUBLISHED` / failed), each platform's result and provider post ID, the post visible on the platform in the expected mode, the quota change (counted once), and the app's result screen.

A server send attempt or a `PUBLISHED` status alone is not delivery; the post must be seen on the platform. A draft or private post must not be described as public.

## Clean up

Deleting a post on a social platform is permanent. List what was created and ask the owner whether to remove each item and who removes it. Restore any temporary Staging switch you changed with approval.

## Record

Write `docs/testing/results/<YYYY-MM-DD>-<topic>.md`, following `2026-08-10-social-publishing-pixel8.md`: candidate SHA, CI run, overall status (PASS, FAIL, or BLOCKED with the stopping point), Production status (unchanged), APK and fixture hashes, device, each attempt with time, caption, mode, and result, and what remains unverified. Link it from the matching section in `docs/STAGING.md`.
