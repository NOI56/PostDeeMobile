# Social Publishing Safety And Controlled YouTube Attempt — Pixel 8

This record covers the Staging-only social-publishing safety check and one
controlled YouTube-private attempt. It is not evidence that PostPeer publishing
passed end to end.

Candidate/deployed Staging SHA: `fcccb89642478ea70b2c89ccc507351f108dcb9e`

GitHub Actions: `PASS` ([run 31361704959](https://github.com/NOI56/PostDeeMobile/actions/runs/31361704959))

Overall status: `BLOCKED — the controlled attempt stopped at publishing readiness before upload and did not reach PostPeer`

Production status: `UNCHANGED`

## Local and artifact evidence

- API verification: `952/952 PASS`, build `PASS`, Prisma validation `PASS`
- Staging APK SHA-256: `2A68EC3D3B2F0F45D98ACDF19272FB1FF7E3AEFFC3092F862F5653AD5AF63910`
- Staging APK size/time: `271,387,056` bytes; `2026-08-10T06:26:53.8346170Z`
- Pixel 8 AVD/serial: `Pixel_8` / `emulator-5554`
- Public-domain 9:16 fixture SHA-256: `1FE7018BF07EB17AAE245E1240870D2263097A03A8940D1B0C2730928446D4B6`
- Fixture properties: H.264/AAC, 720×1280, 30 fps, 8.006 seconds,
  `471,110` bytes; host and device hashes matched

## Disabled fail-fast check — PASS

With Staging still set to `SOCIAL_PUBLISHER=disabled`, the signed-in Pro account
showed `249/250` post units remaining. The uploader selected only YouTube Shorts,
immediate posting, and this caption:

`[STAGING PRIVATE TEST] PostDee publish verification 2026-08-10`

The single submit action at `2026-08-10T13:51:56.985+07:00` returned:

- `ระบบรับงานโพสต์ยังไม่เปิดใช้งานในขณะนี้`
- `วิดีโอยังไม่ได้อัปโหลด กรุณาลองใหม่ภายหลัง`

No watermark/upload/publish progress started, and the balance stayed `249/250`.
This proves the current Mobile preflight stops this path before upload. It does
not replace direct deployed tests of the authoritative create/reschedule/cancel
routes or the old-client upload-cleanup path.

## Temporary environment-change deployment — INCONCLUSIVE

Staging alone was temporarily edited toward `SOCIAL_PUBLISHER=postpeer` while
`SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG=true` remained set. Render deployment
`dep-d9sncdf10e5c73a7kleg` became Live at about `13:59 ICT` on the exact candidate
SHA, and `/health` returned HTTP 200 with
`{"status":"ok","service":"postdee-api"}` at
`2026-08-10T06:59:53.5792756Z`.

That release logged scheduler/listener startup in both publisher modes and did
not log the runtime publisher mode or a successful empty-backlog guard check.
The later Mobile readiness result was still unavailable. Therefore this record
cannot prove that the Live process actually saw `postpeer`, that the guard ran,
or that the active backlog was empty. Provider, storage, queue, and
connected-account readiness all remain unproven.

## One controlled YouTube-private attempt — BLOCKED

At about `14:05 ICT`, the same exact APK and fixture were used with one platform,
YouTube Shorts, immediate posting, and the exact caption above. The operator
pressed submit once and did not retry.

The app again reported publishing unavailable before upload. The post-unit
balance remained `249/250`; there was no upload progress, PostPeer result,
provider URL/id, or YouTube-post evidence. Therefore this action did not exercise
`POST /posts`, the publish worker, or PostPeer, and it must not be described as a
connected-account E2E pass. The captured evidence does not establish why Mobile
still observed unavailable while the temporary Render deployment was Live.

No account/channel identifier is stored in this public repository record. The
test-account isolation/disposable status was also not proven, so that release
check remains open.

## Rollback — PASS

Staging was immediately restored to `SOCIAL_PUBLISHER=disabled` without changing
Production. Render deployment `dep-d9snh15bedkc73dt2p2g` became Live at about
`14:08 ICT` on the same candidate SHA. The Environment page was re-read and
showed `SOCIAL_PUBLISHER=disabled`. `/health` returned HTTP 200 with
`{"status":"ok","service":"postdee-api"}` at
`2026-08-10T07:11:37.5494693Z`.

An authenticated readiness request after this final rollback was not separately
captured. Keep Staging disabled, diagnose the enabled/readiness mismatch, and
repeat at most one controlled private test only after that mismatch is explained.
Do not retry an ambiguous provider outcome; this run had no provider-acceptance
evidence.

## Follow-up diagnostics — CODE ONLY, NOT DEPLOYMENT EVIDENCE

The follow-up candidate adds observability for the next controlled run:

- readiness `200` and `503` both set `Cache-Control: private, no-store`
- process startup parses config once and passes the same object to the app and
  scheduler diagnostics
- startup logs only non-secret `mode`, `publisher`, and `emptyBacklogGuard`
- the explicit empty-backlog guard-pass message is logged only after
  `scheduler.start()` succeeds

These changes do not show that caching caused the blocked attempt and do not
retroactively prove that deployment `dep-d9sncdf10e5c73a7kleg` saw `postpeer` or
ran the activation guard. Keep this result `BLOCKED` until a new exact-SHA
Staging deploy records the runtime-mode line, the guard-pass line, authenticated
readiness `200` with the no-store header, and then one separately authorized
private publishing attempt.
