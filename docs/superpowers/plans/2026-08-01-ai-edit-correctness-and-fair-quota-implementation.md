# AI Editing Correctness and Fair Quota Implementation Plan

> **For agentic workers:** Execute this plan task-by-task and use the checkbox (`- [ ]`) items for tracking. Parallel subagents are recommended for independent tests/reviews. Superpowers skills may be used when installed, but are not a prerequisite.

**Goal:** ทำให้ระบบตัดต่อด้วย AI ทำเฉพาะสิ่งที่ผู้ใช้เลือก, ไม่ตัดคำพูดจากหลักฐานที่ไม่ชัด, ไม่เริ่ม/จบกลางประโยคเมื่อมีเวลา transcript ที่เชื่อถือได้, และไม่หักนาทีเมื่อระบบ repeat-only สร้างผลลัพธ์ไม่ได้หรือเมื่อปรับสีอย่างเดียวบนเครื่อง

**Architecture:** API จะสร้าง transcript, แผนตัด และ “ตำแหน่งต้องสงสัยว่าเงียบ” แต่จะไม่ใช้ transcript gap เป็นคำสั่งตัดจริง มือถือเป็นผู้ยืนยันช่วงเงียบด้วย waveform ก่อนเรนเดอร์ ส่วนเวลาไทยระดับตัวอักษรจะถูกประกอบเป็นคำได้เฉพาะเมื่อจับคู่แบบ NFC ตรงทั้งหมด การตัดสินหักโควตาจะรวมไว้ใน pure policy เดียว และการปรับสีอย่างเดียวจะมี local-render route ที่ไม่เรียก `/ai-edits/prepare`

**Tech Stack:** Express + TypeScript + Vitest, Flutter/Dart + flutter_test, ElevenLabs transcript contract, Gemini edit planner, FFmpegKit `silencedetect`, Prisma/memory AI usage stores

## Global Constraints

- ใช้ TDD ทุก task: เขียน test ให้ล้มก่อน, รันเห็น RED, แก้เท่าที่จำเป็น, แล้วรันเห็น GREEN
- ทุก optional capability ต้องเริ่ม `false` ทั้ง mobile และ API; ห้ามเปิด capability อื่นแฝงเมื่อผู้ใช้เลือกเพียงหนึ่งอย่าง
- Transcript boundary เป็น metadata ภายใน ห้ามทำให้ซับปรากฏเมื่อ `subtitle == false`
- API `silenceRanges` เป็น candidate เท่านั้น; final silence cuts ต้องมาจาก mobile waveform verifier
- ถ้าหลักฐานเสียง, เวลาไทย หรือ FFmpeg probe ไม่ชัด ให้เก็บช่วงนั้นไว้ (fail closed)
- ห้ามเปลี่ยนระบบ Hook 3 วินาทีแรก, Gemini planner ranking, ElevenLabs transcription, รูปแบบซับที่ผ่านแล้ว หรือสิทธิ์ Pro ในงานชุดนี้
- ห้ามแก้ codec fallback, 30fps, ขนาดไฟล์, -1 dBTP limiter, A/V timebase หรือ entitlement timeout; เก็บเป็น renderer-quality batch ถัดไป
- ห้าม commit `staging.local.json`, API keys, token หรือไฟล์วิดีโอทดสอบ
- หลังแต่ละ task ให้ตรวจ `git diff --check` และ commit เฉพาะไฟล์ของ task นั้น
- ทุก command block เริ่มจาก worktree root `D:\PostDeeMobile\.worktrees\main-integrate-duration`; API ใช้ `npm.cmd --prefix apps/api ...`, Flutter block ต้อง `Push-Location 'apps/mobile'` และ `Pop-Location` ใน `finally`, จากนั้นคำสั่ง Git จึงทำที่ root
- PowerShell ไม่หยุดเองเมื่อ `npm`, Flutter, ADB หรือโปรแกรมภายนอกคืน exit code ผิดพลาด: หลัง native command ทุกบรรทัดต้องตรวจ `$LASTEXITCODE` และ `throw` ทันทีเมื่อไม่ใช่ `0`; ห้าม commit, ติดตั้ง APK หรือใช้ผลทดสอบจากขั้นถัดไปหาก gate ก่อนหน้าล้ม

---

## Task 1: ปิด optional capability ทุกตัวโดยค่าเริ่มต้นใน API

**Files:**

- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.test.ts`

**Interfaces:** ไม่เปลี่ยน API contract; `readAiEditCapabilities(undefined)` ยังคงคืน `AiEditCapabilityFlags` ครบทุก key แต่เป็น `false` ทั้งหมด

- [ ] **Step 1: เพิ่ม failing tests สำหรับค่า default และคำขอแบบเปิดทีละตัว**

เพิ่มใน `aiEditRecipe.test.ts`:

```ts
describe('AI edit capability defaults', () => {
  it('keeps every optional capability disabled when omitted', () => {
    expect(readAiEditCapabilities(undefined)).toEqual({
      subtitle: false,
      silence: false,
      filler: false,
      hook: false,
      beatsync: false,
      reframe: false,
      zoom: false,
      color: false,
      sfx: false,
      audio: false,
      translate: false,
      pricetag: false,
      cta: false,
      watermark: false
    });
  });

  it('does not enable hidden capabilities when one capability is selected', () => {
    expect(readAiEditCapabilities({ color: true })).toMatchObject({
      color: true,
      subtitle: false,
      silence: false,
      filler: false
    });
  });
});
```

- [ ] **Step 2: รัน test เพื่อยืนยันว่า RED เพราะ subtitle/silence ยังเป็น true**

Run from worktree root:

```powershell
npm.cmd --prefix apps/api run test -- src/modules/aiEdits/aiEditRecipe.test.ts
$redExitCode = $LASTEXITCODE
if ($redExitCode -eq 0) { throw "Expected capability-default test to fail before implementation" }
```

Expected: test `keeps every optional capability disabled when omitted` fails on `subtitle` and `silence`.

- [ ] **Step 3: เปลี่ยน `defaultCapabilities` ให้ false ครบทุก key**

```ts
const defaultCapabilities: AiEditCapabilityFlags = Object.fromEntries(
  aiEditCapabilityKeys.map((key) => [key, false])
) as AiEditCapabilityFlags;
```

คง `readAiEditCapabilities()` ให้ clone defaults ก่อนอ่าน boolean ที่ client ส่งมา ห้ามเพิ่ม fallback เปิด subtitle/silence ใน route.

- [ ] **Step 4: รัน focused test และตรวจ diff**

```powershell
npm.cmd --prefix apps/api run test -- src/modules/aiEdits/aiEditRecipe.test.ts
if ($LASTEXITCODE -ne 0) { throw "Capability-default tests failed with exit code $LASTEXITCODE" }
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
```

- [ ] **Step 5: Commit**

```powershell
git add apps/api/src/modules/aiEdits/aiEditRecipe.ts apps/api/src/modules/aiEdits/aiEditRecipe.test.ts
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "fix: default ai edit capabilities to off"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

---

## Task 2: ตรวจความสมบูรณ์ของ transcript และเปลี่ยน gaps เป็น internal silence candidates เท่านั้น

**Files:**

- Modify: `apps/api/src/modules/aiEdits/transcriptionProvider.ts`
- Modify: `apps/api/src/modules/aiEdits/transcriptionProvider.test.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.test.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRoutes.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRoutes.test.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditAudioRoutes.test.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditAudioCleanupRoutes.test.ts`
- Modify: `apps/api/src/modules/captions/captionRoutes.test.ts`
- Modify: `apps/mobile/lib/core/network/postdee_api_client.dart`
- Modify: `apps/mobile/test/postdee_api_client_test.dart`

**Interfaces:**

```ts
const findInternalSilenceCandidates = (
  ranges: TimedRange[],
  minGapSeconds: number,
  durationSeconds?: number
): EditPlanCut[];

const readStrictTranscriptEvidence = <T extends TimedRange>(
  ranges: readonly T[],
  durationSeconds: number
): T[] | undefined;

type TranscriptTimingIntegrity = 'trusted' | 'untrusted';

type TranscriptionResult = {
  // existing fields...
  timingIntegrity: TranscriptTimingIntegrity;
  hasTimedAudioEvents: boolean;
};
```

`AiEditRecipe.silenceRanges` ยังคงชื่อเดิมเพื่อไม่ทำลาย client เก่า แต่ความหมายใหม่คือ candidate; `AiEditRecipe.cutRanges` ต้องไม่รวม candidate เหล่านี้

- [ ] **Step 1: แก้/เพิ่ม API tests ให้บังคับ contract ใหม่**

เพิ่ม case ที่มีช่วงเงียบหัว, กลาง, ท้าย:

```ts
it('reports only internal transcript gaps as silence candidates', () => {
  const recipe = buildRecipe({
    text: 'หนึ่ง สอง',
    durationSeconds: 10,
    segments: [
      { text: 'หนึ่ง', start: 2, end: 3 },
      { text: 'สอง', start: 5, end: 6 }
    ],
    capabilities: { silence: true }
  });

  expect(recipe.silenceRanges).toEqual([{ start: 3, end: 5 }]);
  expect(recipe.cutRanges).not.toContainEqual({ start: 3, end: 5 });
  expect(recipe.cutRanges).not.toContainEqual({ start: 0, end: 2 });
  expect(recipe.cutRanges).not.toContainEqual({ start: 6, end: 10 });
  expect(recipe.capabilities.silence.state).toBe('hinted');
});
```

แก้ route test ที่เคยคาดว่า leading/trailing silence ถูกสร้าง ให้คาดเฉพาะ internal candidate และตรวจว่า `cutRanges` ไม่มี candidate.

เพิ่ม table tests ที่ raw segment/word มี start ติดลบ, end เกิน duration (`5–999` ในคลิป 20 วินาที), non-finite, end <= start, ลำดับเวลาถอยหลัง หรือ overlap. ใน Task นี้ให้ assert เฉพาะว่า `readStrictTranscriptEvidence` คืน `undefined`, `silenceRanges` ว่างและไม่มี executable silence cut; ห้าม clamp เป็นช่วง 5–20. ย้าย assertion ของ `analysisOutcomes.silence == 'unavailable'` ไป Task 4 และ assertion ของ `transcript.boundarySegments` ไป Task 5 หลัง contract เหล่านั้นถูกเพิ่มแล้ว. คง `readSafeTimedRange` เดิมได้เฉพาะเส้นทาง display compatibility แต่ห้ามใช้อนุญาต boundary/silence/repeat cut.

เพิ่ม provider regression ใน `transcriptionProvider.test.ts`: ElevenLabs payload มี valid word `ชุมชน`, malformed `type: 'word'` สำหรับ `เอ่อ` (เช่นไม่มี `end`) และ valid word `ชุมชน`. Adapter ยังคงข้อความ/คำ valid สำหรับการแสดงผล แต่ต้องคืน `timingIntegrity == 'untrusted'`; ห้ามทิ้ง event แล้วอ้างว่า timeline ที่เหลือสมบูรณ์. เพิ่ม cases payload `words` ไม่ใช่ array, มี non-object/unknown item, word text ว่าง, start/end ไม่ finite, start ติดลบ, `end <= start`, ลำดับย้อนหลัง และ overlap. `spacing` ที่ถูกชนิดยังคง `trusted`; `audio_event` ที่มีเวลาถูกต้องให้ `trusted` ได้แต่ต้องตั้ง `hasTimedAudioEvents: true`, ส่วน audio event ที่เวลาผิดให้ untrusted.

เพิ่ม recipe regression ที่รับ transcript เดียวกันพร้อม `timingIntegrity: 'untrusted'`: เมื่อเปิด silence ต้องได้ `silenceRanges` ว่างและไม่มี executable cut แม้ valid words ก่อน–หลังดูเหมือนมี gap. Task 3 จะเพิ่ม repeat assertion, Task 4 จะเพิ่ม outcome/quota และ Task 5 จะเพิ่ม boundary assertionหลัง contract แต่ละส่วนมีอยู่จริง.

เพิ่ม route/API-client regression สำหรับ `422 AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE`: target/style/prompt request ต้องไม่มี planner/recipe/quota mutation และ mobile แปลงเป็นข้อความ “ยืนยันเวลาเสียงไม่ได้ กรุณาลองใหม่” โดยไม่เริ่ม render. Subtitle-only untrusted ต้องคืน burn subtitle ว่างและสถานะ unavailable ไม่ใช่ซับบางส่วน.

- [ ] **Step 2: เพิ่ม mobile model regression test สำหรับ `withPlan()`**

ใน `postdee_api_client_test.dart` สร้าง recipe ที่มี `silenceRanges` แล้วเรียก `withPlan()`:

```dart
test('withPlan keeps silence candidates out of executable cut ranges', () {
  final recipeWithSilenceCandidate = AiEditRecipeResult.fromJson(const {
    'version': 1,
    'status': 'ready',
    'renderMode': 'mobile-ffmpeg',
    'transcript': {
      'text': '',
      'language': 'th',
      'durationSeconds': 40,
      'segments': [],
      'words': [],
      'model': 'test',
    },
    'subtitles': {
      'enabled': false,
      'segments': [],
      'style': {},
    },
    'cutRanges': [
      {'start': 5, 'end': 6},
    ],
    'silenceRanges': [
      {'start': 5, 'end': 6},
    ],
    'fillerRanges': [],
    'capabilities': {},
  });
  final updated = recipeWithSilenceCandidate.withPlan(
    const AiEditPlanResult(
      cuts: [AiEditCut(start: 20, end: 30)],
      summary: 'test',
      model: 'test',
    ),
  );

  expect(updated.cutRanges, hasLength(1));
  expect(updated.cutRanges.single.start, 20);
  expect(updated.silenceRanges.single.start, 5);
});
```

- [ ] **Step 3: รัน RED**

```powershell
npm.cmd --prefix apps/api run test -- src/modules/aiEdits/transcriptionProvider.test.ts src/modules/aiEdits/aiEditRecipe.test.ts src/modules/aiEdits/aiEditRoutes.test.ts src/modules/aiEdits/aiEditAudioRoutes.test.ts src/modules/aiEdits/aiEditAudioCleanupRoutes.test.ts src/modules/captions/captionRoutes.test.ts
$apiRedExitCode = $LASTEXITCODE
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\postdee_api_client_test.dart
  $mobileRedExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($apiRedExitCode -eq 0 -or $mobileRedExitCode -eq 0) {
  throw "Expected both API and mobile silence-candidate regressions to fail before implementation"
}
```

Expected: API ยังสร้าง edge ranges/รวม silence ใน `cutRanges`, ไม่มี timing-integrity contract/การ propagate ข้าม chunks; Dart `withPlan()` ยัง fold candidate กลับเข้า final cuts.

- [ ] **Step 4: ทำ API ให้สร้างเฉพาะ internal candidates**

แทน `findSilenceRanges` ด้วย logic ต่อไปนี้:

```ts
const findInternalSilenceCandidates = (
  ranges: TimedRange[],
  minGapSeconds = 0.6,
  durationSeconds?: number
): EditPlanCut[] => {
  if (!hasFinitePositiveDuration(durationSeconds)) return [];
  const strict = readStrictTranscriptEvidence(ranges, durationSeconds);
  if (!strict) return [];
  const sorted = [...strict]
    .sort((left, right) => left.start - right.start || left.end - right.end);

  const candidates: EditPlanCut[] = [];
  let activeEnd = sorted[0]?.end;
  for (let index = 1; activeEnd !== undefined && index < sorted.length; index += 1) {
    const next = sorted[index]!;
    if (next.start - activeEnd + Number.EPSILON >= minGapSeconds) {
      candidates.push({ start: activeEnd, end: next.start });
    }
    activeEnd = Math.max(activeEnd, next.end);
  }
  return candidates;
};
```

`readStrictTranscriptEvidence` ต้องตรวจ raw provider order ก่อน sort: duration finite/positive, ทุก start/end finite, `start >= 0`, `end > start`, `end <= durationSeconds` และ `start >= previous.end`; หากผิดเพียงรายการเดียวคืน `undefined` ทั้ง timeline เพื่อ fail closed. กำหนด `strictTranscriptSegments`/`strictTranscriptWords` เป็น `T[] | undefined`; เมื่อ source เป็น undefined ให้ `strictReliableTranscriptSegments = strictTranscriptSegments?.filter(isReliableTranscriptSegment) ?? []` เพื่อให้ derived list ไม่ nullable. หาก `transcript.timingIntegrity != 'trusted'` ให้ source strict lists เป็น `undefined` โดยไม่พยายามซ่อมจาก subset. Task 2 ใช้ strict lists ตัดสิน silence candidate; Task 3 ต้องใช้ strict lists ตัดสิน repeated speech; Task 5 จึงค่อยใช้ strict list สร้าง repaired `boundarySegments`. Protected ranges บน mobile ยังคง validate raw evidence แยกและไม่ใช้ข้อมูลเสีย.

ใน `normalizeElevenLabsTranscription()` ตรวจ raw `payload.words` ก่อน filter และคืน `timingIntegrity`/`hasTimedAudioEvents` ทุกครั้ง: array ที่หาย, item ที่ไม่ใช่ object/ชนิดไม่รู้จัก หรือ word/audio event ที่ไม่ผ่านกฎข้อความ/เวลา/ลำดับต้องเป็น `untrusted`; payload ที่ครบเป็น `trusted`. Parser เก็บ valid subset ไว้ใน internal transcript เพื่อวินิจฉัยได้ แต่ `buildAiEditRecipe()` ห้ามสร้าง burn-subtitle segments, planning segments, silence, repeat หรือ boundary จาก untrusted timing. `spacing` ที่ถูก contract ไม่เป็นเหตุให้ untrusted; valid `audio_event` ตั้ง barrier flagเพื่อให้ Task 3 ปิด auto repeatโดยไม่ปิด subtitle/targetทั้งคลิป. แก้ validatorจาก `end >= start` เป็น `end > start`.

เทียบ semantic coverage ระหว่าง `payload.text` กับข้อความที่ประกอบจาก valid word/spacing events หลัง NFC + collapse whitespace; หาก payload ระบุข้อความแต่ event timeline ขาดคำ แม้ไม่เห็น malformed item ให้ `timingIntegrity: 'untrusted'`. Audio-event label ที่ไม่ใช่ข้อความพูดไม่ต้องถูกบังคับให้ตรงกับ payload text. เพิ่ม regression `payload.text = 'ชุมชน เอ่อ ชุมชน'` แต่ raw events มีเพียงสอง `ชุมชน`: ต้อง untrustedและไม่มี gap/repeat cut.

Provider อื่นและ mock ต้องกำหนด field นี้อย่างชัดเจน; ห้าม default missing เป็น trusted. OpenAI-compatible adapter ต้อง audit raw segments/words ก่อน map และห้ามแปลง missing timing เป็น `0` แล้วเรียก trusted. อัปเดต typed test fixtures ที่ TypeScript ชี้ทั้งหมดให้ระบุ `'trusted'` เฉพาะหลักฐานปกติ และ `'untrusted'` ใน safety cases. ใน `/prepare` หาก timing untrusted และมี style/prompt/target (รวม target + subtitle) ให้หยุดก่อน `editPlanProvider.plan()`/recipe/render ด้วย `422 AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE`, ไม่ reserve ledger และให้มือถือแสดงลองใหม่; ห้ามส่ง recipe original-duration ที่มือถืออาจ trim เองแล้วดูเหมือน target สำเร็จ. Subtitle/silence/repeat-only สามารถคืน recipe สถานะ unavailable เพื่ออธิบายเหตุผลได้ แต่ต้องไม่มี burn subtitle/cut และ Task 4 ต้องไม่คิดนาทีเมื่อไม่มี outcome อื่นสำเร็จ.

การรวม audio chunks ใน `shiftTranscriptionResult()`/`mergeChunkedTranscriptions()` ต้อง propagate แบบ all-or-nothing: ผลรวมเป็น `trusted` เฉพาะเมื่อทุก chunk trusted และการ shift/clip ไม่ทิ้งหรือหั่น segment/word ใด; `hasTimedAudioEvents` ของผลรวมเป็น OR ของทุก chunk. หากช่วงถูก drop/clip หรือ chunk ใด untrusted ให้ผลรวม untrusted แต่ยังเก็บ safe display subset. ใน Task 2 เพิ่ม tests ที่ `aiEditAudioRoutes.test.ts` เฉพาะ integrity propagation, planner call count 0 และไม่มี executable timing evidence; ย้าย `analysisOutcomes`/ledger assertions ของกรณีเดียวกันไป Task 4 หลัง fair-usage contract ถูกสร้างแล้ว.

