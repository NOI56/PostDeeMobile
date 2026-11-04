import 'caption_language_catalog.generated.dart';

export 'caption_language_catalog.generated.dart'
    show CaptionLanguageDetails, captionLanguageCatalog;

/// Product choices for text output, independent of the clip's spoken language.
/// Google's text-language list does not guarantee audio recognition coverage.
const captionOutputLanguages = captionLanguageNativeNames;

/// Preserve old drafts, normalize aliases, and safely read future drafts.
String readCaptionOutputLanguage(Object? value) => value is String
    ? captionLanguageAliases[value.trim().toLowerCase()] ?? 'auto'
    : 'auto';

CaptionLanguageDetails? captionOutputLanguageDetails(String value) {
  final code = readCaptionOutputLanguage(value);
  for (final language in captionLanguageCatalog) {
    if (language.code == code) return language;
  }
  return null;
}

/// Search app labels, native names, codes and compatibility aliases together.
List<CaptionLanguageDetails> searchCaptionOutputLanguages(String query) {
  final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
  return captionLanguageCatalog.where((language) {
    final searchable = [
      language.code,
      language.nativeName,
      language.englishName,
      language.thaiName,
      ...language.aliases,
    ].join(' ').toLowerCase();
    return terms.every(searchable.contains);
  }).toList(growable: false);
}
