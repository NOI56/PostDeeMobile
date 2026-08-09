# AI Edit Correctness — Pixel 8

This is the evidence record for the Task 9 isolated Pixel 8 matrix. Automated
verification and local artifact hashes may be recorded before deployment, but no
device-matrix row may be marked pass until the candidate and deployed Staging
SHA match and the case has real evidence.

Candidate deploy SHA: `6695e5f1d6050e0656c2bfd591fbbad745d80963`

Deployed Staging SHA: `6695e5f1d6050e0656c2bfd591fbbad745d80963`

API runtime code SHA: `6695e5f1d6050e0656c2bfd591fbbad745d80963`

Health status/time: `HTTP 200 — {"status":"ok","service":"postdee-api"} at 2026-08-09T12:29:24.3197833Z`

Matrix APK SHA-256: `879E74425CC95B5E1C98831A688F20F687CECD7F8C5F078714C3A4AC789A2145`

Fixture SHA-256: recorded per file below

Overall status: `BLOCKED — likely ElevenLabs provider quota exhaustion` — the initial upstream HTTP `401` events were recorded at `19:47:44` and `19:47:24` ICT. A new 30-day, Speech-to-Text-only Staging key was then deployed on the unchanged code SHA and the 21:57 ICT `target-30` rerun was attributed to that new key, but it still returned upstream HTTP `401`. ElevenLabs showed 9,994/10,000 workspace credits used (6 remaining), so quota exhaustion is the leading diagnosis; the exact upstream response detail was not captured. Both attempts failed closed before output or PostDee quota use, and the remaining API-dependent rows stay pending.

## Local verification completed before deployment

