import '../../core/network/postdee_api_client.dart';
import 'subtitle_burn_video_processor.dart';

/// Grouping for the auto-edit style gallery.
enum EditStyleGroup { hardSell, storytelling, engagement, custom }

extension EditStyleGroupLabel on EditStyleGroup {
  String get label {
    switch (this) {
      case EditStyleGroup.hardSell:
        return 'เน้นยอดขาย';
      case EditStyleGroup.storytelling:
        return 'สร้างตัวตน · เล่าเรื่อง';
      case EditStyleGroup.engagement:
        return 'มีส่วนร่วม · เอนเตอร์เทน';
      case EditStyleGroup.custom:
        return 'สั่ง AI เอง';
    }
  }
}

/// Maps a style to the editing mechanisms PostDee can actually apply today:
/// pacing (auto silence cut), speed, and keyword-based content keep. Styles
/// that truly need audio/visual AI carry [requiresAi] so the UI can be honest.
class EditStylePlan {
  const EditStylePlan({
    this.silenceMinGapSec,
    this.speed = 1.0,
    this.keepKeywords = const [],
    this.keepFollowingSegment = false,
    this.requiresAi = false,
    this.isCustomPrompt = false,
    this.filterIndex = 0,
    this.volume = 1.0,
    this.comingSoon = false,
  });

  /// Auto silence-cut threshold. null = do not auto-cut (keep natural pauses).
  final double? silenceMinGapSec;
  final double speed;

  /// Color-grade look index into the editor's filter list (0 = ปกติ, 1 = สดใส,
  /// 4 = อบอุ่น, ...) so each style has a distinct feel, not just pacing.
  final int filterIndex;

  /// Output volume multiplier (e.g. ASMR boosts the satisfying sounds).
  final double volume;

  /// Thai keywords for "keep only relevant segments, cut the rest". Empty = no
  /// content filtering (pacing only).
  final List<String> keepKeywords;

  /// For Q&A: also keep the segment right after a matched question.
  final bool keepFollowingSegment;

  /// Style depends on audio/visual analysis we don't have yet; only a pacing
  /// fallback is applied for now.
  final bool requiresAi;

  /// Style 10 — free-form prompt (Pro). Execution needs an LLM backend.
  final bool isCustomPrompt;

  /// Genuinely cannot work yet: it needs non-speech audio or visual analysis we
  /// don't have (e.g. laughter detection, sound texture). The UI must not
  /// pretend to apply it — show a "coming soon" message instead.
  final bool comingSoon;

  /// Whether the style relies on the spoken transcript (keyword keep or silence
  /// cut). These need real on-device transcription to do anything meaningful.
  bool get needsSpeech => keepKeywords.isNotEmpty || silenceMinGapSec != null;
}

class EditStyle {
  const EditStyle({
    required this.id,
    required this.emoji,
    required this.name,
    required this.group,
    required this.editingNote,
    required this.suitableFor,
    required this.plan,
  });

  final String id;
  final String emoji;
  final String name;
  final EditStyleGroup group;
  final String editingNote;
  final String suitableFor;
  final EditStylePlan plan;
}

/// The user's chosen style plus any free-form prompt (custom style).
class EditStyleSelection {
  const EditStyleSelection({required this.style, this.prompt});

  final EditStyle style;
  final String? prompt;
}

