import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/edit_styles.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';

void main() {
  test('exposes all 10 styles with a single custom-prompt style', () {
    expect(editStyles, hasLength(10));
    expect(editStyles.where((s) => s.plan.isCustomPrompt), hasLength(1));
  });

  EditStyle byId(String id) => editStyles.firstWhere((s) => s.id == id);

  test('marks audio-only styles as coming soon, others not', () {
    expect(byId('comedy').plan.comingSoon, isTrue);
    expect(byId('asmr').plan.comingSoon, isTrue);
    expect(byId('flash_sale').plan.comingSoon, isFalse);
    expect(byId('vlog').plan.comingSoon, isFalse);
  });

  test('flags speech-based styles via needsSpeech', () {
    expect(byId('fast_review').plan.needsSpeech, isTrue); // silence cut
    expect(byId('flash_sale').plan.needsSpeech, isTrue); // keywords
    expect(byId('qa').plan.needsSpeech, isTrue);
    expect(byId('vlog').plan.needsSpeech, isFalse);
    expect(byId('aesthetic').plan.needsSpeech, isFalse);
  });

  test('gives sell styles a vivid look and aesthetic a warm look', () {
    EditStyle byId(String id) => editStyles.firstWhere((s) => s.id == id);

    expect(byId('flash_sale').plan.filterIndex, 1); // สดใส
    expect(byId('aesthetic').plan.filterIndex, 4); // อบอุ่น
    expect(byId('asmr').plan.volume, greaterThan(1.0)); // boost sounds
    expect(byId('vlog').plan.filterIndex, 0); // natural
  });

  test('matches keywords case-insensitively', () {
    expect(segmentMatchesKeywords('ราคาพิเศษวันนี้', const ['ราคา']), isTrue);
    expect(segmentMatchesKeywords('FLASH sale', const ['flash']), isTrue);
    expect(segmentMatchesKeywords('สวัสดีค่ะ', const ['ราคา']), isFalse);
    expect(segmentMatchesKeywords('อะไรก็ได้', const []), isFalse);
  });

  test('keeps keyword segments and cuts the rest', () {
    final cuts = buildStyleCutRanges(
      segments: const [
        ClipTranscriptSegment(text: 'สวัสดีค่ะ', start: 0, end: 3),
        ClipTranscriptSegment(text: 'ราคาพิเศษ 99 บาท', start: 3, end: 6),
        ClipTranscriptSegment(text: 'ขอบคุณค่ะ', start: 6, end: 10),
      ],
      durationSeconds: 10,
      plan: const EditStylePlan(keepKeywords: ['ราคา', 'บาท']),
    );

    expect(cuts, hasLength(2));
    expect(cuts[0].start, 0);
    expect(cuts[0].end, 3);
    expect(cuts[1].start, 6);
    expect(cuts[1].end, 10);
  });

  test('Q&A keeps the answer segment after a matched question', () {
    final cuts = buildStyleCutRanges(
      segments: const [
        ClipTranscriptSegment(text: 'ใช้ดีไหมคะ', start: 0, end: 2),
        ClipTranscriptSegment(text: 'ดีมากเลยค่ะ', start: 2, end: 5),
        ClipTranscriptSegment(text: 'จบแล้วนะ', start: 5, end: 8),
      ],
      durationSeconds: 8,
      plan: const EditStylePlan(
        keepKeywords: ['ไหม'],
        keepFollowingSegment: true,
      ),
    );

    // Keep 0-2 (question) + 2-5 (answer) → only the tail 5-8 is cut.
    expect(cuts, hasLength(1));
    expect(cuts.first.start, 5);
    expect(cuts.first.end, 8);
  });

  test('no content filter (or no match) leaves the clip uncut', () {
    final noKeywords = buildStyleCutRanges(
      segments: const [ClipTranscriptSegment(text: 'a', start: 0, end: 5)],
      durationSeconds: 5,
      plan: const EditStylePlan(),
    );
    final noMatch = buildStyleCutRanges(
      segments: const [ClipTranscriptSegment(text: 'สวัสดี', start: 0, end: 5)],
      durationSeconds: 5,
      plan: const EditStylePlan(keepKeywords: ['ราคา']),
    );

    expect(noKeywords, isEmpty);
    expect(noMatch, isEmpty);
  });

  test('estimates the final length after cuts and speed', () {
    final estimate = estimateResultSeconds(
      durationSeconds: 10,
      cutRanges: const [
        SilenceCutRange(start: 0, end: 3),
        SilenceCutRange(start: 6, end: 7),
      ],
      speed: 2,
    );

    // kept = 10 - (3 + 1) = 6, then /2 = 3.
    expect(estimate, closeTo(3, 0.001));
  });

  test('estimate subtracts the trimmed-away head and tail', () {
    final estimate = estimateResultSeconds(
      durationSeconds: 30,
      cutRanges: const [],
      trimStartSec: 5,
      trimEndSec: 15,
    );

    // Only the 5..15 window survives, no cuts, speed 1 -> 10 seconds.
    expect(estimate, closeTo(10, 0.001));
  });

  test('estimate counts only the cut slice inside the trim window', () {
    final estimate = estimateResultSeconds(
      durationSeconds: 30,
      cutRanges: const [
        // Half inside the 5..15 window (8..15 -> outside part 15..20 ignored).
        SilenceCutRange(start: 8, end: 20),
        // Fully outside the window -> ignored.
        SilenceCutRange(start: 0, end: 4),
      ],
      trimStartSec: 5,
      trimEndSec: 15,
    );

    // window = 10, removed inside window = (15 - 8) = 7, kept = 3.
    expect(estimate, closeTo(3, 0.001));
  });
}
