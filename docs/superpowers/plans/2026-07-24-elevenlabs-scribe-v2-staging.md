# ElevenLabs Scribe v2 Staging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ElevenLabs Scribe v2 as an optional PostDee transcription provider and produce a fair Thai A/B report against Groq without changing the mobile UI or production provider.

**Architecture:** Keep the existing `TranscriptionProvider` interface and add one ElevenLabs adapter selected by environment configuration. Normalize Scribe word and spacing events into PostDee words and short segments, then use an operator-only comparison utility to calculate Thai character error rate, timing statistics, latency, and cost from sanitized results.

**Tech Stack:** Node.js, TypeScript, Express configuration, native `fetch`/`FormData`, Vitest, Render staging, ElevenLabs Speech-to-Text API, Groq Speech-to-Text API.

## Global Constraints

- Mobile UI and mobile API contracts do not change.
- Normal customer requests call exactly one configured transcription provider.
- Automatic fallback is not added during the trial.
- Production keeps `TRANSCRIPTION_PROVIDER=groq`.
- Staging can return to Groq by changing one environment value.
- `ELEVENLABS_API_KEY` and `GROQ_API_KEY` never enter Git, logs, benchmark artifacts, or command output.
- The first trial does not enable ElevenLabs keyterm prompting, diarization, or audio-event tags.
- The ElevenLabs key must be rotated before 2026-08-23.
- New behavior is implemented test-first.

---

### Task 1: Add ElevenLabs configuration without changing defaults

**Files:**
- Modify: `apps/api/src/config/env.test.ts:20-220,517-520`
- Modify: `apps/api/src/config/env.ts:16,20-95,289-297,454-530`

**Interfaces:**
- Consumes: process environment values supplied to `readServerConfig`.
- Produces: `TranscriptionProviderKind` including `elevenlabs`, plus `ServerConfig.elevenLabsApiKey` and `ServerConfig.elevenLabsTranscriptionModel`.

- [ ] **Step 1: Write failing configuration tests**

Add expectations for the default model and live values:

```ts
expect(config).toMatchObject({
  elevenLabsApiKey: undefined,
  elevenLabsTranscriptionModel: 'scribe_v2'
});
```

Add the live environment values to the populated configuration fixture:

```ts
ELEVENLABS_API_KEY: 'elevenlabs-key',
ELEVENLABS_TRANSCRIPTION_MODEL: 'scribe_v2'
```

Assert that they are read:

```ts
expect(config).toMatchObject({
  elevenLabsApiKey: 'elevenlabs-key',
  elevenLabsTranscriptionModel: 'scribe_v2'
});
```

Update the invalid-provider expectation:

```ts
expect(() => readServerConfig({ TRANSCRIPTION_PROVIDER: 'local' })).toThrow(
  'TRANSCRIPTION_PROVIDER must be mock, openai, groq, or elevenlabs'
);
```

- [ ] **Step 2: Run the configuration test and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/config/env.test.ts
```

Expected: FAIL because the ElevenLabs properties do not exist and
`elevenlabs` is not an accepted provider.

- [ ] **Step 3: Implement the minimal configuration**

Extend the provider kind:

```ts
export type TranscriptionProviderKind =
  | 'mock'
  | 'openai'
  | 'groq'
  | 'elevenlabs';
```

Add fields to `ServerConfig`:

```ts
elevenLabsApiKey?: string;
elevenLabsTranscriptionModel: string;
```

Accept the provider:

```ts
if (
  value !== 'mock' &&
  value !== 'openai' &&
  value !== 'groq' &&
  value !== 'elevenlabs'
) {
  throw new Error(
    'TRANSCRIPTION_PROVIDER must be mock, openai, groq, or elevenlabs'
  );
}
```

Read the values:

```ts
elevenLabsApiKey: readOptional(env, 'ELEVENLABS_API_KEY'),
elevenLabsTranscriptionModel:
  readOptional(env, 'ELEVENLABS_TRANSCRIPTION_MODEL') ?? 'scribe_v2',
