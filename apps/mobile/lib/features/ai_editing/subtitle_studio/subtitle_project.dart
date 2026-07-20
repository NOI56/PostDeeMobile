enum SubtitleTimingMode { word, segment, estimated }

enum SubtitleAlignment { top, middle, bottom }

class SubtitleProjectValidationException implements Exception {
  const SubtitleProjectValidationException(this.message);

  final String message;

  @override
  String toString() => 'SubtitleProjectValidationException: $message';
}

class SubtitleWord {
  const SubtitleWord({
    required this.wordId,
    required this.text,
    required this.sourceStartMs,
    required this.sourceEndMs,
    this.separatorAfter = '',
  });

  final String wordId;
  final String text;
  final int sourceStartMs;
  final int sourceEndMs;
  final String separatorAfter;

  Map<String, Object?> toJson() => {
        'wordId': wordId,
        'text': text,
        'sourceStartMs': sourceStartMs,
        'sourceEndMs': sourceEndMs,
        'separatorAfter': separatorAfter,
      };

  factory SubtitleWord.fromJson(Map<String, Object?> json) => SubtitleWord(
        wordId: _requiredString(json, 'wordId'),
        text: _requiredString(json, 'text'),
        sourceStartMs: _requiredInt(json, 'sourceStartMs'),
        sourceEndMs: _requiredInt(json, 'sourceEndMs'),
        separatorAfter: _optionalString(json, 'separatorAfter') ?? '',
      );
}

class SubtitleCue {
  const SubtitleCue({
    required this.cueId,
    required this.sourceStartMs,
    required this.sourceEndMs,
    required this.text,
    required this.timingMode,
    List<SubtitleWord> words = const [],
    this.styleOverride,
    this.positionOverride,
    this.soundEffect,
  }) : _words = words;

  final String cueId;
  final int sourceStartMs;
  final int sourceEndMs;
  final String text;
  final List<SubtitleWord> _words;
  List<SubtitleWord> get words => List.unmodifiable(_words);
  final SubtitleTimingMode timingMode;
  final SubtitleStyle? styleOverride;
  final SubtitleAlignment? positionOverride;
  final String? soundEffect;

  SubtitleCue copyWith({
    String? cueId,
    int? sourceStartMs,
    int? sourceEndMs,
    String? text,
    List<SubtitleWord>? words,
    SubtitleTimingMode? timingMode,
    SubtitleStyle? styleOverride,
    SubtitleAlignment? positionOverride,
    String? soundEffect,
  }) =>
      SubtitleCue(
        cueId: cueId ?? this.cueId,
        sourceStartMs: sourceStartMs ?? this.sourceStartMs,
        sourceEndMs: sourceEndMs ?? this.sourceEndMs,
        text: text ?? this.text,
        words: words ?? this.words,
        timingMode: timingMode ?? this.timingMode,
        styleOverride: styleOverride ?? this.styleOverride,
        positionOverride: positionOverride ?? this.positionOverride,
        soundEffect: soundEffect ?? this.soundEffect,
      );

  Map<String, Object?> toJson() => {
        'cueId': cueId,
        'sourceStartMs': sourceStartMs,
        'sourceEndMs': sourceEndMs,
        'text': text,
        'words': words.map((word) => word.toJson()).toList(growable: false),
        'timingMode': timingMode.name,
        if (styleOverride != null) 'styleOverride': styleOverride!.toJson(),
        if (positionOverride != null)
          'positionOverride': positionOverride!.name,
        if (soundEffect != null) 'soundEffect': soundEffect,
      };

  factory SubtitleCue.fromJson(Map<String, Object?> json) => SubtitleCue(
        cueId: _requiredString(json, 'cueId'),
        sourceStartMs: _requiredInt(json, 'sourceStartMs'),
        sourceEndMs: _requiredInt(json, 'sourceEndMs'),
        text: _requiredString(json, 'text'),
        words: _objectList(json, 'words')
            .map(SubtitleWord.fromJson)
            .toList(growable: false),
        timingMode: _timingMode(_requiredString(json, 'timingMode')),
        styleOverride: _optionalObject(json, 'styleOverride') == null
            ? null
            : SubtitleStyle.fromJson(_optionalObject(json, 'styleOverride')!),
        positionOverride: _optionalString(json, 'positionOverride') == null
            ? null
            : _alignment(_optionalString(json, 'positionOverride')!),
        soundEffect: _optionalString(json, 'soundEffect'),
      );
}

