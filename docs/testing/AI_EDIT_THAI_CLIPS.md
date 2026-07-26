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

## Duration policy

- Accept an original clip up to 10:00. Reject anything longer before upload or
  AI preprocessing begins.
- Keep the duration control at the far-right `original / no shortening` stop
  after a clip is selected.
- For an original longer than 3:00, moving left from the original stop enters
  AI shortening at 3:00, then continues down to 0:05.
- For an original at or below 3:00, never allow the requested result to exceed
  the original duration.

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

## 2026-07-26 transcription comparison

Staging commit `612a8cc` processed four 45-second Thai clips to 30-second
results with both ElevenLabs Scribe v2 and Groq. A manually checked 19.1-second
opening plus the publisher-supplied Thai transcript for the 45-second news clip
provided 763 normalized reference characters.

| Provider | Combined verified CER |
| --- | ---: |
| ElevenLabs Scribe v2 | 2.7523% |
| Groq Whisper | 71.5596% |

Groq returned substantially less text on every four-style replay. Its
normalized character coverage relative to ElevenLabs was 14.69% for news,
34.35% for scripted speech, 18.18% for natural interview, and 42.04% for noisy
field audio. These ratios diagnose omissions; the last three are not CER
because no independent Thai reference transcript is available.

The source-page audit found no human TimedText for the scripted, interview, or
noisy clips. YouTube exposes only auto-generated Thai captions for the
scripted and interview sources, and no caption track for the noisy source.
Those captions are another model observation, not independent ground truth,
so they are intentionally excluded from CER.

The noisy clip also exposed two recurring domain-term errors:
`นกโรงประจุก` instead of `นกกรงหัวจุก`, and `สี่ย่องแปดดอก` instead of the
competition term `4 ยก 8 ดอก`. Both correct forms are now staging-only
ElevenLabs keyterms. Replaying the complete 45-second source through the live
Pixel 8 emulator produced `นกกรงหัวจุก`, `สี่ยก`, and `แปดดอก`, with neither
previous error present. The rendered SRT contained 52 physical single-line
cues, a maximum of four semantic words per cue, and no cue above the five-word
limit. The video, audio, and MP4 container each remained exactly 45.000
seconds.

The fresh ElevenLabs renders exposed three PostDee cue-boundary regressions:
`ทำใ / ห้`, `หลา / ยๆ`, and `เด็ / กๆ`. The shared Thai subtitle lexicon now
protects `ทำให้`, `หลายๆ`, and `เด็กๆ`. Replaying all four stored SRTs preserves
every source character, removes all three splits, and keeps every rebuilt cue
at or below 18 graphemes.

After deploy `dep-d9imv8navr4c73b4i720` became Live on commit `049e3d4`, the
three affected 45→30-second app flows were generated again on the Pixel 8
emulator. Their live SRT outputs contained the complete `ทำให้`, `หลายๆ`, and
`เด็กๆ` tokens with none of the previous cross-cue fragments.

The rendered MP4 duration was also probed independently after the live app
flow. The 30-second target produced 30.000 seconds, while a slider-selected
19-second target produced 19.000 seconds for the video stream, audio stream,
and MP4 container. A 150.635-second talking-head clip exposed a separate edge
case: the transcript ended before the silent media tail, so a 60-second target
produced a 61.933-second MP4. The renderer now caps the muxed output at the
requested target, while the existing planner still chooses and expands the
content ranges. Repeating the same 150.635→60-second flow on the Pixel 8 after
the fix produced exactly 60.000 seconds for the video stream, audio stream, and
MP4 container.

## 2026-07-26 Thai combining-mark render acceptance

The first regenerated result used Noto Sans Thai Bold with outline 1. Enlarged
pixel review showed that `้` still visually joined `ํ` in `ซ้ำ`, so that result
was rejected instead of being treated as acceptance.

The same 38 MB / 150.635-second source was then regenerated through the
installed Staging app on the Pixel 8 emulator with Bai Jamjuree Bold. The
render workspace contained the bundled 81,840-byte font, and the final 304x540
preview contained MPEG-4 video plus AAC audio for exactly 60.000 seconds.

Frame inspection covered `ซ้ำแล้ว`, `ซ้ำอีกเพื่อ`, and `มีอาหารที่`. The first
review considered the marks separated, but a 2026-07-27 enlarged audit rejected
that conclusion: at the real 304x540 resolution, the `่` in `ที่` still joined
the `ี`. The tested medium style used font size 25, outline 0.5, and shadow 0.
Prompt and Anuphan remain selectable.