```

- [ ] **Step 4: Run the configuration test and verify GREEN**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/config/env.test.ts
```

Expected: the file passes with zero failures.

- [ ] **Step 5: Commit configuration support**

```powershell
git add apps/api/src/config/env.ts apps/api/src/config/env.test.ts
git commit -m "feat(api): configure ElevenLabs transcription"
```

---

### Task 2: Implement the Scribe v2 adapter and segment normalizer

**Files:**
- Modify: `apps/api/src/modules/aiEdits/transcriptionProvider.test.ts:1-190`
- Modify: `apps/api/src/modules/aiEdits/transcriptionProvider.ts:1-275`

**Interfaces:**
- Consumes: `AudioSource`, `FetchAudio`, ElevenLabs API key, model ID, and the existing `TranscriptionInput`.
- Produces: `createElevenLabsTranscriptionProvider(options): TranscriptionProvider` and config selection through `createTranscriptionProviderFromConfig`.

- [ ] **Step 1: Write a failing test for required configuration**

```ts
it('requires an ElevenLabs key when TRANSCRIPTION_PROVIDER is elevenlabs', () => {
  const config = readServerConfig({
    TRANSCRIPTION_PROVIDER: 'elevenlabs'
  });

  expect(() =>
    createTranscriptionProviderFromConfig({
      config,
      fetchAudio: async () => ({
        data: new Uint8Array([1]),
        filename: 'clip.m4a',
        contentType: 'audio/mp4'
      })
    })
  ).toThrow(/ELEVENLABS_API_KEY is required/);
});
```

