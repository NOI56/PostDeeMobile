import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/uploader/video_preview_localizations.dart';

Future<BuildContext> _context(WidgetTester tester, String? language) async {
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(
    locale: language == null ? null : Locale(language),
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: language == null
        ? null
        : const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
    home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }),
  ));
  await tester.pumpAndSettle();
  return context;
}

void main() {
  testWidgets('Thai and missing app delegate retain exact original copy',
      (tester) async {
    for (final language in <String?>[null, 'th']) {
      final context = await _context(tester, language);
      expect(videoPreviewUsesThai(context), isTrue);
      for (final raw in [
        'ดูคลิป',
        'พรีวิว',
        'กำลังเปิดคลิป…',
        'ยังเปิดคลิปไม่ได้',
        '50 เปอร์เซ็นต์'
      ]) {
        expect(localizeVideoPreviewMessage(context, raw), raw);
      }
      expect(videoPreviewText(context, 'ไทย', 'English'), 'ไทย');
    }
  });

  testWidgets('English maps only the exact app-owned playback controls',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in const {
      'ดูคลิป': 'Watch video',
      'พรีวิว': 'Preview',
      'เล่นคลิป': 'Play video',
      'หยุดคลิป': 'Pause video',
      'เริ่มคลิปใหม่': 'Restart video',
      'ระดับเสียงพรีวิว': 'Preview volume',
      'ปรับเสียงพรีวิว': 'Adjust preview volume',
      'เปิดเสียงพรีวิว': 'Unmute preview',
      'ปิดเสียงพรีวิว': 'Mute preview',
      'เลื่อนเวลาคลิป': 'Seek video'
    }.entries) {
      expect(localizeVideoPreviewMessage(context, entry.key), entry.value);
    }
  });

  testWidgets(
      'English percent semantics accept only whole values from zero to 100',
      (tester) async {
    final context = await _context(tester, 'en');
    for (var percent = 0; percent <= 100; percent++) {
      expect(localizeVideoPreviewMessage(context, '$percent เปอร์เซ็นต์'),
          '$percent percent');
    }
    for (final raw in [
      '-1 เปอร์เซ็นต์',
      '101 เปอร์เซ็นต์',
      '050 เปอร์เซ็นต์',
      '+50 เปอร์เซ็นต์',
      '50.0 เปอร์เซ็นต์',
      '50 เปอร์เซ็นต์\n',
      ' 50 เปอร์เซ็นต์',
      '50 เปอร์เซ็นต์ filename.mp4'
    ]) {
      expect(localizeVideoPreviewMessage(context, raw), raw);
    }
  });

  testWidgets(
      'known initialization, owner and command errors use canonical English',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in const {
      'กำลังเปิดคลิป…': 'Opening video…',
      'ยังเปิดคลิปไม่ได้': 'Could not open this video',
      'ลองเปิดอีกครั้ง หรือกลับไปเลือกคลิปอื่น':
          'Try opening it again, or go back and choose another video.',
      'ลองเปิดคลิปอีกครั้ง': 'Try opening the video again',
      'กลับไปตรวจสถานะเพื่อเปิดตัวอย่างล่าสุด':
          'Go back and check the post status to open the latest preview.',
      'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่':
          'Your account has changed. Reopen the video.',
      'ยังเล่นคลิปไม่ได้ ลองอีกครั้ง': 'Could not play this video. Try again.',
      'ยังปรับเสียงไม่ได้ ลองอีกครั้ง':
          'Could not adjust the preview volume. Try again.',
    }.entries) {
      expect(localizeVideoPreviewMessage(context, entry.key), entry.value);
    }
  });

  testWidgets('unknown provider details, filenames and near matches stay raw',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final raw in [
      'codec-error: ยังเปิดคลิปไม่ได้',
      'ยังเปิดคลิปไม่ได้ (codec 7)',
      'Network detail\nยังเปิดคลิปไม่ได้',
      'ดูคลิป.mp4',
      '/store/ข้อมูลพรีวิว.mp4',
      'https://provider.invalid/video?caption=ดูคลิป',
      'กำลังเปิดคลิป...',
      'เล่นคลิป ',
      '50 เปอร์เซ็นต์ unavailable',
      '๑๐ เปอร์เซ็นต์'
    ]) {
      expect(localizeVideoPreviewMessage(context, raw), raw);
    }
  });

  testWidgets(
      'all non-Thai app locales use English without changing numeric values',
      (tester) async {
    for (final language in ['en', 'vi', 'ja']) {
      final context = await _context(tester, language);
      expect(videoPreviewUsesThai(context), isFalse);
      expect(videoPreviewText(context, 'ไทย', 'English'), 'English');
      expect(localizeVideoPreviewMessage(context, 'พรีวิว'), 'Preview');
      expect(
          localizeVideoPreviewMessage(context, '73 เปอร์เซ็นต์'), '73 percent');
    }
  });

  testWidgets(
      'stored Thai error follows live locale while identical user text stays raw',
      (tester) async {
    final locale = ValueNotifier(const Locale('th'));
    addTearDown(locale.dispose);
    const storedError = 'ยังเปิดคลิปไม่ได้';
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) => MaterialApp(
            locale: value,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: const Column(children: [
              VideoPreviewText(storedError),
              Text(storedError, key: ValueKey('raw-preview-data'))
            ]))));
    await tester.pumpAndSettle();
    expect(find.text(storedError), findsNWidgets(2));
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not open this video'), findsOneWidget);
    expect(find.text(storedError), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('raw-preview-data')))
            .data,
        storedError);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text(storedError), findsNWidgets(2));
  });
}
