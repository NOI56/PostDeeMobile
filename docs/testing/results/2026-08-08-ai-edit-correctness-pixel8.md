# AI Edit Correctness — Pixel 8

This is the evidence record for the Task 9 isolated Pixel 8 matrix. Automated
verification and local artifact hashes may be recorded before deployment, but no
device-matrix row may be marked pass until the candidate and deployed Staging
SHA match and the case has real evidence.

Candidate deploy SHA: `PENDING`

Deployed Staging SHA: `PENDING`

API runtime code SHA: `PENDING`

Health status/time: `PENDING`

Matrix APK SHA-256: `73E535CDF8CE69C1E378C531FA44607BE77C2E4EEFF7F305756D69209ED83A48`

Fixture SHA-256: recorded per file below

Overall status: `PENDING`

## Local verification completed before deployment

- API tests: `914/914 PASS`
- API build: `PASS`
- Prisma validation: `PASS`
- Prisma helper TypeScript check: `PASS`
- Flutter tests: `759/759 PASS`
- Flutter analyze: `PASS`
- Fresh APK modified time (UTC): `2026-08-09T06:11:57.4704356Z`
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
| target-30 | `raw-talking-head-thai-vertical-cc-by-sa.mp4` | target only | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| target-60 | `raw-talking-head-thai-vertical-cc-by-sa.mp4` | target only | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| target-custom | `raw-talking-head-thai-vertical-cc-by-sa.mp4` | target only | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| subtitle | `thai-stacked-marks-30s.mp4` | subtitle | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| silence | `qa-thai-natural-interview-45s.mp4` | silence | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| repeat-safe | `qa-thai-scripted-clean-45s.mp4` (`ชุมชน / ชุมชน`) | repeat | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| repeat-unsafe | `qa-thai-background-noise-45s.mp4` | repeat | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| color-local | `qa-thai-news-voiceover-45s.mp4` | colour | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| color-target | `qa-thai-news-voiceover-45s.mp4` | colour + target | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |
| combined | `raw-talking-head-thai-vertical-cc-by-sa.mp4` | subtitle + silence + repeat | `PENDING` | `PENDING` | `PENDING` | `PENDING` | `PENDING` |

## Renderer acceptance evidence

| Measurement | Result/evidence |
| --- | --- |
| Output codec | `PENDING` |
| Output FPS | `PENDING` |
| Output file size | `PENDING` |
| Audio peak | `PENDING` |
| A/V sync | `PENDING` |

These measurements remain open work. Do not describe them as fixed until this
table contains values and evidence from the exact APK/source hashes above.

## Evidence links and notes

- Pixel 8 AVD/serial: `PENDING`
- Device fixture paths: `PENDING`
- Test start/end time: `PENDING`
- Screenshots: `PENDING`
- Output files: `PENDING`
- Failure/rollback notes: `PENDING`