class SubtitleStyle {
  const SubtitleStyle({
    required this.fontId,
    required this.fontWeight,
    required this.fontSize,
    required this.textColor,
    required this.activeWordColor,
    required this.outlineColor,
    required this.outlineWidth,
    required this.shadowColor,
    required this.shadowDepth,
    required this.alignment,
    required this.normalizedX,
    required this.normalizedY,
    required this.maxLines,
    this.animation = 'none',
  });

  static const defaults = SubtitleStyle(
    fontId: 'Prompt',
    fontWeight: 700,
    fontSize: 22,
    textColor: '#FFFFFF',
    activeWordColor: '#00E5A8',
    outlineColor: '#000000',
    outlineWidth: 2,
    shadowColor: '#000000',
    shadowDepth: 2,
    alignment: SubtitleAlignment.bottom,
    normalizedX: 0.5,
    normalizedY: 0.88,
    maxLines: 2,
  );

  final String fontId;
  final int fontWeight;
  final double fontSize;
  final String textColor;
  final String activeWordColor;
  final String outlineColor;
  final double outlineWidth;
  final String shadowColor;
  final double shadowDepth;
  final SubtitleAlignment alignment;
  final double normalizedX;
  final double normalizedY;
  final int maxLines;
  final String animation;

  Map<String, Object?> toJson() => {
        'fontId': fontId,
        'fontWeight': fontWeight,
        'fontSize': fontSize,
        'textColor': textColor,
        'activeWordColor': activeWordColor,
        'outlineColor': outlineColor,
        'outlineWidth': outlineWidth,
        'shadowColor': shadowColor,
        'shadowDepth': shadowDepth,
        'alignment': alignment.name,
        'normalizedX': normalizedX,
        'normalizedY': normalizedY,
        'maxLines': maxLines,
        'animation': animation,
      };

  factory SubtitleStyle.fromJson(Map<String, Object?> json) => SubtitleStyle(
        fontId: _requiredString(json, 'fontId'),
        fontWeight: _requiredInt(json, 'fontWeight'),
        fontSize: _requiredDouble(json, 'fontSize'),
        textColor: _requiredString(json, 'textColor'),
        activeWordColor: _requiredString(json, 'activeWordColor'),
        outlineColor: _requiredString(json, 'outlineColor'),
        outlineWidth: _requiredDouble(json, 'outlineWidth'),
        shadowColor: _requiredString(json, 'shadowColor'),
        shadowDepth: _requiredDouble(json, 'shadowDepth'),
        alignment: _alignment(_requiredString(json, 'alignment')),
        normalizedX: _requiredDouble(json, 'normalizedX'),
        normalizedY: _requiredDouble(json, 'normalizedY'),
        maxLines: _requiredInt(json, 'maxLines'),
        animation: _optionalString(json, 'animation') ?? 'none',
      );
}

class SubtitleCutRange {
  const SubtitleCutRange({
    required this.sourceStartMs,
    required this.sourceEndMs,
  });

  final int sourceStartMs;
  final int sourceEndMs;

  Map<String, Object?> toJson() => {
        'sourceStartMs': sourceStartMs,
        'sourceEndMs': sourceEndMs,
      };

  factory SubtitleCutRange.fromJson(Map<String, Object?> json) =>
      SubtitleCutRange(
        sourceStartMs: _requiredInt(json, 'sourceStartMs'),
        sourceEndMs: _requiredInt(json, 'sourceEndMs'),
      );
}

class SubtitleProject {
  SubtitleProject({
    required this.schemaVersion,
    required this.projectId,
    required this.sourceFingerprint,
    required this.sourceDurationMs,
    required this.language,
    required List<SubtitleCue> cues,
    required this.defaultStyle,
    required List<SubtitleCutRange> cutRanges,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  })  : cues = List.unmodifiable(cues),
        cutRanges = List.unmodifiable(cutRanges);