- API tests: `914/914 PASS`
- API build: `PASS`
- Prisma validation: `PASS`
- Prisma helper TypeScript check: `PASS`
- Flutter tests: `759/759 PASS`
- Flutter analyze: `PASS`
- GitHub Actions CI for candidate SHA: `PASS` ([run 31312190274](https://github.com/NOI56/PostDeeMobile/actions/runs/31312190274))
- Superseded pre-deploy APK: SHA-256 `73E535CDF8CE69C1E378C531FA44607BE77C2E4EEFF7F305756D69209ED83A48`, modified `2026-08-09T06:11:57.4704356Z`; do not install for this matrix
- Fresh post-deploy APK: SHA-256 `879E74425CC95B5E1C98831A688F20F687CECD7F8C5F078714C3A4AC789A2145`, size `271361927` bytes, modified `2026-08-09T12:30:29.7941984Z`
- Pixel 8 isolated matrix: `PENDING`

These automated results do not replace the deployed-SHA gate or device matrix.

## Runtime contract under test

Every optional subtitle, silence, repeated-speech, and colour toggle starts off.
Target-only shortening remains valid with all optional toggles off.

Transcript gaps are silence candidates only. The Android/iOS client confirms
each candidate against the source waveform before rendering; failed or
ambiguous verification keeps the original audio. Color-only edits at original
duration render locally for Pro users and do not consume AI editing minutes.

Internal repaired transcript boundaries may align target cuts while visible
subtitles are off. Thai repeated-speech timing must reconstruct exactly or fail
closed. Colour plus shortening remains on one prepare call; unknown enabled
capabilities stop before side effects.

## Fixture evidence

| Fixture | SHA-256 | Source/license status | Matrix status |
| --- | --- | --- | --- |
| `raw-talking-head-thai-vertical-cc-by-sa.mp4` | `109B2DBF823170B926D46A5C3B610389CB97648A944CACF0AC70EDFBABB36198` | Wikitongues Dang derivative, CC BY-SA 4.0; documented in `docs/testing/AI_EDIT_THAI_CLIPS.md` | `PENDING` |
| `thai-stacked-marks-30s.mp4` | `89070EC6DB537E4B32BC87A533FB3A14314AF8D6F7A7702416509195A551CC97` | Embedded metadata identifies Wikitongues Dang derivative, CC BY-SA 4.0 | `PENDING` |
| `qa-thai-natural-interview-45s.mp4` | `DFC6D6CCD6D7057E31582A8A0D242421F5E3E66AFD24FE8287DC29DB247FE1CB` | BURIRAM UNITED excerpt, CC BY 3.0; documented in QA report | `PENDING` |
| `qa-thai-scripted-clean-45s.mp4` | `7083E4438DC547B6C689E9E597DABE21730E42C698F9B12252E71C4BDAF95468` | Los Angeles Police Department excerpt, public domain; documented in QA report | `PENDING` |
| `qa-thai-background-noise-45s.mp4` | `02A0EC368102EDA0BB1D1DB39B5D13A55FB711B0A5325B283853AF2D38B00601` | FAT MANGO Showreel excerpt, CC BY 3.0; documented in QA report | `PENDING` |
| `qa-thai-news-voiceover-45s.mp4` | `B6EA38932E70DE18862DF768E3F8DCB5E96375757DE9D199938715EEE6F9B163` | MGR Online VDO excerpt, CC BY 3.0; documented in QA report | `PENDING` |

The fixture files are present and their provenance is documented. Recompute and
compare every hash immediately before the matrix; a mismatch blocks testing.

## Isolated Pixel 8 matrix

| Case | Source | Selected toggles | Start/end | Output duration | Quota before/after | Visual/audio result | Pass |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| target-30 | `raw-talking-head-thai-vertical-cc-by-sa.mp4` | target only, 00:30; all optional toggles off | Initial: `2026-08-09T12:47:32.9789282Z`–`2026-08-09T12:48:01.8139282Z`; recovery rerun request: `2026-08-09 21:57:28 ICT` (end not separately recorded) | no output in either attempt | `178/178 PostDee minutes remaining` in both attempts | Fail-closed before render: `ระบบถอดเสียง AI ยังไม่พร้อม กรุณาลองใหม่อีกครั้ง`. After installing a new STT-only key and deploying the environment on the same SHA, the rerun was attributed to that new key but still received upstream HTTP `401`; ElevenLabs provider balance showed only 6/10,000 workspace credits remaining | `BLOCKED — likely provider quota exhaustion` |
| target-60 | `raw-talking-head-thai-vertical-cc-by-sa.mp4` | target only | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| target-custom | `raw-talking-head-thai-vertical-cc-by-sa.mp4` | target only | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| subtitle | `thai-stacked-marks-30s.mp4` | subtitle | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| silence | `qa-thai-natural-interview-45s.mp4` | silence | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| repeat-safe | `qa-thai-scripted-clean-45s.mp4` (`ชุมชน / ชุมชน`) | repeat | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| repeat-unsafe | `qa-thai-background-noise-45s.mp4` | repeat | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| color-local | `qa-thai-news-voiceover-45s.mp4` | colour only, original duration; all other supported toggles off | `2026-08-09T12:55:22.9445459Z`–`2026-08-09T13:00:28.9891700Z` | `45.019333s` | `178/178 minutes remaining` | Visible colour change at the same 00:16 frame; no cuts/subtitles; decoded audio SHA-256 is identical to source; full export is `qa-thai-news-voiceover-45s_edited.mp4`; direct zero-upload/prepare log evidence pending | `PARTIAL PASS — device/render evidence` |
| color-target | `qa-thai-news-voiceover-45s.mp4` | colour + target | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| combined | `raw-talking-head-thai-vertical-cc-by-sa.mp4` | subtitle + silence + repeat | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |

## Renderer acceptance evidence

| Measurement | Result/evidence |
| --- | --- |
| Output codec | `color-local`: MPEG-4 Simple Profile, `yuv420p`, 720×404; AAC-LC 48 kHz stereo |
| Output FPS | `color-local`: exact `30/1` average and real frame rate; 1,350 video and 2,110 audio packet timestamps are monotonic |
| Output file size | `color-local`: `14,823,307` bytes; SHA-256 `79EE03ABC1432288B974DC2C4BFDCC37498C116FF3953F6DA742F8458CBEE3DB` |
| Audio peak | `color-local`: `-3.4 dBFS`; decoded audio SHA-256 matches the source exactly (`17acc6b77ba46109870b2e663e66b69146fced40ffd5166c1b86570107faf0e5`) |
| A/V sync | `color-local`: video starts `0.000s`, audio starts `0.006s`; durations `45.000s`/`45.013333s`. Technical timebase delta is 6 ms at start and 13.333 ms at end; manual lip-sync judgment for the full matrix remains pending |

These measurements remain open work. Do not describe them as fixed until this
table contains values and evidence from the exact APK/source hashes above.

## Evidence links and notes

- Pixel 8 AVD/serial: `Pixel_8` / `emulator-5554`; Staging package installed and focused, verified `2026-08-09T12:34:41.3673330Z`
- Device fixture paths: `/sdcard/Download/PostDee-QA/{raw-talking-head-thai-vertical-cc-by-sa.mp4,thai-stacked-marks-30s.mp4,qa-thai-natural-interview-45s.mp4,qa-thai-scripted-clean-45s.mp4,qa-thai-background-noise-45s.mp4,qa-thai-news-voiceover-45s.mp4}`; all six device SHA-256 values match the fixture table
- Full-matrix start/end time: `PENDING`; completed case intervals are recorded in the matrix rows above
- Exact candidate/deploy commit: [`6695e5f1d6050e0656c2bfd591fbbad745d80963`](https://github.com/NOI56/PostDeeMobile/commit/6695e5f1d6050e0656c2bfd591fbbad745d80963)
- Render deploy screenshot: ignored local evidence `.tmp/test-evidence/ai-edit-correctness/render-deploy-6695e5f.png`, SHA-256 `2B6F84778EB8A44E0C2C335D11DC149036942DBA7C98CCDB1602D3E898E7B262`
- Render displayed the unique commit prefix `6695e5f` as `Deploy live` on branch `main` at 2026-08-09 19:04 ICT; the linked GitHub commit resolves that prefix to the full deployed SHA recorded above
- Operational warning: Render displayed `Payment failed — Update your credit card to avoid losing access to your workspace's services.` Health was still OK at the recorded time; stop the matrix if the service becomes unavailable
- `target-30` setup screenshot: ignored `.tmp/test-evidence/ai-edit-correctness/target-30-setup.png`, SHA-256 `B7FDFBA43DFFC1A7C68C185C16780DD1802F30ABF12543835F546E8BFAE2CB09`
- `target-30` final-attempt screen recording: ignored `.tmp/test-evidence/ai-edit-correctness/target-30-final-attempt.mp4`, SHA-256 `55F8385902C4D12108A010B053953F4ACB8DFE04E6379D2D51D56814EFA17178`; the final frame captures the Thai provider-unavailable message
- Cropped Render ElevenLabs 401 screenshot: ignored `.tmp/test-evidence/ai-edit-correctness/render-elevenlabs-401.png`, SHA-256 `9A277C96BFD5A5C9378E2EFA130F359E375BF03753047FA1FB0776773C14DB16`; application logs show upstream status `401` at `19:47:44` and `19:47:24` ICT without exposing the API key
- New Staging key evidence: ignored `.tmp/test-evidence/ai-edit-correctness/elevenlabs-key-rotated-enabled.png`, SHA-256 `C48F17F7947E52325EB53EA0D1DC8B54446512ADE917AC13BAE2C6179DD3CE8A`; it records an enabled 30-day key restricted to Speech to Text and does not contain the key value
- Same-SHA environment deploy evidence: ignored `.tmp/test-evidence/ai-edit-correctness/render-env-key-deploy-live.png`, SHA-256 `41F52831742461409C366B2D1D0ED69C99598B5E4433475DB670DA0149BF015B`; Staging stayed on `6695e5f1d6050e0656c2bfd591fbbad745d80963`, and `/health` returned HTTP 200/status `ok` at `2026-08-09T14:51:31.7411980Z`
- Recovery rerun evidence: ignored `.tmp/test-evidence/ai-edit-correctness/target-30-recovery-2026-08-09/setup-before.png` (`9E91A15ED968C12F4C8DECEA30AF3941124F4F8AD73EAF53452E9386396FDFB5`), `attempt.mp4` (`D70F6CF8C0E99A9B7B53946878E4529951F7F7051FE35BEDA505C680F14B32AB`), and `after-failure.png` (`EDB9B2AFD70529ED0949CB487B55793FF7ACD33AEDCFF54132E9344628AF5EDE`)
- New-key request attribution evidence: ignored `.tmp/test-evidence/ai-edit-correctness/elevenlabs-request-log-new-key-401.png`, SHA-256 `B7EEDDC49A3B5FE9F6460B3D60F516AB8F8DF32A57D50231DB3A45E1B3E06D90`; the Request Log is filtered to the new key and shows `/v1/speech-to-text`, HTTP `401`, at `2026-08-09 21:57:28 ICT`. Account-identifying fields remain only in this ignored local evidence and must not be published
- Provider balance evidence: ignored `.tmp/test-evidence/ai-edit-correctness/elevenlabs-quota-9994-of-10000.png`, SHA-256 `B21AB25ACA57E4FE487E099A7BE792632346F40F2149F0582F43F1432F0A2FCD`; it shows 9,994/10,000 workspace credits used (6 remaining). This is separate from the unchanged PostDee balance of 178/178 AI-edit minutes
- Diagnosis references: ElevenLabs documents that 400/401 responses can include `quota_exceeded` ([400/401 help](https://elevenlabs.io/docs/help-center/technical/api-error-code-400-or-401)), API keys consume workspace quota ([API keys](https://elevenlabs.io/docs/overview/administration/workspaces/api-keys)), and Speech to Text usage is duration-priced ([API pricing](https://elevenlabs.io/pricing/api?price.section=speech_to_text)). Because no upstream response detail was captured, this record treats quota exhaustion as the leading diagnosis rather than a confirmed exact error
- Recovery safety: no payment, plan upgrade, Production change, old-key revocation, or code rollback was performed
- `color-local` setup screenshot: ignored `.tmp/test-evidence/ai-edit-correctness/color-setup-view.png`, SHA-256 `40BC12DFBCF5A158991D2EE0B0D430E9D0374162BFDF64EEB7ACD2D61E61E802`
- `color-local` original/AI comparison screenshots: ignored `.tmp/test-evidence/ai-edit-correctness/color-local-original.png` (`9F3A669F54FACC87517A9281E674F7AE5E473EE8507766C1987499FC1A9D3171`) and `color-local-ai.png` (`420D5423E367E56D90C1C6F8344C2FE2B83F720A07151D9FF6EA777003FFE27E`)
- `color-local` full export: ignored `.tmp/test-evidence/ai-edit-correctness/color-local/qa-thai-news-voiceover-45s_edited.mp4`, SHA-256 `79EE03ABC1432288B974DC2C4BFDCC37498C116FF3953F6DA742F8458CBEE3DB`; uploader screenshot SHA-256 `FBC1305975CDCE911958CFE4E3B708BEAC92A711C774A4BA1A06147DCB0B8AAC`
- Additional screenshots: `PARTIAL`; completed-case screenshots are listed above, while the remaining matrix evidence is pending
- Output files: `PARTIAL`; the validated `color-local` full export is listed above, while its direct no-upload/prepare trace and outputs for the remaining matrix rows are pending
- Failure/rollback notes: the new Staging key was demonstrably used, yet ElevenLabs still returned upstream HTTP `401` before recipe/render/quota reservation while only 6/10,000 provider credits remained. This strongly supports provider quota exhaustion but does not prove the exact upstream error detail. Silence/repeat rollback flags do not address provider availability, so no rollback APK was built. Do not retry or purchase/upgrade implicitly; wait for the provider quota reset or restore quota only under separate approval, then rerun `target-30` once before continuing API-dependent rows. The superseded key remains active temporarily and must be reviewed/revoked after the replacement path is accepted; set a finite Staging key cap before future quota replenishment.
