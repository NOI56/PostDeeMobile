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
This proves transport coverage, not editorial quality. Real cut-quality scoring
is blocked locally until `GEMINI_API_KEY`, R2, and authenticated staging mobile
are available together.

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
