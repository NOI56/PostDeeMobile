/// Product choices for caption output, independent of the clip's spoken language.
/// This list does not describe or guarantee audio recognition coverage.
const captionOutputLanguages = <String, String>{
  'th': 'ไทย',
  'en': 'English',
  'zh': '中文',
  'ja': '日本語',
  'ko': '한국어',
  'vi': 'Tiếng Việt',
  'id': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu',
  'lo': 'ລາວ',
  'km': 'ខ្មែរ',
  'my': 'မြန်မာ',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'pt': 'Português',
  'ar': 'العربية',
  'hi': 'हिन्दी',
};

/// Preserve old drafts and drafts from a newer app without losing their content.
String readCaptionOutputLanguage(Object? value) =>
    value is String && captionOutputLanguages.containsKey(value)
        ? value
        : 'auto';