- [ ] **Step 2: Run the provider test and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/aiEdits/transcriptionProvider.test.ts
```

Expected: FAIL because config selection does not handle `elevenlabs`.

- [ ] **Step 3: Write failing request and normalization tests**

Import `createElevenLabsTranscriptionProvider`, then add a request test using a
fake `fetchImpl`. The fake response must contain Thai, a spacing event, English,
punctuation, and an audio event:

Add this fixture helper once and reuse it in the boundary tests:

```ts
const transcribeElevenLabsFixture = async (
  words: Array<Record<string, unknown>>,
  text = words.map((entry) => entry.text ?? '').join('')
) => {
  const provider = createElevenLabsTranscriptionProvider({
    apiKey: 'elevenlabs-key',
    model: 'scribe_v2',
    fetchAudio: async () => ({
      data: new Uint8Array([1, 2, 3]),
      filename: 'clip.m4a',
      contentType: 'audio/mp4'
    }),
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        language_code: 'tha',
        text,
        words
      })
    })
  });

  return provider.transcribe(legacyVideoInput('uploads/elevenlabs-clip'));
};
```

```ts
json: async () => ({
  language_code: 'tha',
  text: 'วันนี้ลด Weekend Market ค่ะ',
  words: [
    { type: 'word', text: 'วันนี้ลด', start: 0.1, end: 0.7 },
    { type: 'spacing', text: ' ' },
    { type: 'word', text: 'Weekend', start: 0.8, end: 1.2 },
    { type: 'spacing', text: ' ' },
    { type: 'word', text: 'Market', start: 1.25, end: 1.6 },
    { type: 'spacing', text: ' ' },
    { type: 'audio_event', text: '(music)', start: 1.6, end: 1.9 },
    { type: 'word', text: 'ค่ะ', start: 2.3, end: 2.6 }
  ]
})
```

Capture and assert the request:

```ts
expect(call).toMatchObject({
  url: 'https://api.elevenlabs.io/v1/speech-to-text',
  apiKey: 'elevenlabs-key',
  modelId: 'scribe_v2',
  languageCode: 'th',
  timestampGranularity: 'word',
  tagAudioEvents: 'false',
  diarize: 'false',
  noVerbatim: 'false'
});
```

Assert normalized output:

```ts
expect(result).toMatchObject({
  text: 'วันนี้ลด Weekend Market ค่ะ',
  language: 'th',
  durationSeconds: 2.6,
  model: 'scribe_v2'
});
expect(result.words).toEqual([
  { word: 'วันนี้ลด', start: 0.1, end: 0.7 },
  { word: 'Weekend', start: 0.8, end: 1.2 },
  { word: 'Market', start: 1.25, end: 1.6 },
  { word: 'ค่ะ', start: 2.3, end: 2.6 }
]);
expect(result.segments.map((segment) => segment.text)).toEqual([
  'วันนี้ลด Weekend Market',
  'ค่ะ'
]);
```

- [ ] **Step 4: Write failing segment-boundary tests**

Add separate tests proving each boundary:

```ts
it.each([
  ['punctuation', [
    { type: 'word', text: 'จริงไหม?', start: 0, end: 0.8 },
    { type: 'word', text: 'จริงค่ะ', start: 0.9, end: 1.6 }
  ], ['จริงไหม?', 'จริงค่ะ']],
  ['pause', [
    { type: 'word', text: 'ช่วงแรก', start: 0, end: 0.8 },
    { type: 'word', text: 'ช่วงใหม่', start: 1.36, end: 2 }
  ], ['ช่วงแรก', 'ช่วงใหม่']],
  ['duration', [
    { type: 'word', text: 'หนึ่ง', start: 0, end: 1.5 },
    { type: 'word', text: 'สอง', start: 1.6, end: 3 },
    { type: 'word', text: 'สาม', start: 3.1, end: 4.1 },
    { type: 'word', text: 'สี่', start: 4.2, end: 4.8 }
  ], ['หนึ่งสองสาม', 'สี่']],
])('splits ElevenLabs segments at the %s boundary', async (_, words, texts) => {
  const result = await transcribeElevenLabsFixture(words);
  expect(result.segments.map((segment) => segment.text)).toEqual(texts);
});
```

Add a 32-grapheme test using Thai combining characters and verify no empty
segment is emitted. Add malformed entries with `NaN`, negative, missing, and
reversed timings and assert they do not appear in `words`.

Add an empty-success test:

```ts
const result = await transcribeElevenLabsFixture([], '');
expect(result).toMatchObject({
  text: '',
  durationSeconds: 0,
  segments: [],
  words: []
});
```

Add a provider-error test:

```ts
it('throws when ElevenLabs responds with an error', async () => {
  const provider = createElevenLabsTranscriptionProvider({
    apiKey: 'elevenlabs-key',
    model: 'scribe_v2',
    fetchAudio: async () => ({
      data: new Uint8Array([1]),
      filename: 'clip.m4a',
      contentType: 'audio/mp4'
    }),
    fetchImpl: async () => ({
      ok: false,
      status: 429,
      json: async () => ({})
    })
  });

  await expect(
    provider.transcribe(legacyVideoInput('uploads/clip'))
  ).rejects.toThrow(/ElevenLabs transcription failed with status 429/);
});
```

- [ ] **Step 5: Verify the new tests fail for the intended missing behavior**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/aiEdits/transcriptionProvider.test.ts
```

Expected: FAIL because the factory and normalization logic are absent, not
because of a fixture or TypeScript syntax error.

- [ ] **Step 6: Implement Scribe response normalization**

Add private response types:

```ts
type ElevenLabsTranscriptEvent = {
  text?: unknown;
  start?: unknown;
  end?: unknown;
  type?: unknown;
};

type ElevenLabsTranscriptionResponse = {
  text?: unknown;
  language_code?: unknown;
  words?: unknown;
};
```

Add helpers with these exact responsibilities:

```ts
const isValidTimedWord = (
  event: ElevenLabsTranscriptEvent
): event is ElevenLabsTranscriptEvent & {
  text: string;
  start: number;
  end: number;
  type: 'word';
} =>
  event.type === 'word' &&
  typeof event.text === 'string' &&
  event.text.trim().length > 0 &&
  typeof event.start === 'number' &&
  Number.isFinite(event.start) &&
  event.start >= 0 &&
  typeof event.end === 'number' &&
  Number.isFinite(event.end) &&
  event.end >= event.start;
```

