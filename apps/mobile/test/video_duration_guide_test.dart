import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/video_duration_guide.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';

Widget guide(
    {double? duration,
    int? tikTokMax,
    bool direct = false,
    bool english = false,
    bool dark = false}) {
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return MaterialApp(
    locale: Locale(english ? 'en' : 'th'),
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
        body: SingleChildScrollView(
            child: Padding(
      padding: AppTheme.screenPadding,
      child: VideoDurationGuide(
          durationSeconds: duration,
          tikTokMaxDurationSeconds: tikTokMax,
          tikTokPublishMode: direct
              ? TikTokPublishMode.directPost
              : TikTokPublishMode.inboxDraft),
    ))),
  );
}

void main() {
  testWidgets(
      'show seconds before selecting a clip without claiming compatibility',
      (tester) async {
    await tester.pumpWidget(guide());
    await tester.pumpAndSettle();
    expect(find.textContaining('600'), findsOneWidget);
    expect(find.textContaining('3–90 '), findsOneWidget);
    expect(find.textContaining('3–900 '), findsOneWidget);
    expect(find.textContaining('180'), findsOneWidget);
    expect(find.text('ผ่านเกณฑ์เวลา'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a 200 second clip exceeds Facebook and Shorts but TikTok stays unknown',
      (tester) async {
    await tester.pumpWidget(guide(duration: 200));
    await tester.pumpAndSettle();
    expect(find.text('ยาวเกิน 110 วินาที'), findsOneWidget);
    expect(find.text('ยาวเกิน 20 วินาที'), findsOneWidget);
    expect(find.text('ผ่านเกณฑ์เวลา'), findsOneWidget);
    expect(find.text('โพสต์ตรง: รอตรวจบัญชี'), findsOneWidget);
    expect(find.text('เวลาส่งร่างผ่านเกณฑ์'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'TikTok uses actual creator limit and respects the integration ceiling',
      (tester) async {
    await tester.pumpWidget(guide(duration: 200, tikTokMax: 180, direct: true));
    await tester.pumpAndSettle();
    expect(find.text('ยาวเกิน 20 วินาที'), findsNWidgets(2));
    expect(find.text('รอตรวจบัญชี'), findsNothing);
    await tester
        .pumpWidget(guide(duration: 601, tikTokMax: 3600, direct: true));
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ตรง: สูงสุด 600 วินาที'), findsOneWidget);
    expect(find.text('ยาวเกิน 1 วินาที'), findsOneWidget);
  });

  testWidgets('unknown Direct Post account never promises the transfer ceiling',
      (tester) async {
    await tester.pumpWidget(guide(duration: 45, direct: true));
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ตรง: รอตรวจบัญชี'), findsOneWidget);
    expect(find.text('รอตรวจบัญชี'), findsOneWidget);
    expect(find.text('โพสต์ตรง: สูงสุด 600 วินาที'), findsNothing);
    expect(find.text('ผ่านเกณฑ์เวลา'), findsNWidgets(3));
  });

  testWidgets(
      'draft transfer keeps its own limit when Direct account allows less',
      (tester) async {
    await tester.pumpWidget(guide(duration: 200, tikTokMax: 180));
    await tester.pumpAndSettle();
    expect(find.text('ส่งเป็นร่าง: สูงสุด 600 วินาที'), findsOneWidget);
    expect(find.text('โพสต์ตรง: สูงสุด 180 วินาที'), findsOneWidget);
    expect(find.text('เวลาส่งร่างผ่านเกณฑ์'), findsOneWidget);
    expect(find.text('ยาวเกิน 20 วินาที'), findsOneWidget); // Shorts only.
  });

  testWidgets('both Reel destinations show the exact minimum', (tester) async {
    await tester.pumpWidget(guide(duration: 2.9));
    await tester.pumpAndSettle();
    expect(find.text('ต้องยาวอย่างน้อย 3 วินาที'), findsNWidgets(2));
  });

  testWidgets('small phone and English dark variant have no layout errors',
      (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(guide(duration: 200, english: true, dark: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('200'), findsOneWidget);
    expect(find.textContaining('180'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
