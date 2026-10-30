import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/onboarding/onboarding_localizations.dart';

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
  testWidgets('Thai and no app delegate preserve original onboarding copy',
      (tester) async {
    for (final language in <String?>[null, 'th']) {
      final context = await _context(tester, language);
      expect(onboardingUsesThai(context), isTrue);
      for (final raw in _messages.keys) {
        expect(localizeOnboardingMessage(context, raw), raw);
      }
      expect(onboardingText(context, 'ภาษาไทย', 'English'), 'ภาษาไทย');
      expect(onboardingStepLabel(context, 2, 3), 'ขั้นตอนที่ 2 จาก 3');
    }
  });
  testWidgets('English onboarding uses the agreed channel and caption copy',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(localizeOnboardingMessage(context, 'เชื่อมช่องทางครั้งเดียว'),
        'Connect your channels once');
    expect(
        localizeOnboardingMessage(context,
            'เลือกวิดีโอ 9:16 หนึ่งคลิป แล้วส่งขึ้นทุกช่องทางพร้อมกัน พร้อม AI ช่วยใส่แคปชั่นภาษาไทย'),
        'Choose one 9:16 video and send it to all your channels, with AI to help write Thai captions.');
  });
  testWidgets('English typed step label and action remain localized',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(onboardingStepLabel(context, 2, 3), 'Step 2 of 3');
    expect(onboardingText(context, 'ภาษาไทย', 'English'), 'English');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const OnboardingText('เริ่มใช้งาน'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('all non-Thai app locales use the exact agreed onboarding copy',
      (tester) async {
    for (final language in ['en', 'vi', 'zh', 'id', 'ms', 'tl', 'ja']) {
      final context = await _context(tester, language);
      expect(onboardingUsesThai(context), isFalse);
      for (final entry in _messages.entries) {
        expect(localizeOnboardingMessage(context, entry.key), entry.value);
      }
      for (final (current, total) in [(1, 3), (2, 3), (3, 3), (12, 20)]) {
        expect(onboardingStepLabel(context, current, total),
            'Step $current of $total');
      }
    }
  });

  testWidgets('native language names and unknown or near-match data stay raw',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final raw in [
      'ไทย',
      'English',
      'user@example.com',
      'คลิปเดียว โพสต์ได้ทุกที่.mp4',
      'ขั้นตอนที่ 2 จาก 3',
      'provider error: ถัดไป',
      for (final key in _messages.keys) ...[' $key', '$key\n', '$key!'],
    ]) {
      expect(localizeOnboardingMessage(context, raw), raw);
    }
  });

  testWidgets(
      'OnboardingText follows live locale while raw text remains intact',
      (tester) async {
    final locale = ValueNotifier(const Locale('th'));
    addTearDown(locale.dispose);
    const stored = 'เชื่อมช่องทางครั้งเดียว';
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
      valueListenable: locale,
      builder: (_, value, __) => MaterialApp(
        locale: value,
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Column(children: [
          OnboardingText(stored),
          Text(stored, key: ValueKey('raw-data')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(stored), findsNWidgets(2));
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Connect your channels once'), findsOneWidget);
    expect(find.text(stored), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('raw-data'))).data,
        stored);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text(stored), findsNWidgets(2));
  });

  testWidgets('OnboardingText preserves its key and Text presentation options',
      (tester) async {
    const style = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
    const key = ValueKey('localized-action');
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: OnboardingText('เริ่มใช้งาน',
          key: key,
          style: style,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.fade,
          softWrap: true),
    ));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(
        find.descendant(of: find.byKey(key), matching: find.byType(Text)));
    expect(text.data, 'Get started');
    expect(text.style, style);
    expect(text.textAlign, TextAlign.center);
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.fade);
    expect(text.softWrap, isTrue);
  });
}

const _messages = <String, String>{
  'เชื่อมช่องทางครั้งเดียว': 'Connect your channels once',
  'เชื่อม TikTok, YouTube Shorts, Instagram Reels และ Facebook Reels บนเพจ ไม่ต้องสลับหลายแอป':
      'Connect TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Reels without switching between apps.',
  'คลิปเดียว โพสต์ได้ทุกที่': 'One video. Every channel.',
  'เลือกวิดีโอ 9:16 หนึ่งคลิป แล้วส่งขึ้นทุกช่องทางพร้อมกัน พร้อม AI ช่วยใส่แคปชั่นภาษาไทย':
      'Choose one 9:16 video and send it to all your channels, with AI to help write Thai captions.',
  'ตั้งเวลา + ดูยอดที่เดียว': 'Schedule and track in one place',
  'วางแผนโพสต์ในปฏิทิน แล้วดูยอดวิว ไลก์ และเอนเกจเมนต์รวมทุกแพลตฟอร์มในหน้าเดียว':
      'Plan posts in your calendar, then see views, likes, and engagement across platforms in one place.',
  'ข้าม': 'Skip',
  'ย้อนกลับ': 'Back',
  'ถัดไป': 'Next',
  'เริ่มใช้งาน': 'Get started',
  'ภาษา': 'Language',
  'เปลี่ยนภาษา': 'Change language',
};
