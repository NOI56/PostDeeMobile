import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/uploader/channel_localizations.dart';

Future<BuildContext> _context(WidgetTester tester, {String? language}) async {
  late BuildContext result;
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
      home: Builder(builder: (context) {
        result = context;
        return const SizedBox();
      })));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('Thai fallback and explicit Thai preserve original messages',
      (tester) async {
    for (final language in <String?>[null, 'th']) {
      final context = await _context(tester, language: language);
      expect(channelUsesThai(context), isTrue);
      expect(localizeChannelMessage(context, 'บันทึกการตั้งค่า'),
          'บันทึกการตั้งค่า');
      expect(channelText(context, 'ไทย', 'English'), 'ไทย');
    }
  });
  testWidgets('known app controls and validations render English',
      (tester) async {
    final context = await _context(tester, language: 'en');
    expect(
        localizeChannelMessage(context, 'บันทึกการตั้งค่า'), 'Save settings');
    expect(localizeChannelMessage(context, 'ยังยืนยันบัญชีไม่ได้'),
        'Account not confirmed');
    expect(localizeChannelMessage(context, 'เลือกผู้ที่สามารถดูวิดีโอ TikTok'),
        'Choose who can view this TikTok video.');
    expect(localizeChannelMessage(context, 'เพิ่มชื่อวิดีโอ YouTube'),
        'Add a YouTube video title.');
  });
  testWidgets(
      'strict dynamic patterns preserve numeric values and unknown text',
      (tester) async {
    final context = await _context(tester, language: 'en');
    expect(localizeChannelMessage(context, 'เชื่อมต่อแล้ว 1 ช่องทาง'),
        '1 channel connected');
    expect(localizeChannelMessage(context, 'เชื่อมต่อแล้ว 4 ช่องทาง'),
        '4 channels connected');
    expect(localizeChannelMessage(context, 'โพสต์ตรง · เฉพาะฉัน'),
        'Direct post · Only me');
    for (final raw in [
      'provider: บันทึกการตั้งค่า',
      'เชื่อมต่อแล้ว 4 ช่องทาง\n',
      'โพสต์ตรง · ร้านของฉัน',
      'merchant supplied caption'
    ]) {
      expect(localizeChannelMessage(context, raw), raw);
    }
  });
  testWidgets('known readiness prefixes preserve unknown provider payloads',
      (tester) async {
    final context = await _context(tester, language: 'en');
    expect(
        localizeChannelMessage(context, 'TikTok: ต้องเชื่อมบัญชีใหม่ก่อนโพสต์'),
        'TikTok: Reconnect this account before posting');
    expect(
        localizeChannelMessage(context,
            'บัญชี Facebook Reels เปลี่ยนแล้ว กรุณารีเฟรชช่องทางและตรวจทานใหม่'),
        'The Facebook Reels account has changed. Refresh channels and review your settings again.');
    for (final raw in [
      'My store: ต้องเชื่อมบัญชีใหม่ก่อนโพสต์',
      'TikTok: provider supplied detail',
      'บัญชี ร้านของฉัน เปลี่ยนแล้ว กรุณารีเฟรชช่องทางและตรวจทานใหม่'
    ]) {
      expect(localizeChannelMessage(context, raw), raw);
    }
  });
  testWidgets('remembered-settings and connection errors use exact app keys',
      (tester) async {
    final context = await _context(tester, language: 'en');
    expect(
        localizeChannelMessage(
            context, 'ตรวจสอบช่องทางที่เชื่อมต่อไม่สำเร็จ ลองใหม่อีกครั้ง'),
        'Could not check connected channels. Please try again.');
    expect(
        localizeChannelMessage(context,
            'ใช้การตั้งค่ากับคลิปนี้แล้ว แต่จำค่าไว้ครั้งถัดไปไม่สำเร็จ'),
        'Settings applied to this video, but they could not be remembered for next time.');
    expect(
        localizeChannelMessage(context,
            'โหลดค่าที่จำไว้ไม่สำเร็จ กรุณาเปิดตั้งค่าช่องทางเพื่อตรวจสอบก่อน'),
        'Could not load remembered settings. Open channel settings to review them first.');
    expect(
        localizeChannelMessage(
            context, 'ตรวจสิทธิ์เผยแพร่ไม่สำเร็จ กรุณารีเฟรชช่องทางก่อนโพสต์'),
        'Could not check publishing permissions. Refresh channels before posting.');
  });
  testWidgets('policy fallback translates only the two actual public URLs',
      (tester) async {
    final context = await _context(tester, language: 'en');
    const prefix =
        'เปิดเงื่อนไข TikTok ไม่สำเร็จ ลองใหม่หรือเปิดลิงก์นี้ในเบราว์เซอร์: ';
    for (final url in [
      'https://www.tiktok.com/legal/page/global/music-usage-confirmation/en',
      'https://www.tiktok.com/legal/page/global/bc-policy/en'
    ]) {
      expect(localizeChannelMessage(context, '$prefix$url'),
          'Could not open TikTok terms. Try again or open this link in your browser: $url');
    }
    const unknown = '${prefix}https://unknown.example/raw';
    expect(localizeChannelMessage(context, unknown), unknown);
  });
  testWidgets('leaf locale changes never translate identical merchant text',
      (tester) async {
    final locale = ValueNotifier(const Locale('th'));
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
              ChannelText('บันทึกการตั้งค่า'),
              Text('บันทึกการตั้งค่า', key: ValueKey('raw-title'))
            ]))));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกการตั้งค่า'), findsNWidgets(2));
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Save settings'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('raw-title'))).data,
        'บันทึกการตั้งค่า');
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('บันทึกการตั้งค่า'), findsNWidgets(2));
  });
}