ใช้ preset เดิม: natural `1.0`, balanced `0.6`, compact `0.4` วินาที และสร้าง final aggregate ดังนี้:

```ts
cutRanges: sortRanges([...planCuts, ...fillerRanges]),
silenceRanges: sortRanges(silenceRanges),
```

ตั้ง silence status เป็น `hinted` พร้อมข้อความว่า mobile ต้องยืนยัน waveform; ห้าม state `applied` เพียงเพราะพบ transcript gap.

- [ ] **Step 5: แก้ `AiEditRecipeResult.withPlan()` ไม่ให้ candidate รั่วกลับเข้า cuts**

```dart
cutRanges: [
  ...updatedPlan.cuts,
  ...fillerRanges,
],
```

- [ ] **Step 6: รัน GREEN และ commit**

```powershell
npm.cmd --prefix apps/api run test -- src/modules/aiEdits/transcriptionProvider.test.ts src/modules/aiEdits/aiEditRecipe.test.ts src/modules/aiEdits/aiEditRoutes.test.ts src/modules/aiEdits/aiEditAudioRoutes.test.ts src/modules/aiEdits/aiEditAudioCleanupRoutes.test.ts src/modules/captions/captionRoutes.test.ts
if ($LASTEXITCODE -ne 0) { throw "Silence-candidate API tests failed with exit code $LASTEXITCODE" }
npm.cmd --prefix apps/api run build
if ($LASTEXITCODE -ne 0) { throw "Timing-integrity API build failed with exit code $LASTEXITCODE" }
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\postdee_api_client_test.dart
  if ($LASTEXITCODE -ne 0) { throw "API client tests failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git add apps/api/src/modules/aiEdits/transcriptionProvider.ts apps/api/src/modules/aiEdits/transcriptionProvider.test.ts apps/api/src/modules/aiEdits/aiEditRecipe.ts apps/api/src/modules/aiEdits/aiEditRecipe.test.ts apps/api/src/modules/aiEdits/aiEditRoutes.ts apps/api/src/modules/aiEdits/aiEditRoutes.test.ts apps/api/src/modules/aiEdits/aiEditAudioRoutes.test.ts apps/api/src/modules/aiEdits/aiEditAudioCleanupRoutes.test.ts apps/api/src/modules/captions/captionRoutes.test.ts apps/mobile/lib/core/network/postdee_api_client.dart apps/mobile/test/postdee_api_client_test.dart
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "fix: fail closed on incomplete transcript timing"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

---

## Task 3: ประกอบเวลาไทยระดับตัวอักษรเป็นคำแบบ exact และ fail closed

**Files:**

- Create: `apps/api/src/modules/aiEdits/thaiTimedTokenReconstructor.ts`
- Create: `apps/api/src/modules/aiEdits/thaiTimedTokenReconstructor.test.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.test.ts`

**Interfaces:**

```ts
export type ThaiTimedWordReconstructionInput = {
  segments: readonly TranscriptSegment[];
  fragments: readonly TranscriptWord[];
  durationSeconds: number;
};

export const reconstructThaiTimedWords = (
  input: ThaiTimedWordReconstructionInput
): TranscriptWord[] | undefined;
```

`undefined` หมายถึงพิสูจน์ขอบคำไม่ได้และห้าม auto cut; `[]` ใช้เฉพาะ input ว่างที่ถูกต้อง

- [ ] **Step 1: เขียน unit tests ของ reconstructor**

อย่างน้อยต้องมี cases ต่อไปนี้:

```ts
it('reconstructs exact Thai character fragments inside one segment', () => {
  const semanticWords = [
    ...new Intl.Segmenter('th', { granularity: 'word' })
      .segment('ชุมชน ชุมชน')
  ].filter((part) => part.isWordLike).map((part) => part.segment);
  expect(semanticWords).toEqual(['ชุมชน', 'ชุมชน']);
  expect(reconstructThaiTimedWords({
    segments: [{ text: 'ชุมชน ชุมชน', start: 1, end: 3 }],
    durationSeconds: 3,
    fragments: [
      { word: 'ชุม', start: 1.0, end: 1.3 },
      { word: 'ชน', start: 1.3, end: 1.6 },
      { word: 'ชุมชน', start: 2.0, end: 2.6 }
    ]
  })).toEqual([
    { word: 'ชุมชน', start: 1.0, end: 1.6 },
    { word: 'ชุมชน', start: 2.0, end: 2.6 }
  ]);
});

const unsafeCases: Array<{ name: string; fragments: TranscriptWord[] }> = [
  { name: 'fragment gap over 150ms', fragments: [
    { word: 'ชุม', start: 1, end: 1.1 },
    { word: 'ชน', start: 1.26, end: 1.6 },
    { word: 'มาก', start: 2, end: 2.3 }
  ] },
  { name: 'backwards timing', fragments: [
    { word: 'ชุม', start: 1.2, end: 1.3 },
    { word: 'ชน', start: 1.1, end: 1.4 },
    { word: 'มาก', start: 2, end: 2.3 }
  ] },
  { name: 'provider token spans two words', fragments: [
    { word: 'ชุมชน มาก', start: 1, end: 2 }
  ] },
  { name: 'text mismatch', fragments: [
    { word: 'ชุมชล', start: 1, end: 2 },
    { word: 'มาก', start: 2.1, end: 2.4 }
  ] }
];

it.each(unsafeCases)('fails closed for $name', ({ fragments }) => {
  expect(reconstructThaiTimedWords({
    segments: [{ text: 'ชุมชน มาก', start: 1, end: 3 }],
    durationSeconds: 3,
    fragments
  })).toBeUndefined();
});

it.each([
  { gap: 0.15, succeeds: true },
  { gap: 0.1501, succeeds: false }
])('enforces the exact 150ms fragment gap boundary: $gap', ({ gap, succeeds }) => {
  const result = reconstructThaiTimedWords({
    segments: [{ text: 'ชุมชน', start: 1, end: 2 }],
    durationSeconds: 2,
    fragments: [
      { word: 'ชุม', start: 1, end: 1.1 },
      { word: 'ชน', start: 1.1 + gap, end: 1.7 }
    ]
  });
  expect(result !== undefined).toBe(succeeds);
});

it.each(['ฯ', '.', '?'])('attaches exact %s punctuation to the previous word', (mark) => {
  expect(reconstructThaiTimedWords({
    segments: [{ text: `ชุมชน${mark}`, start: 1, end: 2 }],
    durationSeconds: 2,
    fragments: [{ word: 'ชุมชน', start: 1, end: 1.5 }]
  })).toEqual([{ word: `ชุมชน${mark}`, start: 1, end: 1.5 }]);
});
```

เพิ่ม test จริงอีกห้ากรณี: ห้ามข้าม segment แม้ข้อความต่อกัน (รวม case fragment แรกอยู่ใน segment แต่ fragment ถัดไปมี `end` เลยขอบ), Unicode NFD/NFC ที่ normalize แล้วตรงต้องผ่าน, ช่องว่างระหว่างสอง semantic words ไม่ต้องมีเวลา, provider ส่ง punctuation fragment ที่เกิน/ไม่ตรงต้องคืน `undefined`, และ provider ส่ง punctuation ติดกับ word token (`ชุมชน?`) ต้องผ่านเมื่อ suffix ใน segment ตรงทุกตัว. ทดสอบทั้ง punctuation ติด token, แยก token และไม่มี timestamp token ตาม contract ที่รองรับ.

- [ ] **Step 2: รัน RED เพราะ module ยังไม่มี**

```powershell
npm.cmd --prefix apps/api run test -- src/modules/aiEdits/thaiTimedTokenReconstructor.test.ts
$redExitCode = $LASTEXITCODE
if ($redExitCode -eq 0) { throw "Expected Thai timing reconstructor test to fail before implementation" }
```

- [ ] **Step 3: Implement exact reconstruction เป็น state machine**

กฎ implementation:

1. ตรวจ fragment ตามลำดับที่ provider ส่งมาก่อนฟังก์ชันใด sort; reject เมื่อ start/end ไม่ finite, `end <= start`, นอก `durationSeconds`, เวลาถอยหลัง หรือ overlap
2. normalize เฉพาะ `.normalize('NFC')`; ห้ามใช้ `normalizeTranscriptTextForCoverage()` เพื่อทำ mismatch ให้หาย
3. ใช้ `readThaiSubtitleWordParts()` หา semantic words ในแต่ละ segment และจับคู่ fragments เฉพาะภายใน segment เดียว
4. ต่อ fragment ได้เมื่อ gap `<= 0.15` วินาทีเท่านั้น
5. output start จาก fragment แรกและ end จาก fragment สุดท้าย
6. token เดียวที่มี internal whitespace/กินมากกว่าหนึ่ง semantic word, ตัวอักษรขาด/เกิน หรือ crossing segment ต้องคืน `undefined`
7. whitespace ระหว่าง semantic words เป็น separator ที่ไม่มีเวลาและไม่ต้อง consume; outer whitespace ของ provider fragment trim ได้ แต่ internal whitespace ห้ามใช้ข้ามคำ
8. punctuation/symbol หลัง semantic word จาก segment ให้ต่อกับคำก่อนหน้าเสมอ; ถ้า provider มี punctuation-only fragment ต้องตรง suffix แบบ NFC จึง consume ได้ ถ้า provider ไม่มี punctuation fragment ให้ใช้ end ของ word fragment เดิมเพราะไม่ได้สร้างขอบ cut ใหม่; punctuation ที่เกินหรือไม่ตรงต้องคืน `undefined`

แกนของ matcher ต้องเป็นรูปนี้:

```ts
const maximumFragmentGapSeconds = 0.15;

const readFollowingPunctuationSuffix = (
  parts: ReturnType<typeof readThaiSubtitleWordParts>,
  wordPartIndex: number
): string => {
  const suffix: string[] = [];
  for (let index = wordPartIndex + 1; index < parts.length; index += 1) {
    const part = parts[index]!;
    if (part.isWordLike) break;
    suffix.push(part.segment.replace(/\s+/gu, ''));
  }
  return suffix.join('').normalize('NFC');
};

const orderedFragments = [...input.fragments];
for (const [index, fragment] of orderedFragments.entries()) {
  if (
    !Number.isFinite(fragment.start) ||
    !Number.isFinite(fragment.end) ||
    fragment.start < 0 ||
    fragment.end <= fragment.start ||
    fragment.end > input.durationSeconds ||
    (index > 0 && fragment.start < orderedFragments[index - 1]!.end)
  ) {
    return undefined;
  }
}

for (const segment of input.segments) {
  const parts = readThaiSubtitleWordParts(segment.text.normalize('NFC'));
  const semanticWords = parts
    .map((part, index) => ({ part, index }))
    .filter(({ part }) => part.isWordLike);

  for (const { part, index: partIndex } of semanticWords) {
    const semanticWord = part.segment.normalize('NFC');
    const first = orderedFragments[fragmentIndex];
    if (!first || first.start < segment.start || first.end > segment.end) {
      return undefined;
    }
    let rebuilt = '';
    const start = first.start;
    let end = first.end;
    const punctuationSuffix = readFollowingPunctuationSuffix(parts, partIndex);
    let consumedAttachedPunctuation = false;
    while (rebuilt.length < semanticWord.length) {
      const fragment = orderedFragments[fragmentIndex++];
      if (
        !fragment ||
        fragment.start < segment.start ||
        fragment.end > segment.end ||
        fragment.start - end > maximumFragmentGapSeconds
      ) {
        return undefined;
      }
      const providerText = fragment.word.trim().normalize('NFC');
      const remainingWord = semanticWord.slice(rebuilt.length);
      if (
        punctuationSuffix.length > 0 &&
        providerText === `${remainingWord}${punctuationSuffix}`
      ) {
        rebuilt += remainingWord;
        consumedAttachedPunctuation = true;
      } else {
        rebuilt += providerText;
      }
      end = fragment.end;
      if (!semanticWord.startsWith(rebuilt)) return undefined;
    }
    if (rebuilt !== semanticWord) return undefined;
    const punctuationFragment = orderedFragments[fragmentIndex];
    const providerPunctuation = punctuationFragment?.word
      .trim()
      .normalize('NFC');
    if (
      !consumedAttachedPunctuation &&
      providerPunctuation &&
      /^[\p{P}\p{S}]+$/u.test(providerPunctuation)
    ) {
      if (
        providerPunctuation !== punctuationSuffix ||
        !punctuationFragment ||
        punctuationFragment.start - end > maximumFragmentGapSeconds ||
        punctuationFragment.start < segment.start ||
        punctuationFragment.end > segment.end
      ) return undefined;
      end = orderedFragments[fragmentIndex++]!.end;
    }
    reconstructed.push({
      word: `${semanticWord}${punctuationSuffix}`,
      start,
      end
    });
  }
}
if (fragmentIndex !== orderedFragments.length) return undefined;
```

ห้ามใช้ coverage normalizer ใน helper นี้; exact match ใช้เฉพาะ NFC, outer whitespace และ punctuation suffix ที่ระบุไว้เท่านั้น.

- [ ] **Step 4: เชื่อมเข้า repeated speech จาก raw provider order โดยไม่กระทบ subtitle timings**

ต้องเรียก reconstructor ใน `buildAiEditRecipe()` เพราะตัวแปร strict/reliable segments อยู่ใน scope นี้ และต้องอ่าน word timeline ทั้งก้อนโดยรักษาลำดับดิบ. ห้าม filter หลักฐานที่ไม่เชื่อถือออกแล้วนำ reliable islands สองฝั่งมาต่อกัน:

```ts
const orderedSpeechFragments = strictTranscriptWords ?? [];
const hasCompleteRepeatTimeline =
  transcript.timingIntegrity === 'trusted' &&
  !transcript.hasTimedAudioEvents &&
  strictTranscriptSegments !== undefined &&
  strictTranscriptWords !== undefined &&
  strictTranscriptSegments.length > 0 &&
  strictReliableTranscriptSegments.length === strictTranscriptSegments.length;
const requiresExactThaiWordVerification =
  hasCompleteRepeatTimeline &&
  transcriptLanguage === 'th' &&
  strictReliableTranscriptSegments.length > 0 &&
  orderedSpeechFragments.length > 0;
const reconstructedSpeechWords =
  requiresExactThaiWordVerification
    ? reconstructThaiTimedWords({
        segments: strictReliableTranscriptSegments,
        fragments: orderedSpeechFragments,
        durationSeconds: transcript.durationSeconds
      })
    : undefined;
const speechReductionWords = !hasCompleteRepeatTimeline
  ? undefined
  : transcriptLanguage === 'th'
    ? reconstructedSpeechWords
    : strictTranscriptWords;
const speechReduction = buildSpeechReduction({
  words: speechReductionWords,
  unsafeReason: transcriptLanguage === 'th'
    ? 'fragmented-word-timing'
    : 'unsafe-word-timing',
  // ส่ง arguments เดิมที่เหลือต่อโดยไม่เปลี่ยนกฎ detector
});
```

เปลี่ยน `buildSpeechReduction()` ให้รับ `words: TranscriptWord[] | undefined` และ `unsafeReason: 'unsafe-word-timing' | 'fragmented-word-timing'`; ถ้าไม่มี words ให้คืน reason ที่ส่งเข้าไป แล้วค่อยเรียก `readSpeechReductionTokens(words)`. ส่ง `speechReductionWords` เข้า repeated-speech path เท่านั้น ห้ามนำ reconstructed words ไปแทนคำที่ใช้แสดง active-word subtitles.

สำหรับภาษาไทยต้องเรียก exact reconstructor ทุกครั้งที่มี strict reliable segments + raw fragments ไม่ใช่ gate ด้วย `hasFragmentedThaiWordTimings()` เดิม เพราะ heuristic เดิมตรวจเฉพาะ fragment เล็กมากบางรูปแบบและพลาดช่องว่าง 0.09–0.15 วินาที. หาก provider timing incomplete, strict timeline ผิด หรือมี segment ใด unreliable ให้ repeat auto-removal ของ recipe ทั้งก้อนเป็น `unavailable`; ห้ามลบ word/segment นั้นแล้วตรวจต่อข้ามช่องว่าง. Heuristic เดิมยังใช้กับ subtitle fallback ได้ แต่ห้ามเป็นผู้อนุญาต repeated-speech cuts. ถ้า reconstruction คืน `undefined` ให้สถานะ `fragmented-word-timing`; ถ้าคืน words ที่ exact ให้ใช้ adjacent repeat detector เดิม ส่วน frequent/distributed repeats ยังคงรายงานอย่างเดียวและ `canAutoRemove == false`.

- [ ] **Step 5: เพิ่ม recipe integration tests**

เพิ่ม tests ใน `aiEditRecipe.test.ts` โดยใช้ helper `buildRecipe()` เดิม:

```ts
it('uses exact reconstructed Thai words for adjacent repeat reduction', () => {
  const words: TranscriptWord[] = [
    { word: 'ชุม', start: 1.0, end: 1.2 },
    { word: 'ชน', start: 1.2, end: 1.4 },
    { word: 'ชุมชน', start: 1.6, end: 2.1 }
  ];
  const originalWords = structuredClone(words);
  const recipe = buildRecipe({
    text: 'ชุมชน ชุมชน',
    segments: [{ text: 'ชุมชน ชุมชน', start: 1, end: 2.1 }],
    words,
    durationSeconds: 3,
    capabilities: { filler: true },
    settings: { speechReductionMode: 'auto' }
  });

  expect(recipe.speechReduction?.status).toBe('ready');
  expect(recipe.speechReduction?.defaultCutRanges).toHaveLength(1);
  expect(words).toEqual(originalWords);
});

it('does not cut when Thai character fragments cannot be proven exact', () => {
  const recipe = buildRecipe({
    text: 'ชุมชน ชุมชน',
    segments: [{ text: 'ชุมชน ชุมชน', start: 1, end: 3 }],
    words: [
      { word: 'ชุม', start: 1, end: 1.1 },
      { word: 'ชล', start: 1.1, end: 1.5 },
      { word: 'ชุมชน', start: 2, end: 2.5 }
    ],
    durationSeconds: 3,
    capabilities: { filler: true },
    settings: { speechReductionMode: 'auto' }
  });

  expect(recipe.speechReduction).toMatchObject({
    status: 'unavailable',
    unavailableReason: 'fragmented-word-timing',
    defaultCutRanges: []
  });
});
```

เพิ่ม case exact fragments ของคำที่กระจายห่างกันโดย assert ว่า group ถูก report แต่ `defaultCutRanges` ว่าง และ case fragments ข้าม segment โดย assert `unavailable`.

เพิ่ม regression ที่ raw fragments ส่งเวลา `[1.2–1.3, 1.0–1.1]` แต่ข้อความเรียงแล้วดูเหมือนถูกต้อง; assert `speechReduction.status == 'unavailable'` เพื่อยืนยันว่า `readValidTranscriptWords()` ที่ sort ภายหลังไม่สามารถซ่อน provider-order error ได้. เพิ่ม punctuation integration `ชุมชน? ชุมชน?` แล้ว assert reconstructed token ยังทำให้ adjacent detector เคารพ sentence boundary และไม่เสนอ cut ข้าม `?`.

เพิ่ม integration สองชุดที่แต่ละ semantic word มีเพียง 2–3 fragments (เพื่อไม่พึ่ง minimum-token heuristic เดิม): gap ประมาณ 0.10 วินาทีต้อง reconstruct และตรวจ adjacent repeat ได้; fixture เดียวกันที่ gap 0.16 วินาทีต้องคืน `speechReduction.status == 'unavailable'`, ไม่มี cut และ Task 4 ต้องไม่คิดนาทีเมื่อเป็น repeat-only.

เพิ่ม regression อีกชุด: raw segment มี `end` เกิน duration เช่น `5–999` ในคลิป 20 วินาที แต่ fragments ภายในดูเหมือนจับคู่คำได้. Assert ว่า strict segment timeline ถูกปฏิเสธ, `speechReduction.status == 'unavailable'`, ไม่มี repeat cut และใน Task 4 repeat-only case นี้ไม่ถูกหักนาที; ห้ามให้ display-safe/clamped segment อนุญาต auto cut.

เพิ่ม barrier regressions สองแบบ: (1) reliable `ชุมชน`, low-confidence/unreliable `เอ่อ`, reliable `ชุมชน`; (2) provider `timingIntegrity: 'untrusted'` เพราะ raw word `เอ่อ` ถูกทิ้งระหว่าง valid words. ทั้งสองต้องคืน `speechReduction.status == 'unavailable'`, ไม่มี default cut และ Task 4 repeat-only route ต้องไม่หักนาที. ข้อความ read-only อาจแสดงว่าหลักฐานเวลาไม่พอ แต่ detector ห้ามจับคำซ้ำข้าม unknown speech.

เพิ่ม valid audio-event barrier regression: words `ชุมชน`, timed audio event `(laughter)`, words `ชุมชน` พร้อม `timingIntegrity: 'trusted'` และ `hasTimedAudioEvents: true`. Subtitle/target path ยังใช้ได้ แต่ repeat ต้อง unavailable/ไม่มี cutและ repeat-only ไม่หักนาที; ห้ามลบ audio event ออกจาก timelineแล้วถือว่าสองคำติดกัน.

- [ ] **Step 6: รัน GREEN และ commit**

```powershell
npm.cmd --prefix apps/api run test -- src/modules/aiEdits/thaiTimedTokenReconstructor.test.ts src/modules/aiEdits/aiEditRecipe.test.ts
if ($LASTEXITCODE -ne 0) { throw "Thai timing tests failed with exit code $LASTEXITCODE" }
npm.cmd --prefix apps/api run build
if ($LASTEXITCODE -ne 0) { throw "API build failed with exit code $LASTEXITCODE" }
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git add apps/api/src/modules/aiEdits/thaiTimedTokenReconstructor.ts apps/api/src/modules/aiEdits/thaiTimedTokenReconstructor.test.ts apps/api/src/modules/aiEdits/aiEditRecipe.ts apps/api/src/modules/aiEdits/aiEditRecipe.test.ts
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "fix: reconstruct exact thai repeat timings"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

