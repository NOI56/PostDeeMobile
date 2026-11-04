import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/caption_language.dart';

void main() {
  test('caption outputs include all 109 documented languages once', () {
    const documentedCodes = <String>{
      'af',
      'sq',
      'am',
      'ar',
      'hy',
      'as',
      'az',
      'eu',
      'be',
      'bn',
      'bs',
      'bg',
      'ca',
      'ceb',
      'zh',
      'co',
      'hr',
      'cs',
      'da',
      'dv',
      'nl',
      'en',
      'eo',
      'et',
      'fil',
      'fi',
      'fr',
      'fy',
      'gl',
      'ka',
      'de',
      'el',
      'gu',
      'ht',
      'ha',
      'haw',
      'hi',
      'he',
      'hmn',
      'hu',
      'is',
      'ig',
      'id',
      'ga',
      'it',
      'ja',
      'jv',
      'kn',
      'kk',
      'km',
      'ko',
      'kri',
      'ku',
      'ky',
      'lo',
      'la',
      'lv',
      'lt',
      'lb',
      'mk',
      'mg',
      'ms',
      'ml',
      'mt',
      'mi',
      'mr',
      'mni-Mtei',
      'mn',
      'my',
      'ne',
      'no',
      'ny',
      'or',
      'ps',
      'fa',
      'pl',
      'pt',
      'pa',
      'ro',
      'ru',
      'sm',
      'gd',
      'sr',
      'st',
      'sn',
      'sd',
      'si',
      'sk',
      'sl',
      'so',
      'es',
      'su',
      'sw',
      'sv',
      'tg',
      'ta',
      'te',
      'th',
      'tr',
      'uk',
      'ur',
      'ug',
      'uz',
      'vi',
      'cy',
      'xh',
      'yi',
      'yo',
      'zu',
    };
    expect(captionLanguageCatalog, hasLength(109));
    expect(captionOutputLanguages.keys.toSet(), documentedCodes);
    expect(captionLanguageCatalog.map((language) => language.code).toSet(),
        documentedCodes);
    for (final language in captionLanguageCatalog) {
      expect(language.nativeName.trim(), isNotEmpty, reason: language.code);
      expect(language.englishName.trim(), isNotEmpty, reason: language.code);
      expect(language.thaiName.trim(), isNotEmpty, reason: language.code);
      expect(captionOutputLanguages[language.code], language.nativeName);
    }
    expect(captionOutputLanguages, isNot(contains('auto')));
    expect(captionOutputLanguages.keys.where((code) => code.startsWith('zh')),
        ['zh']);
  });

  test('existing caption output values and native labels remain compatible',
      () {
    const originalChoices = <String, String>{
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
    for (final entry in originalChoices.entries) {
      expect(readCaptionOutputLanguage(entry.key), entry.key);
      expect(captionOutputLanguages[entry.key], entry.value);
    }
  });

  test('draft language aliases normalize without dropping Manipuri script', () {
    expect(readCaptionOutputLanguage(' iw '), 'he');
    expect(readCaptionOutputLanguage('IW'), 'he');
    expect(readCaptionOutputLanguage('tl'), 'fil');
    expect(readCaptionOutputLanguage('FIL'), 'fil');
    expect(readCaptionOutputLanguage('mni'), 'mni-Mtei');
    expect(readCaptionOutputLanguage(' MNI-MTEI '), 'mni-Mtei');
    expect(readCaptionOutputLanguage('RU'), 'ru');
    for (final value in <Object?>[
      null,
      '',
      42,
      <String>[],
      'unknown',
      'auto'
    ]) {
      expect(readCaptionOutputLanguage(value), 'auto', reason: '$value');
    }
  });

  test('search finds Thai, English, native names, codes and aliases', () {
    for (final query in <String>['Russian', ' รัสเซีย ', 'русский', ' RU ']) {
      expect(searchCaptionOutputLanguages(query).map((entry) => entry.code),
          contains('ru'),
          reason: query);
    }
    for (final query in <String>['Hebrew', 'עברית', 'iw']) {
      expect(searchCaptionOutputLanguages(query).map((entry) => entry.code),
          contains('he'),
          reason: query);
    }
    for (final query in <String>['Manipuri', 'mni', 'mni-Mtei']) {
      expect(searchCaptionOutputLanguages(query).map((entry) => entry.code),
          contains('mni-Mtei'),
          reason: query);
    }
    expect(searchCaptionOutputLanguages('tl').map((entry) => entry.code),
        contains('fil'));
    expect(searchCaptionOutputLanguages('no such language 12345'), isEmpty);
    expect(searchCaptionOutputLanguages('  '), hasLength(109));
    for (final language in captionLanguageCatalog) {
      final results = searchCaptionOutputLanguages(language.nativeName);
      expect(results.map((entry) => entry.code), contains(language.code));
      expect(results.map((entry) => entry.code).toSet(),
          hasLength(results.length));
    }
  });
}