/// The 10 auto-edit styles. Copy follows the product brief.
const List<EditStyle> editStyles = [
  EditStyle(
    id: 'fast_review',
    emoji: '⚡',
    name: 'ป้ายยาฉับไว',
    group: EditStyleGroup.hardSell,
    editingNote: 'ตัดช่วงเงียบ/ช่วงหายใจออกให้กระชับและเร็วที่สุด (Jump Cut)',
    suitableFor: 'รีวิวสินค้า Affiliate ที่อยากให้คนกดตะกร้าทันที',
    plan: EditStylePlan(silenceMinGapSec: 0.4, filterIndex: 1),
  ),
  EditStyle(
    id: 'flash_sale',
    emoji: '🏷️',
    name: 'ชี้เป้าโปรเด็ด',
    group: EditStyleGroup.hardSell,
    editingNote: 'เก็บเฉพาะท่อนที่พูดถึงราคา/ส่วนลด/โปรโมชัน สร้างความเร่งด่วน',
    suitableFor: 'แคมเปญ 11.11, 12.12 หรือไลฟ์ลดราคา',
    plan: EditStylePlan(
      silenceMinGapSec: 0.6,
      filterIndex: 1,
      keepKeywords: [
        'ราคา',
        'ลด',
        'บาท',
        'โปร',
        'ส่วนลด',
        'ฟรี',
        'ถูก',
        'คุ้ม',
        'แถม',
        'ส่งฟรี',
      ],
    ),
  ),
  EditStyle(
    id: 'before_after',
    emoji: '🔁',
    name: 'Before & After',
    group: EditStyleGroup.hardSell,
    editingNote: 'สลับช่วง "ปัญหา (Before)" กับ "ผลลัพธ์ (After)" ตัดน้ำทิ้ง',
    suitableFor: 'สกินแคร์, ครีมลดสิว, น้ำยาทำความสะอาด, อาหารเสริม',
    plan: EditStylePlan(
      requiresAi: true,
      filterIndex: 1,
      keepKeywords: ['ก่อน', 'หลัง', 'เคย', 'เดิม', 'ตอนนี้', 'เปลี่ยน', 'ผลลัพธ์'],
    ),
  ),
  EditStyle(
    id: 'vlog',
    emoji: '🌿',
    name: 'เล่าเรื่องชิลๆ',
    group: EditStyleGroup.storytelling,
    editingNote: 'เก็บจังหวะหายใจไว้บ้างให้เป็นธรรมชาติ นำเสนอสินค้าเนียนๆ',
    suitableFor: 'สายแต่งบ้าน, จัดโต๊ะคอม, แม่บ้านทำอาหาร',
    plan: EditStylePlan(),
  ),
  EditStyle(
    id: 'tutorial',
    emoji: '🧩',
    name: 'ฮาวทู / สอนใช้งาน',
    group: EditStyleGroup.storytelling,
    editingNote: 'คัดจังหวะ "ลงมือทำ" เป็นสเตป 1-2-3 ตัดช่วงวกวน/รอคอย',
    suitableFor: 'สินค้าไอที, เครื่องใช้ไฟฟ้า, สูตรทำอาหาร',
    plan: EditStylePlan(
      silenceMinGapSec: 0.8,
      keepKeywords: ['ขั้นตอน', 'ก่อน', 'จากนั้น', 'ต่อไป', 'เสร็จ', 'วิธี'],
    ),
  ),
  EditStyle(
    id: 'qa',
    emoji: '💬',
    name: 'ตอบคอมเมนต์ Q&A',
    group: EditStyleGroup.storytelling,
    editingNote: 'หยิบท่อน "คำถาม" ขึ้นก่อน แล้วตามด้วยท่อน "คำตอบ"',
    suitableFor: 'แม่ค้าอัดคลิปตอบข้อสงสัย ปลดล็อกความลังเลก่อนซื้อ',
    plan: EditStylePlan(
      keepFollowingSegment: true,
      keepKeywords: [
        'ไหม',
        'มั้ย',
        'อะไร',
        'ยังไง',
        'ทำไม',
        'เท่าไหร่',
        'กี่',
        'หรือเปล่า',
      ],
    ),
  ),
  EditStyle(
    id: 'comedy',
    emoji: '😂',
    name: 'ฮาโบ๊ะบ๊ะ',
    group: EditStyleGroup.engagement,
    editingNote: 'เก็บจังหวะหัวเราะ/หลุดฮา/รีแอคชันตกใจ สร้างสีสัน',
    suitableFor: 'สายฮา หรือคลิปไวรัลให้คนคอมเมนต์เยอะ',
    plan: EditStylePlan(requiresAi: true, comingSoon: true, filterIndex: 1),
  ),
  EditStyle(
    id: 'asmr',
    emoji: '🎧',
    name: 'ASMR / ฟินๆ',
    group: EditStyleGroup.engagement,
    editingNote: 'เน้นเสียงแกะกล่อง/เคี้ยวกรอบ/รูดซิป ตัดท่อนเสียงรบกวน',
    suitableFor: 'ของกิน, แกะกล่อง (Unboxing), สินค้าพื้นผิวน่าสัมผัส',
    plan: EditStylePlan(requiresAi: true, comingSoon: true, volume: 1.3),
  ),
  EditStyle(
    id: 'aesthetic',
    emoji: '🕯️',
    name: 'มินิมอลสายคาเฟ่',
    group: EditStyleGroup.engagement,
    editingNote: 'เน้นภาพสวย โทนอุ่นละมุนให้ดูแพง',
    suitableFor: 'เสื้อผ้าแฟชั่น, เครื่องประดับ, คาเฟ่พรีเมียม',
    plan: EditStylePlan(filterIndex: 4),
  ),
  EditStyle(
    id: 'custom_prompt',
    emoji: '✨',
    name: 'สั่ง AI ตัดเอง',
    group: EditStyleGroup.custom,
    editingNote: 'พิมพ์สั่ง AI ได้ดั่งใจ เช่น "ตัดเฉพาะตอนใส่เสื้อแดง เหลือ 45 วิ"',
    suitableFor: 'ไม้ตายของแพ็กเกจ Pro 299 ให้ตัดได้อิสระ',
    plan: EditStylePlan(isCustomPrompt: true),
  ),
];