---

## Task 4: ใช้นโยบายหักโควตาที่ไม่คิดนาทีเมื่อ repeat-only ใช้งานไม่ได้

**Files:**

- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.test.ts`
- Create: `apps/api/src/modules/aiEdits/aiEditUsagePolicy.ts`
- Create: `apps/api/src/modules/aiEdits/aiEditUsagePolicy.test.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRoutes.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRoutes.test.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditAudioRoutes.test.ts`

**Interfaces:**

```ts
export type AiEditOutcomeState =
  | 'not-requested'
  | 'succeeded'
  | 'unavailable';

export type AiEditAnalysisOutcomes = {
  plan: AiEditOutcomeState;
  subtitle: AiEditOutcomeState;
  silence: AiEditOutcomeState;
  speechReduction: AiEditOutcomeState;
};

export const shouldReserveAiEditMinutes = ({
  outcomes,
  isLegacyRequest
}: {
  outcomes: AiEditAnalysisOutcomes;
  isLegacyRequest: boolean;
}): boolean;
```

เพิ่ม `analysisOutcomes: AiEditAnalysisOutcomes` ใน `AiEditRecipe` เพื่อเก็บผลจริง ไม่อนุมานจากปุ่มที่เปิดหรือข้อความสถานะ. `buildAiEditRecipe()` ต้องรับ `hasExplicitPlanRequest` และกำหนด outcome ดังนี้:

- `plan`: `succeeded` เฉพาะเมื่อมี explicit plan request และได้ `plan` ที่ใช้ได้; ถ้าขอแต่ไม่ได้ผลเป็น `unavailable`
- `subtitle`: `succeeded` เฉพาะเมื่อเปิด, `timingIntegrity == 'trusted'` และมี subtitle segment ที่ใช้ได้อย่างน้อยหนึ่งช่วง; untrusted timing ต้องไม่มี burn subtitle และเป็น `unavailable`
- `silence`: `succeeded` เมื่อเปิดและ transcript timeline ผ่านกฎ reliability/completeness แม้ไม่มี candidate; ถ้า timeline ไม่ปลอดภัยเป็น `unavailable`
- `speechReduction`: `succeeded` เฉพาะ `speechReduction.status == 'ready'`; timing ที่ประกอบไม่ได้เป็น `unavailable`
- ความสามารถที่ไม่ได้ขอเป็น `not-requested`; color ไม่ใช่ AI outcome ใน policy นี้

Mobile parser อนุญาตให้ไม่อ่าน field ใหม่นี้เพราะใช้ตัดสิน ledger ฝั่ง API เท่านั้น แต่ `API.md` ต้องบันทึก contract ไว้ใน Task 9.

- [ ] **Step 1: เขียน policy matrix test ก่อน**

```ts
const outcomes = (
  value: Partial<AiEditAnalysisOutcomes>
): AiEditAnalysisOutcomes => ({
  plan: 'not-requested',
  subtitle: 'not-requested',
  silence: 'not-requested',
  speechReduction: 'not-requested',
  ...value
});

it.each([
  ['repeat-only unavailable', outcomes({ speechReduction: 'unavailable' }), false],
  ['repeat-only ready', outcomes({ speechReduction: 'succeeded' }), true],
  ['repeat unavailable plus subtitle success', outcomes({
    speechReduction: 'unavailable', subtitle: 'succeeded'
  }), true],
  ['repeat unavailable plus subtitle unavailable', outcomes({
    speechReduction: 'unavailable', subtitle: 'unavailable'
  }), false],
  ['repeat unavailable plus silence success-empty', outcomes({
    speechReduction: 'unavailable', silence: 'succeeded'
  }), true],
  ['repeat unavailable plus silence unavailable', outcomes({
    speechReduction: 'unavailable', silence: 'unavailable'
  }), false],
  ['repeat unavailable plus plan success', outcomes({
    speechReduction: 'unavailable', plan: 'succeeded'
  }), true],
  ['repeat unavailable plus plan unavailable', outcomes({
    speechReduction: 'unavailable', plan: 'unavailable'
  }), false]
])('%s => reserve=%s', (_name, analysisOutcomes, expected) => {
  expect(shouldReserveAiEditMinutes({
    outcomes: analysisOutcomes,
    isLegacyRequest: false
  })).toBe(expected);
});
```

เพิ่ม regression: request แบบ legacy ที่ไม่มี capability field และไม่มี plan ยังคงคิดนาทีด้วย `isLegacyRequest: true` เพื่อไม่ขยายขอบเขตพฤติกรรมโดยไม่ตั้งใจ; color-only ที่หลุดมาถึง API มีทุก outcome เป็น `not-requested` และไม่คิดนาที.

- [ ] **Step 2: รัน RED**

```powershell
npm.cmd --prefix apps/api run test -- src/modules/aiEdits/aiEditUsagePolicy.test.ts
$redExitCode = $LASTEXITCODE
if ($redExitCode -eq 0) { throw "Expected AI usage policy test to fail before implementation" }
```

- [ ] **Step 3: Implement pure policy**

```ts
export const shouldReserveAiEditMinutes = ({
  outcomes,
  isLegacyRequest
}: UsagePolicyInput): boolean => {
  if (isLegacyRequest) return true;
  return Object.values(outcomes).some((state) => state === 'succeeded');
};
```

- [ ] **Step 4: ปฏิเสธคำขอที่ไม่มีงาน AI จริงก่อนเรียก provider แล้วเชื่อม policy หลัง recipe**

ใน `/ai-edits/prepare`:

```ts
const hasExplicitPlanRequest = Boolean(
  styleId || prompt || targetDurationSeconds !== undefined
);
const isLegacyRequest = request.body.capabilities === undefined &&
  !hasExplicitPlanRequest;
const hasSupportedAnalysisRequest = hasExplicitPlanRequest ||
  capabilities.subtitle ||
  capabilities.silence ||
  capabilities.filler;

// Must run before transcription/upload-provider work. The official mobile
// color-only route is local and must never reach /prepare.
if (!isLegacyRequest && !hasSupportedAnalysisRequest) {
  response.status(400).json({
    status: 'error',
    code: 'AI_EDIT_NO_ANALYSIS_REQUESTED',
    message: 'เลือกงาน AI ที่ต้องการก่อนเริ่มวิเคราะห์'
  });
  return;
}

// Existing transcription/planning and buildAiEditRecipe happen here.

const shouldReserve = shouldReserveAiEditMinutes({
  outcomes: recipe.analysisOutcomes,
  isLegacyRequest
});

if (!shouldReserve) {
  const currentUsedMinutes = await aiEditUsageStore.sumMinutesForMonth({
    userId: authUser.id,
    monthKey
  });
  response.json({
    status: 'ok',
    recipe,
    quota: buildQuota(currentUsedMinutes)
  });
  return;
}
```

คง atomic `reserve()` เดิมสำหรับกรณีอื่นทั้งหมด ห้ามใช้ค่า `usedMinutes` จาก pre-check เพราะ request คู่ขนานอาจเปลี่ยนยอดระหว่าง transcription.

เพิ่ม route tests สำหรับ explicit `capabilities: {}` และ `{ color: true }`: ตอบ `400 AI_EDIT_NO_ANALYSIS_REQUESTED`, `transcribe`/Gemini/upload-provider call count เป็น 0 และ ledger ไม่เพิ่ม. Legacy request ที่ละ `capabilities` ทั้ง field ยังคงเดินเส้นทางเดิมและคิดนาที. Pure policy ที่คืน false สำหรับ all `not-requested` เป็น defense-in-depth แต่ route validation ต้องกันค่า provider ก่อนเสมอ.

- [ ] **Step 5: เพิ่ม route tests ตรวจ ledger จริง**

เพิ่ม route test โดยตรวจยอดจริงก่อน/หลัง (ไม่ต้องเปิด internal store ให้ test):

```ts
it('does not meter an unavailable repeat-only preparation', async () => {
  const transcribe = vi.fn(async () => ({
    text: 'ชุมชน ชุมชน',
    language: 'th',
    durationSeconds: 60,
    segments: [{ text: 'ชุมชน ชุมชน', start: 0, end: 3 }],
    words: [
      { word: 'ชุม', start: 0, end: 0.1 },
      { word: 'ชล', start: 0.1, end: 0.5 },
      { word: 'ชุมชน', start: 0.7, end: 1.2 }
    ],
    timingIntegrity: 'trusted',
    hasTimedAudioEvents: false,
    model: 'test-elevenlabs'
  }));
  const app = createApp({ transcriptionProvider: { transcribe } });
  const headers = { 'x-postdee-subscription-plan': 'PRO' };

  const response = await request(app)
    .post('/ai-edits/prepare')
    .set(headers)
    .send({
      videoS3Key: ownedUploadKey('local-dev-user', 'repeat.mp4'),
      durationSeconds: 60,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' }
    })
    .expect(200);

  expect(response.body.recipe.speechReduction.status).toBe('unavailable');
  expect(response.body.quota.usedMinutes).toBe(0);
  const after = await request(app).get('/ai-edits/quota').set(headers).expect(200);
  expect(after.body.quota.usedMinutes).toBe(0);
});
```

ทำ table/helper เพิ่มโดยเปลี่ยน provider transcript/plan/capabilities และ assert ทั้ง `analysisOutcomes` กับยอดจริงเฉพาะคำขอที่ได้ recipe: repeat-only ready = 1, repeat unavailable + subtitle สำเร็จ = 1, repeat unavailable + subtitle ไม่มี segment = 0, repeat unavailable + target plan สำเร็จ = 1, repeat unavailable + plan ใช้ไม่ได้ = 0, silence timeline ปลอดภัยแต่ candidate ว่าง = 1 และ silence timeline ไม่ปลอดภัย = 0. Color-only/explicit empty เป็น rejection suite แยก: assert HTTP 400/code/call counts/ledger = 0 และห้าม assert `analysisOutcomes` เพราะไม่มี recipe ถูกสร้าง. ใช้ app ใหม่ต่อ case เพื่อไม่ให้ usage จาก caseก่อนหน้าปนกัน. Rerender เป็น mobile-only actionและต้องไม่มี request `/ai-edits/prepare` เพิ่ม.

เพิ่ม repeat-only route cases จาก Task 3 ทั้ง provider malformed-word (`timingIntegrity: 'untrusted'`), reliable–unreliable–reliable และ valid timed-audio-event barrier: `analysisOutcomes.speechReduction == 'unavailable'`, ledger ก่อน/หลังเท่ากันและไม่มี default cut. เพิ่ม silence-only malformed-word case: outcome เป็น `unavailable`, candidate/cut ว่างและ ledger ไม่เพิ่ม. Target/style/prompt ที่ untrusted เป็น rejection suite แยก: HTTP 422/code `AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE`, planner call count 0, ไม่มี recipe และ ledger ไม่เพิ่ม.

นำ chunk fixtures จาก Task 2 มาตรวจ ledger ใน Task 4: untrusted middle chunk และ clipped range ต้องให้ requested silence/repeat outcomes เป็น unavailable และไม่ reserve นาทีเมื่อไม่มี analysis อื่นสำเร็จ; หาก subtitle สร้าง segment ได้จริงจึงคิดหนึ่งครั้งจาก subtitle outcome เท่านั้น.

หมายเหตุ: คง preliminary quota pre-check ไว้ในรอบนี้; ไม่เปลี่ยน semantics ของ quota-full request ก่อน transcription.

- [ ] **Step 6: รัน GREEN, build และ commit**

```powershell
npm.cmd --prefix apps/api run test -- src/modules/aiEdits/aiEditUsagePolicy.test.ts src/modules/aiEdits/aiEditRoutes.test.ts src/modules/aiEdits/aiEditAudioRoutes.test.ts
if ($LASTEXITCODE -ne 0) { throw "AI usage policy tests failed with exit code $LASTEXITCODE" }
npm.cmd --prefix apps/api run build
if ($LASTEXITCODE -ne 0) { throw "API build failed with exit code $LASTEXITCODE" }
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git add apps/api/src/modules/aiEdits/aiEditRecipe.ts apps/api/src/modules/aiEdits/aiEditRecipe.test.ts apps/api/src/modules/aiEdits/aiEditUsagePolicy.ts apps/api/src/modules/aiEdits/aiEditUsagePolicy.test.ts apps/api/src/modules/aiEdits/aiEditRoutes.ts apps/api/src/modules/aiEdits/aiEditRoutes.test.ts apps/api/src/modules/aiEdits/aiEditAudioRoutes.test.ts
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "fix: reserve ai minutes only for usable results"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

---

## Task 5: แยก transcript boundary evidence ออกจากซับที่มองเห็น

**Files:**

- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.test.ts`
- Modify: `apps/mobile/lib/core/network/postdee_api_client.dart`
- Create: `apps/mobile/lib/features/ai_editing/ai_edit_timeline_mapper.dart`
- Create: `apps/mobile/test/ai_edit_timeline_mapper_test.dart`
- Modify: `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`
- Modify: `apps/mobile/test/postdee_api_client_test.dart`
- Modify: `apps/mobile/test/ai_editing_screen_test.dart`

**Interfaces:**

```dart
class AiEditTimelineEvidence {
  const AiEditTimelineEvidence({
    required this.boundarySegments,
    required this.protectedSpeechRanges,
  });

  final List<SubtitleSegment> boundarySegments;
  final List<SilenceCutRange> protectedSpeechRanges;

  bool get hasReliableBoundaries => boundarySegments.isNotEmpty;
}

AiEditTimelineEvidence mapAiEditTimelineEvidence(
  AiEditTranscriptResult transcript,
);
```

เพิ่ม field แบบ backward-compatible:

```ts
// AiEditRecipe.transcript on API
boundarySegments: TranscriptSegment[];
```

```dart
// AiEditTranscriptResult on mobile
// constructor: this.boundarySegments = const []
final List<ClipTranscriptSegment> boundarySegments;
```

กำหนด constructor parameter เป็น `this.boundarySegments = const []` และ `fromJson` ใช้ `json['boundarySegments']` เมื่อเป็น list มิฉะนั้น `const []`; ทำให้ local recipe และ caller เดิม compile ต่อได้โดยไม่ต้องส่ง field. API ต้องส่ง `boundarySegments` จาก `repairThaiSubtitleSegmentBoundaries(strictReliableTranscriptSegments, language, transcript.text)` ตาม strict validator ใน Task 2 ไม่ใช่ display-safe/clamped segments. ห้ามให้ mobile ใช้ raw `transcript.segments` เป็น sentence boundary เพราะ provider segment อาจแบ่งกลางคำไทย; raw segments/words ยังคงใช้เป็น protected speech ranges แบบอนุรักษนิยม. หาก payload เก่าไม่มี `boundarySegments` ให้ mobile fail closed ด้วยรายการ boundary ว่าง ไม่ fallback ไป raw segment.

- [ ] **Step 1: เขียน mapper tests**

```dart
AiEditTranscriptResult transcriptFixture({
  List<ClipTranscriptSegment> segments = const [],
  List<ClipTranscriptSegment> boundarySegments = const [],
  List<AiEditTranscriptWordResult> words = const [],
  double durationSeconds = 20,
}) => AiEditTranscriptResult(
  text: segments.map((segment) => segment.text).join(' '),
  language: 'th',
  durationSeconds: durationSeconds,
  segments: segments,
  boundarySegments: boundarySegments,
  words: words,
  model: 'test-elevenlabs',
);

test('maps transcript boundaries without creating visible subtitle state', () {
  final evidence = mapAiEditTimelineEvidence(transcriptFixture(
    segments: const [
      ClipTranscriptSegment(text: 'ประโยคสมบูรณ์', start: 10, end: 15),
    ],
    boundarySegments: const [
      ClipTranscriptSegment(text: 'ประโยคสมบูรณ์', start: 10, end: 15),
    ],
  ));

  expect(evidence.boundarySegments.single.text, 'ประโยคสมบูรณ์');
  expect(evidence.protectedSpeechRanges.single.start, 10);
});

test('drops invalid timing instead of guessing', () {
  const invalid = ClipTranscriptSegment(text: 'bad', start: 5, end: 4);
  final evidence = mapAiEditTimelineEvidence(transcriptFixture(
    segments: const [invalid],
    boundarySegments: const [invalid],
  ));
  expect(evidence.boundarySegments, isEmpty);
  expect(evidence.protectedSpeechRanges, isEmpty);
});

for (final segment in const [
  ClipTranscriptSegment(
    text: 'confidence ต่ำ', start: 1, end: 2, avgLogprob: -1.01),
  ClipTranscriptSegment(
    text: 'อาจไม่มีเสียง', start: 1, end: 2, noSpeechProbability: 0.61),
  ClipTranscriptSegment(
    text: 'ข้อความบีบอัดซ้ำ', start: 1, end: 2, compressionRatio: 2.41),
]) {
  test('does not use ${segment.text} as an unreliable sentence boundary', () {
    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        segments: [segment],
        boundarySegments: [segment],
      ),
    );
    expect(evidence.boundarySegments, isEmpty);
    expect(evidence.protectedSpeechRanges, isNotEmpty);
  });
}
```

เพิ่ม cases: prompt leakage `ชื่อแอปให้เขียนเป็นภาษาไทยว่า`/`คำศัพท์เฉพาะ`, unexpected script/`�`, empty text, non-finite/out-of-duration ranges, overlapping boundary segments, global transcript words, validated `segment.words`, sort/dedupe และ input ไม่ถูก mutate. ทุก test ที่พิสูจน์การ reject boundary ต้องใส่ candidate เดียวกันใน `boundarySegments` ด้วย และใส่ raw copy ใน `segments` เพื่อพิสูจน์ว่า candidate ถูก reject แต่ช่วงเสียงยังถูกป้องกัน; ห้ามปล่อย `boundarySegments` ว่างเพราะ test จะผ่านโดยไม่ได้ทดสอบ reliability. Segment ที่ไม่น่าเชื่อถือหรือ timeline ที่ overlap ห้ามเป็น boundary แต่ช่วงเวลาที่ยัง valid ต้องอยู่ใน protected ranges แบบอนุรักษนิยม.

เพิ่ม API regression ให้ raw segments แบ่งคำไทยกลางคำ เช่น `ดุ๊ก` + `ดิ๊กมาก` แต่ `recipe.transcript.boundarySegments` คืนช่วงที่ซ่อมและรวมเป็น `ดุ๊กดิ๊กมาก`; เพิ่ม mobile JSON parser regression สำหรับ field นี้ และ mapper regression ที่ raw segment มีขอบ 1.0 วินาทีแต่ repaired boundary ครอบ 0–2 วินาที แล้ว assert ว่า 1.0 ไม่ถูกใช้เป็นขอบตัด. เพิ่ม payload เก่าที่ไม่มี field แล้ว assert `boundarySegments` ว่าง.

เพิ่ม API regression จาก Task 2 ที่ `timingIntegrity: 'untrusted'` แม้ valid segment subset ดูซ่อมได้: `recipe.transcript.boundarySegments` ต้องว่าง. Mobile จึง fail closed และแสดง warning หลักฐานขอบประโยคไม่พอโดยไม่ fallback ไป raw segments.

ขยาย fixture ใน `ai_editing_screen_test.dart` เพื่อให้แต่ละ test กำหนด transcript ภายในได้โดยไม่ผูกกับ visible subtitle:

```diff
 AiEditPrepareResult _createPrepareFixture({
   AiEditPlanResult plan = const AiEditPlanResult(
     cuts: [],
     summary: '',
     model: 'none',
   ),
   double transcriptDurationSeconds = 45,
+  List<ClipTranscriptSegment> transcriptSegments = const [
+    ClipTranscriptSegment(
+      text: 'รีวิวสินค้าชิ้นนี้ดีมาก',
+      start: 0,
+      end: 10,
+    ),
+    ClipTranscriptSegment(text: 'ราคาคุ้มมาก', start: 11, end: 20),
+  ],
+  List<ClipTranscriptSegment>? transcriptBoundarySegments,
   List<ClipTranscriptSegment> subtitleSegments = const [
     ClipTranscriptSegment(
       text: 'รีวิวสินค้าชิ้นนี้ดีมาก',
       start: 0,
       end: 10,
     ),
   ],
 }) =>