The transcript strings were already valid NFC Thai in the generated SRT, so
this regression was in font metrics plus outline thickness, not in ElevenLabs
transcription or Thai Unicode ordering.

## 2026-07-27 context-aware Thai tone-mark correction

Code-point inspection confirmed the source SRT already used the valid sequence
`ท + ี + ่`. Nine ordinary Thai fonts and outline widths from 0 through 0.5
were rasterized at 304x540; all could still collapse stacked marks to one
component. The corrective path keeps editable text untouched and replaces only
tone marks stacked above `ั/ิ/ี/ึ/ื/็/ํ` or immediately before composed or
decomposed `ำ` in the temporary libass SRT. Internally renamed OFL derivatives
for Bai Jamjuree, Prompt, and Anuphan each map those four temporary private-use
values to the matching face's raised tone glyphs. Direct tones such as `เก่ง`,
`กุ้ง`, and `จ๋า` remain unchanged.

Pixel 8 Staging acceptance used a new 30-second Thai talking-head extract and
consumed one metered minute. The short-source preview was 406x720 with video and
audio for exactly 30.000 seconds. Its 38-cue temporary SRT exercised 12 mai-ek,
7 mai-tho, and 1 mai-chattawa protected glyphs. Pixel inspection of
`ที่ในเมือง`, `แล้วซ้ำอีก`, and `ตั๋วครั้งนึง` showed visible gaps between the
upper vowel and tone mark while the direct tone in `แล้ว` retained its normal
shape. Subtitle Studio then re-rendered the same analysis locally with
Bai Jamjuree, Anuphan, and Prompt; each workspace contained its matching
PostDee derivative and all three outputs passed the same frame check without
using another AI minute.

The current generated Bai derivative and extracted Android SRT were also
rendered through libass at the long-source 304x540 preview size. The same three
frames remained separated. The saved 38-cue draft retained `fontId: Prompt`,
normal Thai such as `ที่ในเมือง`, and no `U+E000` through `U+E003`; the private
glyphs existed only in temporary render SRT files.

## 2026-07-27 active-word and effect automation

The staging contract now publishes validated `words` inside each subtitle cue.
Automated API and mobile tests cover legacy field omission, authoritative empty
lists, malformed/mixed payloads, non-finite and overlapping ranges, exact cue
text reconstruction, Thai character fragments, current-word preview colour,
ASS text escaping, source-time trim shifting, and static SRT fallback. Pop and
fade select ASS even without word timing. Pop runs `78 -> 103 -> 100` only at
cue start; fade-in belongs to the first dialogue slice and fade-out to the last.
Tests also cover removal of trimmed-out word timings and the single static-SRT
retry after an explicit subtitle/libass ASS failure.

The original long Thai talking-head fixtures still need new active-word exports
on the Pixel 8 plus sampled-frame comparison against the live Flutter preview.
Physical Android and iPhone tests remain required before enabling this path in
a Store build.

## 2026-07-27 short-source active-word E2E and regressions

A real Pixel 8 Staging run selected a 30-second, 540x960 Thai talking-head
source and requested a 20-second result. Prepare took about 10 seconds and
reported three silence cuts, one filler word, and 2.8 seconds of detected
cleanup. The accepted Pop render probes as exactly 20.000 seconds, 406x720,
2,833,565 bytes, with MPEG-4 video and AAC audio. Sampled frames kept captions
to one line, showed the active word in green, retained visible Thai stacked-mark
separation, and did not clip either horizontal edge.

The same run exposed two server cue-boundary regressions in its saved 38-cue
draft: `มีของให|ม่ๆ` and `นึงระยะทา|งใกล้ๆ`. Provider normalization and recipe
generation now share exact tests for `ใหม่ๆ` and `ใกล้ๆ`. The automatic cue
grouper also rebalances whole words for fixable sub-0.7-second pairs while
preserving the selected word cap, 18-grapheme cap, gaps, and source timing.
Truly unavoidable fast cues remain short rather than being stretched.

The mobile project identity now carries cue-segmentation revision 2 and the
draft controller requires the exact project ID, so this pre-fix draft cannot
overwrite a newly mapped project. The original file is retained for recovery.
Inspection of the rendered ASS also found sub-centisecond slices that rounded to
equal start/end timestamps. ASS generation now quantizes boundaries first,
omits collapsed events, and recalculates first/last Pop or Fade flags.

The Staging AI-edit quota reached zero after this run. The exact server
tokenization fixes therefore still require a deployed build plus refreshed test
quota for another live provider pass; automated API and renderer regressions
cover them in the meantime.