Use `Intl.Segmenter('th', { granularity: 'grapheme' })` to count visible
graphemes. Build segments in event order, preserve spacing only as display
text, flush before a word after a pause of at least `0.55`, and flush after a
word when terminal punctuation is present, duration is at least `4`, or the
visible text reaches `32` graphemes.

- [ ] **Step 7: Implement the ElevenLabs HTTP adapter**

Create and export:

```ts
export const createElevenLabsTranscriptionProvider = ({
  apiKey,
  model,
  fetchAudio,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey: string;
  model: string;
  fetchAudio: FetchAudio;
  fetchImpl?: FetchImpl;
}): TranscriptionProvider => ({
  transcribe: async (input) => {
    const audio = await fetchAudio(input);
    const form = new FormData();
    form.append(
      'file',
      new Blob([audio.data], { type: audio.contentType }),
      audio.filename
    );
    form.append('model_id', model);
    form.append('language_code', 'th');
    form.append('timestamps_granularity', 'word');
    form.append('tag_audio_events', 'false');
    form.append('diarize', 'false');
    form.append('no_verbatim', 'false');

    const response = await fetchImpl(
      'https://api.elevenlabs.io/v1/speech-to-text',
      {
        method: 'POST',
        headers: { 'xi-api-key': apiKey },
        body: form as unknown as RequestInit['body']
      }
    );

    if (!response.ok) {
      throw new Error(
        `ElevenLabs transcription failed with status ${
          response.status ?? 'unknown'
        }`
      );
    }

    return normalizeElevenLabsTranscription(
      await response.json(),
      model
    );
  }
});
```

Add the `elevenlabs` branch to `createTranscriptionProviderFromConfig`,
requiring the API key and `fetchAudio`.

- [ ] **Step 8: Run provider and media-input tests**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/aiEdits/transcriptionProvider.test.ts src/modules/aiEdits/transcriptionMediaInput.test.ts
```

Expected: both files pass with zero failures.

- [ ] **Step 9: Commit the adapter**

```powershell
git add apps/api/src/modules/aiEdits/transcriptionProvider.ts apps/api/src/modules/aiEdits/transcriptionProvider.test.ts
git commit -m "feat(api): add ElevenLabs Scribe transcription"
```

---

### Task 3: Add a sanitized comparison calculator

**Files:**
- Create: `apps/api/src/modules/aiEdits/transcriptionComparison.test.ts`
- Create: `apps/api/src/modules/aiEdits/transcriptionComparison.ts`
- Create: `apps/api/scripts/compareTranscriptions.ts`
- Modify: `apps/api/package.json`

**Interfaces:**
- Consumes: a corrected reference transcript and sanitized provider observations with transcript text, duration, latency, manual hallucination/opening annotations, and timing-error samples.
- Produces: `buildTranscriptionComparison(input): TranscriptionComparisonReport` and a JSON report containing no credentials.

- [ ] **Step 1: Write failing comparison tests**

Define test input:

```ts
const comparison = buildTranscriptionComparison({
  referenceText: 'สวัสดีครับ วันนี้ลดราคา',
  providers: [
    {
      provider: 'groq',
      text: 'สวัสดีครับ วันนี้ลดรา',
      audioDurationSeconds: 60,
      elapsedMilliseconds: 400,
      usdPerHour: 0.111,
      hallucinatedPhraseCount: 1,
      openingSpeechOmitted: false,
      timingErrorsMilliseconds: [100, 200, 300, 400]
    },
    {
      provider: 'elevenlabs',
      text: 'สวัสดีครับ วันนี้ลดราคา',
      audioDurationSeconds: 60,
      elapsedMilliseconds: 700,
      usdPerHour: 0.22,
      hallucinatedPhraseCount: 0,
      openingSpeechOmitted: false,
      timingErrorsMilliseconds: [50, 100, 150, 200]
    }
  ]
});
```

Assert:

```ts
expect(comparison.providers[0]).toMatchObject({
  provider: 'groq',
  estimatedCostUsd: 0.00185,
  medianTimingErrorMilliseconds: 250,
  p95TimingErrorMilliseconds: 400
});
expect(comparison.providers[1].characterErrorRate).toBe(0);
expect(comparison.accuracyWinner).toBe('elevenlabs');
expect(comparison.relativeCerImprovementPercent).toBe(100);
```

Add tests that normalization removes whitespace and punctuation but preserves
Thai letters, and that a CER difference below three percentage points is
reported as an accuracy tie.

- [ ] **Step 2: Run the comparison test and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/aiEdits/transcriptionComparison.test.ts
```

