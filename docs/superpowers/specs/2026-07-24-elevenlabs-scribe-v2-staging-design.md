# ElevenLabs Scribe v2 Staging and Groq Comparison Design

**Date:** 2026-07-24  
**Status:** Approved design pending written-spec review  
**Scope:** PostDee API transcription provider and staging-only A/B evaluation

## Goal

Add ElevenLabs Scribe v2 as an optional Thai transcription provider, keep
Groq available as an immediate configuration rollback, and measure which
provider produces better PostDee subtitles on the same source clips.

The decision priority is:

1. Thai transcription accuracy and absence of hallucinated words.
2. Subtitle word-boundary timing.
3. Processing latency.
4. Estimated provider cost.

## Non-goals

- Do not change the mobile UI.
- Do not call both providers for normal customer requests.
- Do not add automatic ElevenLabs-to-Groq fallback in this trial.
- Do not switch production away from Groq during the trial.
- Do not commit or log either provider's API key.
- Do not change the edit-plan provider; Groq continues to create edit plans.

## Architecture

The existing `TranscriptionProvider` interface remains the boundary used by
AI editing and caption generation. A new ElevenLabs adapter implements that
same interface and is selected with:

```text
TRANSCRIPTION_PROVIDER=elevenlabs
ELEVENLABS_API_KEY=<Render secret>
ELEVENLABS_TRANSCRIPTION_MODEL=scribe_v2
```

`mock`, `openai`, and `groq` remain supported. The default ElevenLabs model is
`scribe_v2`. The committed Render staging blueprint declares the secret
without its value. Production continues to declare Groq as its transcription
provider.

## ElevenLabs request

The adapter downloads the same stored audio bytes used by the current Groq
adapter and sends one multipart request to:

```text
POST https://api.elevenlabs.io/v1/speech-to-text
xi-api-key: <secret>
```

The form contains:

```text
file=<audio bytes>
model_id=scribe_v2
language_code=th
timestamps_granularity=word
tag_audio_events=false
diarize=false
```

The request does not enable keyterm prompting during the first comparison, so
the test measures the base model and avoids the optional prompting surcharge.
Verbatim speech remains enabled so fillers are available to PostDee's existing
filler-word editing logic.

## Response normalization

ElevenLabs response items are normalized into PostDee's existing
`TranscriptionResult`:

- Items with `type=word` and valid numeric `start` and `end` become
  `TranscriptWord` entries.
- Items with `type=spacing` are used only to reconstruct readable mixed
  Thai/English text; they never become timed subtitle words.
- Audio-event and unknown item types are ignored.
- Invalid, non-finite, negative, or reversed timings are excluded.
- `language_code` is passed through the existing language normalizer.
- Duration is the greatest valid word end time, or zero when there are no
  timed words.
- The adapter reports the configured model name as `model`.

Because Scribe v2 does not return PostDee-style segments, the adapter groups
valid timed words into short segments. A segment ends at the earliest of:

- terminal punctuation;
- a pause of at least 0.55 seconds;
- 4.0 seconds of segment duration; or
- 32 Unicode grapheme clusters of visible text.

Spacing events may contribute display spaces but do not change timing. Empty
segments are not emitted. This limits oversized subtitle phrases while the
mobile subtitle renderer remains responsible for final one-line layout.

## Error handling and safety

- Missing `ELEVENLABS_API_KEY` fails API startup when
  `TRANSCRIPTION_PROVIDER=elevenlabs`.
- Missing media fetching support fails API startup with a provider-specific
  message.
- Non-2xx ElevenLabs responses produce a provider failure and never silently
  fall back to mock or Groq.
- Malformed successful responses are normalized safely; an empty response
  produces empty text, words, and segments instead of fabricated speech.
- API keys are read only from environment variables and are never included in
  request logs, errors, benchmark artifacts, or Git.
- The existing 30-day ElevenLabs key must be rotated before 2026-08-23.

An explicit failure is important during A/B testing: silent fallback would
make a Groq result look like an ElevenLabs result and invalidate the
comparison.

## Test strategy

### Automated tests

Tests are written before implementation and cover:

- configuration parsing and rejection of unsupported provider names;
- required ElevenLabs key and media downloader;
- endpoint, `xi-api-key`, model, Thai language, timestamp, audio-event, and
  diarization form fields;
- word/spacing/audio-event normalization;
- mixed Thai/English spacing;
- duration derivation;
- punctuation, pause, duration, and grapheme segment boundaries;
- malformed timing and empty response handling;
- non-2xx provider errors;
- Render staging secret declaration while production remains on Groq.

The full API test suite and TypeScript build must pass before deployment.

### Live A/B corpus

Use the exact same encoded audio file for both providers. The minimum corpus is
three Thai clips:

1. The existing 2:30 vertical talking-head test clip.
2. A Thai product/review clip with brand names or English loanwords.
3. A Thai clip with music, background noise, or faster speech.

Each clip gets a human-corrected reference transcript. At least 20 spoken-word
anchors per clip receive manually checked start and end times. Provider output
is saved as sanitized benchmark JSON containing transcript, timings, model,
elapsed milliseconds, and no secrets.

## Comparison metrics

The report includes raw values for both providers:

- **Thai character error rate (CER):** insertions, deletions, and substitutions
  against the corrected transcript. Lower is better.
- **Hallucinated phrase count:** provider text unsupported by audible speech.
  Lower is better.
- **Opening coverage:** whether audible speech at the clip start is omitted.
- **Median timing error:** absolute start/end error across the checked anchors.
  Lower is better.
- **P95 timing error:** exposes occasional badly shifted subtitles.
- **Processing latency:** wall-clock seconds for the provider request.
- **Estimated cost:** published per-minute price multiplied by tested duration.

Accuracy is decisive. If one provider lowers CER by at least 20% relative
without increasing hallucinations, it wins even when it is slower. If the CER
difference is less than 3 percentage points, timing breaks the tie, followed
by latency and cost.

The result is reported as both absolute values and relative improvement, for
example:

```text
CER: Groq 18.0%, ElevenLabs 10.0%
ElevenLabs relative improvement: (18 - 10) / 18 = 44.4%
```

## Rollout

1. Deploy code with Groq still selected.
2. Run the Groq pass and retain sanitized output.
3. Set staging `TRANSCRIPTION_PROVIDER=elevenlabs`.
4. Run the ElevenLabs pass with the same source files.
5. Produce the comparison report.
6. Keep the better provider on staging for app testing.
7. Change production only after the user reviews the results.

Rollback requires setting staging `TRANSCRIPTION_PROVIDER=groq`; no app build
or database migration is required.

## Acceptance criteria

- ElevenLabs is selectable without changing mobile code.
- Groq continues working and remains one-setting rollback.
- Automated tests prove request and normalization behavior.
- The full API tests and build pass.
- At least the existing 2:30 Thai clip completes through both providers.
- The report states accuracy, hallucinations, opening coverage, timing,
  latency, cost, and relative improvement.
- Production provider settings remain unchanged until explicit approval.