@@
         transcript: AiEditTranscriptResult(
@@
-          segments: const [
-            ClipTranscriptSegment(
-              text: 'รีวิวสินค้าชิ้นนี้ดีมาก',
-              start: 0,
-              end: 10,
-            ),
-            ClipTranscriptSegment(
-              text: 'ราคาคุ้มมาก',
-              start: 11,
-              end: 20,
-            ),
-          ],
+          segments: transcriptSegments,
+          boundarySegments:
+              transcriptBoundarySegments ?? transcriptSegments,
```

- [ ] **Step 2: รัน RED**

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_timeline_mapper_test.dart
  $redExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($redExitCode -eq 0) { throw "Expected timeline mapper test to fail before implementation" }
```

- [ ] **Step 3: Implement mapper แบบ fail closed**

ใช้ implementation shape นี้; helper `_mergeRanges` ต้อง sort แล้วรวมเฉพาะช่วงที่ overlap/touch กัน:

```dart
AiEditTimelineEvidence mapAiEditTimelineEvidence(
  AiEditTranscriptResult transcript,
) {
  final duration = transcript.durationSeconds;
  bool isValid(double start, double end) =>
      duration.isFinite &&
      duration > 0 &&
      start.isFinite &&
      end.isFinite &&
      start >= 0 &&
      end > start &&
      end <= duration;

  bool isReliable(ClipTranscriptSegment segment) {
    final text = segment.text.trim().toLowerCase();
    const leakedSignals = [
      'ชื่อแอปให้เขียนเป็นภาษาไทยว่า',
      'คำศัพท์เฉพาะ',
    ];
    final unexpectedScript = RegExp(
      r'[\u0400-\u04FF\u4E00-\u9FFF\uAC00-\uD7AF'
      r'\u0600-\u06FF\u0900-\u097F\u3040-\u30FF\uFFFD]',
      unicode: true,
    );
    return text.isNotEmpty &&
        !leakedSignals.any(text.contains) &&
        !unexpectedScript.hasMatch(text) &&
        (segment.avgLogprob == null || segment.avgLogprob! >= -1) &&
        (segment.noSpeechProbability == null ||
            segment.noSpeechProbability! <= 0.6) &&
        (segment.compressionRatio == null ||
            segment.compressionRatio! <= 2.4);
  }

  final boundaryCandidates = transcript.boundarySegments
      .where((segment) =>
          isReliable(segment) && isValid(segment.start, segment.end))
      .map((segment) => SubtitleSegment(
            text: segment.text.trim(),
            start: segment.start,
            end: segment.end,
          ))
      .toList(growable: false)
    ..sort((left, right) => left.start.compareTo(right.start));
  final boundariesOverlap = boundaryCandidates.asMap().entries.any(
        (entry) => entry.key > 0 &&
            entry.value.start < boundaryCandidates[entry.key - 1].end,
      );
  final boundarySegments = boundariesOverlap
      ? const <SubtitleSegment>[]
      : boundaryCandidates;

  final protected = <SilenceCutRange>[
    for (final segment in transcript.segments)
      if (isValid(segment.start, segment.end))
        SilenceCutRange(start: segment.start, end: segment.end),
    for (final word in transcript.words)
      if (isValid(word.start, word.end))
        SilenceCutRange(start: word.start, end: word.end),
    for (final segment in transcript.segments)
      for (final word in segment.words ?? const <AiEditTranscriptWordResult>[])
        if (isValid(word.start, word.end))
          SilenceCutRange(start: word.start, end: word.end),
  ];

  return AiEditTimelineEvidence(
    boundarySegments: List.unmodifiable(boundarySegments),
    protectedSpeechRanges: List.unmodifiable(_mergeRanges(protected)),
  );
}
```

ห้าม clamp ค่าเสียหายชัดเจนหรือ mutate input; boundary cues ห้าม merge เพราะแต่ละ cue คือขอบประโยคที่ alignment ต้องรักษา.

- [ ] **Step 4: เพิ่ม widget integration test ก่อนแก้ screen**

สร้าง prepared recipe ที่ `subtitle.enabled == false`, `subtitles.segments == []`, แต่ transcript cue คร่อมปลาย 30 วินาที:

```dart
testWidgets('uses transcript boundaries without rendering subtitles', (tester) async {
  final pickedVideo = _createPickedVideoFixture(
    'boundary-only.mp4',
    durationSeconds: 45,
  );
  AiEditPrepareRequest? prepareRequest;
  BurnSubtitleRequest? captured;

  await tester.pumpWidget(_testApp(AiEditingScreen(
    initialTargetDurationSeconds: 30,
    pickVideo: () async => pickedVideo,
    loadSubscription: () async => _subscriptionFixture('PRO'),
    extractAudio: _extractAudioFixture,
    cleanupAiEditAudio: (_) async {},
    createUpload: (_) async => const UploadResult(
      id: 'boundary-upload',
      videoS3Key: 'uploads/boundary-only.mp4',
      storageProvider: 's3',
    ),
    uploadVideoFile: (_, __) async {},
    prepareEdit: (request) async {
      prepareRequest = request;
      return _createPrepareFixture(
        transcriptDurationSeconds: 45,
        transcriptSegments: const [
          ClipTranscriptSegment(text: 'เปิดเรื่องสมบูรณ์', start: 0, end: 4),
          ClipTranscriptSegment(
            text: 'ประโยคที่คร่อมขอบเวลา',
            start: 29.5,
            end: 30.6,
          ),
        ],
        subtitleSegments: const [],
        plan: const AiEditPlanResult(
          cuts: [AiEditCut(start: 30, end: 45)],
          summary: 'keep the first story window',
          model: 'test-gemini',
        ),
      );
    },
    burnVideo: (request) async {
      captured = request;
      return _createRenderedVideoFixture('boundary-result.mp4');
    },
  )));

  await tester.tap(find.byKey(const ValueKey('ai-add-video')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('ai-process-button')));
  await tester.pumpAndSettle();

  expect(captured!.segments, isEmpty);
  expect(captured!.silenceRanges, contains(
    isA<SilenceCutRange>().having((range) => range.start, 'start', 30.6),
  ));
  expect(captured!.outputDurationSeconds, closeTo(30.6, 0.01));
  expect(prepareRequest!.capabilities.values, everyElement(isFalse));
});
```

เพิ่ม test `reports missing boundary evidence without inventing a new cut` โดย transcript segments/words ว่าง, planner cut 30–45, แล้ว assert cut ยังเริ่ม 30, ไม่มี subtitle overlay และพบ key `ai-boundary-evidence-unavailable` ในหน้า review.

เพิ่ม test หัวคลิป `aligns a leading plan cut to transcript boundary when subtitles are off`: planner cut 0–10, reliable cue 9.4–10.5, visible subtitle listว่าง แล้ว assert final leading cut จบ `closeTo(9.25, 0.01)` ตาม pre-roll เดิม 0.15 วินาที (และไม่กินต้น cue), `BurnSubtitleRequest.segments` ว่าง และ request capabilities ทุกตัว false. ห้ามส่ง `subtitlePreRollSeconds: 0` เพราะจะเปลี่ยนพฤติกรรมซับเดิมเพื่อให้ test ผ่าน.

Expected RED: cut starts at 30.0 because current screen uses visible subtitle segments for boundary alignment.

- [ ] **Step 5: ใช้ boundary evidence ใน `_renderPreparedRecipe()`**

```dart
final timelineEvidence = mapAiEditTimelineEvidence(recipe.transcript);
final boundarySegments = timelineEvidence.boundarySegments;

if (sourceDuration > 0 && boundarySegments.isNotEmpty) {
  planCutRanges = alignLeadingCutToFirstSubtitle(
    planCutRanges,
    boundarySegments,
    sourceDuration,
  );
  if (!_isUsingOriginalDuration) {
    planCutRanges = alignTargetTailToSubtitleBoundary(
      cuts: planCutRanges,
      subtitleSegments: boundarySegments,
      durationSeconds: sourceDuration,
      targetSeconds: _selectedDurationSeconds.toDouble(),
    );
  }
}
```

แทน block alignment เดิมด้วย block นี้เพียงจุดเดียว; อย่าประกาศ `subtitleSegments` ซ้ำ รายการซับที่มองเห็นต้องคง logic capability-gated เดิมไว้สำหรับ `BurnSubtitleRequest.segments` เท่านั้น. หลัง alignment ห้าม clamp กลับมา 30.0; ให้ `BurnSubtitleRequest.outputDurationSeconds` และข้อความผลลัพธ์ใช้เวลาที่ปรับจริงภายใน tolerance เดิม. หากไม่มี boundary ที่เชื่อถือได้ ให้ใช้ planner story window เดิมและไม่เดา boundary ใหม่ พร้อมแสดง review metadata:

```dart
String? _boundaryEvidenceWarning;

_boundaryEvidenceWarning =
    !_isUsingOriginalDuration && !timelineEvidence.hasReliableBoundaries
        ? 'ไม่พบขอบประโยคที่ยืนยันได้ · ใช้ช่วงเรื่องจาก AI โดยไม่เดาเวลาใหม่'
        : null;
```

render widget ที่มี `const ValueKey('ai-boundary-evidence-unavailable')` เมื่อ warning ไม่เป็น null และล้าง warning เมื่อเลือกวิดีโอใหม่. ห้ามแตะ Hook scoring.
การ assign `_boundaryEvidenceWarning` ต้องทำทุก render ไม่ใช่เฉพาะ failure branch: เมื่อกลับมาใช้ original duration หรือพบ reliable boundary ต้องตั้งเป็น `null` ทันที. เพิ่ม widget test ที่เริ่มจากผลก่อนหน้าซึ่งมี warning แล้ว rerender ด้วย reliable boundary และ original duration เพื่อยืนยันว่า warning เก่าไม่ค้าง.

- [ ] **Step 6: รัน focused tests และ commit**

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_timeline_mapper_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Timeline mapper tests failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_editing_screen_test.dart --plain-name "uses transcript boundaries without rendering subtitles"
  if ($LASTEXITCODE -ne 0) { throw "Boundary widget test failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\subtitle_timeline_alignment_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Timeline alignment tests failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git add apps/api/src/modules/aiEdits/aiEditRecipe.ts apps/api/src/modules/aiEdits/aiEditRecipe.test.ts apps/mobile/lib/core/network/postdee_api_client.dart apps/mobile/lib/features/ai_editing/ai_edit_timeline_mapper.dart apps/mobile/lib/features/ai_editing/ai_editing_screen.dart apps/mobile/test/postdee_api_client_test.dart apps/mobile/test/ai_edit_timeline_mapper_test.dart apps/mobile/test/ai_editing_screen_test.dart
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "fix: align ai cuts to transcript boundaries"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

---

## Task 6: สร้าง waveform silence verifier บนมือถือ

**Files:**

- Create: `apps/mobile/lib/features/ai_editing/ai_edit_silence_verifier.dart`
- Create: `apps/mobile/test/ai_edit_silence_verifier_test.dart`

**Interfaces:**

```dart
class AiEditSilenceDetectOutput {
  const AiEditSilenceDetectOutput({required this.succeeded, required this.logs});
  final bool succeeded;
  final String logs;
}

class AiEditSilenceVerificationResult {
  const AiEditSilenceVerificationResult({
    required this.cutRanges,
    required this.probeSucceeded,
  });
  const AiEditSilenceVerificationResult.failed()
      : cutRanges = const [],
        probeSucceeded = false;

  final List<SilenceCutRange> cutRanges;
  final bool probeSucceeded;
}

typedef AiEditSilenceDetectRunner =
    Future<AiEditSilenceDetectOutput> Function(List<String> arguments);

List<SilenceCutRange> parseAiEditSilenceLog(
  String logs, {
  required double sourceDurationSeconds,
});

List<SilenceCutRange> intersectVerifiedSilenceCuts({
  required List<SilenceCutRange> transcriptCandidates,
  required List<SilenceCutRange> waveformSilences,
  required List<SilenceCutRange> protectedSpeechRanges,
  required double sourceDurationSeconds,
  double safetyPaddingSeconds = 0.10,
  double minimumCutSeconds = 0.25,
});

class AiEditSilenceVerifier {
  AiEditSilenceVerifier({AiEditSilenceDetectRunner? runFfmpeg});

  Future<AiEditSilenceVerificationResult> call({
    required File sourceFile,
    required double sourceDurationSeconds,
    required List<SilenceCutRange> transcriptCandidates,
    required List<SilenceCutRange> protectedSpeechRanges,
  });
}
```

- [ ] **Step 1: เขียน pure/native-runner tests**

ต้องครอบคลุม:

- command exact for the fixture path: `-hide_banner -nostats -i C:\fixtures\clip.mp4 -af silencedetect=noise=-40dB:d=0.20 -f null -`
- parse logs หลายบรรทัด `silence_start`/`silence_end`
- orphan/malformed marker ไม่ถูกเดา
- negative/out-of-duration timestamps เช่น start `-1` หรือ end `999` ถูกทิ้งทั้งคู่ ไม่ clamp ให้กลายเป็นช่วงที่ดูเหมือนปลอดภัย
- candidate ∩ waveform เท่านั้น
- padding เข้าในช่วง 0.10 วินาทีต่อข้าง “หลัง” intersection
- ช่วงหลัง padding สั้นกว่า 0.25 วินาทีถูกทิ้ง
- candidate ที่แตะ 0 หรือ source duration ถูกทิ้งเพื่อรักษาหัว/ท้าย
- range ที่ทับ protected speech แม้บางส่วนถูกทิ้งทั้งช่วง
- runner throw/non-zero → `probeSucceeded == false`, cuts ว่าง
- runner สำเร็จแต่ไม่พบ silence → `probeSucceeded == true`, cuts ว่าง

ตัวอย่างแกน assertion:

```dart
test('keeps only padded waveform intersections away from speech', () async {
  final verifier = AiEditSilenceVerifier(
    runFfmpeg: (_) async => const AiEditSilenceDetectOutput(
      succeeded: true,
      logs: 'silence_start: 5.0\nsilence_end: 6.0 | silence_duration: 1.0',
    ),
  );

  final result = await verifier.call(
    sourceFile: File('clip.mp4'),
    sourceDurationSeconds: 20,
    transcriptCandidates: const [SilenceCutRange(start: 4.8, end: 6.2)],
    protectedSpeechRanges: const [],
  );

  expect(result.probeSucceeded, isTrue);
  expect(result.cutRanges.single.start, closeTo(5.1, 0.001));
  expect(result.cutRanges.single.end, closeTo(5.9, 0.001));
});
```

- [ ] **Step 2: รัน RED**

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_silence_verifier_test.dart
  $redExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($redExitCode -eq 0) { throw "Expected silence verifier test to fail before implementation" }
```

- [ ] **Step 3: Implement parser/intersection และ production runner**

ใช้ `FFmpegKit.executeWithArguments`, `ReturnCode.isSuccess` และ `session.getAllLogsAsString()` ตาม pattern ที่มีใน `subtitle_burn_video_processor.dart`.

Parser ต้องจับ event ตามลำดับ log และไม่เดา orphan marker:

```dart
List<SilenceCutRange> parseAiEditSilenceLog(
  String logs, {
  required double sourceDurationSeconds,
}) {
  if (!sourceDurationSeconds.isFinite || sourceDurationSeconds <= 0) {
    return const [];
  }
  final eventPattern = RegExp(
    r'silence_(start|end):\s*(-?[0-9]+(?:\.[0-9]+)?)',
  );
  final parsed = <SilenceCutRange>[];
  double? openStart;
  for (final match in eventPattern.allMatches(logs)) {
    final value = double.tryParse(match.group(2)!);
    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        value > sourceDurationSeconds) {
      openStart = null;
      continue;
    }
    if (match.group(1) == 'start') {
      if (openStart != null) {
        // Two starts without a closing end are malformed. Discard both
        // instead of guessing which timestamp is authoritative.
        openStart = null;
        continue;
      }
      openStart = value;
      continue;
    }
    final start = openStart;
    openStart = null;
    if (start == null) continue;
    if (value > start) {
      parsed.add(SilenceCutRange(start: start, end: value));
    }
  }
  return List.unmodifiable(parsed);
}
```

Production runner ใช้ arguments จริงดังนี้:

```dart
final arguments = <String>[
  '-hide_banner',
  '-nostats',
  '-i',
  sourceFile.path,
  '-af',
  'silencedetect=noise=-40dB:d=0.20',
  '-f',
  'null',
  '-',
];
```

ลำดับ pure algorithm:

```dart
import 'dart:math' as math;

final overlapStart = math.max(candidate.start, waveform.start);
final overlapEnd = math.min(candidate.end, waveform.end);
final paddedStart = overlapStart + 0.10;
final paddedEnd = overlapEnd - 0.10;
if (paddedEnd - paddedStart < 0.25) continue;
if (protected.any((speech) =>
    paddedStart < speech.end && paddedEnd > speech.start)) continue;
verified.add(SilenceCutRange(start: paddedStart, end: paddedEnd));
```

ก่อน loop ให้ทิ้ง candidate ที่ `start <= epsilon` หรือ `end >= duration - epsilon`; normalize finite bounds และ sort/dedupe output. ห้าม split ช่วงเพื่อหลบ protected speech เพราะจะเพิ่มการเดา.

- [ ] **Step 4: รัน GREEN และ commit**

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_silence_verifier_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Silence verifier tests failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git add apps/mobile/lib/features/ai_editing/ai_edit_silence_verifier.dart apps/mobile/test/ai_edit_silence_verifier_test.dart
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "feat: verify ai silence cuts from waveform"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

---

## Task 7: เชื่อม verified silence เข้าหน้า AI Editor และ Subtitle Studio อย่างปลอดภัย

**Files:**

- Create: `apps/mobile/lib/features/ai_editing/ai_edit_safety_flags.dart`
- Modify: `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`
- Modify: `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project_mapper.dart`
- Create: `apps/mobile/test/ai_edit_safety_flags_test.dart`
- Modify: `apps/mobile/test/ai_editing_screen_test.dart`
- Modify: `apps/mobile/test/subtitle_project_mapper_test.dart`

**Interfaces:**

เพิ่ม dependency injection ใน `AiEditingScreen`:

```dart
typedef AiEditSilenceVerification =
    Future<AiEditSilenceVerificationResult> Function({
  required File sourceFile,
  required double sourceDurationSeconds,
  required List<SilenceCutRange> transcriptCandidates,
  required List<SilenceCutRange> protectedSpeechRanges,
});

// Add `this.verifySilence` to AiEditingScreen's constructor.
final AiEditSilenceVerification? verifySilence;
```

แยก source ที่กำลังตั้งค่าจาก source ที่มีผลลัพธ์ยอมรับแล้ว:

```dart
PickedVideoFile? _selectedVideo; // working/pending source ในหน้า setup
double? _selectedVideoDurationSeconds;
PickedVideoFile? _activeSourceVideo; // accepted source ของ review/edit/export
double? _activeSourceDurationSeconds;
```

`_selectedVideo` เปลี่ยนได้ทันทีเมื่อผู้ใช้ลองคลิปใหม่ แต่ `_activeSourceVideo` และ state ผลลัพธ์ทั้งหมดต้องเปลี่ยนพร้อมกันหลัง initial render สำเร็จเท่านั้น. Review, original preview, subtitle edit, silence retry และ export ต้องอ่าน active source; ห้ามจับ recipe/project ที่ยอมรับแล้วคู่กับ pending source.

เพิ่ม safety rollback flags ที่ default เปิดพฤติกรรมใหม่ แต่ปิดแยกได้ตอน build โดยไม่ย้อนโค้ดปลอดภัย:

```dart
class AiEditSafetyFlags {
  const AiEditSafetyFlags({
    this.verifiedSilenceEnabled = true,
    this.automaticRepeatCutsEnabled = true,
  });

  const AiEditSafetyFlags.fromEnvironment()
      : verifiedSilenceEnabled = const bool.fromEnvironment(
          'AI_EDIT_VERIFIED_SILENCE_ENABLED',
          defaultValue: true,
        ),
        automaticRepeatCutsEnabled = const bool.fromEnvironment(
          'AI_EDIT_AUTO_REPEAT_CUTS_ENABLED',
          defaultValue: true,
        );

  final bool verifiedSilenceEnabled;
  final bool automaticRepeatCutsEnabled;
}

// AiEditingScreen constructor default
this.safetyFlags = const AiEditSafetyFlags.fromEnvironment();
final AiEditSafetyFlags safetyFlags;
```

เมื่อ `verifiedSilenceEnabled == false`: `_isCapabilityAvailable('silence')` ต้องเป็น false, effective capability ต้อง false และ verifier/final silence cuts ต้องไม่ทำงาน. เมื่อ `automaticRepeatCutsEnabled == false`: ยังส่ง filler requestเพื่อแสดงกลุ่มที่ตรวจพบ แต่ selection เป็น read-only, initial/review/export removed occurrence IDs ต้องว่าง และ renderer ห้ามรับ repeat cut; แสดง key `ai-repeat-read-only`. ห้ามเปลี่ยน server defaults กลับเป็น trueและห้ามใช้ transcript gaps โดยตรงไม่ว่าค่า flag ใด.

เพิ่ม optional effective cuts ใน mapper:

```dart
SubtitleProject mapAiEditRecipeToSubtitleProject({
  required AiEditRecipeResult recipe,
  required String projectId,
  required String sourceFingerprint,
  required DateTime now,
  List<AiEditCut>? effectiveCutRanges,
  int maxCharsPerCue = 18,
});

SubtitleProject replaceSubtitleProjectCutRanges({
  required SubtitleProject project,
  required List<SilenceCutRange> effectiveCutRanges,
  required DateTime now,
});

class _PreparedRecipeRenderResult {
  const _PreparedRecipeRenderResult({
    required this.video,
    required this.appliedSpeechOccurrenceIds,
    required this.appliedCutRanges,
  });

  final BurnedSubtitleResult video;
  final Set<String> appliedSpeechOccurrenceIds;
  final List<SilenceCutRange> appliedCutRanges;
}
```

- [ ] **Step 1: เพิ่ม widget/mapper failing tests**

เริ่มด้วย pure/default tests ของ `AiEditSafetyFlags` และ widget rollback tests: injected silence flag false แล้ว card/effective request/verifier/cuts ปิดทั้งหมด; injected automatic-repeat flag false แล้ว API ยังคืน detection groups ให้ดูได้ แต่ปุ่มเลือกตัดถูกปิด, key `ai-repeat-read-only` ปรากฏ และ initial/review/export ไม่มี repeat cut. Tests ต้องยืนยันซับ/target/color ไม่เปลี่ยนเมื่อปิด flag ใด flagหนึ่ง.

เพิ่ม test แรกตาม pattern `AiEditingScreen` ที่มีอยู่:

```dart
testWidgets('renders only locally verified silence intersections',
    (tester) async {
  final pickedVideo = _createPickedVideoFixture('silence.mp4');
  BurnSubtitleRequest? burnRequest;
  var verificationCalls = 0;

  await tester.pumpWidget(_testApp(AiEditingScreen(
    initialTargetDurationSeconds: null,
    pickVideo: () async => pickedVideo,
    loadSubscription: () async => _subscriptionFixture('PRO'),
    extractAudio: _extractAudioFixture,
    cleanupAiEditAudio: (_) async {},
    createUpload: (_) async => const UploadResult(
      id: 'silence-upload',
      videoS3Key: 'uploads/silence.mp4',
      storageProvider: 's3',
    ),
    uploadVideoFile: (_, __) async {},
    prepareEdit: (_) async => _createPrepareFixture(),
    verifySilence: ({
      required sourceFile,
      required sourceDurationSeconds,
      required transcriptCandidates,
      required protectedSpeechRanges,
    }) async {
      verificationCalls += 1;
      return const AiEditSilenceVerificationResult(
        cutRanges: [SilenceCutRange(start: 10.1, end: 10.9)],
        probeSucceeded: true,
      );
    },
    burnVideo: (request) async {
      burnRequest = request;
      return _createRenderedVideoFixture('silence-result.mp4');
    },
  )));

  await tester.tap(find.byKey(const ValueKey('ai-add-video')));
  await tester.pumpAndSettle();
  await _enableCapability(tester, 'silence');
  await tester.tap(find.byKey(const ValueKey('ai-process-button')));
  await tester.pumpAndSettle();

  expect(verificationCalls, 1);
  expect(
    burnRequest!.silenceRanges
        .map((range) => '${range.start}-${range.end}')
        .toList(),
    ['10.1-10.9'],
  );
});
```

เพิ่ม retry test เต็มโดยให้ verifier ล้มครั้งแรกและผ่านครั้งที่สอง:

```dart
testWidgets('retries only waveform verification without preparing again',
    (tester) async {
  final pickedVideo = _createPickedVideoFixture('silence-retry.mp4');
  var prepareCalls = 0;
  var verificationCalls = 0;
  final burnRequests = <BurnSubtitleRequest>[];

  await tester.pumpWidget(_testApp(AiEditingScreen(
    initialTargetDurationSeconds: null,
    pickVideo: () async => pickedVideo,
    loadSubscription: () async => _subscriptionFixture('PRO'),
    extractAudio: _extractAudioFixture,
    cleanupAiEditAudio: (_) async {},
    createUpload: (_) async => const UploadResult(
      id: 'silence-retry-upload',
      videoS3Key: 'uploads/silence-retry.mp4',
      storageProvider: 's3',
    ),
    uploadVideoFile: (_, __) async {},
    prepareEdit: (_) async {
      prepareCalls += 1;
      return _createPrepareFixture();
    },
    verifySilence: ({
      required sourceFile,
      required sourceDurationSeconds,
      required transcriptCandidates,
      required protectedSpeechRanges,
    }) async {
      verificationCalls += 1;
      return verificationCalls == 1
          ? const AiEditSilenceVerificationResult.failed()
          : const AiEditSilenceVerificationResult(
              cutRanges: [SilenceCutRange(start: 10.1, end: 10.9)],
              probeSucceeded: true,
            );
    },
    burnVideo: (request) async {
      burnRequests.add(request);
      return _createRenderedVideoFixture(
        'silence-retry-result-${burnRequests.length}.mp4',
      );
    },
  )));

  await tester.tap(find.byKey(const ValueKey('ai-add-video')));
  await tester.pumpAndSettle();
  await _enableCapability(tester, 'silence');
  await tester.tap(find.byKey(const ValueKey('ai-process-button')));
  await tester.pumpAndSettle();

  expect(prepareCalls, 1);
  expect(verificationCalls, 1);
  expect(find.byKey(const ValueKey('ai-silence-verification-retry')),
      findsOneWidget);

  await tester.tap(
    find.byKey(const ValueKey('ai-silence-verification-retry')),
  );
  await tester.pumpAndSettle();

  expect(prepareCalls, 1);
  expect(verificationCalls, 2);
  expect(
    burnRequests.last.silenceRanges
        .map((range) => '${range.start}-${range.end}')
        .toList(),
    contains('10.1-10.9'),
  );
});
```

เพิ่ม success/empty test แล้ว assert ข้อความ “ตรวจแล้ว · ไม่พบช่วงเงียบที่ปลอดภัย”. เพิ่ม counter tests: silence=false = 0 call; review rerender/subtitle edit/export = ยังคง 1 call; เลือก source ใหม่แล้วเปิด silence = 2 calls.

เพิ่ม mapper test:

```dart
final recipeWithRawCandidate = recipeFixture(
  durationSeconds: 20,
  cutRanges: const [AiEditCut(start: 4.8, end: 6.2)],
);
final project = mapAiEditRecipeToSubtitleProject(
  recipe: recipeWithRawCandidate,
  projectId: 'project-verified-cuts',
  sourceFingerprint: 'source-1',
  now: DateTime.utc(2026, 8, 1),
  effectiveCutRanges: const [],
);
final updated = replaceSubtitleProjectCutRanges(
  project: project,
  effectiveCutRanges: const [SilenceCutRange(start: 10.1, end: 10.9)],
  now: DateTime.utc(2026, 8, 1, 0, 1),
);
expect(project.cutRanges, isEmpty);
expect(updated.cutRanges.single.sourceStartMs, 10100);
expect(updated.cutRanges.single.sourceEndMs, 10900);
expect(updated.recipeFingerprint, isNot(project.recipeFingerprint));
```

- [ ] **Step 2: รัน RED**

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_editing_screen_test.dart --plain-name "renders only locally verified silence intersections"
  $screenRedExitCode = $LASTEXITCODE
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\subtitle_project_mapper_test.dart
  $mapperRedExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($screenRedExitCode -eq 0 -or $mapperRedExitCode -eq 0) {
  throw "Expected silence integration and project mapper tests to fail before implementation"
}
```

- [ ] **Step 3: เก็บผล verify แบบมีสถานะและ cache**

เพิ่ม state:

```dart
AiEditSilenceVerificationResult _acceptedSilenceVerification =
    const AiEditSilenceVerificationResult(
  cutRanges: [],
  probeSucceeded: true,
);
List<SilenceCutRange> get _verifiedSilenceRanges =>
    _acceptedSilenceVerification.cutRanges;
bool get _silenceVerificationUnavailable =>
    !_acceptedSilenceVerification.probeSucceeded;
bool _silenceRetryInProgress = false;
final Map<String, AiEditSilenceVerificationResult>
    _silenceVerificationBySignature = {};
```

signature ต้องรวม source path + last-modified + duration + transcript candidates + protected ranges. Cache เฉพาะ `probeSucceeded == true` รวม success/empty; ห้าม cache failed เพื่อให้กดลองใหม่ได้.

```dart
String _buildSilenceVerificationSignature({
  required File sourceFile,
  required double durationSeconds,
  required List<SilenceCutRange> candidates,
  required List<SilenceCutRange> protectedSpeechRanges,
}) => jsonEncode({
  'path': sourceFile.absolute.path,
  'modified': sourceFile.lastModifiedSync().toUtc().toIso8601String(),
  'durationSeconds': durationSeconds,
  'candidates': [
    for (final range in candidates) [range.start, range.end],
  ],
  'protectedSpeechRanges': [
    for (final range in protectedSpeechRanges) [range.start, range.end],
  ],
});
```

เรียก verifier หลังได้ recipe และก่อน initial render เฉพาะเมื่อ effective silence=true และ candidate ไม่ว่าง ใช้ `mapAiEditTimelineEvidence(recipe.transcript).protectedSpeechRanges` เป็น protected evidence.

เมื่อเลือก source ใหม่ ให้เปลี่ยนเฉพาะ `_selectedVideo`, `_selectedVideoDurationSeconds` และ working setup. ห้าม reset `_activeSourceVideo`, `_activeSourceDurationSeconds`, `_acceptedSilenceVerification`, accepted recipe/project/capabilities/result หรือ `_acceptedSetup`. Cache silence มี source fingerprint อยู่แล้วจึงเก็บข้าม source ได้; หากต้องล้าง working cache ให้ล้างเฉพาะค่าของ pending attempt และห้ามกระทบ accepted result. ปุ่ม `ai-remove-video` เมื่อมี accepted resultให้ล้างเฉพาะ pending selection; หาก render ของ source ใหม่ล้ม ให้กลับหน้า review ของ accepted source เดิม. การทิ้ง accepted resultทั้งหมดทำได้เฉพาะ explicit discard/ออกจาก flow เท่านั้น.

เพิ่ม helper และ retry action ที่ใช้ source/recipe เดิม:

```dart
Future<AiEditSilenceVerificationResult> _verifySilenceForRecipe({
  required AiEditRecipeResult recipe,
  required File sourceFile,
  bool force = false,
}) async {
  final evidence = mapAiEditTimelineEvidence(recipe.transcript);
  final candidates = [
    for (final range in recipe.silenceRanges)
      SilenceCutRange(start: range.start, end: range.end),
  ];
  if (candidates.isEmpty) {
    return const AiEditSilenceVerificationResult(
      cutRanges: [],
      probeSucceeded: true,
    );
  }
  final signature = _buildSilenceVerificationSignature(
    sourceFile: sourceFile,
    durationSeconds: recipe.transcript.durationSeconds,
    candidates: candidates,
    protectedSpeechRanges: evidence.protectedSpeechRanges,
  );
  if (!force && _silenceVerificationBySignature[signature] case final cached?) {
    return cached;
  }
  final verifier = widget.verifySilence ?? AiEditSilenceVerifier().call;
  final result = await verifier(
    sourceFile: sourceFile,
    sourceDurationSeconds: recipe.transcript.durationSeconds,
    transcriptCandidates: candidates,
    protectedSpeechRanges: evidence.protectedSpeechRanges,
  );
  if (result.probeSucceeded) {
    _silenceVerificationBySignature[signature] = result;
  }
  return result;
}
```

ใน initial processing ใช้ local result เดียวกันทั้ง review และ render แล้ว commit หลัง render สำเร็จ:

```dart
final silenceVerification = effectiveCapabilities['silence'] == true
    ? await _verifySilenceForRecipe(recipe: recipe, sourceFile: file)
    : const AiEditSilenceVerificationResult(
        cutRanges: [],
        probeSucceeded: true,
      );
final reviewCapabilities = _buildReviewCapabilities(
  recipe,
  silenceVerification: silenceVerification,
);
// mappedProject is the local project created in Step 5 for this exact source.
// It is not committed to _subtitleProject until this render succeeds.
final rendered = await _renderPreparedRecipe(
  recipe: recipe,
  sourceVideo: picked,
  capabilities: reviewCapabilities,
  verifiedSilenceRanges: silenceVerification.cutRanges,
  removedSpeechOccurrenceIds: initialSpeechOccurrenceIds,
  renderProject: mappedProject,
);
if (mounted) {
  setState(() => _acceptedSilenceVerification = silenceVerification);
}
```

เพิ่ม retry action นี้ (helper `_replaceProjectCutsAfterRender` เรียก `replaceSubtitleProjectCutRanges` เมื่อ project ไม่เป็น null):

```dart
Future<void> _retrySilenceVerification() async {
  if (_silenceRetryInProgress) return;
  final recipe = _preparedEdit?.recipe;
  final picked = _activeSourceVideo;
  if (recipe == null || picked == null) return;

  setState(() => _silenceRetryInProgress = true);
  try {
    final verification = await _verifySilenceForRecipe(
      recipe: recipe,
      sourceFile: File(picked.path),
      force: true,
    );
    if (!verification.probeSucceeded) {
      if (mounted) {
        setState(() => _acceptedSilenceVerification = verification);
      }
      return;
    }

    final retryCapabilities = Map<String, bool>.from(_reviewCapabilities);
    if (verification.cutRanges.isNotEmpty) {
      retryCapabilities['silence'] = true;
    } else {
      retryCapabilities.remove('silence');
    }
    final rendered = await _renderPreparedRecipe(
      recipe: recipe,
      sourceVideo: picked,
      capabilities: retryCapabilities,
      verifiedSilenceRanges: verification.cutRanges,
      removedSpeechOccurrenceIds: _reviewRemovedSpeechOccurrenceIds,
      renderProject: _subtitleProject,
    );
    if (!mounted) return;
    setState(() {
      _acceptedSilenceVerification = verification;
      _reviewCapabilities
        ..clear()
        ..addAll(retryCapabilities);
      _appliedReviewCapabilities
        ..clear()
        ..addAll(retryCapabilities);
      _renderedResult = rendered.video;
      _subtitleProject = _replaceProjectCutsAfterRender(
        _subtitleProject,
        rendered.appliedCutRanges,
      );
      _prepareReviewForResult(rendered.video, sourceVideo: picked);
    });
  } on SubtitleBurnException catch (error) {
    if (mounted) _showError('${error.message} · ผลลัพธ์เดิมยังอยู่');
  } finally {
    if (mounted) setState(() => _silenceRetryInProgress = false);
  }
}

SubtitleProject? _replaceProjectCutsAfterRender(
  SubtitleProject? project,
  List<SilenceCutRange> appliedCutRanges,
) => project == null
    ? null
    : replaceSubtitleProjectCutRanges(
        project: project,
        effectiveCutRanges: appliedCutRanges,
        now: DateTime.now().toUtc(),
      );
```

ห้ามเรียก `extractAudio`, upload หรือ `prepareEdit`. เมื่อ probe ยังล้มให้คงไฟล์เดิมและ warning. ถ้า probe สำเร็จแต่ไม่พบช่วงที่ตัดได้ ให้ปิด silence capability และแสดง “ตรวจแล้ว · ไม่พบ” แทนการอ้างว่าใช้การตัดช่วงเงียบแล้ว. ปุ่ม retry ใช้ `const ValueKey('ai-silence-verification-retry')` และปิดชั่วคราวระหว่าง probe/render.

- [ ] **Step 4: ส่ง verified ranges ผ่าน render ทั้ง 4 จุด**

แก้ `_renderPreparedRecipe()`:

```dart
Future<_PreparedRecipeRenderResult> _renderPreparedRecipe({
  required AiEditRecipeResult recipe,
  required PickedVideoFile sourceVideo,
  required Map<String, bool> capabilities,
  required List<SilenceCutRange> verifiedSilenceRanges,
  required SubtitleProject? renderProject,
  Set<String>? removedSpeechOccurrenceIds,
  VideoRenderPurpose purpose = VideoRenderPurpose.preview,
}) async {
  final picked = sourceVideo;
  final originalFile = File(picked.path);
  final effectiveRemovedSpeechOccurrenceIds =
      widget.safetyFlags.automaticRepeatCutsEnabled
          ? (removedSpeechOccurrenceIds ?? const <String>{})
          : const <String>{};
  // Keep requestedSpeechCleanupRanges as input to the existing subtitle/audio
  // sanitizer. Only ranges returned by the sanitizer may become real cuts.
  final cleanupCutRanges = <SilenceCutRange>[
    if (capabilities['silence'] == true) ...verifiedSilenceRanges,
    ...sanitizedSpeechCleanup.appliedCleanupRanges,
  ];
  final cutRanges = sourceDuration > 0
      ? mergeProtectedCutRanges(
          planCuts: planCutRanges,
          cleanupCuts: cleanupCutRanges,
          durationSeconds: sourceDuration,
        )
      : <SilenceCutRange>[...planCutRanges, ...cleanupCutRanges];
}
```

`sourceVideo` และ `renderProject` ต้องเป็น required (`renderProject` ยังคง nullable): renderer ใช้ source ที่รับเป็น argumentเท่านั้นและห้ามอ่าน `_selectedVideo`; `null` project หมายถึงรอบนี้ไม่มีโปรเจกต์ซับจริง ๆ และห้าม fallback ไปอ่าน `_subtitleProject` จาก state. ภายใน renderer ให้ใช้เฉพาะ `renderProject` สำหรับ cue/style, subtitle/audio sanitizer และการสร้าง subtitle segments; cache signature ต้องรวม source fingerprint กับ `renderProject?.recipeFingerprint` เพื่อห้ามวิดีโอหรือโปรเจกต์คนละชุดใช้ cache ร่วมกัน. จุดเรียก initial setup ส่ง pending `picked` + local `mappedProject`; retry/review/export ส่ง `_activeSourceVideo` + accepted `_subtitleProject`; subtitle-edit rerender ส่ง active source + โปรเจกต์ฉบับแก้ที่เป็น local ของรอบนั้นโดยตรง. ตรวจทุก call site ให้ส่ง argumentทั้งสองเสมอ.

ใช้ `effectiveRemovedSpeechOccurrenceIds` แทน parameter ดิบใน sanitizer, cache signature และ renderer request ทุกจุด. นี่เป็น safety gate ชั้นสุดท้ายสำหรับ initial render, review toggle, subtitle rerender และ export; ต่อให้ state เก่ามี selected IDs อยู่ flag false ก็ต้องส่งชุดว่างลง renderer.

ห้ามรวม `requestedSpeechCleanupRanges` ดิบเข้ากับ final cuts. initial render, review toggle, subtitle edit และ full export ต้องส่ง verified silence listเดียวกัน. เพิ่ม `appliedCutRanges: List<SilenceCutRange>.unmodifiable(cutRanges)` ใน `_PreparedRecipeRenderResult` ครบทั้ง 3 return paths: ทางคืนไฟล์ต้นฉบับเมื่อ `!needsLocalRender`, ทาง cache hit และทาง render สำเร็จ. Commit active source + state ใหม่หลัง setup render สำเร็จเท่านั้น เพื่อไม่ทำลายผลเก่าหาก render ใหม่ล้ม. ปรับ `_prepareReviewForResult`, original/AI source matching และ review duration cache ให้รับ/ใช้ accepted source path อย่างชัดเจน ไม่อ่าน pending `_selectedVideo`.

เปลี่ยน helper เป็น `_prepareReviewForResult(result, {required PickedVideoFile sourceVideo})` และใช้ `sourceVideo.path` เป็น original path. ทุก call หลัง initial/review/subtitle/retry ต้องส่ง source เดียวกับที่ส่งเข้า renderer; `_isCurrentReviewSource(ReviewVideoSource.original, ...)` เปรียบเทียบกับ `_activeSourceVideo?.path`. ห้าม helper เหล่านี้ fallback ไป `_selectedVideo` เพราะค่านั้นอาจเป็นคลิปถัดไปที่ยัง render ไม่สำเร็จ.

เปลี่ยน `_buildReviewCapabilities` ให้รับผล verify โดยตรง เพราะ Task 2 เปลี่ยน server status เป็น `hinted` และห้าม gate ด้วย `silence.isApplied` อีก:

```dart
Map<String, bool> _buildReviewCapabilities(
  AiEditRecipeResult recipe, {
  required AiEditSilenceVerificationResult silenceVerification,
}) {
  final filler = recipe.capabilities['filler'];
  final hasStructuredSpeechReduction = recipe.speechReduction.isReady &&
      buildSpeechReductionReviewGroups(recipe.speechReduction).isNotEmpty;
  final canUseLegacySpeechReduction =
      _speechReductionSelectionMode == _SpeechReductionSelectionMode.ai &&
          (filler?.isApplied ?? false) &&
          recipe.fillerRanges.isNotEmpty;
  return {
    if ((_capabilities['subtitle'] ?? false) &&
        (recipe.capabilities['subtitle']?.isApplied ?? false) &&
        recipe.subtitles.segments.isNotEmpty)
      'subtitle': true,
    if ((_capabilities['silence'] ?? false) &&
        silenceVerification.probeSucceeded &&
        silenceVerification.cutRanges.isNotEmpty)
      'silence': true,
    if (widget.safetyFlags.automaticRepeatCutsEnabled &&
        (_capabilities['filler'] ?? false) &&
        (hasStructuredSpeechReduction || canUseLegacySpeechReduction))
      'filler': true,
    if (_capabilities['color'] ?? false) 'color': true,
  };
}
```

จุดสำคัญคือ silence เข้า capability map เฉพาะเมื่อ probe สำเร็จและมี verified cut จริง. success/empty ไม่เปิด capability แต่ status แยกยังแสดง “ตรวจแล้ว · ไม่พบ”; failure ไม่สร้าง cutและแสดง warning/retry. `_buildAnalysisSummary` ต้องนับเวลาเฉพาะ verified list ไม่อ่าน raw `recipe.silenceRanges` เป็นผลตัดจริง. เพิ่ม widget tests ทั้ง initial success/empty และ retry success/empty ให้ assert ว่า map ไม่มี `silence`, ไม่มี cut ถูกส่งเข้า renderer และ status “ตรวจแล้ว · ไม่พบ” ยังมองเห็น.

- [ ] **Step 5: ป้องกัน candidate รั่วเข้า Subtitle Studio โดยไม่มีวงจรกับ repeat sanitizer**

สร้าง subtitle project เริ่มต้นด้วย cue/style เท่านั้นก่อน render เมื่อเปิดซับ เพื่อให้ repeat sanitizer รักษาข้อความกับเสียงตรงกัน แต่ไม่รับ raw cuts. เก็บเป็น local variable, ส่งเข้า `_renderPreparedRecipe(renderProject: mappedProject)` โดยตรง และห้ามเขียน `_subtitleProject` จนกว่า render จะสำเร็จ:

```dart
SubtitleProject? mappedProject;
if (reviewCapabilities['subtitle'] == true) {
  final identity = buildSubtitleProjectIdentity(
    sourceFile: file,
    setupSignature: prepareSignature,
  );
  final baseProject = mapAiEditRecipeToSubtitleProject(
    recipe: recipe,
    projectId: identity.projectId,
    sourceFingerprint: identity.sourceFingerprint,
    now: DateTime.now().toUtc(),
    effectiveCutRanges: const [],
    maxCharsPerCue:
        _buildEditOptions(reviewCapabilities).subtitleMaxChars ?? 18,
  );
  mappedProject = baseProject.copyWith(
    defaultStyle: _subtitleStyleForSetup(
      baseProject.defaultStyle,
      reviewCapabilities,
    ),
  );
}
```

หลัง `_renderPreparedRecipe()` sanitize repeat และคืน final `appliedCutRanges` แล้วจึงอัปเดต project:

```dart
SubtitleProject replaceSubtitleProjectCutRanges({
  required SubtitleProject project,
  required List<SilenceCutRange> effectiveCutRanges,
  required DateTime now,
}) {
  final mapped = effectiveCutRanges
      .map((range) => SubtitleCutRange(
            sourceStartMs: _secondsToMilliseconds(range.start, 'Cut range'),
            sourceEndMs: _secondsToMilliseconds(range.end, 'Cut range'),
          ))
      .toList()
    ..sort((left, right) =>
        left.sourceStartMs != right.sourceStartMs
            ? left.sourceStartMs.compareTo(right.sourceStartMs)
            : left.sourceEndMs.compareTo(right.sourceEndMs));
  final cutRanges = _mergeCutRanges(mapped);
  final updated = project.copyWith(
    recipeFingerprint: _buildRecipeFingerprint(
      sourceDurationMs: project.sourceDurationMs,
      language: project.language,
      cues: project.cues,
      defaultStyle: project.defaultStyle,
      cutRanges: cutRanges,
    ),
    cutRanges: cutRanges,
    revision: project.revision + 1,
    updatedAt: now.toUtc(),
  );
  validateSubtitleProject(updated);
  return updated;
}

final projectWithAppliedCuts = mappedProject == null
    ? null
    : replaceSubtitleProjectCutRanges(
        project: mappedProject,
        effectiveCutRanges: rendered.appliedCutRanges,
        now: DateTime.now().toUtc(),
      );
```

ทำแบบเดียวกันหลัง review rerender/subtitle edit/retry เพื่อให้ Subtitle Studio เห็น planner + verified silence + repeat cuts ที่ผ่าน sanitizer จริง. Helper ต้อง sort/merge/validate ranges, เพิ่ม revision/updatedAt และคำนวณ `recipeFingerprint` ใหม่. ใน mapper ใช้ `effectiveCutRanges ?? recipe.cutRanges` เพื่อรักษา compatibility ของ caller เก่า แต่ AI Editor caller ใหม่ต้องส่ง `const []` ก่อน renderเสมอและ replace หลัง render; ห้ามส่ง raw `recipe.cutRanges`. สำหรับ subtitle edit ให้สร้าง local edited project แล้วส่งเป็น `renderProject` ในรอบเดียวกัน ก่อนค่อย commit โปรเจกต์ที่อัปเดต cut หลัง render สำเร็จ.

เพิ่ม regression widget test ที่มีผลคลิป A และ `_subtitleProject` A อยู่แล้ว จากนั้นเลือกคลิป B ซึ่งมี cue/project คนละชุด: renderer ต้องได้รับ source B + `mappedProject` B และต้องไม่เห็น path/cue ของ A. จากนั้นให้ renderer throw แล้ว assert ว่า active source/duration, accepted recipe/project/preview/verification เดิมยังเป็น A และ export ส่ง source A ให้ renderer. เพิ่มอีก test ให้ cache signatureต่างกันเมื่อ source fingerprint หรือ `recipeFingerprint` ของ `renderProject` ต่างกัน แม้ recipe/capabilities/cuts เท่ากัน.

- [ ] **Step 6: ปรับ existing silence tests ให้ inject verifier**

ประกาศ helper ใน test file แล้วส่งเข้า `AiEditingScreen` ทุก case ที่เปิด silence:

```dart
Future<AiEditSilenceVerificationResult> _verifyAllSilenceCandidates({
  required File sourceFile,
  required double sourceDurationSeconds,
  required List<SilenceCutRange> transcriptCandidates,
  required List<SilenceCutRange> protectedSpeechRanges,
}) async => AiEditSilenceVerificationResult(
  cutRanges: List<SilenceCutRange>.unmodifiable(transcriptCandidates),
  probeSucceeded: true,
);
```

ใช้ helper นี้เฉพาะ tests ที่ไม่ได้กำลังทดสอบ intersection/padding โดยตรง; tests ใหม่ใช้ range 10.1–10.9 ที่กำหนดชัดเจน. ห้ามให้ unit/widget tests เรียก native FFmpeg.

- [ ] **Step 7: รัน mobile suite ที่เกี่ยวข้องและ commit**

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_safety_flags_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Safety flag tests failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_silence_verifier_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Silence verifier tests failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_editing_screen_test.dart
  if ($LASTEXITCODE -ne 0) { throw "AI editing screen tests failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\subtitle_project_mapper_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Subtitle project mapper tests failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\subtitle_timeline_alignment_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Subtitle timeline alignment tests failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git add apps/mobile/lib/features/ai_editing/ai_edit_safety_flags.dart apps/mobile/lib/features/ai_editing/ai_editing_screen.dart apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project_mapper.dart apps/mobile/test/ai_edit_safety_flags_test.dart apps/mobile/test/ai_editing_screen_test.dart apps/mobile/test/subtitle_project_mapper_test.dart
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "fix: render only verified silence cuts"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

---

## Task 8: ทำ color-only + original duration เป็น local, unmetered render

**Files:**

- Modify: `apps/mobile/lib/features/ai_editing/ai_edit_media_strategy.dart`
- Create: `apps/mobile/lib/features/ai_editing/ai_edit_local_recipe.dart`
- Modify: `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`
- Modify: `apps/mobile/lib/features/ai_editing/subtitle_burn_video_processor.dart`
- Modify: `apps/mobile/test/ai_edit_media_strategy_test.dart`
- Create: `apps/mobile/test/ai_edit_local_recipe_test.dart`
- Modify: `apps/mobile/test/ai_editing_screen_test.dart`
- Modify: `apps/mobile/test/subtitle_burn_test.dart`

**Interfaces:**

```dart
enum AiEditAnalysisMode { audioOnly, localRenderOnly }

AiEditAnalysisMode selectAiEditAnalysisMode(
  Map<String, bool> capabilities, {
  required bool usesOriginalDuration,
});

AiEditRecipeResult buildLocalColorAiEditRecipe({
  required double durationSeconds,
});

String editedVideoOutputFileName(
  String fileName, {
  required bool hasSubtitles,
});
```

- [ ] **Step 1: เขียน strategy/local recipe/output-name tests**

```dart
test('routes color-only original duration to local render', () {
  expect(
    selectAiEditAnalysisMode(
      {'color': true},
      usesOriginalDuration: true,
    ),
    AiEditAnalysisMode.localRenderOnly,
  );
});

test('keeps color plus shortening on the audio planning route', () {
  expect(
    selectAiEditAnalysisMode(
      {'color': true},
      usesOriginalDuration: false,
    ),
    AiEditAnalysisMode.audioOnly,
  );
});

test('uses a neutral output suffix without visible subtitles', () {
  expect(
    editedVideoOutputFileName('seller.demo.mov', hasSubtitles: false),
    'seller.demo_edited.mp4',
  );
  expect(
    editedVideoOutputFileName('clip.mp4', hasSubtitles: true),
    'clip_subtitled.mp4',
  );
});

test('builds a cut-free local color recipe at the real source duration', () {
  final recipe = buildLocalColorAiEditRecipe(durationSeconds: 150.64);
  expect(recipe.renderMode, 'local-render-only');
  expect(recipe.transcript.durationSeconds, 150.64);
  expect(recipe.transcript.model, 'local-color-preset');
  expect(recipe.subtitles.enabled, isFalse);
  expect(recipe.cutRanges, isEmpty);
  expect(recipe.silenceRanges, isEmpty);
  expect(recipe.fillerRanges, isEmpty);
  expect(recipe.capabilities['color']?.isApplied, isTrue);
});

test('fails closed for an enabled unknown capability', () {
  expect(
    () => selectAiEditAnalysisMode(
      {'future_visual_ai': true},
      usesOriginalDuration: true,
    ),
    throwsA(isA<UnsupportedAiEditAnalysisException>()),
  );
});
```

เพิ่ม table test สำหรับ color+subtitle, color+silence และ color+filler โดย assert `AiEditAnalysisMode.audioOnly` ทุกแถว.

- [ ] **Step 2: เพิ่ม widget tests สำหรับ side-effect counts**

แก้ existing color test ให้จับ side effects ครบ:

```dart
testWidgets('color-only original duration checks Pro then renders locally',
    (tester) async {
  final pickedVideo = _createPickedVideoFixture('color-local.mp4');
  var extractCalls = 0;
  var createUploadCalls = 0;
  var uploadCalls = 0;
  var prepareCalls = 0;
  var renderCalls = 0;
  BurnSubtitleRequest? burnRequest;

  await tester.pumpWidget(_testApp(AiEditingScreen(
    initialTargetDurationSeconds: null,
    pickVideo: () async => pickedVideo,
    loadSubscription: () async => _subscriptionFixture('PRO'),
    loadAiEditQuota: () async => const AiEditQuota(
      limitMinutes: 200,
      usedMinutes: 14,
      remainingMinutes: 186,
    ),
    extractAudio: (source) async {
      extractCalls += 1;
      return _extractAudioFixture(source);
    },
    createUpload: (_) async {
      createUploadCalls += 1;
      return const UploadResult(
        id: 'must-not-upload',
        videoS3Key: 'uploads/must-not-upload.mp4',
        storageProvider: 's3',
      );
    },
    uploadVideoFile: (_, __) async => uploadCalls += 1,
    prepareEdit: (_) async {
      prepareCalls += 1;
      return _createPrepareFixture();
    },
    burnVideo: (request) async {
      renderCalls += 1;
      burnRequest = request;
      return _createRenderedVideoFixture('color-local-result.mp4');
    },
  )));

  await tester.tap(find.byKey(const ValueKey('ai-add-video')));
  await tester.pumpAndSettle();
  await _enableCapability(tester, 'color');
  await tester.tap(find.byKey(const ValueKey('ai-process-button')));
  await tester.pumpAndSettle();

  expect([extractCalls, createUploadCalls, uploadCalls, prepareCalls],
      [0, 0, 0, 0]);
  expect(renderCalls, 1);
  expect(burnRequest!.segments, isEmpty);
  expect(burnRequest!.filterIndex, greaterThan(0));
  expect(find.textContaining('เหลือ 186 นาที'), findsWidgets);
});
```

เพิ่ม test `color-only fails safely when source duration is unavailable`: ให้ทั้ง `_selectedVideoDurationSeconds` และ `picked.durationSeconds` เป็น null, assert แสดงข้อความอ่านความยาวไม่สำเร็จ และ `extractAudio`/upload/prepare/burn/quota mutation เป็น 0. Test นี้บังคับให้ unwrap `double?` ก่อนส่งเข้า local recipe และกัน Dart compile/runtime regression.

ทำอีกสี่ tests ด้วย setup เดียวกัน: Basic แสดง Pro sheet และ counters ทุกตัว 0; color + target 30s ทำ extract/create/upload/prepare อย่างละ 1 และ `request.targetDurationSeconds == 30`; ใช้ `Completer<BurnedSubtitleResult>` ค้าง renderer เพื่อ assert ข้อความ local และไม่พบข้อความเตรียมเสียง; renderer รอบแรก throw แล้วกด retry สำเร็จโดย prepare/upload ยัง 0 และ quota ยัง 186. การเรียก `loadAiEditQuota` ใน `initState` เป็น GET เพื่อแสดงยอดและอนุญาตให้เกิดหนึ่งครั้ง.

- [ ] **Step 3: รัน RED**

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_media_strategy_test.dart
  $strategyRedExitCode = $LASTEXITCODE
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_local_recipe_test.dart
  $recipeRedExitCode = $LASTEXITCODE
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\subtitle_burn_test.dart
  $burnRedExitCode = $LASTEXITCODE
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_editing_screen_test.dart --plain-name "color-only original duration checks Pro then renders locally"
  $screenRedExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
$failedRedChecks = @(
  @($strategyRedExitCode, $recipeRedExitCode, $burnRedExitCode, $screenRedExitCode) |
    Where-Object { $_ -ne 0 }
)
if ($failedRedChecks.Count -eq 0) {
  throw "Expected at least one color-only test to fail before implementation"
}
```

- [ ] **Step 4: Implement selector และ local recipe**

Selector ต้องอ่าน effective capabilities:

```dart
AiEditAnalysisMode selectAiEditAnalysisMode(
  Map<String, bool> capabilities, {
  required bool usesOriginalDuration,
}) {
  const audioCapabilities = {'subtitle', 'silence', 'filler', 'color'};
  final enabled = capabilities.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toSet();
  final unsupported = enabled.difference(audioCapabilities);
  if (unsupported.isNotEmpty) {
    throw UnsupportedAiEditAnalysisException(unsupported.first);
  }
  if (usesOriginalDuration && enabled.length == 1 && enabled.single == 'color') {
    return AiEditAnalysisMode.localRenderOnly;
  }
  return AiEditAnalysisMode.audioOnly;
}
```

สร้าง local recipe เต็มในไฟล์ใหม่:

```dart
AiEditRecipeResult buildLocalColorAiEditRecipe({
  required double durationSeconds,
}) {
  if (!durationSeconds.isFinite || durationSeconds <= 0) {
    throw ArgumentError.value(
      durationSeconds,
      'durationSeconds',
      'must be finite and greater than zero',
    );
  }
  const skipped = AiEditCapabilityStatusResult(
    enabled: false,
    state: 'skipped',
    message: 'ไม่ได้เลือกใน UI',
  );
  return AiEditRecipeResult(
    version: 1,
    status: 'ready',
    renderMode: 'local-render-only',
    transcript: AiEditTranscriptResult(
      text: '',
      language: 'th',
      durationSeconds: durationSeconds,
      segments: const [],
      words: const [],
      model: 'local-color-preset',
    ),
    subtitles: const AiEditSubtitlesResult(
      enabled: false,
      segments: [],
      style: AiEditSubtitleStyleResult(
        mode: 'bold',
        color: '#FFFFFF',
        wordsPerLine: 2,
        position: 'bottom',
      ),
    ),
    cutRanges: const [],
    silenceRanges: const [],
    fillerRanges: const [],
    plan: const AiEditPlanResult(
      cuts: [],
      summary: 'ปรับสีบนอุปกรณ์',
      model: 'local-color-preset',
    ),
    capabilities: const {
      'subtitle': skipped,
      'silence': skipped,
      'filler': skipped,
      'color': AiEditCapabilityStatusResult(
        enabled: true,
        state: 'applied',
        message: 'ปรับสีบนอุปกรณ์',
      ),
    },
  );
}
```

ห้ามใส่ local recipe ลง `_preparedEditsByAnalysisSignature` เพราะเมื่อผู้ใช้เปิด AI capability เพิ่มภายหลังต้องเรียก prepare ใหม่.

- [ ] **Step 5: แยก local branch ใน `_processVideo()` หลัง Pro check**

โครงสร้าง:

```dart
final prepareSignature = _buildPrepareSignature(picked, file);
final effectiveCapabilities = Map<String, bool>.from(_effectiveCapabilities);
final analysisMode = selectAiEditAnalysisMode(
  effectiveCapabilities,
  usesOriginalDuration: _isUsingOriginalDuration,
);
AiEditPrepareResult? prepared;
AiEditRecipeResult? localRecipe;
if (analysisMode == AiEditAnalysisMode.localRenderOnly) {
  final localDuration = _selectedVideoDurationSeconds ?? picked.durationSeconds;
  if (localDuration == null ||
      !localDuration.isFinite ||
      localDuration <= 0) {
    throw const SubtitleBurnException(
      'อ่านความยาววิดีโอต้นฉบับไม่สำเร็จ',
    );
  }
  setState(() => _processingTitle = 'กำลังปรับสีและแสงบนเครื่อง...');
  localRecipe = buildLocalColorAiEditRecipe(
    durationSeconds: localDuration,
  );
}
```

ประกาศ `prepareSignature` ก่อนแยก local/network branch เพราะการสร้าง Subtitle Project ด้านล่างยังใช้ค่านี้. ย้าย declaration `var prepared` เดิมออกมาก่อน branch ตาม snippet แล้วครอบ block ปัจจุบันตั้งแต่ `var prepared = _preparedEditsBySignature[prepareSignature]` ถึงก่อน `if (!mounted) return;` ด้วย `if (localRecipe == null) { ... }` โดยไม่เปลี่ยน cache/extract/upload/visual-proxy logic ภายใน. หลัง block ใช้ shared assignment นี้:

ลบ call เดิม `selectAiEditAnalysisMode(_buildPrepareRequest('__capability_check__.m4a').capabilities)` ภายใน audio block เพราะ selector ถูกเรียกครั้งเดียวก่อน branch แล้ว; การปล่อย call เดิมไว้จะทั้งซ้ำและไม่ตรง signature ใหม่.

```dart
if (!mounted) return;
final preparedResult = prepared;
final activeRecipe = localRecipe ?? preparedResult!.recipe;
final recommendedSpeechOccurrenceIds = {
  for (final cut in activeRecipe.speechReduction.defaultCutRanges)
    cut.occurrenceId,
};
final initialSpeechOccurrenceIds =
    widget.safetyFlags.automaticRepeatCutsEnabled &&
            _speechReductionSelectionMode == _SpeechReductionSelectionMode.ai
        ? recommendedSpeechOccurrenceIds
        : <String>{};
setState(() {
  _processingTitle = 'กำลังสร้างวิดีโอตัวอย่าง...';
  _renderProgress = null;
});

final silenceVerification = effectiveCapabilities['silence'] == true
    ? await _verifySilenceForRecipe(recipe: activeRecipe, sourceFile: file)
    : const AiEditSilenceVerificationResult(
        cutRanges: [],
        probeSucceeded: true,
      );
final reviewCapabilities = _buildReviewCapabilities(
  activeRecipe,
  silenceVerification: silenceVerification,
);
final rendered = await _renderPreparedRecipe(
  recipe: activeRecipe,
  sourceVideo: picked,
  capabilities: reviewCapabilities,
  verifiedSilenceRanges: silenceVerification.cutRanges,
  removedSpeechOccurrenceIds: initialSpeechOccurrenceIds,
  renderProject: mappedProject,
);
if (!mounted) return;

final result = rendered.video;
final selectedSpeechOccurrenceIds =
    widget.safetyFlags.automaticRepeatCutsEnabled &&
            reviewCapabilities['filler'] == true
        ? rendered.appliedSpeechOccurrenceIds
        : <String>{};
if (result.colorFilterSkipped) reviewCapabilities.remove('color');

// mappedProject ต้องเป็น local variable ตาม Task 7 และยังห้ามเขียนลง state
// ก่อน render สำเร็จ
final projectWithAppliedCuts = mappedProject == null
    ? null
    : replaceSubtitleProjectCutRanges(
        project: mappedProject,
        effectiveCutRanges: rendered.appliedCutRanges,
        now: DateTime.now().toUtc(),
      );
final acceptedSetup = _captureSetupSnapshot();
setState(() {
  if (preparedResult != null) {
    _aiEditQuota = preparedResult.quota;
    _isLoadingAiEditQuota = false;
    _aiEditQuotaLoadFailed = false;
  }
  _activeSourceVideo = picked;
  _activeSourceDurationSeconds =
      picked.durationSeconds ?? activeRecipe.transcript.durationSeconds;
  _activeRecipe = activeRecipe;
  _preparedEdit = preparedResult;
  _acceptedSilenceVerification = silenceVerification;
  _subtitleProject = projectWithAppliedCuts;
  _renderedResult = result;
  _prepareReviewForResult(result, sourceVideo: picked);
  _acceptedSetup = acceptedSetup;
  _reviewCapabilities
    ..clear()
    ..addAll(reviewCapabilities);
  _appliedReviewCapabilities
    ..clear()
    ..addAll(reviewCapabilities);
  _reviewRemovedSpeechOccurrenceIds
    ..clear()
    ..addAll(selectedSpeechOccurrenceIds);
  _appliedRemovedSpeechOccurrenceIds
    ..clear()
    ..addAll(selectedSpeechOccurrenceIds);
  _stage = _AiEditingStage.review;
  _processing = false;
  _renderProgress = null;
  _renderCancelRequested = false;
});
```

`mappedProject` ใน snippet หมายถึง local `SubtitleProject?` ที่สร้างตาม Task 7; ห้าม `setState(_subtitleProject = ...)` ก่อน render. Local route ทำให้ `preparedResult == null` จึงไม่เขียนทับ quota. เพิ่ม state `AiEditRecipeResult? _activeRecipe` แยกจาก `_preparedEdit`; API caches และ `_preparedEdit` ยังคงเป็น `AiEditPrepareResult`, ส่วน local route ตั้ง `_preparedEdit = null` และไม่สร้าง quota response ปลอม.

กฎ atomic commit: ก่อน render อนุญาตให้เปลี่ยนเฉพาะ pending `_selectedVideo`/setup และข้อความ/เปอร์เซ็นต์กำลังประมวลผล. `_activeSourceVideo`, `_activeSourceDurationSeconds`, `_activeRecipe`, `_preparedEdit`, `_subtitleProject`, accepted verification, review/applied capabilities, selected repeats และ `_renderedResult` ต้อง commit ใน success `setState` เดียวกัน. ถ้า render ล้มและมีผลเก่าอยู่ ทุก state สำหรับ review/edit/export รวมทั้ง source ต้องยังชี้ชุดเก่า และ failure handler กลับ review ของผลเก่าแทนการแสดง recipe เก่ากับ pending source ใหม่. โควตาจาก API หากถูกคิดไปแล้วให้ refresh แยกจาก backendใน failure handlerเพื่อให้ตัวเลขตรง ledger แต่ห้าม commit prepared recipe ใหม่เพียงเพราะ refresh โควตา.

เพิ่ม regression widget test: สร้างผล A สำเร็จ → เลือก source B และสร้าง local `mappedProject` B คนละ fingerprint/cue → assert ว่า initial renderer รับ source/project B ไม่อ่าน active source/project A → ให้ renderer throw → assert ว่า active source/duration, recipe, project, review/applied capabilities, selected repeat IDs, verification, preview และ export ยังใช้ A ทั้งชุด; processing state กลับ review A พร้อม error และการ refreshโควตาไม่เปลี่ยน accepted content state.

เพิ่ม regression หลัง shared local/network refactor โดย inject `automaticRepeatCutsEnabled: false` และ recipe ที่มี default repeat cut: initial render, review rerender, subtitle edit และ export ต้องส่ง removed occurrence IDs ว่างทั้งหมด, capability map ไม่มี `filler`, แต่ detection groups/read-only copy ยังมองเห็น; เปิด flag กลับแล้ว behavior เดิมต้องผ่าน.

เปลี่ยนทุกจุดที่ “อ่าน recipe เพื่อ review/render/export” จาก `_preparedEdit?.recipe` เป็น `_activeRecipe` และทุกจุดที่อ่าน source ของผลที่ยอมรับแล้วจาก `_selectedVideo` เป็น `_activeSourceVideo`: `_handleReviewCapabilityChanged`, `_renderPreparedRecipe` callers, `_prepareReviewForResult`, original preview/source matching, subtitle project rerender, `_openPostFlow`, `_buildAnalysisSummary`, repeated-speech summary/selection, capability status copy และ retry silence. `_returnToSetup` สามารถ seed pending source จาก active source ได้ แต่ picker/remove ของ pending sourceห้ามล้าง active state; explicit discard ต้องล้าง active source/content พร้อมกัน. จุดที่อ่าน working setup และ API quota/caches ยังคงใช้ `_selectedVideo`/`AiEditPrepareResult`. ตรวจครบด้วย:

```powershell
rg -n "_preparedEdit" apps/mobile/lib/features/ai_editing/ai_editing_screen.dart
rg -n "_selectedVideo" apps/mobile/lib/features/ai_editing/ai_editing_screen.dart
```

หลัง refactor อนุญาตให้เหลือ `_preparedEdit` เฉพาะ field assignment/reset และ API-response-specific logic; ห้ามมี `_preparedEdit?.recipe` เหลืออยู่. Local branch render `activeRecipe` กับไฟล์ต้นฉบับโดยตรง, จุดแสดง quota ใช้ `_aiEditQuota` เดิม และห้ามเขียนทับ quota ใน local branch.

- [ ] **Step 6: ใช้ชื่อ `_edited.mp4` เมื่อไม่มีซับจริง**

แทน `_subtitledFileName` ด้วย public pure helper และใช้ค่าที่ renderer คำนวณแล้ว:

```dart
String editedVideoOutputFileName(
  String fileName, {
  required bool hasSubtitles,
}) {
  final trimmed = fileName.trim();
  final dotIndex = trimmed.lastIndexOf('.');
  final baseName = dotIndex <= 0 ? trimmed : trimmed.substring(0, dotIndex);
  final suffix = hasSubtitles ? 'subtitled' : 'edited';
  return '${baseName}_$suffix.mp4';
}

final outputFile = File(
  '${workingDirectory.path}$separator'
  '${editedVideoOutputFileName(
    request.fileName,
    hasSubtitles: hasSubtitles,
  )}',
);
```

ต้องอิง subtitle file content จริง ไม่อิง toggle อย่างเดียว.

- [ ] **Step 7: รัน GREEN, mobile regression และ commit**

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_media_strategy_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Media strategy tests failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_edit_local_recipe_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Local recipe tests failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\subtitle_burn_test.dart
  if ($LASTEXITCODE -ne 0) { throw "Subtitle burn tests failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test test\ai_editing_screen_test.dart
  if ($LASTEXITCODE -ne 0) { throw "AI editing screen tests failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git add apps/mobile/lib/features/ai_editing/ai_edit_media_strategy.dart apps/mobile/lib/features/ai_editing/ai_edit_local_recipe.dart apps/mobile/lib/features/ai_editing/ai_editing_screen.dart apps/mobile/lib/features/ai_editing/subtitle_burn_video_processor.dart apps/mobile/test/ai_edit_media_strategy_test.dart apps/mobile/test/ai_edit_local_recipe_test.dart apps/mobile/test/ai_editing_screen_test.dart apps/mobile/test/subtitle_burn_test.dart
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "fix: render color-only edits locally"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

---

## Task 9: Sync เอกสาร, ตรวจครบระบบ และทดสอบ Pixel 8 แบบแยกทีละความสามารถ

**Files:**

- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `API.md`
- Modify: `ARCHITECTURE.md`
- Modify: `docs/STAGING.md`
- Modify: `docs/GO_LIVE.md`
- Modify: `docs/testing/AI_EDIT_THAI_CLIPS.md`
- Modify: `docs/superpowers/plans/2026-08-01-ai-edit-correctness-and-fair-quota-implementation.md`
- Create: `docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md`

แผนเก่าใน `docs/superpowers/plans/` เป็นประวัติและไม่ต้องแก้ย้อนหลัง; ไฟล์ implementation ปัจจุบันด้านบนเป็น plan/status ที่ต้องติ๊กและแนบผลจริง.

- [ ] **Step 1: Sync docs กับ contract ที่พัฒนาเสร็จจริง**

เอกสารต้องระบุอย่างตรงกัน:

- ทุก optional toggle เริ่มปิด
- API transcript gaps คือ silence candidates; mobile waveform เป็น final authority
- target boundary ใช้ transcript ภายในได้โดยไม่เปิด visible subtitles
- exact Thai reconstruction เท่านั้น; fail closed เมื่อประกอบไม่ได้
- repeat-only unavailable และ color-only local ไม่ลด AI minutes
- color-only original duration เป็น local Pro feature; color+shortening ยังใช้ prepare หนึ่งครั้ง
- renderer codec/fps/file-size/audio-peak/A-V-sync ยังเป็นงานถัดไป ห้ามเขียนว่าแก้แล้ว

ใช้ข้อความ canonical นี้ในเอกสารทุกแห่งที่อธิบาย silence/color เพื่อไม่ให้ความหมายขัดกัน:

```markdown
Transcript gaps are silence candidates only. The Android/iOS client confirms
each candidate against the source waveform before rendering; failed or
ambiguous verification keeps the original audio. Color-only edits at original
duration render locally for Pro users and do not consume AI editing minutes.
```

- [ ] **Step 2: รัน API verification ครบ**

Run from worktree root:

```powershell
Push-Location 'apps/api'
try {
  npm.cmd run test
  if ($LASTEXITCODE -ne 0) { throw "API tests failed with exit code $LASTEXITCODE" }
  npm.cmd run build
  if ($LASTEXITCODE -ne 0) { throw "API build failed with exit code $LASTEXITCODE" }
  $env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'
  npm.cmd run prisma:validate
  if ($LASTEXITCODE -ne 0) { throw "Prisma validation failed with exit code $LASTEXITCODE" }
  npx.cmd tsc --noEmit --target ES2022 --module NodeNext --moduleResolution NodeNext --esModuleInterop --skipLibCheck prisma\seed.ts prisma.config.ts
  if ($LASTEXITCODE -ne 0) { throw "Prisma helper typecheck failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
```

- [ ] **Step 3: รัน Flutter verification ครบ**

Run from worktree root:

```powershell
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' analyze
  if ($LASTEXITCODE -ne 0) { throw "Flutter analyze failed with exit code $LASTEXITCODE" }
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' test
  if ($LASTEXITCODE -ne 0) { throw "Flutter tests failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
```

- [ ] **Step 4: สร้าง APK Staging โดยไม่ commit secrets**

ตรวจว่าไฟล์ local config มีอยู่ก่อน:

```powershell
Test-Path 'D:\PostDeeMobile\apps\mobile\staging.local.json'
```

ถ้าเป็น `True`:

```powershell
Push-Location 'apps/mobile'
try {
  $buildStartedAt = (Get-Date).ToUniversalTime()
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' build apk --debug --dart-define-from-file='D:\PostDeeMobile\apps\mobile\staging.local.json'
  if ($LASTEXITCODE -ne 0) { throw "Staging APK build failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
$stagingApkPath = 'D:\PostDeeMobile\.worktrees\main-integrate-duration\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path -LiteralPath $stagingApkPath)) { throw "Staging APK was not created" }
$stagingApk = Get-Item -LiteralPath $stagingApkPath
if ($stagingApk.LastWriteTimeUtc -lt $buildStartedAt.AddSeconds(-2)) {
  throw "Staging APK is stale: $($stagingApk.LastWriteTimeUtc)"
}
$stagingApkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagingApkPath).Hash
$stagingApkHash
```

ถ้าเป็น `False` ให้รายงานว่ายังสร้าง Staging APK ไม่ได้; ห้ามสร้าง key ปลอมหรือ commit config.

ตรวจ local QA fixtures ที่มีอยู่แล้วก่อน deploy; ห้ามสร้างหรือดาวน์โหลดคลิปใหม่โดยไม่จำเป็น. ชุด `multi-style` มีคลิปข่าว, พูดตามสคริปต์, สัมภาษณ์ธรรมชาติ และเสียงรบกวน พร้อม SRT และ `QA_REPORT.md` ที่บันทึกแหล่งที่มา/สิทธิ์ใช้งาน. คลิป raw และ stacked marks อ้างอิงสิทธิ์จาก `docs/testing/AI_EDIT_THAI_CLIPS.md`. หากไฟล์, metadata หรือ hash ใดหาย ให้หยุดและรายงาน; ห้ามเดา source หรือแทนด้วย media ที่ไม่ทราบสิทธิ์.

```powershell
$fixtureRoot = 'D:\PostDeeMobile\.tmp\test-videos'
$multiStyleRoot = Join-Path $fixtureRoot 'multi-style'
$requiredFixtures = @(
  (Join-Path $fixtureRoot 'raw-talking-head-thai-vertical-cc-by-sa.mp4'),
  (Join-Path $fixtureRoot 'thai-stacked-marks-30s.mp4'),
  (Join-Path $multiStyleRoot 'qa-thai-natural-interview-45s.mp4'),
  (Join-Path $multiStyleRoot 'qa-thai-scripted-clean-45s.mp4'),
  (Join-Path $multiStyleRoot 'qa-thai-background-noise-45s.mp4'),
  (Join-Path $multiStyleRoot 'qa-thai-news-voiceover-45s.mp4'),
  (Join-Path $multiStyleRoot 'qa-natural-interview-captions.srt'),
  (Join-Path $multiStyleRoot 'qa-scripted-captions.srt'),
  (Join-Path $multiStyleRoot 'qa-background-noise-captions.srt'),
  (Join-Path $multiStyleRoot 'qa-news-captions.srt'),
  (Join-Path $multiStyleRoot 'QA_REPORT.md'),
  'docs\testing\AI_EDIT_THAI_CLIPS.md'
)
foreach ($fixture in $requiredFixtures) {
  if (-not (Test-Path -LiteralPath $fixture) -or (Get-Item -LiteralPath $fixture).Length -le 0) {
    throw "Missing QA fixture: $fixture"
  }
}
$videoFixtures = $requiredFixtures | Where-Object { $_ -like '*.mp4' }
$videoFixtureHashes = $videoFixtures | ForEach-Object {
  Get-FileHash -Algorithm SHA256 -LiteralPath $_
}
$videoFixtureHashes | Format-Table Path, Hash -AutoSize
```

อ่าน `QA_REPORT.md` และ SRT เพื่อยืนยันชนิดคลิป/คำพูดซ้ำก่อนทดสอบ; scripted fixture มีคำ `ชุมชน` ต่อเนื่องข้าม cue สำหรับ repeat-safe ส่วน background-noise ใช้ยืนยัน fail-closed. บันทึก SHA-256 ของวิดีโอทุกไฟล์และ source/license ลงผลทดสอบ; ห้าม stage media.

- [ ] **Step 5: Commit เอกสารเตรียมทดสอบ ขออนุญาต และนำ API candidate ขึ้น Staging ก่อน**

สร้างโฟลเดอร์ผลทดสอบที่ยังไม่มี แล้วใช้ `apply_patch` สร้างไฟล์ผลสถานะ `PENDING` จาก schema ใน Step 6; ห้ามใช้ shell เขียนเนื้อหาไฟล์. ส่วนหัวต้องมี fields เหล่านี้ตั้งแต่แรก: `Candidate deploy SHA`, `Deployed Staging SHA`, `API runtime code SHA`, `Health status/time`, `Matrix APK SHA-256`, `Fixture SHA-256` และ `Overall status`; ค่าที่ยังไม่ทราบใช้ `PENDING`.

```powershell
if (-not (Test-Path 'docs/testing/results')) {
  New-Item -ItemType Directory -Path 'docs/testing/results' | Out-Null
}
```

ตรวจและ commit implementation + เอกสารเตรียมทดสอบจาก worktree root:

```powershell
git status --short
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git log --oneline origin/main..HEAD
if ($LASTEXITCODE -ne 0) { throw "git log failed" }
git diff --stat origin/main...HEAD
if ($LASTEXITCODE -ne 0) { throw "git diff failed" }
git add README.md ROADMAP.md API.md ARCHITECTURE.md docs/STAGING.md docs/GO_LIVE.md docs/testing/AI_EDIT_THAI_CLIPS.md docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md docs/superpowers/plans/2026-08-01-ai-edit-correctness-and-fair-quota-implementation.md
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "docs: prepare ai edit correctness staging validation"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

ยืนยันว่าไม่มี secret, video, APK หรือไฟล์นอก scope แล้วขอผู้ใช้อนุญาต `push main และ deploy Staging` เพราะเป็นการเปลี่ยนระบบภายนอก. เมื่อได้รับอนุญาต:

```powershell
$candidateDeploySha = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $candidateDeploySha -notmatch '^[0-9a-f]{40}$') {
  throw "Unable to read candidate deploy SHA"
}
$apiRuntimeSha = (git log -1 --format=%H -- apps/api).Trim()
if ($LASTEXITCODE -ne 0 -or $apiRuntimeSha -notmatch '^[0-9a-f]{40}$') {
  throw "Unable to read API runtime SHA"
}
git push origin main
if ($LASTEXITCODE -ne 0) { throw "git push failed with exit code $LASTEXITCODE" }
gh run list --branch main --limit 5
if ($LASTEXITCODE -ne 0) { throw "GitHub checks query failed with exit code $LASTEXITCODE" }
$health = Invoke-RestMethod 'https://postdee-api-staging.onrender.com/health' -ErrorAction Stop
if ($health.status -ne 'ok') { throw "Staging health status is not ok" }
```

รอ GitHub checks และ Render auto-deploy ให้ผ่าน แล้วตรวจใน Render Dashboard ว่า service `postdee-api-staging` ติดตาม `main` และ **deployed commit SHA ตรงกับ `$candidateDeploySha`**; `/health` เพียงอย่างเดียวไม่ยืนยันว่าเป็นโค้ดใหม่. หาก SHA ไม่ตรง, deploy ล้ม หรือ Blueprint ชี้ branch อื่น ให้หยุดก่อน Pixel 8 matrix; ห้ามยิง deploy hook ที่ไม่ทราบ target และห้าม deploy Production.

เมื่อ SHA ตรง ให้ใช้ `apply_patch` แทนค่า PENDING ในผลทดสอบด้วย candidate SHA, deployed SHA ที่อ่านจาก Dashboard, API runtime SHA และ health status/time จริง. Matrix เริ่มได้ต่อเมื่อทั้งสอง deploy SHA เป็นเลข 40 หลักและเท่ากัน; นี่เป็นหลักฐานถาวรว่ามือถือทดสอบกับ backend รุ่นใด.

- [ ] **Step 6: ติดตั้งบน Pixel 8 และทดสอบ isolated matrix กับ API SHA ใหม่**

หลัง API SHA ใหม่ deploy แล้ว ให้สร้าง APK ซ้ำใน block เดียวกับการติดตั้งเพื่อไม่พึ่งตัวแปรข้ามช่วงขออนุญาตและไม่เผลอใช้ APK เก่า. จากนั้นตรวจว่ามี emulator ที่ boot สำเร็จเพียงเครื่องเดียว, ส่ง fixtures เข้าเครื่อง แล้วติดตั้ง/เปิดแอป Staging:

```powershell
$resultPath = 'docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md'
$resultText = Get-Content -LiteralPath $resultPath -Raw -Encoding utf8
$candidateMatch = [regex]::Match($resultText, '(?m)^Candidate deploy SHA:\s*`?([0-9a-f]{40})`?\s*$')
$deployedMatch = [regex]::Match($resultText, '(?m)^Deployed Staging SHA:\s*`?([0-9a-f]{40})`?\s*$')
if (-not $candidateMatch.Success -or -not $deployedMatch.Success) {
  throw "Result evidence is missing candidate/deployed Staging SHA"
}
if ($candidateMatch.Groups[1].Value -ne $deployedMatch.Groups[1].Value) {
  throw "Candidate and deployed Staging SHA do not match"
}
$localHead = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $localHead -ne $candidateMatch.Groups[1].Value) {
  throw "Local HEAD no longer matches the deployed matrix candidate"
}
$matrixHealth = Invoke-RestMethod 'https://postdee-api-staging.onrender.com/health' -ErrorAction Stop
if ($matrixHealth.status -ne 'ok') { throw "Staging health status is not ok before matrix" }

$stagingConfig = 'D:\PostDeeMobile\apps\mobile\staging.local.json'
if (-not (Test-Path -LiteralPath $stagingConfig)) { throw "Missing Staging config" }
Push-Location 'apps/mobile'
try {
  $matrixBuildStartedAt = (Get-Date).ToUniversalTime()
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' build apk --debug --dart-define-from-file=$stagingConfig
  if ($LASTEXITCODE -ne 0) { throw "Matrix APK build failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
$stagingApkPath = 'D:\PostDeeMobile\.worktrees\main-integrate-duration\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path -LiteralPath $stagingApkPath)) { throw "Matrix APK was not created" }
$matrixApk = Get-Item -LiteralPath $stagingApkPath
if ($matrixApk.LastWriteTimeUtc -lt $matrixBuildStartedAt.AddSeconds(-2)) {
  throw "Matrix APK is stale: $($matrixApk.LastWriteTimeUtc)"
}
$matrixApkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagingApkPath).Hash

$adb = 'C:\Users\stopp\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$online = @(& $adb devices | Select-String '^emulator-\d+\s+device$')
if ($LASTEXITCODE -ne 0) { throw "ADB devices failed with exit code $LASTEXITCODE" }
if ($online.Count -ne 1) { throw "Expected one booted Pixel 8 emulator; found $($online.Count)." }
$pixel8 = ($online[0].Line -split '\s+')[0]
$avdName = (& $adb -s $pixel8 shell getprop ro.boot.qemu.avd_name).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to read AVD name" }
if ($avdName -notmatch '(?i)pixel[_ -]?8') { throw "Expected Pixel 8 AVD; found '$avdName'." }
$deviceFixtureRoot = '/sdcard/Download/PostDee-QA'
& $adb -s $pixel8 shell mkdir -p $deviceFixtureRoot
if ($LASTEXITCODE -ne 0) { throw "Unable to create device fixture directory" }
$hostVideoFixtures = @(
  'D:\PostDeeMobile\.tmp\test-videos\raw-talking-head-thai-vertical-cc-by-sa.mp4',
  'D:\PostDeeMobile\.tmp\test-videos\thai-stacked-marks-30s.mp4',
  'D:\PostDeeMobile\.tmp\test-videos\multi-style\qa-thai-natural-interview-45s.mp4',
  'D:\PostDeeMobile\.tmp\test-videos\multi-style\qa-thai-scripted-clean-45s.mp4',
  'D:\PostDeeMobile\.tmp\test-videos\multi-style\qa-thai-background-noise-45s.mp4',
  'D:\PostDeeMobile\.tmp\test-videos\multi-style\qa-thai-news-voiceover-45s.mp4'
)
foreach ($hostFixture in $hostVideoFixtures) {
  if (-not (Test-Path -LiteralPath $hostFixture)) { throw "Missing host fixture: $hostFixture" }
  $deviceFixture = "$deviceFixtureRoot/$([IO.Path]::GetFileName($hostFixture))"
  & $adb -s $pixel8 push $hostFixture $deviceFixture
  if ($LASTEXITCODE -ne 0) { throw "ADB push failed: $hostFixture" }
  & $adb -s $pixel8 shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$deviceFixture"
  if ($LASTEXITCODE -ne 0) { throw "Media scan failed: $deviceFixture" }
  & $adb -s $pixel8 shell ls -l $deviceFixture
  if ($LASTEXITCODE -ne 0) { throw "Fixture not visible on device: $deviceFixture" }
}

if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stagingApkPath).Hash -ne $matrixApkHash) {
  throw "APK changed before install"
}
& $adb -s $pixel8 install -r $stagingApkPath
if ($LASTEXITCODE -ne 0) { throw "APK install failed with exit code $LASTEXITCODE" }
& $adb -s $pixel8 shell am force-stop com.postdee.postdee_mobile.staging
if ($LASTEXITCODE -ne 0) { throw "Unable to stop existing Staging app" }
& $adb -s $pixel8 shell monkey -p com.postdee.postdee_mobile.staging -c android.intent.category.LAUNCHER 1
if ($LASTEXITCODE -ne 0) { throw "Unable to launch Staging app" }
```

ใน Android file picker ให้เลือกไฟล์จาก `Download/PostDee-QA`; บันทึก `$matrixApkHash` และ device path ของแต่ละ case ลงผลทดสอบเพื่อยืนยันว่า matrix ใช้ build/fixture ชุดเดียวกัน.

ใช้คลิปไทยชุดเดิม สร้างผลใหม่ทุก case เพราะวิดีโอเก่าเก็บ recipe เก่า:

1. **Target only:** เลือก 30s, 60s และ custom; subtitle/silence/repeat/color ปิด ตรวจว่าไม่เริ่มหรือจบกลาง cue เมื่อมี reliable timing และหน้าจอแสดงความยาวจริงหากเกิน tolerance เพื่อรักษาประโยค
2. **Subtitle only:** ซับหนึ่งแถว, ไม่เลยขอบ, วรรณยุกต์ไม่จม, ไม่มี silence/repeat/color แฝง
3. **Silence only:** หัว/ท้ายอยู่ครบ, ไม่มีคำพูดถูกตัด, raw candidate ที่ waveform ไม่ยืนยันไม่ถูกตัด, probe fail แสดงลองใหม่
4. **Repeat only clear audio:** exact adjacent repeat พบได้, ผู้ใช้ยังเปลี่ยนว่าจะเก็บ/ตัด occurrence ได้
5. **Repeat only unsafe timing/noisy:** ไม่มี auto cut และ quota ก่อน/หลังเท่ากัน
6. **Color only original:** สีเปลี่ยน, ไม่มี audio upload/prepare, quota เท่าเดิม, ชื่อไฟล์ `_edited.mp4`
7. **Color + 30s target:** prepare หนึ่งครั้ง, quota ลดหนึ่งครั้ง, color และ target มีผลพร้อมกัน
8. **Combined subtitle + silence + repeat:** prepare/charge ครั้งเดียว และ final cuts ไม่ทับ protected speech

เก็บสำหรับแต่ละ case: เวลาเริ่ม/จบ, duration ผลจริง, quota ก่อน/หลัง, screenshot review, และไฟล์ผลลัพธ์. ห้ามเปิด Production หาก silence clip ชุดเดิมยังตัดคำพูดหรือช่วงเปิด.

บันทึกผลในตารางเดียวกันตาม schema นี้ โดยไม่ใส่ key/token:

```markdown
| Case | Source | Selected toggles | Start/end | Output duration | Quota before/after | Visual/audio result | Pass |
|---|---|---|---|---:|---|---|---|
| target-30 | raw-talking-head-thai-vertical-cc-by-sa.mp4 | target only |  |  |  |  |  |
| target-60 | raw-talking-head-thai-vertical-cc-by-sa.mp4 | target only |  |  |  |  |  |
| target-custom | raw-talking-head-thai-vertical-cc-by-sa.mp4 | target only |  |  |  |  |  |
| subtitle | thai-stacked-marks-30s.mp4 | subtitle |  |  |  |  |  |
| silence | qa-thai-natural-interview-45s.mp4 | silence |  |  |  |  |  |
| repeat-safe | qa-thai-scripted-clean-45s.mp4 (`ชุมชน / ชุมชน`) | repeat |  |  |  |  |  |
| repeat-unsafe | qa-thai-background-noise-45s.mp4 | repeat |  |  |  |  |  |
| color-local | qa-thai-news-voiceover-45s.mp4 | color |  |  |  |  |  |
| color-target | qa-thai-news-voiceover-45s.mp4 | color + target |  |  |  |  |  |
| combined | raw-talking-head-thai-vertical-cc-by-sa.mp4 | subtitle + silence + repeat |  |  |  |  |  |
```

เขียนค่าจริงและลิงก์ screenshot/file evidence ลง `docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md`; ไฟล์วิดีโอและภาพหลักฐานขนาดใหญ่คงอยู่ใน ignored `.tmp` เท่านั้น ไม่ stage เข้า Git.

- [ ] **Step 7: ใช้ rollout gate และทดสอบทางถอยกลับ**

ถ้า matrix ผ่านทุก case ให้ไป Step 8. หากพบ silence ตัดคำพูดจริง/ช่วงเปิด หรือ exact repeat reconstruction ยังคลุมเครือ ให้หยุด rollout และสร้าง APK rollback จาก commit เดิมด้วย flags ที่ Task 7 ทดสอบไว้. เลือกโหมดตาม case ที่ล้มเท่านั้น; ห้ามปิดทั้งสองความสามารถโดยอัตโนมัติ:

Agent ต้องประกาศโหมดที่เลือกใน task conversation แล้วสร้าง shell command โดยแทน `$null` บรรทัดแรกด้วย literal `'silence'`, `'repeat'` หรือ `'both'` จากผล matrix จริง. รันทั้ง block ใน tool call เดียว; ห้ามใช้ interactive promptและห้ามปล่อย `$null`:

```powershell
$rollbackMode = $null # agent ต้องแทนด้วย literal จาก matrix ก่อนรัน
switch ($rollbackMode) {
  'silence' {
    $rollbackDefines = @('--dart-define=AI_EDIT_VERIFIED_SILENCE_ENABLED=false')
  }
  'repeat' {
    $rollbackDefines = @('--dart-define=AI_EDIT_AUTO_REPEAT_CUTS_ENABLED=false')
  }
  'both' {
    $rollbackDefines = @(
      '--dart-define=AI_EDIT_VERIFIED_SILENCE_ENABLED=false',
      '--dart-define=AI_EDIT_AUTO_REPEAT_CUTS_ENABLED=false'
    )
  }
  default { throw 'Set rollbackMode from the failed matrix case before building' }
}
Push-Location 'apps/mobile'
try {
  & 'D:\PostDeeMobile\.tools\flutter\bin\flutter.bat' build apk --debug `
    --dart-define-from-file='D:\PostDeeMobile\apps\mobile\staging.local.json' `
    @rollbackDefines
  if ($LASTEXITCODE -ne 0) { throw "Rollback APK build failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
$stagingApkPath = 'D:\PostDeeMobile\.worktrees\main-integrate-duration\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path -LiteralPath $stagingApkPath)) { throw "Rollback APK was not created" }
$rollbackApkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagingApkPath).Hash
$rollbackApkHash
$adb = 'C:\Users\stopp\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$online = @(& $adb devices | Select-String '^emulator-\d+\s+device$')
if ($LASTEXITCODE -ne 0) { throw "ADB devices failed during rollback" }
if ($online.Count -ne 1) { throw "Expected one booted Pixel 8 emulator; found $($online.Count)." }
$pixel8 = ($online[0].Line -split '\s+')[0]
$avdName = (& $adb -s $pixel8 shell getprop ro.boot.qemu.avd_name).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to read rollback AVD name" }
if ($avdName -notmatch '(?i)pixel[_ -]?8') { throw "Expected Pixel 8 AVD; found '$avdName'." }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stagingApkPath).Hash -ne $rollbackApkHash) {
  throw "Rollback APK changed before install"
}
& $adb -s $pixel8 install -r $stagingApkPath
if ($LASTEXITCODE -ne 0) { throw "Rollback APK install failed" }
& $adb -s $pixel8 shell am force-stop com.postdee.postdee_mobile.staging
if ($LASTEXITCODE -ne 0) { throw "Unable to stop Staging app for rollback" }
& $adb -s $pixel8 shell monkey -p com.postdee.postdee_mobile.staging -c android.intent.category.LAUNCHER 1
if ($LASTEXITCODE -ne 0) { throw "Unable to launch rollback Staging app" }
```

- ถ้าเสียเฉพาะ silence ให้ปิดเฉพาะ `AI_EDIT_VERIFIED_SILENCE_ENABLED`; effective silence/UI/verifier/final cuts ต้องปิด แต่ subtitle/target/repeat/color ทำงานเดิม
- ถ้าเสียเฉพาะ repeat ให้ปิดเฉพาะ `AI_EDIT_AUTO_REPEAT_CUTS_ENABLED`; detection groups ยังคงอ่านได้ แต่เลือก/ตัด occurrence ไม่ได้
- ติดตั้ง APK rollback บน Pixel 8 และ rerun case ที่เสียพร้อม smoke test subtitle-only, target-only และ color-only เพื่อยืนยันว่าไม่ปิดความสามารถอื่น
- บันทึกผลเป็น `BLOCKED` และห้ามเปิด Production; rollback ห้ามคืน server defaults เป็น true และห้ามนำ transcript gaps กลับมาเป็น executable cuts
- Sync ขั้นตอน/flags นี้ลง `docs/STAGING.md` และ `docs/GO_LIVE.md`

- [ ] **Step 8: ตรวจ Git และ commit หลักฐานหลัง matrix**

```powershell
git status --short
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace validation failed" }
git add README.md ROADMAP.md API.md ARCHITECTURE.md docs/STAGING.md docs/GO_LIVE.md docs/testing/AI_EDIT_THAI_CLIPS.md docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md docs/superpowers/plans/2026-08-01-ai-edit-correctness-and-fair-quota-implementation.md
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
git commit -m "docs: record ai edit correctness staging results"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
```

- [ ] **Step 9: Review หลักฐานก่อน push รอบสุดท้าย**

```powershell
git log --oneline origin/main..HEAD
if ($LASTEXITCODE -ne 0) { throw "git log failed" }
git diff --stat origin/main...HEAD
if ($LASTEXITCODE -ne 0) { throw "git diff failed" }
git status --short --branch
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
```

ยืนยันว่าไม่มี secret, video, APK หรือไฟล์นอก scope. ใช้ code-review/verification workflow ที่มีอยู่เพื่อตรวจ change set และหลักฐาน test อีกครั้ง; หากติดตั้ง Superpowers plugin อยู่จะใช้ review skills ของ plugin เพิ่มได้ แต่ไม่ใช่ข้อบังคับ.

- [ ] **Step 10: Push หลักฐานรอบสุดท้ายเฉพาะเมื่อได้รับอนุญาต**

ขั้นนี้เปลี่ยนระบบภายนอก จึงต้องขอผู้ใช้ยืนยันอีกครั้งหลังเห็นผล Pixel 8 matrix. ก่อน push ต้องยืนยันว่า diff จาก SHA ที่ทดสอบมีเฉพาะเอกสาร/หลักฐาน; หากมี runtime code เปลี่ยนหลัง Step 5 ต้องกลับไปรัน API/Flutter/build, deploy API และ Pixel matrix ใหม่ทั้งหมด.

```powershell
git diff --name-only HEAD~1..HEAD
if ($LASTEXITCODE -ne 0) { throw "git diff failed" }
git push origin main
if ($LASTEXITCODE -ne 0) { throw "git push failed" }
gh run list --branch main --limit 5
if ($LASTEXITCODE -ne 0) { throw "GitHub checks query failed" }
$finalHealth = Invoke-RestMethod 'https://postdee-api-staging.onrender.com/health' -ErrorAction Stop
if ($finalHealth.status -ne 'ok') { throw "Staging health status is not ok after evidence push" }
```

รอ checks ผ่าน. Render อาจ redeploy เพราะ docs commit แต่ runtime code ต้องตรง SHA ที่ผ่าน matrix; ตรวจ Dashboard อีกครั้ง. ห้ามยิง deploy hook ที่ไม่ทราบ target และห้าม deploy Production ในแผนนี้.

---

## Definition of Done

- API/mobile defaults ปิดทุก optional capability และ tests ยืนยันครบ
- Target-only ใช้ transcript boundary โดยไม่มี subtitle overlay
- API ไม่สร้าง leading/trailing silence candidates และไม่ใส่ candidates ใน executable cuts
- Mobile ตัด silence เฉพาะ transcript candidate ∩ waveform silence, padding 0.10s, final >=0.25s และไม่ทับ protected speech
- FFmpeg silence probe ล้มเหลวแล้วไม่ตัด พร้อม retry ได้
- Thai character timings ประกอบเป็นคำได้เฉพาะ exact NFC ภายใน segment และ gap <=0.15s
- Repeat-only unavailable ไม่เพิ่ม usage ledger; combined successful request เพิ่มครั้งเดียว
- Color-only original duration ผ่าน Pro check แต่ไม่ extract/upload/prepare และไม่ลด quota
- ผลไม่มีซับใช้ชื่อ `_edited.mp4`
- API tests/build/Prisma checks, Flutter analyze/tests, Android APK และ Pixel 8 isolated matrix ผ่าน
- เอกสารหลักตรงกับระบบจริง และยังระบุ renderer-quality batch ว่ายังไม่เสร็จ
- ยังไม่มี Production deploy; Staging push/deploy ทำหลังผู้ใช้อนุญาตและ CI ผ่านเท่านั้น