Expected: FAIL because `transcriptionComparison.ts` does not exist.

- [ ] **Step 3: Implement deterministic comparison functions**

Implement:

```ts
export const normalizeThaiForCer = (value: string): string =>
  value
    .normalize('NFC')
    .toLocaleLowerCase('th')
    .replace(/[\p{P}\p{S}\s]/gu, '');
```

Implement a two-row Levenshtein distance function to avoid a full
`referenceLength × hypothesisLength` matrix. Calculate:

```ts
characterErrorRate = distance / Math.max(1, reference.length);
estimatedCostUsd = usdPerHour * audioDurationSeconds / 3600;
```

Sort timing errors and calculate median and nearest-rank P95. Accuracy wins
when relative CER improves by at least 20% without increasing hallucinations.
When absolute CER differs by less than `0.03`, report an accuracy tie so timing,
latency, and cost can be reviewed in that order.

- [ ] **Step 4: Add the operator-only JSON wrapper**

`scripts/compareTranscriptions.ts` reads three explicit arguments:

```text
--reference .tmp/transcription-benchmark/reference.json
--groq .tmp/transcription-benchmark/groq.json
--elevenlabs .tmp/transcription-benchmark/elevenlabs.json
```

It validates that the JSON contains no properties matching
`/api.?key|authorization|secret|token/i`, calls
`buildTranscriptionComparison`, and writes the report to stdout. It never reads
provider credentials.

Add:

```json
"benchmark:transcription": "tsx scripts/compareTranscriptions.ts"
```

- [ ] **Step 5: Verify comparison tests and a fixture CLI run**

Create ignored fixture files with `apply_patch` before the CLI run:

`apps/api/.tmp/transcription-benchmark/reference.json`:

```json
{ "referenceText": "สวัสดีครับ วันนี้ลดราคา" }
```

`apps/api/.tmp/transcription-benchmark/groq.json`:

```json
{
  "provider": "groq",
  "text": "สวัสดีครับ วันนี้ลดรา",
  "audioDurationSeconds": 60,
  "elapsedMilliseconds": 400,
  "usdPerHour": 0.111,
  "hallucinatedPhraseCount": 1,
  "openingSpeechOmitted": false,
  "timingErrorsMilliseconds": [100, 200, 300, 400]
}
```

`apps/api/.tmp/transcription-benchmark/elevenlabs.json`:

