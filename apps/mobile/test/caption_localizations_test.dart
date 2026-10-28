import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/caption_writing_style.dart';
import 'package:postdee_mobile/features/uploader/caption_localizations.dart';

Future<BuildContext> _context(WidgetTester tester, String language) async {
  late BuildContext result;
  await tester.pumpWidget(MaterialApp(
      locale: Locale(language),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: Builder(builder: (context) {
        result = context;
        return const SizedBox();
      })));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('English caption messages translate known UI copy',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(
        localizeCaptionMessage(context, 'ตั้งค่าขั้นสูง'), 'Advanced settings');
    expect(localizeCaptionMessage(context, 'แคปชั่น'), 'Caption');
    expect(localizeCaptionMessage(context, 'สไตล์การเขียน'), 'Writing style');
    expect(localizeCaptionMessage(context, 'ดูคลิป'), 'Watch video');
  });

  testWidgets('English dynamic counters retain the supplied numeric values',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(localizeCaptionMessage(context, '7 ตัวอักษร'), '7 characters');
    expect(
        localizeCaptionMessage(
            context, '10 / 5,000 ไบต์ · ชื่อคลิปตั้งในช่องทาง'),
        '10 / 5,000 bytes · Set the video title in Channels');
  });

  testWidgets('Thai and unknown provider text stay unchanged', (tester) async {
    final context = await _context(tester, 'th');
    expect(captionUsesThai(context), isTrue);
    expect(localizeCaptionMessage(context, 'ตั้งค่าขั้นสูง'), 'ตั้งค่าขั้นสูง');
    final english = await _context(tester, 'en');
    const raw = 'provider-code: ข้อความเดิม';
    expect(localizeCaptionMessage(english, raw), raw);
  });

  testWidgets(
      'style display labels leave serialized preferences and examples intact',
      (tester) async {
    final context = await _context(tester, 'en');
    const profile = CaptionWritingStyleProfile(
        style: CaptionWritingStyle(
            tone: CaptionWritingTone.playful,
            length: CaptionWritingLength.short,
            emoji: CaptionWritingEmoji.none,
            examples: ['ตั้งค่าขั้นสูง', 'สไตล์การเขียน']));
    final before = profile.toJson();
    expect(
        [
          profile.style.tone.label,
          profile.style.length.label,
          profile.style.emoji.label
        ].map((label) => localizeCaptionMessage(context, label)).join(' · '),
        'Fun / playful · Short and concise · No emoji');
    expect(profile.toJson(), before);
    expect(profile.style.tone.value, 'playful');
    expect(profile.style.examples, ['ตั้งค่าขั้นสูง', 'สไตล์การเขียน']);
    expect(localizeCaptionMessage(context, 'ตัวอย่างที่จำไว้ 2/3'),
        'Remembered examples 2/3');
  });

  testWidgets(
      'formatted platform limits keep exact counts, byte units and limits',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in const {
      'TikTok: 2,201 / 2,200 ตัวอักษร': 'TikTok: 2,201 / 2,200 characters',
      'Instagram: 17 / 2,200 ตัวอักษร': 'Instagram: 17 / 2,200 characters',
      'Facebook: 63,207 / 63,206 ตัวอักษร':
          'Facebook: 63,207 / 63,206 characters',
      'YouTube: 5,001 / 5,000 ไบต์': 'YouTube: 5,001 / 5,000 bytes',
      '1 ตัวอักษร': '1 character',
    }.entries) {
      expect(localizeCaptionMessage(context, entry.key), entry.value);
    }
    for (final raw in [
      'YouTube: 10 / 2,200 ตัวอักษร',
      'TikTok: 2,,201 / 2,200 ตัวอักษร',
      'prefix Instagram: 1 / 2,200 ตัวอักษร',
      'YouTube: 5 / 5,000 ไบต์\n'
    ]) {
      expect(localizeCaptionMessage(context, raw), raw);
    }
  });

  testWidgets(
      'credit cost messages preserve only valid selected-channel counts',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final count in ['1', '2', '3', '4']) {
      final credits = '$count ${count == '1' ? 'credit' : 'credits'}';
      expect(localizeCaptionMessage(context, 'สร้างแคปชั่น · $count เครดิต'),
          'Generate captions · $credits');
      expect(
          localizeCaptionMessage(context,
              'เครดิตไม่พอ ต้องใช้ $count เครดิต ลดช่องทางหรือเติมเครดิตแล้วลองใหม่'),
          'Not enough credits. $credits required. Choose fewer channels or add credits and try again.');
    }
    expect(localizeCaptionMessage(context, 'สร้างแคปชั่น · 5 เครดิต'),
        'สร้างแคปชั่น · 5 เครดิต');
  });

  testWidgets('preview count and charged fallback messages remain distinct',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final count in ['0', '1', '2', '3']) {
      final channels = '$count ${count == '1' ? 'channel' : 'channels'}';
      expect(localizeCaptionMessage(context, 'แคปชั่นจาก AI $count ช่องทาง'),
          'AI captions for $channels');
      expect(localizeCaptionMessage(context, 'ตรวจข้อความสำรอง $count ช่องทาง'),
          'Review fallback captions for $channels');
      expect(localizeCaptionMessage(context, 'ใช้ $count แคปชั่น'),
          'Use $count ${count == '1' ? 'caption' : 'captions'}');
    }
    expect(localizeCaptionMessage(context, 'แคปชั่นจาก AI ทั้ง 4 ช่องทาง'),
        'AI captions for all 4 channels');
    expect(localizeCaptionMessage(context, 'ตรวจข้อความสำรองทั้ง 4 ช่องทาง'),
        'Review fallback captions for all 4 channels');
    expect(localizeCaptionMessage(context, 'ใช้ทั้ง 4 แคปชั่น'),
        'Use all 4 captions');
    const raw = 'AI วิเคราะห์คลิปไม่สำเร็จ กรุณาตรวจข้อความ 2 ช่องทางก่อนใช้';
    expect(localizeCaptionMessage(context, raw),
        'AI could not analyze the video. Review the text for 2 channels before use.');
    expect(localizeCaptionMessage(context, '$raw · ไม่หักโควตา AI'),
        'AI could not analyze the video. Review the text for 2 channels before use. · No AI quota charged');
    expect(localizeCaptionMessage(context, 'unknown · ไม่หักโควตา AI'),
        'unknown · ไม่หักโควตา AI');
  });

  testWidgets(
      'owned failures translate while raw provider and later-page text stay intact',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in const {
      'บันทึกสไตล์ไม่สำเร็จ กรุณาลองใหม่':
          'Could not save your style. Please try again.',
      'คุณแก้ข้อความระหว่างที่ AI ทำงาน จึงเก็บข้อความที่คุณเขียนไว้':
          'You edited the text while AI was working. Your writing has been kept.',
      'ระบบ AI ยังส่งแคปชั่นไม่ครบช่องทางที่เลือก กรุณาลองใหม่ภายหลัง':
          'AI did not return captions for all selected channels. Please try again later.',
      'ให้ AI คิดแคปชั่นไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
          'AI could not write a caption. Please try again.',
      'AI วิเคราะห์คลิปไม่สำเร็จ แคปชันนี้เป็นข้อความสำรอง กรุณาตรวจและแก้ไขก่อนใช้ · ไม่หักโควตา AI':
          'AI could not analyze the video. This is fallback text. Review and edit it before use. · No AI quota charged',
    }.entries) {
      expect(localizeCaptionMessage(context, entry.key), entry.value);
    }
    for (final raw in [
      'provider-html <b>แคปชั่น</b>',
      'custom\nสไตล์การเขียน',
      'แคปชั่น My Custom Channel',
      'เลือกบัญชีปลายทางและตั้งค่าของแต่ละช่องทาง',
      'ตรวจข้อมูลและเลือกเวลาที่ต้องการโพสต์'
    ]) {
      expect(localizeCaptionMessage(context, raw), raw);
    }
  });

  testWidgets(
      'plain app uses Thai fallback and supported non-Thai locales use English',
      (tester) async {
    late BuildContext fallback;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      fallback = context;
      return const CaptionText('แคปชั่น');
    })));
    expect(captionUsesThai(fallback), isTrue);
    expect(find.text('แคปชั่น'), findsOneWidget);
    expect(captionText(fallback, 'ไทย', 'English'), 'ไทย');
    for (final language in ['en', 'vi', 'ja']) {
      final context = await _context(tester, language);
      expect(captionUsesThai(context), isFalse);
      expect(localizeCaptionMessage(context, 'แคปชั่น'), 'Caption');
      expect(captionText(context, 'ไทย', 'English'), 'English');
    }
  });

  testWidgets(
      'leaf caption labels switch locale while identical user text stays raw',
      (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
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
                CaptionText('แคปชั่น'),
                Text('แคปชั่น', key: ValueKey('raw-caption'))
              ]),
            )));
    await tester.pumpAndSettle();
    expect(find.text('Caption'), findsOneWidget);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('แคปชั่น'), findsNWidgets(2));
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Caption'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('raw-caption'))).data,
        'แคปชั่น');
  });
}