/// True when [text] contains any of [keywords] (case-insensitive). Pure.
bool segmentMatchesKeywords(String text, List<String> keywords) {
  if (keywords.isEmpty) {
    return false;
  }

  final haystack = text.toLowerCase();

  for (final keyword in keywords) {
    final needle = keyword.trim().toLowerCase();
    if (needle.isNotEmpty && haystack.contains(needle)) {
      return true;
    }
  }

  return false;
}

/// Builds the absolute-second cut ranges for a keyword-keep style: keep the
/// matching segments (plus the following one for Q&A), and cut every other
/// span of the clip. Returns `[]` when the style does no content filtering, or
/// when nothing matched (safe fallback = keep everything). Pure + testable.
List<SilenceCutRange> buildStyleCutRanges({
  required List<ClipTranscriptSegment> segments,
  required double durationSeconds,
  required EditStylePlan plan,
}) {
  if (plan.keepKeywords.isEmpty ||
      segments.isEmpty ||
      durationSeconds <= 0) {
    return const [];
  }

  final keep = <int>{};
  for (var i = 0; i < segments.length; i += 1) {
    if (segmentMatchesKeywords(segments[i].text, plan.keepKeywords)) {
      keep.add(i);
      if (plan.keepFollowingSegment && i + 1 < segments.length) {
        keep.add(i + 1);
      }
    }
  }

  if (keep.isEmpty) {
    return const [];
  }

  // Merge kept segment intervals (sorted by index → by time).
  final merged = <List<double>>[];
  for (final index in keep.toList()..sort()) {
    final start = segments[index].start;
    final end = segments[index].end;

    if (merged.isNotEmpty && start <= merged.last[1] + 0.001) {
      if (end > merged.last[1]) {
        merged.last[1] = end;
      }
    } else {
      merged.add([start, end]);
    }
  }

  // The complement of the kept intervals within [0, duration] is what we cut.
  final cuts = <SilenceCutRange>[];
  var cursor = 0.0;
  for (final interval in merged) {
    final keptStart = interval[0].clamp(0.0, durationSeconds);
    if (keptStart > cursor + 0.05) {
      cuts.add(SilenceCutRange(start: cursor, end: keptStart));
    }
    cursor = interval[1].clamp(0.0, durationSeconds);
  }
  if (durationSeconds > cursor + 0.05) {
    cuts.add(SilenceCutRange(start: cursor, end: durationSeconds));
  }

  return cuts;
}

/// Estimated final length after cuts and speed change. Pure + testable.
double estimateResultSeconds({
  required double durationSeconds,
  required List<SilenceCutRange> cutRanges,
  double speed = 1.0,
}) {
  final cut = cutRanges.fold<double>(0, (sum, r) => sum + (r.end - r.start));
  final kept = (durationSeconds - cut).clamp(0.0, durationSeconds);
  final effectiveSpeed = speed <= 0 ? 1.0 : speed;

  return kept / effectiveSpeed;
}
