import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';

void main() {
  test('formats SRT timestamps as HH:MM:SS,mmm', () {
    expect(formatSrtTimestamp(0), '00:00:00,000');
    expect(formatSrtTimestamp(3.2), '00:00:03,200');
    expect(formatSrtTimestamp(65.5), '00:01:05,500');
    expect(formatSrtTimestamp(3661.001), '01:01:01,001');
  });

  test('builds a valid SRT body from transcript segments', () {
    final srt = buildSrtContent(const [
      SubtitleSegment(text: 'สวัสดีค่ะ', start: 0, end: 3.2),
      SubtitleSegment(text: ' ขายดีมาก ', start: 3.2, end: 6),
    ]);

    expect(srt, contains('1\n00:00:00,000 --> 00:00:03,200\nสวัสดีค่ะ'));
    expect(srt, contains('2\n00:00:03,200 --> 00:00:06,000\nขายดีมาก'));
  });

  test('skips empty subtitle segments', () {
    final srt = buildSrtContent(const [
      SubtitleSegment(text: '   ', start: 0, end: 1),
    ]);

    expect(srt.trim(), isEmpty);
  });

  test('flattens explicit subtitle line breaks before burn-in', () {
    final srt = buildSrtContent(const [
      SubtitleSegment(text: 'ขายดีมาก\nส่งฟรี', start: 0, end: 2),
    ]);

    expect(srt, contains('ขายดีมาก ส่งฟรี'));
    expect(srt, isNot(contains('ขายดีมาก\nส่งฟรี')));
  });

  test('keeps every Thai upper and lower mark attached in SRT output', () {
    const thaiMarkCoverage =
        'กั กิ กี กึ กื กุ กู ก็ ก่ ก้ ก๊ ก๋ ก์ กำ กิ่ กี้ กึ๊ กื๋ กุ่ กู้';
    final srt = buildSrtContent(const [
      SubtitleSegment(text: thaiMarkCoverage, start: 0, end: 3),
    ]);

    expect(srt, contains(thaiMarkCoverage));
  });

  test('lifts only Thai tone marks stacked above upper vowels or sara am', () {
    expect(
      liftStackedThaiToneMarksForRender('ที่ นี้ ชิ้น ขึ้น ซ้ำ ปิ๊ง'),
      'ที\uE000 นี\uE001 ชิ\uE001น ขึ\uE001น ซ\uE001ำ ปิ\uE002ง',
    );
    expect(
      liftStackedThaiToneMarksForRender('เก่ง กุ้ง จ๋า ก๋วยเตี๋ยว'),
      'เก่ง กุ้ง จ๋า ก๋วยเตี\uE003ยว',
    );
    expect(
      liftStackedThaiToneMarksForRender('ขายดี Weekend Market'),
      'ขายดี Weekend Market',
    );
  });

  test('lifts every Thai tone mark above every supported upper mark', () {
    const upperMarks = [
      0x0E31,
      0x0E34,
      0x0E35,
      0x0E36,
      0x0E37,
      0x0E47,
      0x0E4D,
    ];

    for (final upperMark in upperMarks) {
      for (var toneMark = 0x0E48; toneMark <= 0x0E4B; toneMark += 1) {
        final input = String.fromCharCodes([0x0E01, upperMark, toneMark]);
        final expected = String.fromCharCodes([
          0x0E01,
          upperMark,
          0xE000 + toneMark - 0x0E48,
        ]);

        expect(liftStackedThaiToneMarksForRender(input), expected);
      }
    }
  });

  test('lifts a tone before precomposed or decomposed sara am', () {
    final precomposed = String.fromCharCodes([0x0E19, 0x0E49, 0x0E33]);
    final decomposed = String.fromCharCodes([0x0E19, 0x0E49, 0x0E4D, 0x0E32]);
    final expectedPrecomposed = String.fromCharCodes([0x0E19, 0xE001, 0x0E33]);
    final expectedDecomposed =
        String.fromCharCodes([0x0E19, 0xE001, 0x0E4D, 0x0E32]);

    expect(
      liftStackedThaiToneMarksForRender(precomposed),
      expectedPrecomposed,
    );
    expect(
      liftStackedThaiToneMarksForRender(decomposed),
      expectedDecomposed,
    );
  });

  test('protects marks only when the matching mark-safe font asset is used',
      () {
    expect(
      shouldProtectStackedThaiMarksForRender(
        fontName: postDeeSubtitleThaiFontName,
        fontAssetPath: postDeeSubtitleThaiFontAssetPath,
      ),
      isTrue,
    );
    expect(
      shouldProtectStackedThaiMarksForRender(
        fontName: postDeeSubtitleAnuphanFontName,
        fontAssetPath:
            'assets/fonts/postdee_subtitle/PostDeeSubtitleAnuphan-Bold.ttf',
      ),
      isTrue,
    );
    expect(
      shouldProtectStackedThaiMarksForRender(
        fontName: postDeeSubtitlePromptFontName,
        fontAssetPath:
            'assets/fonts/postdee_subtitle/PostDeeSubtitlePrompt-Black.ttf',
      ),
      isTrue,
    );
    expect(
      shouldProtectStackedThaiMarksForRender(
        fontName: postDeeSubtitleThaiFontName,
        fontAssetPath: 'assets/fonts/anuphan/Anuphan-Bold.ttf',
      ),
      isFalse,
    );
    expect(
      shouldProtectStackedThaiMarksForRender(
        fontName: 'Prompt',
        fontAssetPath:
            'assets/fonts/postdee_subtitle/PostDeeSubtitlePrompt-Bold.ttf',
      ),
      isFalse,
    );
  });

  test('builds mark-safe SRT only for the PostDee subtitle render font', () {
    const segments = [
      SubtitleSegment(text: 'มีอาหารที่ ซ้ำแล้ว', start: 0, end: 2),
    ];

    final normal = buildSrtContent(segments);
    final protected = buildSrtContent(
      segments,
      protectStackedThaiMarks: true,
    );

    expect(normal, contains('มีอาหารที่ ซ้ำแล้ว'));
    expect(protected, contains('มีอาหารที\uE000 ซ\uE001ำแล้ว'));
    expect(protected, isNot(contains('มีอาหารที่ ซ้ำแล้ว')));
  });

  test('formats ASS timestamps as H:MM:SS.cc', () {
    expect(formatAssTimestamp(0), '0:00:00.00');
    expect(formatAssTimestamp(3.2), '0:00:03.20');
    expect(formatAssTimestamp(65.55), '0:01:05.55');
    expect(formatAssTimestamp(3661.01), '1:01:01.01');
  });

  test('does not emit ASS events that collapse to zero duration', () {
    final ass = buildSubtitleFileContent(
      const [
        SubtitleSegment(text: 'too short', start: 1.241, end: 1.244),
        SubtitleSegment(text: 'normal cue', start: 2, end: 3),
      ],
      subtitleAnimation: 'pop',
    ).content;
    final dialogues =
        ass.split('\n').where((line) => line.startsWith('Dialogue:')).toList();

    expect(dialogues, hasLength(1));
    expect(dialogues.single, contains('normal cue'));
    expect(dialogues.single, isNot(contains('too short')));
    expect(dialogues.single, contains('0:00:02.00,0:00:03.00'));
  });

  test('keeps active text and animation edges after collapsed word events', () {
    const segment = SubtitleSegment(
      text: 'a b c',
      start: 1.241,
      end: 2.244,
      words: [
        SubtitleWordTiming(text: 'a', start: 1.241, end: 1.244),
        SubtitleWordTiming(text: 'b', start: 1.244, end: 2.241),
        SubtitleWordTiming(text: 'c', start: 2.241, end: 2.244),
      ],
    );

    final fade = buildActiveWordAssContent(
      const [segment],
      activeWordColor: '#FF0000',
      subtitleAnimation: 'fade',
    );
    final fadeDialogues =
        fade.split('\n').where((line) => line.startsWith('Dialogue:')).toList();
    expect(fadeDialogues, hasLength(1));
    expect(fadeDialogues.single, contains('0:00:01.24,0:00:02.24'));
    expect(
      fadeDialogues.single,
      contains(r'a {\1c&H000000FF&}b{\1c&H00FFFFFF&} c'),
    );
    expect(fadeDialogues.single, contains(r'{\fad(180,180)}'));

    final pop = buildActiveWordAssContent(
      const [segment],
      activeWordColor: '#FF0000',
      subtitleAnimation: 'pop',
    );
    final popDialogues =
        pop.split('\n').where((line) => line.startsWith('Dialogue:')).toList();
    expect(popDialogues, hasLength(1));
    expect(popDialogues.single, contains(r'\fscx78'));
    expect(popDialogues.single, contains(r'\fscx103'));
  });

  test('builds active-word ASS while keeping the full sentence visible', () {
    final ass = buildActiveWordAssContent(
      const [
        SubtitleSegment(
          text: 'ขายดีมาก',
          start: 0,
          end: 2,
          words: [
            SubtitleWordTiming(text: 'ขาย', start: 0.2, end: 0.8),
            SubtitleWordTiming(text: 'ดีมาก', start: 0.8, end: 1.5),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
    );

    expect(
      ass,
      contains('Dialogue: 0,0:00:00.00,0:00:00.20,Default,,0,0,0,,ขายดีมาก'),
    );
    expect(
      ass,
      contains(
        r'Dialogue: 0,0:00:00.20,0:00:00.80,Default,,0,0,0,,'
        r'{\1c&H000000FF&}ขาย{\1c&H00FFFFFF&}ดีมาก',
      ),
    );
    expect(
      ass,
      contains(
        r'Dialogue: 0,0:00:00.80,0:00:01.50,Default,,0,0,0,,'
        r'ขาย{\1c&H000000FF&}ดีมาก{\1c&H00FFFFFF&}',
      ),
    );
    expect(
      ass,
      contains('Dialogue: 0,0:00:01.50,0:00:02.00,Default,,0,0,0,,ขายดีมาก'),
    );
  });

  test('uses active timing and static cues together in one ASS file', () {
    final ass = buildActiveWordAssContent(
      const [
        SubtitleSegment(
          text: 'คำแรก',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'คำ', start: 0, end: 0.5),
            SubtitleWordTiming(text: 'แรก', start: 0.5, end: 1),
          ],
        ),
        SubtitleSegment(text: 'ประโยคปกติ', start: 1, end: 2),
      ],
      activeWordColor: '#00E3A4',
    );

    expect(
      ass,
      contains(r'{\1c&H00A4E300&}คำ{\1c&H00FFFFFF&}แรก'),
    );
    expect(
      ass,
      contains(
        'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,ประโยคปกติ',
      ),
    );
  });

  test('escapes user text before placing it in ASS dialogue events', () {
    final ass = buildActiveWordAssContent(
      const [
        SubtitleSegment(
          text: r'ก่อน{\bord20}หลัง\Nต่อ,จบ',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'หลัง', start: 0.2, end: 0.8),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
    );

    expect(ass, isNot(contains(r'{\bord20}')));
    expect(ass, isNot(contains(r'\Nต่อ')));
    expect(ass, contains(r'ก่อน｛＼bord20｝'));
    expect(ass, contains(r'หลัง＼Nต่อ,จบ'));
  });

  test('applies mark-safe Thai glyphs to active-word ASS text', () {
    final ass = buildActiveWordAssContent(
      const [
        SubtitleSegment(
          text: 'มีอาหารที่นี่',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'ที่', start: 0, end: 0.5),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
      protectStackedThaiMarks: true,
    );

    expect(ass, contains('ที\uE000'));
    expect(ass, isNot(contains('ที่')));
  });

  test('selects ASS only when active color and a valid timed cue exist', () {
    final active = buildSubtitleFileContent(
      const [
        SubtitleSegment(
          text: 'ขายดี',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'ขาย', start: 0, end: 0.5),
            SubtitleWordTiming(text: 'ดี', start: 0.5, end: 1),
          ],
        ),
        SubtitleSegment(text: 'ส่งฟรี', start: 1, end: 2),
      ],
      activeWordColor: '#FF0000',
    );
    final noColor = buildSubtitleFileContent(
      const [
        SubtitleSegment(
          text: 'ขายดี',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'ขาย', start: 0, end: 0.5),
            SubtitleWordTiming(text: 'ดี', start: 0.5, end: 1),
          ],
        ),
      ],
    );
    final invalidTiming = buildSubtitleFileContent(
      const [
        SubtitleSegment(
          text: 'ขายดี',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'ขาย', start: 0.5, end: 0.5),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
    );

    expect(active.fileName, 'captions.ass');
    expect(active.usesActiveWordTiming, isTrue);
    expect(active.content, startsWith('[Script Info]'));
    expect(noColor.fileName, 'captions.srt');
    expect(noColor.usesActiveWordTiming, isFalse);
    expect(noColor.content, contains('00:00:00,000 --> 00:00:01,000'));
    expect(invalidTiming.fileName, 'captions.srt');
    expect(invalidTiming.usesActiveWordTiming, isFalse);
  });

  test('falls back the whole cue when word timing is incomplete or unsafe', () {
    const validCue = SubtitleSegment(
      text: 'พร้อมใช้',
      start: 2,
      end: 3,
      words: [
        SubtitleWordTiming(text: 'พร้อม', start: 2, end: 2.5),
        SubtitleWordTiming(text: 'ใช้', start: 2.5, end: 3),
      ],
    );
    const unsafeCues = <SubtitleSegment>[
      SubtitleSegment(
        text: 'ขายดีมาก',
        start: 0,
        end: 1,
        words: [
          // "ดีมาก" is missing, so a partial highlight would be misleading.
          SubtitleWordTiming(text: 'ขาย', start: 0, end: 0.5),
        ],
      ),
      SubtitleSegment(
        text: 'ขายดี',
        start: 0,
        end: 1,
        words: [
          SubtitleWordTiming(text: 'ขาย', start: 0, end: 0.7),
          SubtitleWordTiming(text: 'ดี', start: 0.6, end: 1),
        ],
      ),
      SubtitleSegment(
        text: 'ขายดี',
        start: 0,
        end: 1,
        words: [
          SubtitleWordTiming(text: 'ขาย', start: 0.5, end: 1),
          SubtitleWordTiming(text: 'ดี', start: 0, end: 0.5),
        ],
      ),
      SubtitleSegment(
        text: 'ขายดี',
        start: 0,
        end: 1,
        words: [
          SubtitleWordTiming(text: 'ไม่ตรง', start: 0, end: 1),
        ],
      ),
    ];

    for (final unsafeCue in unsafeCues) {
      final onlyUnsafe = buildSubtitleFileContent(
        [unsafeCue],
        activeWordColor: '#FF0000',
      );
      expect(
        onlyUnsafe.fileName,
        'captions.srt',
        reason: 'unsafe cue must not activate ASS',
      );

      final mixed = buildActiveWordAssContent(
        [unsafeCue, validCue],
        activeWordColor: '#FF0000',
      );
      final unsafeDialogue = mixed
          .split('\n')
          .where((line) =>
              line.startsWith('Dialogue:') && line.contains(unsafeCue.text))
          .toList();
      expect(unsafeDialogue, hasLength(1));
      expect(unsafeDialogue.single, isNot(contains(r'{\1c')));
    }
  });

  test('allows untimed whitespace and punctuation between timed words', () {
    final selected = buildSubtitleFileContent(
      const [
        SubtitleSegment(
          text: 'ขายดี, ส่งฟรี!',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'ขายดี', start: 0, end: 0.5),
            SubtitleWordTiming(text: 'ส่งฟรี', start: 0.5, end: 1),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
    );

    expect(selected.fileName, 'captions.ass');
    expect(
      selected.content,
      contains(r'{\1c&H000000FF&}ขายดี{\1c&H00FFFFFF&}, ส่งฟรี!'),
    );
  });

  test('allows untimed Unicode symbols when timed words reconstruct the cue',
      () {
    final selected = buildSubtitleFileContent(
      const [
        SubtitleSegment(
          text: 'sell, free! \u2728',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'sell', start: 0, end: 0.5),
            SubtitleWordTiming(text: 'free', start: 0.5, end: 1),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
    );

    expect(selected.fileName, 'captions.ass');
    expect(selected.usesActiveWordTiming, isTrue);
    expect(selected.content, contains('free! \u2728'));
  });

  test('requires Thai abbreviation and repetition marks in timed word text',
      () {
    for (final mark in const ['\u0E2F', '\u0E46']) {
      final selected = buildSubtitleFileContent(
        [
          SubtitleSegment(
            text: 'word$mark',
            start: 0,
            end: 1,
            words: const [
              SubtitleWordTiming(text: 'word', start: 0, end: 1),
            ],
          ),
        ],
        activeWordColor: '#FF0000',
      );

      expect(selected.fileName, 'captions.srt');
      expect(selected.usesActiveWordTiming, isFalse);
    }
  });

  test('uses ASS for pop and fade even without word timing', () {
    const segments = [
      SubtitleSegment(text: 'ประโยคแรก', start: 0, end: 1),
      SubtitleSegment(text: 'ประโยคสอง', start: 1, end: 2),
    ];

    final pop = buildSubtitleFileContent(
      segments,
      subtitleAnimation: 'pop',
    );
    final fade = buildSubtitleFileContent(
      segments,
      subtitleAnimation: 'fade',
    );

    expect(pop.fileName, 'captions.ass');
    expect(pop.usesActiveWordTiming, isFalse);
    expect(
      RegExp(r'\\fscx78').allMatches(pop.content),
      hasLength(2),
    );
    expect(
      RegExp(r'\\fscx103').allMatches(pop.content),
      hasLength(2),
    );
    expect(fade.fileName, 'captions.ass');
    expect(fade.usesActiveWordTiming, isFalse);
    expect(
      RegExp(r'\\fad\(180,180\)').allMatches(fade.content),
      hasLength(2),
    );
  });

  test('applies one pop bounce without restarting it for every timed word', () {
    final ass = buildActiveWordAssContent(
      const [
        SubtitleSegment(
          text: 'ขายดี',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'ขาย', start: 0, end: 0.5),
            SubtitleWordTiming(text: 'ดี', start: 0.5, end: 1),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
      subtitleAnimation: 'pop',
    );
    final dialogues =
        ass.split('\n').where((line) => line.startsWith('Dialogue:')).toList();

    expect(dialogues, hasLength(2));
    expect(
      dialogues.first,
      contains(
        r'{\fscx78\fscy78'
        r'\t(0,120,\fscx103\fscy103)'
        r'\t(120,220,\fscx100\fscy100)}',
      ),
    );
    expect(dialogues.last, isNot(contains(r'\fscx78')));
    expect(dialogues.last, isNot(contains(r'\fscx103')));
    expect(
      RegExp(r'\\fscx78').allMatches(ass),
      hasLength(1),
    );
  });

  test('places timed fade-in and fade-out only at the cue edges', () {
    final ass = buildActiveWordAssContent(
      const [
        SubtitleSegment(
          text: 'หนึ่งสองสาม',
          start: 0,
          end: 1.2,
          words: [
            SubtitleWordTiming(text: 'หนึ่ง', start: 0, end: 0.4),
            SubtitleWordTiming(text: 'สอง', start: 0.4, end: 0.8),
            SubtitleWordTiming(text: 'สาม', start: 0.8, end: 1.2),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
      subtitleAnimation: 'fade',
    );
    final dialogues =
        ass.split('\n').where((line) => line.startsWith('Dialogue:')).toList();

    expect(dialogues, hasLength(3));
    expect(dialogues.first, contains(r'{\fad(180,0)}'));
    expect(dialogues.first, isNot(contains(r'\fad(180,180)')));
    expect(dialogues[1], isNot(contains(r'\fad(')));
    expect(dialogues.last, contains(r'{\fad(0,180)}'));
    expect(dialogues.last, isNot(contains(r'\fad(180,180)')));
  });

  test('keeps both fade edges when a cue has only one dialogue event', () {
    final ass = buildActiveWordAssContent(
      const [
        SubtitleSegment(
          text: 'คำเดียว',
          start: 0,
          end: 1,
          words: [
            SubtitleWordTiming(text: 'คำเดียว', start: 0, end: 1),
          ],
        ),
      ],
      activeWordColor: '#FF0000',
      subtitleAnimation: 'fade',
    );
    final dialogue =
        ass.split('\n').singleWhere((line) => line.startsWith('Dialogue:'));

    expect(dialogue, contains(r'{\fad(180,180)}'));
  });

  test('shortens the pop keyframes to fit a short cue', () {
    final ass = buildSubtitleFileContent(
      const [
        SubtitleSegment(text: 'เร็ว', start: 0, end: 0.1),
      ],
      subtitleAnimation: 'pop',
    ).content;

    expect(
      ass,
      contains(
        r'{\fscx78\fscy78'
        r'\t(0,55,\fscx103\fscy103)'
        r'\t(55,100,\fscx100\fscy100)}',
      ),
    );
    expect(ass, isNot(contains(r'\t(120,220,')));
  });

  test('normalizes unknown animation to none and preserves SRT fallback', () {
    const segments = [
      SubtitleSegment(text: 'ซับปกติ', start: 0, end: 1),
    ];

    final none = buildSubtitleFileContent(
      segments,
      subtitleAnimation: 'none',
    );
    final unknown = buildSubtitleFileContent(
      segments,
      subtitleAnimation: 'bounce',
    );
    final empty = buildSubtitleFileContent(
      const [],
      subtitleAnimation: 'fade',
    );

    expect(none.fileName, 'captions.srt');
    expect(unknown.fileName, 'captions.srt');
    expect(unknown.content, none.content);
    expect(empty.fileName, 'captions.srt');
    expect(empty.content, isEmpty);
  });

  test('retries ASS as SRT only for an explicit subtitle render failure', () {
    expect(
      shouldRetryAssRenderWithStaticSrt(
        subtitleFileName: 'captions.ass',
        failureLogs: '[Parsed_subtitles_0 @ 0001] Unable to open captions.ass',
      ),
      isTrue,
    );
    expect(
      shouldRetryAssRenderWithStaticSrt(
        subtitleFileName: 'captions.ass',
        failureLogs:
            "Error initializing filter 'subtitles' with args captions.ass",
      ),
      isTrue,
    );
    expect(
      shouldRetryAssRenderWithStaticSrt(
        subtitleFileName: 'captions.ass',
        failureLogs:
            '[libass @ 0001] Could not create a libass track from captions.ass',
      ),
      isTrue,
    );

    const unrelatedFailure = '[Parsed_subtitles_0 @ 0001] '
        'libass API version: 0x1701000\n'
        'Error initializing output stream 0:0 -- Error while opening encoder';
    expect(
      shouldRetryAssRenderWithStaticSrt(
        subtitleFileName: 'captions.ass',
        failureLogs: unrelatedFailure,
      ),
      isFalse,
    );
    expect(
      shouldRetryAssRenderWithStaticSrt(
        subtitleFileName: 'captions.srt',
        failureLogs: '[Parsed_subtitles_0 @ 0001] Unable to open captions.srt',
      ),
      isFalse,
    );
    expect(
      shouldRetryAssRenderWithStaticSrt(
        subtitleFileName: 'captions.ass',
        failureLogs: '[Parsed_subtitles_0 @ 0001] Unable to open captions.ass',
        cancellationRequested: true,
      ),
      isFalse,
    );
    expect(
      shouldRetryAssRenderWithStaticSrt(
        subtitleFileName: 'captions.ass',
        failureLogs: '[Parsed_subtitles_0 @ 0001] Unable to open captions.ass',
        alreadyRetried: true,
      ),
      isFalse,
    );
  });

  test('clips and shifts segments to the trim window', () {
    final clipped = clipSegmentsToTrim(
      const [
        SubtitleSegment(text: 'a', start: 0, end: 3),
        SubtitleSegment(
          text: 'b',
          start: 5,
          end: 9,
          words: [
            SubtitleWordTiming(text: 'b', start: 5.5, end: 8.5),
          ],
        ),
        SubtitleSegment(text: 'c', start: 20, end: 22),
      ],
      trimStartSec: 4,
      trimEndSec: 8,
    );

    // 'a' (0-3) is before the window → dropped. 'c' (20-22) is after → dropped.
    expect(clipped.length, 1);
    expect(clipped.first.text, 'b');
    expect(clipped.first.start, 1); // 5 - 4
    expect(clipped.first.end, 4); // clipped at trim end 8, then shifted by 4
    expect(clipped.first.words.single.start, 1.5);
    expect(clipped.first.words.single.end, 4);
  });

  test('removes fully trimmed words from valid timed cue text', () {
    final clipped = clipSegmentsToTrim(
      const [
        SubtitleSegment(
          text: 'one two three!',
          start: 0,
          end: 3,
          words: [
            SubtitleWordTiming(text: 'one', start: 0, end: 0.8),
            SubtitleWordTiming(text: 'two', start: 1, end: 1.8),
            SubtitleWordTiming(text: 'three', start: 2, end: 3),
          ],
        ),
      ],
      trimStartSec: 0.9,
      trimEndSec: 1.9,
    );

    expect(clipped, hasLength(1));
    expect(clipped.single.text, 'two');
    expect(clipped.single.words, hasLength(1));
    expect(clipped.single.words.single.text, 'two');
    expect(clipped.single.words.single.start, closeTo(0.1, 0.0001));
    expect(clipped.single.words.single.end, closeTo(0.9, 0.0001));
    expect(
      buildSubtitleFileContent(
        clipped,
        activeWordColor: '#FF0000',
      ).fileName,
      'captions.ass',
    );
  });

  test('clips a partially retained valid word without keeping other words', () {
    final clipped = clipSegmentsToTrim(
      const [
        SubtitleSegment(
          text: 'one two three',
          start: 0,
          end: 3,
          words: [
            SubtitleWordTiming(text: 'one', start: 0, end: 0.8),
            SubtitleWordTiming(text: 'two', start: 1, end: 1.8),
            SubtitleWordTiming(text: 'three', start: 2, end: 3),
          ],
        ),
      ],
      trimStartSec: 1.2,
      trimEndSec: 1.6,
    );

    expect(clipped, hasLength(1));
    expect(clipped.single.text, 'two');
    expect(clipped.single.start, 0);
    expect(clipped.single.end, closeTo(0.4, 0.0001));
    expect(clipped.single.words, hasLength(1));
    expect(clipped.single.words.single.start, 0);
    expect(clipped.single.words.single.end, closeTo(0.4, 0.0001));
  });

  test('keeps unsafe trimmed timing on the static subtitle fallback', () {
    final clipped = clipSegmentsToTrim(
      const [
        SubtitleSegment(
          text: 'one two',
          start: 0,
          end: 2,
          words: [
            // Incomplete timing: "one" has no word range.
            SubtitleWordTiming(text: 'two', start: 1, end: 2),
          ],
        ),
      ],
      trimStartSec: 1,
      trimEndSec: 2,
    );

    expect(clipped, hasLength(1));
    expect(clipped.single.text, 'one two');
    expect(
      buildSubtitleFileContent(
        clipped,
        activeWordColor: '#FF0000',
      ).fileName,
      'captions.srt',
    );
  });

  test('drops a valid timed cue when the trim keeps no spoken word', () {
    final clipped = clipSegmentsToTrim(
      const [
        SubtitleSegment(
          text: 'spoken',
          start: 0,
          end: 3,
          words: [
            SubtitleWordTiming(text: 'spoken', start: 1, end: 2),
          ],
        ),
      ],
      trimStartSec: 0,
      trimEndSec: 0.5,
    );

    expect(clipped, isEmpty);
  });

  test('builds ffmpeg args for trim, speed, volume and subtitles', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      subtitlePath: '/captions.srt',
      speed: 2.0,
      volume: 1.5,
      trimStartSec: 4,
      trimEndSec: 10,
    );
    final joined = args.join(' ');

    expect(joined, contains('-ss 4.000'));
    expect(joined, contains('-to 10.000'));
    expect(joined, contains('subtitles='));
    expect(joined, contains('setpts=0.5000*PTS'));
    expect(joined, contains('atempo=2.000'));
    expect(joined, contains('volume=1.500'));
    expect(joined, contains('-c:a aac')); // re-encode because of audio filters
  });

  test('caps the rendered file at the requested result duration', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      maxOutputDurationSec: 60,
      silenceRanges: const [
        SilenceCutRange(start: 60, end: 148.7),
      ],
    );

    expect(args, containsAllInOrder(['-t', '60.000', '/out.mp4']));
  });

  test('copies audio when there are no audio edits', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      subtitlePath: '/captions.srt',
    );
    final joined = args.join(' ');

    expect(joined, contains('-c:a copy'));
    expect(joined, isNot(contains('atempo')));
  });

  test('detects silent gaps between transcript segments', () {
    final ranges = detectSilenceRanges(
      const [
        SubtitleSegment(text: 'a', start: 0, end: 3),
        SubtitleSegment(text: 'b', start: 5, end: 8), // 2s gap before
        SubtitleSegment(text: 'c', start: 8.3, end: 10), // 0.3s gap → ignored
      ],
      minGapSec: 0.8,
    );

    expect(ranges.length, 1);
    expect(ranges.first.start, 3);
    expect(ranges.first.end, 5);
  });

  test('builds video select and compact audio concat for silence ranges', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      silenceRanges: const [
        SilenceCutRange(start: 3, end: 5),
        SilenceCutRange(start: 12, end: 14),
      ],
    );
    final joined = args.join(' ');

    expect(
        joined,
        contains("select='not(between(t,3.000,5.000)+"
            "between(t,12.000,14.000))'"));
    expect(joined, contains('[0:a]atrim=start=0.000:end=3.000'));
    expect(joined, contains('[0:a]atrim=start=5.000:end=12.000'));
    expect(joined, contains('[0:a]atrim=start=14.000'));
    expect(joined, contains('concat=n=3:v=0:a=1[aout]'));
    expect(joined, contains('-map 0:v:0? -map [aout]'));
    expect(joined, isNot(contains('aselect=')));
    expect(joined, contains('-c:a aac'));
  });

  test('gives libass the bundled subtitle font directory and family', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      subtitlePath: '/work/captions.srt',
      subtitleFontsDirectory: '/work/fonts',
      subtitleFontName: 'Prompt',
    );
    final vf = args[args.indexOf('-vf') + 1];

    expect(vf, contains("fontsdir='/work/fonts'"));
    expect(vf, contains('FontName=Prompt'));
  });

  test('combines silence, sticker, speed and volume in one mapped graph', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      silenceRanges: const [SilenceCutRange(start: 3, end: 5)],
      stickerImagePaths: const ['/sticker.png'],
      speed: 1.5,
      volume: 0.8,
    );
    final joined = args.join(' ');

    expect(joined, contains('overlay='));
    expect(joined, contains('[0:a]atrim=start=0.000:end=3.000'));
    expect(joined, contains('[0:a]atrim=start=5.000'));
    expect(joined, contains('concat=n=2:v=0:a=1'));
    expect(joined, contains('atempo=1.500'));
    expect(joined, contains('volume=0.800'));
    expect(joined, contains('-map [vout] -map [aout]'));
    expect(joined, isNot(contains(' -af ')));
    expect(joined, isNot(contains('aselect=')));
  });

  test('sorts and merges overlapping silence ranges before rendering', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      silenceRanges: const [
        SilenceCutRange(start: 5, end: 8),
        SilenceCutRange(start: 3, end: 6),
      ],
    );
    final joined = args.join(' ');

    expect(joined, contains("select='not(between(t,3.000,8.000))'"));
    expect(joined, contains('[0:a]atrim=start=0.000:end=3.000'));
    expect(joined, contains('[0:a]atrim=start=8.000'));
    expect(joined, contains('concat=n=2:v=0:a=1'));
  });

  test('builds color filter for presets and adjustments', () {
    expect(buildColorFilter(filterIndex: 0), isEmpty);
    expect(buildColorFilter(filterIndex: 3), 'hue=s=0');
    expect(
      buildColorFilter(filterIndex: 0, brightness: 0.5, contrast: 0.4),
      "lutrgb=r='clip((val-128)*1.400+128+63.750,0,255)':"
      "g='clip((val-128)*1.400+128+63.750,0,255)':"
      "b='clip((val-128)*1.400+128+63.750,0,255)'",
    );
    expect(buildColorFilter(filterIndex: 1), 'hue=s=1.400');
    expect(buildColorFilter(filterIndex: 2), startsWith('hue=s=0.700'));
    expect(buildColorFilter(filterIndex: 1), isNot(contains('eq=')));
    expect(buildColorFilter(filterIndex: 4), contains('colorbalance'));
  });

  test('retries a requested color filter without color as a safe fallback', () {
    expect(
      buildColorFilterFallbacks('hue=s=1.400'),
      ['hue=s=1.400', ''],
    );
    expect(buildColorFilterFallbacks(''), ['']);
  });

  test('builds drawtext filters and sanitizes risky characters', () {
    final filters = buildDrawTextFilters(
      const [
        TextOverlaySpec('ลดราคา 50%'),
        TextOverlaySpec("it's: ok"),
        TextOverlaySpec('   '),
      ],
      fontPath: '/fonts/Prompt.ttf',
    );

    expect(filters.length, 2); // blank skipped
    expect(filters.first, contains("fontfile='/fonts/Prompt.ttf'"));
    expect(filters.first, contains('text='));
    expect(filters.first, isNot(contains('%')));
    expect(filters[1], isNot(contains("'s")));
  });

  test('drawtext + sticker overlays honor custom positions', () {
    final text = buildDrawTextFilters(
      const [TextOverlaySpec('hi', dx: 0.25, dy: 0.6)],
      fontPath: '/f.ttf',
    );
    expect(text.first, contains('x=(w*0.250-text_w/2)'));
    expect(text.first, contains('y=h*0.600'));

    final fc = buildStickerFilterComplex(
      videoFilters: const [],
      stickerCount: 1,
      positions: const [(0.3, 0.7)],
    );
    expect(
        fc,
        contains('overlay=main_w*0.300-overlay_w/2:'
            'main_h*0.700-overlay_h/2:eof_action=repeat'));
  });

  test('color grade comes before subtitles in the filter chain', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      colorFilter: 'hue=s=0',
      subtitlePath: '/captions.srt',
    );
    final vf = args[args.indexOf('-vf') + 1];

    expect(vf.indexOf('hue=s=0'), lessThan(vf.indexOf('subtitles=')));
  });

  test('picks platform hardware H.264 encoder with mpeg4 fallback', () {
    final android = hardwareH264Encoder(isAndroid: true, isIOS: false);
    expect(android.codec, 'h264_mediacodec');
    expect(android.scaleEvenDimensions, isTrue);
    expect(android.encoderArgs, contains('-pix_fmt'));

    final ios = hardwareH264Encoder(isAndroid: false, isIOS: true);
    expect(ios.codec, 'h264_videotoolbox');
    expect(ios.scaleEvenDimensions, isTrue);

    // Desktop/test hosts have no hardware encoder → universal MPEG-4 fallback.
    final other = hardwareH264Encoder(isAndroid: false, isIOS: false);
    expect(other.codec, fallbackMpeg4Encoder.codec);
  });

  test('applies the chosen video codec and even-dimension scaling', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      videoCodec: 'h264_mediacodec',
      videoEncoderArgs: const ['-b:v', '6M', '-pix_fmt', 'yuv420p'],
      scaleEvenDimensions: true,
    );
    final joined = args.join(' ');
    final vf = args[args.indexOf('-vf') + 1];

    expect(joined, contains('-c:v h264_mediacodec'));
    expect(joined, contains('-b:v 6M'));
    expect(joined, contains('-pix_fmt yuv420p'));
    expect(vf, contains('scale=trunc(iw/2)*2:trunc(ih/2)*2'));
  });

  test('caps preview dimensions and keeps the aspect ratio', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      videoCodec: 'h264_mediacodec',
      videoEncoderArgs: const ['-b:v', '2M', '-pix_fmt', 'yuv420p'],
      scaleEvenDimensions: true,
      maxVideoDimension: 720,
      maxVideoFrameRate: 24,
    );
    final joined = args.join(' ');
    final vf = args[args.indexOf('-vf') + 1];

    expect(joined, contains('-b:v 2M'));
    expect(
      vf,
      contains(
        "scale=w='min(720,iw)':h='min(720,ih)':"
        'force_original_aspect_ratio=decrease:force_divisible_by=2',
      ),
    );
    expect(vf, isNot(contains('scale=trunc(iw/2)*2')));
    expect(vf, contains('fps=24'));
  });

  test('uses a smaller preview profile for long source videos', () {
    final short = videoPreviewProfileForSourceDuration(45);
    final long = videoPreviewProfileForSourceDuration(150);

    expect(short.maxVideoDimension, 720);
    expect(short.videoBitrate, '2M');
    expect(short.maxVideoFrameRate, 24);
    expect(long.maxVideoDimension, 540);
    expect(long.videoBitrate, '1M');
    expect(long.maxVideoFrameRate, 20);
  });

  test('writes FFmpeg progress to a file that can be polled on Android', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      progressPath: '/tmp/render-progress.txt',
    );

    expect(
      args.join(' '),
      contains(
        '-stats_period 0.5 -progress /tmp/render-progress.txt -nostats',
      ),
    );
  });

  test('reads processed time from FFmpeg progress file content', () {
    expect(
      parseFfmpegProgressSeconds(
        'frame=120\nout_time_us=12345678\nprogress=continue\n',
      ),
      closeTo(12.345678, 0.000001),
    );
    expect(
      parseFfmpegProgressSeconds(
        'frame=120\nout_time_ms=7654321\nprogress=continue\n',
      ),
      closeTo(7.654321, 0.000001),
    );
    expect(parseFfmpegProgressSeconds('progress=continue\n'), isNull);
  });

  test('detects FFmpeg completion from the polled progress file', () {
    expect(
      ffmpegProgressReportedEnd(
        'frame=120\nout_time_us=12345678\nprogress=end\n',
      ),
      isTrue,
    );
    expect(
      ffmpegProgressReportedEnd(
        'frame=120\nout_time_us=12345678\nprogress=continue\n',
      ),
      isFalse,
    );
    expect(ffmpegProgressReportedEnd('progress=ending\n'), isFalse);
  });

  test('verifies output when the callback lost a successful completion', () {
    expect(
      shouldVerifyFfmpegOutput(
        returnCodeValue: null,
        progressReportedEnd: true,
      ),
      isTrue,
    );
    expect(
      shouldVerifyFfmpegOutput(
        returnCodeValue: null,
        progressReportedEnd: false,
      ),
      isFalse,
    );
    expect(
      shouldVerifyFfmpegOutput(
        returnCodeValue: 1,
        progressReportedEnd: true,
      ),
      isFalse,
    );
    expect(
      shouldVerifyFfmpegOutput(
        returnCodeValue: 0,
        progressReportedEnd: false,
      ),
      isTrue,
    );
  });

  test('render cancellation token cancels an attached session once', () async {
    final token = RenderCancellationToken();
    var cancelCalls = 0;

    await token.attach(() async => cancelCalls += 1);
    await token.cancel();
    await token.cancel();

    expect(token.isCancelled, isTrue);
    expect(cancelCalls, 1);
  });

  test('render cancellation token cancels a session attached later', () async {
    final token = RenderCancellationToken();
    var cancelCalls = 0;

    await token.cancel();
    await token.attach(() async => cancelCalls += 1);

    expect(cancelCalls, 1);
  });

  test('defaults to the mpeg4 encoder when no codec is given', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      volume: 1.2,
    );
    final joined = args.join(' ');

    expect(joined, contains('-c:v mpeg4 -q:v 4'));
    expect(joined, isNot(contains('scale=trunc')));
  });

  test('builds a sticker overlay graph stacked from the top-right', () {
    final fc = buildStickerFilterComplex(
      videoFilters: const ['hue=s=0'],
      stickerCount: 2,
    );

    expect(fc, contains('[0:v]hue=s=0[vbase]'));
    expect(
      fc,
      contains('[vbase][1:v]overlay=main_w-overlay_w-12:12:'
          'eof_action=repeat[v0]'),
    );
    expect(
      fc,
      contains('[v0][2:v]overlay=main_w-overlay_w-12:116:'
          'eof_action=repeat[vout]'),
    );
  });

  test('sticker graph overlays directly on the raw input with no filters', () {
    final fc = buildStickerFilterComplex(
      videoFilters: const [],
      stickerCount: 1,
    );

    expect(
      fc,
      '[0:v][1:v]overlay=main_w-overlay_w-12:12:eof_action=repeat[vout]',
    );
  });

  test('adds sticker inputs and maps the overlay output', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      colorFilter: 'hue=s=0',
      stickerImagePaths: const ['/s0.png', '/s1.png'],
    );
    final joined = args.join(' ');

    expect(joined, contains('-i /s0.png'));
    expect(joined, contains('-i /s1.png'));
    expect(joined, contains('-filter_complex'));
    expect(joined, contains('-map [vout]'));
    expect(joined, contains('-map 0:a?'));
    expect(joined, isNot(contains('-vf'))); // overlay path replaces -vf
  });

  test('purges stale render temp dirs but keeps the current ones', () async {
    final base = Directory.systemTemp.createTempSync('postdee-purge-test-');
    addTearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });
    final sep = Platform.pathSeparator;
    final stale1 = Directory('${base.path}${sep}postdee-edit-old')
      ..createSync();
    final stale2 = Directory('${base.path}${sep}postdee-sticker-old')
      ..createSync();
    final keep = Directory('${base.path}${sep}postdee-edit-keep')..createSync();
    final other = Directory('${base.path}${sep}unrelated')..createSync();

    final removed = await purgeEditTempDirs(base, keepPaths: {keep.path});

    expect(removed, 2);
    expect(stale1.existsSync(), isFalse);
    expect(stale2.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  });

  test('renderer keeps its input temp dir while removing other stale dirs',
      () async {
    final base =
        Directory.systemTemp.createTempSync('postdee-purge-call-test-');
    addTearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });
    final sep = Platform.pathSeparator;
    final inputDir = Directory('${base.path}${sep}postdee-edit-current')
      ..createSync();
    final inputFile = File('${inputDir.path}${sep}previous-render.mp4')
      ..writeAsBytesSync([0, 1, 2]);
    final acceptedResult = Directory('${base.path}${sep}postdee-edit-accepted')
      ..createSync();
    final acceptedFile = File('${acceptedResult.path}${sep}accepted.mp4')
      ..writeAsBytesSync([2, 1, 0]);
    final staleEdit = Directory('${base.path}${sep}postdee-edit-stale')
      ..createSync();
    final staleSticker = Directory('${base.path}${sep}postdee-sticker-stale')
      ..createSync();

    final processor = FfmpegSubtitleBurnVideoProcessor(
      renderTempDirectory: base,
    );

    await expectLater(
      processor(
        BurnSubtitleRequest(
          inputFile: inputFile,
          fileName: 'previous-render.mp4',
          segments: const [],
          preserveTempDirectoryPaths: {acceptedResult.path},
        ),
      ),
      throwsA(isA<SubtitleBurnException>()),
    );

    expect(inputDir.existsSync(), isTrue);
    expect(inputFile.existsSync(), isTrue);
    expect(acceptedResult.existsSync(), isTrue);
    expect(acceptedFile.existsSync(), isTrue);
    expect(staleEdit.existsSync(), isFalse);
    expect(staleSticker.existsSync(), isFalse);
  });

  test('keeps the simple -vf path when there are no stickers', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      colorFilter: 'hue=s=0',
    );
    final joined = args.join(' ');

    expect(joined, contains('-vf hue=s=0'));
    expect(joined, isNot(contains('-filter_complex')));
    expect(joined, isNot(contains('-map')));
  });

  test('builds subtitle force style with size and position', () {
    final bottom = buildSubtitleForceStyle(fontSize: 24, atBottom: true);
    expect(bottom, contains('FontName=PostDee Subtitle Thai'));
    expect(bottom, contains('Fontsize=24'));
    expect(bottom, contains('Outline=0.5'));
    expect(bottom, contains('Shadow=0'));
    expect(bottom, contains('Alignment=2'));
    expect(bottom, contains('MarginL=24'));
    expect(bottom, contains('MarginR=24'));
    expect(bottom, contains('MarginV=28'));
    expect(bottom, contains('WrapStyle=2'));

    final top = buildSubtitleForceStyle(fontSize: 14, atBottom: false);
    expect(top, contains('Fontsize=14'));
    expect(top, contains('Alignment=8'));
  });

  test('builds the selected font, colors, outline, shadow, and middle position',
      () {
    final style = buildSubtitleForceStyle(
      fontSize: 28,
      alignment: BurnSubtitleAlignment.middle,
      fontName: 'Anuphan',
      textColor: '#12AB34',
      outlineColor: '#112233',
      outlineWidth: 3,
      shadowColor: '#445566',
      shadowDepth: 4,
    );

    expect(style, contains('FontName=Anuphan'));
    expect(style, contains('PrimaryColour=&H0034AB12'));
    expect(style, contains('OutlineColour=&H00332211'));
    expect(style, contains('BackColour=&H00665544'));
    expect(style, contains('Outline=3'));
    expect(style, contains('Shadow=4'));
    expect(style, contains('Alignment=5'));
  });

  test('applies subtitle font size and top position to the args', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      subtitlePath: '/captions.srt',
      subtitleFontSize: 24,
      subtitleAtBottom: false,
    );
    final vf = args[args.indexOf('-vf') + 1];

    expect(vf, contains('Fontsize=24'));
    expect(vf, contains('Alignment=8'));
  });

  test('accepts a rendered output only when it has a video stream', () {
    // h264_mediacodec on some devices exits 0 while writing an audio-only
    // file; the render loop must reject that output and try the fallback.
    expect(renderedOutputHasVideo(['video', 'audio']), isTrue);
    expect(renderedOutputHasVideo(['audio']), isFalse);
    expect(renderedOutputHasVideo(['audio', null]), isFalse);
    expect(renderedOutputHasVideo([]), isFalse);
    expect(renderedOutputHasVideo(null), isFalse);
  });
}