```json
{
  "provider": "elevenlabs",
  "text": "สวัสดีครับ วันนี้ลดราคา",
  "audioDurationSeconds": 60,
  "elapsedMilliseconds": 700,
  "usdPerHour": 0.22,
  "hallucinatedPhraseCount": 0,
  "openingSpeechOmitted": false,
  "timingErrorsMilliseconds": [50, 100, 150, 200]
}
```

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/aiEdits/transcriptionComparison.test.ts
npm.cmd run benchmark:transcription -- --reference .tmp/transcription-benchmark/reference.json --groq .tmp/transcription-benchmark/groq.json --elevenlabs .tmp/transcription-benchmark/elevenlabs.json
```

Expected: tests pass and the CLI prints CER, hallucinations, opening coverage,
median/P95 timing error, elapsed time, estimated cost, and relative CER
improvement without any secret-like fields.

- [ ] **Step 6: Commit comparison tooling**

```powershell
git add apps/api/src/modules/aiEdits/transcriptionComparison.ts apps/api/src/modules/aiEdits/transcriptionComparison.test.ts apps/api/scripts/compareTranscriptions.ts apps/api/package.json
git commit -m "test(api): add transcription comparison report"
```

---

### Task 4: Sync Render and project documentation

**Files:**
- Modify: `apps/api/src/config/renderStagingConfig.test.ts:50-75`
- Modify: `apps/api/src/config/renderConfig.test.ts:29-40`
- Modify: `render.staging.yaml:70-78`
- Modify: `apps/api/.env.example:20-30`
- Modify: `README.md:45-55,225-235,740-750`
- Modify: `API.md:700-710,1575-1586`
- Modify: `ARCHITECTURE.md:245-255`
- Modify: `ROADMAP.md` in the AI editing provider section

**Interfaces:**
- Consumes: the new environment variable names and rollout rules.
- Produces: a staging Blueprint that preserves the secret declaration and documentation that matches runtime behavior.

- [ ] **Step 1: Write the failing Render staging test**

Add `ELEVENLABS_API_KEY` to the staging secret list and assert the trial model:

```ts
expectEnvSecret(source, 'ELEVENLABS_API_KEY');
expectEnvValue(source, 'ELEVENLABS_TRANSCRIPTION_MODEL', 'scribe_v2');
expectEnvValue(source, 'TRANSCRIPTION_PROVIDER', 'groq');
```

Add a production assertion in `renderConfig.test.ts`:

```ts
expect(source).not.toContain('value: elevenlabs');
```

- [ ] **Step 2: Run Render configuration tests and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/config/renderStagingConfig.test.ts src/config/renderConfig.test.ts
```

Expected: staging test fails because the ElevenLabs secret and model are not
declared.

- [ ] **Step 3: Update Blueprint and environment example**

Add to `render.staging.yaml` while keeping Groq selected:

```yaml
      - key: TRANSCRIPTION_PROVIDER
        value: groq
      - key: ELEVENLABS_API_KEY
        sync: false
      - key: ELEVENLABS_TRANSCRIPTION_MODEL
        value: scribe_v2
```

Add to `apps/api/.env.example`:

```text
ELEVENLABS_API_KEY="replace_me"
ELEVENLABS_TRANSCRIPTION_MODEL="scribe_v2"
```

- [ ] **Step 4: Update architecture and operator documentation**

Document all four provider choices, the one-provider-per-request rule, the
staging-only A/B sequence, Groq rollback, no automatic fallback, and the
2026-08-23 key rotation deadline. Do not state that ElevenLabs is better until
the live report exists.

- [ ] **Step 5: Run docs/config tests and check formatting**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/config/renderStagingConfig.test.ts src/config/renderConfig.test.ts
cd ../..
git diff --check
rg -n "TRANSCRIPTION_PROVIDER.*mock.*openai.*groq" README.md API.md ARCHITECTURE.md
```

Expected: tests pass, `git diff --check` prints nothing, and every provider
list that covers transcription also includes `elevenlabs`.

- [ ] **Step 6: Commit documentation and Blueprint**

```powershell
git add apps/api/src/config/renderStagingConfig.test.ts render.staging.yaml apps/api/.env.example README.md API.md ARCHITECTURE.md ROADMAP.md
git commit -m "docs: configure ElevenLabs staging trial"
```

---

### Task 5: Verify, deploy to staging, and run the live A/B

**Files:**
- Runtime output only: `.tmp/transcription-benchmark/reference.json`
- Runtime output only: `.tmp/transcription-benchmark/groq.json`
- Runtime output only: `.tmp/transcription-benchmark/elevenlabs.json`
- Runtime output only: `.tmp/transcription-benchmark/report.json`

**Interfaces:**
- Consumes: the existing Thai test video at `D:\PostDeeMobile\.tmp\test-videos\raw-talking-head-thai-vertical-cc-by-sa.mp4`, staging-only API keys, and manually corrected reference annotations.
- Produces: a sanitized A/B report and a recommendation; no runtime output is committed.

- [ ] **Step 1: Run focused and full verification**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/config/env.test.ts src/config/renderStagingConfig.test.ts src/config/renderConfig.test.ts src/modules/aiEdits/transcriptionProvider.test.ts src/modules/aiEdits/transcriptionMediaInput.test.ts src/modules/aiEdits/transcriptionComparison.test.ts
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'
npm.cmd run prisma:validate
```

