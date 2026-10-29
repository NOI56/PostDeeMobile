import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/uploader/cover_editor_localizations.dart';

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
      })));
  await tester.pumpAndSettle();
  return context;
}

void main() {
  testWidgets(
      'Thai and missing app delegate retain exact editor and timeline copy',
      (tester) async {
    for (final language in <String?>[null, 'th']) {
      final context = await _context(tester, language);
      expect(coverEditorUsesThai(context), isTrue);
      expect(localizeCoverEditorMessage(context, 'แต่งหน้าปก'), 'แต่งหน้าปก');
      expect(coverEditorText(context, 'ไทย', 'English'), 'ไทย');
      expect(coverTimelineSemantics(context, '00:05', '01:10', 65),
          '00:05 จาก 01:10 เหลือ 65 วินาที');
      expect(coverRemainingTime(context, 65), 'เหลือ 65 วิ');
    }
  });

  testWidgets(
      'English editor labels and known processor failures translate exactly',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(localizeCoverEditorMessage(context, 'แต่งหน้าปก'), 'Edit cover');
    expect(localizeCoverEditorMessage(context, 'เลือกเฟรมหน้าปกจากคลิป'),
        'Choose a cover frame');
    expect(localizeCoverEditorMessage(context, 'ข้อความบนหน้าปก (ไม่ใส่ก็ได้)'),
        'Cover text (optional)');
    expect(
        localizeCoverEditorMessage(context, 'ไม่พบไฟล์วิดีโอสำหรับสร้างหน้าปก'),
        'Video file not found. Choose your video again.');
  });

  testWidgets(
      'English timeline preserves supplied clocks and uses singular and plural seconds',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final seconds in [0, 1, 2, 65]) {
      expect(coverTimelineSemantics(context, '00:05', '01:10', seconds),
          '00:05 of 01:10, $seconds ${seconds == 1 ? 'second' : 'seconds'} remaining');
      expect(coverRemainingTime(context, seconds), '$seconds sec remaining');
    }
  });

  testWidgets(
      'styling, saving and known processor errors use exact canonical copy',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in const {
      'เลื่อนเลือกภาพจากคลิป': 'Choose a frame from your video',
      'ภาพตัวอย่างจะเปลี่ยนตามตำแหน่งเวลา แล้วใช้ภาพนั้นเป็นหน้าปก':
          'Move the slider to preview a frame, then use it as your cover.',
      'เช่น ลดวันนี้เท่านั้น': 'e.g. Today only',
      'ฟอนต์': 'Font',
      'ความหนาและขนาด': 'Weight and size',
      'สีข้อความ': 'Text color',
      'พื้นหลังข้อความ': 'Text background',
      'ตำแหน่งข้อความ': 'Text position',
      'บน': 'Top',
      'กลาง': 'Center',
      'ล่าง': 'Bottom',
      'ปกติ': 'Regular',
      'กึ่งหนา': 'Semi-bold',
      'หนา': 'Bold',
      'หนาพิเศษ': 'Extra-bold',
      'กำลังสร้างหน้าปก...': 'Creating cover...',
      'ใช้หน้าปกนี้': 'Use this cover',
      'ยังเปิดภาพเคลื่อนไหวไม่ได้ แต่ยังเลือกเวลาและสร้างหน้าปกได้':
          'Video preview is unavailable. You can still choose a time and create a cover.',
      'สร้างหน้าปกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
          'Could not create the cover. Try again.',
      'ไม่พบรูปหน้าปก กรุณาเลือกรูปใหม่':
          'Cover image not found. Choose another image.',
      'สร้างภาพหน้าปกไม่สำเร็จ กรุณาลองเลือกเฟรมหรือรูปใหม่':
          'Could not create the cover image. Choose another frame or image.',
      'ตำแหน่งวิดีโอ': 'Video position',
    }.entries) {
      expect(localizeCoverEditorMessage(context, entry.key), entry.value);
    }
  });

  testWidgets(
      'non-Thai locales preserve typed clocks and remaining values in English',
      (tester) async {
    for (final language in ['en', 'vi', 'ja']) {
      final context = await _context(tester, language);
      expect(coverEditorUsesThai(context), isFalse);
      expect(coverEditorText(context, 'ไทย', 'English'), 'English');
      expect(localizeCoverEditorMessage(context, 'ฟอนต์'), 'Font');
      expect(coverTimelineSemantics(context, '01:02:03', '04:05:06', 10983),
          '01:02:03 of 04:05:06, 10983 seconds remaining');
      expect(coverRemainingTime(context, 10983), '10983 sec remaining');
      expect(coverTimelineSemantics(context, '--:--', '00:00', 0),
          '--:-- of 00:00, 0 seconds remaining');
    }
  });

  testWidgets('unknown provider text, user data and near matches stay raw',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final raw in [
      'codec error: สร้างหน้าปกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
      'ไม่พบรูปหน้าปก กรุณาเลือกรูปใหม่ (provider detail)',
      'native error\nไม่พบไฟล์วิดีโอสำหรับสร้างหน้าปก',
      'แต่งหน้าปก.mp4',
      '/ร้านของฉัน/สีข้อความ.png',
      'ลดวันนี้เท่านั้น 🎉',
      'ฟอนต์ ',
      'กำลังสร้างหน้าปก…',
      'เหลือ 12 วิ',
      'การรองรับหน้าปก'
    ]) {
      expect(localizeCoverEditorMessage(context, raw), raw);
    }
    expect(coverTimelineSemantics(context, 'ฟอนต์', 'แต่งหน้าปก', 2),
        'ฟอนต์ of แต่งหน้าปก, 2 seconds remaining');
  });

  testWidgets(
      'stored errors follow live language while identical cover text stays raw',
      (tester) async {
    final locale = ValueNotifier(const Locale('th'));
    addTearDown(locale.dispose);
    const storedError = 'สร้างหน้าปกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
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
              CoverEditorText(storedError),
              Text(storedError, key: ValueKey('raw-cover-text'))
            ]))));
    await tester.pumpAndSettle();
    expect(find.text(storedError), findsNWidgets(2));
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not create the cover. Try again.'), findsOneWidget);
    expect(find.text(storedError), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('raw-cover-text'))).data,
        storedError);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text(storedError), findsNWidgets(2));
  });
}
