import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/uploader/review_localizations.dart';

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
              GlobalCupertinoLocalizations.delegate
            ],
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      })));
  await tester.pumpAndSettle();
  return context;
}

void main() {
  testWidgets('Thai fallback is exact and non-Thai uses English',
      (tester) async {
    for (final language in <String?>[null, 'th', 'en', 'vi']) {
      final context = await _context(tester, language);
      final thai = language == null || language == 'th';
      expect(reviewUsesThai(context), thai);
      expect(localizeReviewMessage(context, 'พรีวิว'),
          thai ? 'พรีวิว' : 'Preview');
      expect(reviewText(context, 'ไทย', 'English'), thai ? 'ไทย' : 'English');
    }
  });
  testWidgets('strict outcomes retain draft destination, count and local clock',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(localizeReviewMessage(context, 'โพสต์ไปยัง 1 ช่องทาง'),
        'Post to 1 channel');
    expect(localizeReviewMessage(context, 'โพสต์ไปยัง 4 ช่องทาง'),
        'Post to 4 channels');
    expect(
        localizeReviewMessage(
            context, 'ส่งเป็นร่างเข้า TikTok · ส่งออกจริงและใช้โควตาโพสต์'),
        'Send as draft to TikTok · Sends the video and uses your post quota.');
    expect(
        localizeReviewMessage(context,
            'ส่งเข้าร่างเวลา 30 ต.ค. 09:05 น. · Facebook Page · ส่งออกจริงและใช้โควตาโพสต์'),
        'Send to drafts on 30 Oct at 09:05 · Facebook Page · Sends the post and uses your post quota.');
    expect(
        localizeReviewMessage(
            context, 'โพสต์ตรง · เฉพาะฉัน · TikTok อาจประมวลผลหลายนาที'),
        'Direct post · Only me · TikTok may take several minutes to process.');
  });
  testWidgets('known answer details translate but unknown raw data never does',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(localizeReviewMessage(context, 'สำหรับเด็ก: ไม่ใช่'),
        'Made for kids: No');
    expect(
        localizeReviewMessage(context, 'สร้างโดย AI: ยังไม่ระบุ (ไม่บังคับ)'),
        'AI-generated: Not specified (optional)');
    for (final raw in [
      'ชื่อวิดีโอ: พรีวิว',
      'provider: พรีวิว',
      'โพสต์ไปยัง 4 ช่องทาง\n',
      'ส่งเป็นร่างเข้า ร้านของฉัน · ส่งออกจริงและใช้โควตาโพสต์',
      'สำหรับเด็ก: ข้อมูลร้าน'
    ]) {
      expect(localizeReviewMessage(context, raw), raw);
    }
  });
  testWidgets(
      'schedule policy translates only the exact 14 and 30 day messages',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final days in [14, 30]) {
      final base =
          'ตั้งเวลาโพสต์ล่วงหน้าได้สูงสุด $days วัน กรุณาเลือกเวลาใหม่';
      expect(localizeReviewMessage(context, base),
          'You can schedule posts up to $days days ahead. Choose another time.');
      expect(
          localizeReviewMessage(context,
              '$base หากเคยกดยืนยันแล้ว ให้ตรวจปฏิทินก่อนเริ่มโพสต์ใหม่'),
          'You can schedule posts up to $days days ahead. Choose another time. If you already confirmed, check Calendar before starting a new post.');
    }
    const raw = 'ตั้งเวลาโพสต์ล่วงหน้าได้สูงสุด 90 วัน กรุณาเลือกเวลาใหม่';
    expect(localizeReviewMessage(context, raw), raw);
    expect(
        localizeReviewMessage(
            context, 'การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299'),
        'Scheduling requires Starter (199 THB) or Pro (299 THB).');
    expect(
        localizeReviewMessage(
            context, 'ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่ก่อนตั้งเวลา'),
        'Could not verify your plan. Try again before scheduling.');
    expect(
        localizeReviewMessage(context,
            'Starter ตั้งเวลาล่วงหน้าได้ 14 วัน และ Pro 30 วัน กรุณาเลือกเวลาใหม่'),
        'Starter allows scheduling up to 14 days ahead and Pro up to 30 days. Choose another time.');
  });
  testWidgets(
      'phone verification explains free post units without changing Thai',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(
        localizeReviewMessage(
            context, 'ยืนยันเบอร์โทรก่อนโพสต์ฟรี 3 ครั้งต่อเดือน'),
        'Verify your phone number before using the 3 free post units per month.');
  });
  testWidgets('draft readiness accepts only an exact finite platform list',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(
        localizeReviewMessage(context,
            'เชื่อมช่องทางที่เก็บไว้ในร่างให้ครบก่อนโพสต์: TikTok, Facebook Reels'),
        'Reconnect all channels saved in this draft before posting: TikTok, Facebook Reels');
    for (final raw in [
      'เชื่อมช่องทางที่เก็บไว้ในร่างให้ครบก่อนโพสต์: My shop',
      'เชื่อมช่องทางที่เก็บไว้ในร่างให้ครบก่อนโพสต์: TikTok, Unknown',
      'เชื่อมช่องทางที่เก็บไว้ในร่างให้ครบก่อนโพสต์: TikTok\n',
      'เชื่อมช่องทางที่เก็บไว้ในร่างให้ครบก่อนโพสต์: TikTok, TikTok'
    ]) {
      expect(localizeReviewMessage(context, raw), raw);
    }
  });
}
