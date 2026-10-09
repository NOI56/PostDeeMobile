enum CaptionWritingTone {
  auto('auto', 'อัตโนมัติ'),
  friendly('friendly', 'เป็นกันเอง'),
  playful('playful', 'สนุก/ตลก'),
  directReview('direct_review', 'รีวิวตรง ๆ'),
  softSell('soft_sell', 'ขายแบบนุ่มนวล');

  const CaptionWritingTone(this.value, this.label);
  final String value;
  final String label;
}

enum CaptionWritingLength {
  auto('auto', 'อัตโนมัติ'),
  short('short', 'สั้น กระชับ'),
  medium('medium', 'เล่าเพิ่มอีกนิด');

  const CaptionWritingLength(this.value, this.label);
  final String value;
  final String label;
}

enum CaptionWritingEmoji {
  auto('auto', 'อัตโนมัติ'),
  none('none', 'ไม่ใช้อีโมจิ'),
  light('light', 'ใช้เล็กน้อย');

  const CaptionWritingEmoji(this.value, this.label);
  final String value;
  final String label;
}

/// Examples describe writing style only, never facts about the new clip.
class CaptionWritingStyle {
  const CaptionWritingStyle({
    this.tone = CaptionWritingTone.auto,
    this.length = CaptionWritingLength.auto,
    this.emoji = CaptionWritingEmoji.auto,
    this.examples = const [],
  });

  final CaptionWritingTone tone;
  final CaptionWritingLength length;
  final CaptionWritingEmoji emoji;
  final List<String> examples;

  String get summary => [tone.label, length.label, emoji.label].join(' · ');

  CaptionWritingStyle copyWith({
    CaptionWritingTone? tone,
    CaptionWritingLength? length,
    CaptionWritingEmoji? emoji,
    List<String>? examples,
  }) =>
      CaptionWritingStyle(
        tone: tone ?? this.tone,
        length: length ?? this.length,
        emoji: emoji ?? this.emoji,
        examples: _normalizeExamples(examples ?? this.examples),
      );

  Map<String, Object?> toJson() => {
        'tone': tone.value,
        'length': length.value,
        'emoji': emoji.value,
        'examples': _normalizeExamples(examples),
      };

  factory CaptionWritingStyle.fromJson(Map<String, Object?> json) =>
      CaptionWritingStyle(
        tone: CaptionWritingTone.values
                .where((value) => value.value == json['tone'])
                .firstOrNull ??
            CaptionWritingTone.auto,
        length: CaptionWritingLength.values
                .where((value) => value.value == json['length'])
                .firstOrNull ??
            CaptionWritingLength.auto,
        emoji: CaptionWritingEmoji.values
                .where((value) => value.value == json['emoji'])
                .firstOrNull ??
            CaptionWritingEmoji.auto,
        examples: _normalizeExamples(json['examples']),
      );
}

List<String> _normalizeExamples(Object? value) {
  if (value is! List) return const [];
  final examples = <String>[];
  for (final item in value) {
    if (item is! String) continue;
    var text = item.trim();
    if (text.length > 500) {
      text = text.substring(0, 500);
      final last = text.codeUnitAt(text.length - 1);
      if (last >= 0xd800 && last <= 0xdbff) {
        text = text.substring(0, text.length - 1);
      }
      text = text.trimRight();
    }
    if (text.isEmpty || examples.contains(text)) continue;
    examples.add(text);
    if (examples.length == 3) break;
  }
  return List.unmodifiable(examples);
}

class CaptionWritingStyleProfile {
  const CaptionWritingStyleProfile({
    this.style = const CaptionWritingStyle(),
    this.rememberEdits = true,
  });

  final CaptionWritingStyle style;
  final bool rememberEdits;

  CaptionWritingStyle get forGeneration =>
      rememberEdits ? style.copyWith() : style.copyWith(examples: const []);

  CaptionWritingStyleProfile copyWith({
    CaptionWritingStyle? style,
    bool? rememberEdits,
  }) =>
      CaptionWritingStyleProfile(
        style: style ?? this.style,
        rememberEdits: rememberEdits ?? this.rememberEdits,
      );

  CaptionWritingStyleProfile withLearnedCaption(String caption) {
    if (!rememberEdits || caption.trim().isEmpty) return this;
    return copyWith(
        style: style.copyWith(examples: [caption, ...style.examples]));
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'style': style.toJson(),
        'rememberEdits': rememberEdits,
      };

  factory CaptionWritingStyleProfile.fromJson(Map<String, Object?> json) {
    final style = json['style'];
    if (json['version'] != 1 || style is! Map) {
      return const CaptionWritingStyleProfile();
    }
    return CaptionWritingStyleProfile(
      style: CaptionWritingStyle.fromJson(Map<String, Object?>.from(style)),
      rememberEdits: json['rememberEdits'] != false,
    );
  }
}