  final int schemaVersion;
  final String projectId;
  final String sourceFingerprint;
  final int sourceDurationMs;
  final String language;
  final List<SubtitleCue> cues;
  final SubtitleStyle defaultStyle;
  final List<SubtitleCutRange> cutRanges;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  SubtitleProject copyWith({
    int? schemaVersion,
    String? projectId,
    String? sourceFingerprint,
    int? sourceDurationMs,
    String? language,
    List<SubtitleCue>? cues,
    SubtitleStyle? defaultStyle,
    List<SubtitleCutRange>? cutRanges,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      SubtitleProject(
        schemaVersion: schemaVersion ?? this.schemaVersion,
        projectId: projectId ?? this.projectId,
        sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
        sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
        language: language ?? this.language,
        cues: cues ?? this.cues,
        defaultStyle: defaultStyle ?? this.defaultStyle,
        cutRanges: cutRanges ?? this.cutRanges,
        revision: revision ?? this.revision,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'projectId': projectId,
        'sourceFingerprint': sourceFingerprint,
        'sourceDurationMs': sourceDurationMs,
        'language': language,
        'cues': cues.map((cue) => cue.toJson()).toList(growable: false),
        'defaultStyle': defaultStyle.toJson(),
        'cutRanges':
            cutRanges.map((range) => range.toJson()).toList(growable: false),
        'revision': revision,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory SubtitleProject.fromJson(Map<String, Object?> json) {
    final project = SubtitleProject(
      schemaVersion: _requiredInt(json, 'schemaVersion'),
      projectId: _requiredString(json, 'projectId'),
      sourceFingerprint: _requiredString(json, 'sourceFingerprint'),
      sourceDurationMs: _requiredInt(json, 'sourceDurationMs'),
      language: _requiredString(json, 'language'),
      cues: _objectList(json, 'cues')
          .map(SubtitleCue.fromJson)
          .toList(growable: false),
      defaultStyle:
          SubtitleStyle.fromJson(_requiredObject(json, 'defaultStyle')),
      cutRanges: _objectList(json, 'cutRanges')
          .map(SubtitleCutRange.fromJson)
          .toList(growable: false),
      revision: _requiredInt(json, 'revision'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      updatedAt: _requiredDateTime(json, 'updatedAt'),
    );
    validateSubtitleProject(project);
    return project;
  }
}

void validateSubtitleProject(SubtitleProject project) {
  if (project.schemaVersion != 1) {
    throw const SubtitleProjectValidationException(
        'Unsupported schema version.');
  }
  _validateNonEmpty(project.projectId, 'project ID');
  _validateNonEmpty(project.sourceFingerprint, 'source fingerprint');
  _validateNonEmpty(project.language, 'language');
  if (project.sourceDurationMs <= 0) {
    throw const SubtitleProjectValidationException(
        'Source duration must be positive.');
  }
  if (project.revision < 0) {
    throw const SubtitleProjectValidationException(
        'Revision cannot be negative.');
  }
  _validateStyle(project.defaultStyle);

  final cueIds = <String>{};
  var previousCueEnd = 0;
  for (final cue in project.cues) {
    _validateNonEmpty(cue.cueId, 'cue ID');
    _validateNonEmpty(cue.text, 'cue text');
    if (!cueIds.add(cue.cueId)) {
      throw SubtitleProjectValidationException(
          'Duplicate cue ID: ${cue.cueId}.');
    }
    _validateRange(
      startMs: cue.sourceStartMs,
      endMs: cue.sourceEndMs,
      sourceDurationMs: project.sourceDurationMs,
      label: 'Cue ${cue.cueId}',
    );
    if (cue.sourceStartMs < previousCueEnd) {
      throw SubtitleProjectValidationException('Cues overlap at ${cue.cueId}.');
    }
    previousCueEnd = cue.sourceEndMs;
    if (cue.styleOverride != null) _validateStyle(cue.styleOverride!);

    if (cue.timingMode == SubtitleTimingMode.word) {
      if (cue.words.isEmpty) {
        throw SubtitleProjectValidationException(
            'Word-timed cue ${cue.cueId} has no words.');
      }
      _validateWords(cue);
    }
  }

  var previousCutEnd = 0;
  for (final range in project.cutRanges) {
    _validateRange(
      startMs: range.sourceStartMs,
      endMs: range.sourceEndMs,
      sourceDurationMs: project.sourceDurationMs,
      label: 'Cut range',
    );
    if (range.sourceStartMs < previousCutEnd) {
      throw const SubtitleProjectValidationException(
          'Cut ranges must not overlap.');
    }
    previousCutEnd = range.sourceEndMs;
  }
}

void _validateWords(SubtitleCue cue) {
  final wordIds = <String>{};
  var previousWordEnd = cue.sourceStartMs;
  for (final word in cue.words) {
    _validateNonEmpty(word.wordId, 'word ID');
    _validateNonEmpty(word.text, 'word text');
    if (!wordIds.add(word.wordId)) {
      throw SubtitleProjectValidationException(
          'Duplicate word ID: ${word.wordId}.');
    }
    if (word.sourceStartMs < cue.sourceStartMs ||
        word.sourceEndMs > cue.sourceEndMs ||
        word.sourceStartMs >= word.sourceEndMs ||
        word.sourceStartMs < previousWordEnd) {
      throw SubtitleProjectValidationException(
          'Invalid word timing in cue ${cue.cueId}.');
    }
    previousWordEnd = word.sourceEndMs;
  }
}

void _validateStyle(SubtitleStyle style) {
  _validateNonEmpty(style.fontId, 'font ID');
  if (style.fontWeight <= 0 ||
      !style.fontSize.isFinite ||
      style.fontSize <= 0 ||
      !style.outlineWidth.isFinite ||
      style.outlineWidth < 0 ||
      !style.shadowDepth.isFinite ||
      style.shadowDepth < 0 ||
      !style.normalizedX.isFinite ||
      !style.normalizedY.isFinite ||
      style.normalizedX < 0 ||
      style.normalizedX > 1 ||
      style.normalizedY < 0 ||
      style.normalizedY > 1 ||
      (style.maxLines != 1 && style.maxLines != 2)) {
    throw const SubtitleProjectValidationException('Invalid subtitle style.');
  }
  for (final color in [
    style.textColor,
    style.activeWordColor,
    style.outlineColor,
    style.shadowColor,
  ]) {
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(color)) {
      throw SubtitleProjectValidationException('Invalid colour: $color.');
    }
  }
}

void _validateRange({
  required int startMs,
  required int endMs,
  required int sourceDurationMs,
  required String label,
}) {
  if (startMs < 0 || endMs <= startMs || endMs > sourceDurationMs) {
    throw SubtitleProjectValidationException('$label has invalid timing.');
  }
}

void _validateNonEmpty(String value, String label) {
  if (value.trim().isEmpty) {
    throw SubtitleProjectValidationException('$label cannot be empty.');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw SubtitleProjectValidationException('$key must be a string.');
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw SubtitleProjectValidationException('$key must be a string.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw SubtitleProjectValidationException('$key must be an integer.');
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num && value.isFinite) return value.toDouble();
  throw SubtitleProjectValidationException('$key must be a finite number.');
}

Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) return value;
  throw SubtitleProjectValidationException('$key must be an object.');
}

Map<String, Object?>? _optionalObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is Map<String, Object?>) {
    return value as Map<String, Object?>?;
  }
  throw SubtitleProjectValidationException('$key must be an object.');
}

List<Map<String, Object?>> _objectList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw SubtitleProjectValidationException('$key must be a list.');
  }
  return value.map((item) {
    if (item is Map<String, Object?>) return item;
    throw SubtitleProjectValidationException('$key must contain objects.');
  }).toList(growable: false);
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw SubtitleProjectValidationException('$key must be an ISO date-time.');
  }
  return parsed.toUtc();
}

SubtitleTimingMode _timingMode(String value) => switch (value) {
      'word' => SubtitleTimingMode.word,
      'segment' => SubtitleTimingMode.segment,
      'estimated' => SubtitleTimingMode.estimated,
      _ => throw SubtitleProjectValidationException(
          'Unsupported timing mode: $value.'),
    };

SubtitleAlignment _alignment(String value) => switch (value) {
      'top' => SubtitleAlignment.top,
      'middle' => SubtitleAlignment.middle,
      'bottom' => SubtitleAlignment.bottom,
      _ => throw SubtitleProjectValidationException(
          'Unsupported alignment: $value.'),
    };
