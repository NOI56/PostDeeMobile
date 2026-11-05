import '../../core/models/caption_language.dart';

/// Caption preferences edited against the retained original video. The group
/// owns the shared text; this small snapshot preserves guidance and language
/// without changing the source's media or publishing intent.
class ClipGroupCaptionContext {
  const ClipGroupCaptionContext({
    required this.aiGuidance,
    required this.captionLanguage,
  });

  final String aiGuidance;
  final String captionLanguage;

  Map<String, Object?> toJson() {
    validateClipGroupCaptionContext(this);
    return {
      'aiGuidance': aiGuidance,
      'captionLanguage': captionLanguage,
    };
  }

  factory ClipGroupCaptionContext.fromJson(Map<String, dynamic> json) {
    if (json['aiGuidance'] is! String || json['captionLanguage'] is! String) {
      throw const FormatException('Invalid clip group caption context');
    }
    final context = ClipGroupCaptionContext(
        aiGuidance: json['aiGuidance'] as String,
        captionLanguage: json['captionLanguage'] as String);
    validateClipGroupCaptionContext(context);
    return context;
  }

  @override
  bool operator ==(Object other) =>
      other is ClipGroupCaptionContext &&
      aiGuidance == other.aiGuidance &&
      captionLanguage == other.captionLanguage;

  @override
  int get hashCode => Object.hash(aiGuidance, captionLanguage);
}

void validateClipGroupCaptionContext(ClipGroupCaptionContext context) {
  // Coarse parsing bound from the entire journal's 262144-byte ceiling, not
  // a product limit on guidance. The repository still checks actual UTF-8 size.
  if (context.aiGuidance.length > 262144 ||
      (context.captionLanguage != 'auto' &&
          !captionOutputLanguages.containsKey(context.captionLanguage))) {
    throw const FormatException('Invalid clip group caption context');
  }
}
