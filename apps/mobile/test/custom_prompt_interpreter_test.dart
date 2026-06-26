import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/custom_prompt_interpreter.dart';

void main() {
  test('parses a target length in seconds and minutes', () {
    expect(parseCustomPrompt('ช่วยทำให้เหลือ 45 วิ').targetSeconds, 45);
    expect(parseCustomPrompt('ตัดให้เหลือ 30 วินาที').targetSeconds, 30);
    expect(parseCustomPrompt('เอาแค่ 1 นาที').targetSeconds, 60);
    expect(parseCustomPrompt('ทำให้สวยๆ').targetSeconds, isNull);
  });

  test('detects a profanity-removal intent', () {
    expect(parseCustomPrompt('ตัดคำหยาบออกให้หมด').removeProfanity, isTrue);
    expect(parseCustomPrompt('เซ็นเซอร์คำไม่สุภาพ').removeProfanity, isTrue);
    expect(parseCustomPrompt('ทำให้กระชับ').removeProfanity, isFalse);
  });

  test('an uninterpretable prompt is empty', () {
    expect(parseCustomPrompt('ทำให้ดูดีๆ หน่อย').isEmpty, isTrue);
  });

  test('trims the tail to fit a target length', () {
    final cuts = buildCustomPromptCutRanges(
      segments: const [],
      durationSeconds: 60,
      instruction: const CustomPromptInstruction(targetSeconds: 45),
    );

    expect(cuts, hasLength(1));
    expect(cuts.first.start, closeTo(45, 0.01));
    expect(cuts.first.end, closeTo(60, 0.01));
  });

  test('cuts profane segments and then fits the target', () {
    final cuts = buildCustomPromptCutRanges(
      segments: const [
        ClipTranscriptSegment(text: 'สวัสดีค่ะ', start: 0, end: 10),
        ClipTranscriptSegment(text: 'ไอ้เหี้ยอะไรเนี่ย', start: 10, end: 12),
        ClipTranscriptSegment(text: 'ขายของต่อ', start: 12, end: 30),
      ],
      durationSeconds: 30,
      instruction:
          const CustomPromptInstruction(targetSeconds: 15, removeProfanity: true),
    );

    // Profane 10-12 is cut. Kept = [0-10]+[12-30]; target 15 → keep 10 then 5
    // more of the 12-30 span (up to 17), cutting [17-30].
    expect(cuts.any((c) => c.start == 10 && c.end == 12), isTrue);
    expect(cuts.any((c) => (c.start - 17).abs() < 0.01 && c.end == 30), isTrue);
  });
}