Expected: all focused tests, all API tests, TypeScript build, and Prisma
validation exit zero.

- [ ] **Step 2: Review the complete change**

Run:

```powershell
git status --short --branch
git diff origin/main...HEAD --stat
git diff origin/main...HEAD -- apps/api/src/modules/aiEdits/transcriptionProvider.ts apps/api/src/config/env.ts render.staging.yaml
```

Verify that no mobile files, production provider values, secrets, or unrelated
features changed.

- [ ] **Step 3: Push the clean feature branch**

```powershell
git push -u origin codex/elevenlabs-scribe-v2-staging
```

Keep production untouched. Point only `postdee-api-staging` temporarily to the
clean feature branch and deploy with `TRANSCRIPTION_PROVIDER=groq`.

- [ ] **Step 4: Capture the Groq baseline securely**

Use an in-memory operator session so keys are never printed. Submit the exact
same media bytes to the current Groq provider, record elapsed milliseconds,
and save only this sanitized shape:

```json
{
  "provider": "groq",
  "model": "whisper-large-v3",
  "text": "human-readable transcript",
  "words": [{ "word": "ข้อความ", "start": 0.1, "end": 0.5 }],
  "audioDurationSeconds": 150,
  "elapsedMilliseconds": 1000,
  "usdPerHour": 0.111,
  "hallucinatedPhraseCount": 0,
  "openingSpeechOmitted": false,
  "timingErrorsMilliseconds": []
}
```

Never include request headers or environment values.

- [ ] **Step 5: Switch staging to ElevenLabs and capture the trial**

Set only:

```text
TRANSCRIPTION_PROVIDER=elevenlabs
```

Deploy, confirm `/health`, process the exact same media bytes, and save the same
sanitized shape with:

```json
{
  "provider": "elevenlabs",
  "model": "scribe_v2",
  "usdPerHour": 0.22
}
```

If the provider fails, retain the exact HTTP status without response headers,
return staging to Groq, and diagnose before retrying.

- [ ] **Step 6: Correct the reference and annotate timing**

Listen to the clip from the beginning, correct the Thai transcript, mark
whether either provider skipped opening speech, count unsupported phrases, and
check at least 20 matching word start/end anchors. Store timing errors in
milliseconds, not API timestamps.

Repeat with a CC-licensed Thai product/review clip and a CC-licensed Thai clip
containing music, noise, or fast speech. Record each source URL and license in
the report notes.

- [ ] **Step 7: Generate and review the comparison**

Run:

```powershell
cd apps/api
npm.cmd run benchmark:transcription -- --reference .tmp/transcription-benchmark/reference.json --groq .tmp/transcription-benchmark/groq.json --elevenlabs .tmp/transcription-benchmark/elevenlabs.json
```

Report absolute CER, hallucinations, opening coverage, median/P95 timing error,
latency, estimated cost, and relative CER improvement. Accuracy is decisive;
do not choose a cheaper provider that materially transcribes Thai worse.

- [ ] **Step 8: Leave staging on the evidence-backed winner**

If ElevenLabs lowers relative CER by at least 20% without increasing
hallucinations, leave staging on `elevenlabs`. Otherwise return staging to
`groq`. Confirm `/health` and one complete app flow through the review screen.
Production remains on Groq until the user explicitly approves a production
change.

- [ ] **Step 9: Commit no benchmark artifacts**

Run:

```powershell
git status --short
git check-ignore -v .tmp/transcription-benchmark/report.json
```

Expected: `.tmp` benchmark files are ignored and the worktree contains no
uncommitted source changes.
