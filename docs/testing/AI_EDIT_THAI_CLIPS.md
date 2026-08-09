# Thai AI Edit Test Clips

These fixtures exercise preprocessing and, once credentials are available,
whole-video Gemini selection. Media binaries live under ignored `.tmp` folders
and are not committed.

| Fixture | Type | Duration | Source and license |
| --- | --- | ---: | --- |
| `raw-talking-head-thai-vertical-cc-by-sa.mp4` | Vertical Thai talking head with blurred fill | 150.64 s | Local derivative supplied for testing; duration matches Wikitongues Dang. Treat as CC BY-SA 4.0 and retain attribution. |
| `thai-talking-head-dang-cc-by-sa.webm` | Horizontal Thai talking head, longer speech | 150.64 s | Wikitongues / Wikimedia Commons, CC BY-SA 4.0: https://commons.wikimedia.org/wiki/File:WIKITONGUES-_Dang_speaking_Thai.webm |
| `thai-talking-head-tao-cc-by-sa.webm` | Horizontal Thai talking head, different speaker | 114.24 s | Wikitongues and Teddy Nee / Wikimedia Commons, CC BY-SA 4.0: https://commons.wikimedia.org/wiki/File:WIKITONGUES-_Tao_speaking_Thai.webm |
| `thai-market-pexels-30139108.mp4` | Fast visual market scene, no speech | 7.96 s | LayG Traveller / Pexels free-use license: https://www.pexels.com/video/30139108/ |
| `thai-food-demo-pexels-5915856.mp4` | Close-up Thai food demonstration, no speech | 12.28 s | Francesco Navarro / Pexels free-use license: https://www.pexels.com/video/5915856/ |
| `thai-stacked-marks-30s.mp4` | Local 9:16 Thai subtitle/stacked-mark fixture | 30.03 s | Embedded MP4 metadata identifies title `Thai raw talking-head test clip`, artist `Wikitongues`, and source `WIKITONGUES- Dang speaking Thai, Wikimedia Commons`; comment says it was reframed to 9:16 without cutting content or changing audio; copyright is CC BY-SA 4.0. SHA-256: `89070EC6DB537E4B32BC87A533FB3A14314AF8D6F7A7702416509195A551CC97`. |
| `qa-thai-news-voiceover-45s.mp4` | Local 45 s news/fast-visual excerpt | 45 s | MGR Online VDO, `"น้องหมูเด้ง" เซเลบสวนสัตว์เปิดเขาเขียว`, CC BY 3.0: https://commons.wikimedia.org/wiki/File:%22น้องหมูเด้ง%22_เซเลบสวนสัตว์เปิดเขาเขียว_-_เรื่องเด่นทั่วไทย.webm |
| `qa-thai-scripted-clean-45s.mp4` | Local 45 s clean scripted-speech excerpt | 45 s | Los Angeles Police Department, `AAPI Hate Crime PSA - Thai`, public domain: https://commons.wikimedia.org/wiki/File:AAPI_Hate_Crime_PSA_-_Thai.webm |
| `qa-thai-natural-interview-45s.mp4` | Local 45 s natural-interview excerpt | 45 s | BURIRAM UNITED, `GU Talk EP.07 พี ศศลักษณ์ ไหประโคน`, CC BY 3.0: https://commons.wikimedia.org/wiki/File:GU_Talk_EP.07_พี_ศศลักษณ์_ไหประโคน.webm |
| `qa-thai-background-noise-45s.mp4` | Local 45 s field-speech/background-noise excerpt | 45 s | FAT MANGO Showreel, `Traditional Bird Singing Contest, Phuket`, CC BY 3.0: https://commons.wikimedia.org/wiki/File:Traditional_Bird_Singing_Contest,_Phuket_-_A_mini_documentary.webm |

The Pexels license permits free use and modification; do not redistribute an
unaltered stock file as a stock asset or imply endorsement. CC BY-SA derivatives
must keep attribution, link the license, note modifications, and use a compatible
share-alike license when distributed.

## 2026-07-23 preprocessing result

Command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-ai-edit-visual-proxy.ps1 `
  -InputDirectory .tmp/test-videos/licensed
```

| Case | Source size | Proxy size | Source / proxy duration | Result |
| --- | ---: | ---: | ---: | --- |
| Thai food demo | 7.46 MB | 0.13 MB | 12.28 / 12.00 s | Pass |
| Dynamic Thai market | 38.72 MB | 0.06 MB | 7.96 / 8.00 s | Pass |
| Tao talking head | 18.58 MB | 0.77 MB | 114.24 / 113.26 s | Pass |
| Vertical talking head | 38.31 MB | 1.49 MB | 150.64 / 151.00 s | Pass |

All proxies cover the complete timeline at 1 fps, use 360 px width, remain far
below the 50 MiB API cap, and differ from source duration by less than one second.
This proves transport coverage, not editorial quality. The original local
credential blocker no longer describes the current repository baseline: the
operational documents record configured Staging provider paths, but secret
values cannot be verified from Git. The remaining release gate is a fresh,
authenticated Staging run of these fixtures on the deployed build, followed by
Thai editorial scoring and physical-device preview/export checks. Reconfirm the
hidden Render credentials before each controlled provider run.

## Duration policy

- Accept an original clip up to 10:00. Reject anything longer before upload or
  AI preprocessing begins.
- Keep the duration control at the far-right `original / no shortening` stop
  after a clip is selected.
- For an original longer than 3:00, moving left from the original stop enters
  AI shortening at 3:00, then continues down to 0:05.
- For an original at or below 3:00, never allow the requested result to exceed
  the original duration.

## Current correctness contract and isolated matrix

Every optional subtitle, silence, repeated-speech, and colour switch starts off.
Test one capability at a time before the combined case; target-only shortening
is valid with all optional switches off.

Transcript gaps are silence candidates only. The Android/iOS client confirms
each candidate against the source waveform before rendering; failed or
ambiguous verification keeps the original audio. Internal repaired
`transcript.boundarySegments` may align target cuts while visible subtitles are
off; missing or unsafe evidence keeps the planner cut instead of falling back to
raw provider segments. Thai repeated-speech fragments must reconstruct by exact
NFC text in raw provider order inside one reliable segment, or fail closed.

Unavailable-only repeat/subtitle/silence analysis does not consume AI editing
minutes. Color-only edits at original duration render locally for Pro users and
do not consume AI editing minutes. Colour plus shortening stays on one prepare
call; unknown enabled capabilities fail closed before side effects. A local
colour result without real subtitle content must use `_edited.mp4`.

Use the ten matrix rows in
`docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md`. Before running,
recompute SHA-256 for the APK and every video fixture and record the exact values;
the documented stacked-mark hash is provenance evidence, not permission to skip
the matrix-time hash. Output codec, FPS, file size, audio peak, and A/V sync are
still pending device checks and must not be described as fixed without evidence.

## Editorial acceptance rubric

For each speech fixture test 30 s, 60 s, and one custom target. A Thai reviewer
scores each result from 1–5 for:

- opening hook;
- complete and coherent speech;
- visible subject/product relevance;
- avoidance of blur, empty frames, and duplicated moments;
- target duration within one second.

Do not call the feature production-ready unless the average is at least 4/5,
no sentence is cut mid-word, and visual planning beats the audio-only baseline
on at least two of the three content styles.
