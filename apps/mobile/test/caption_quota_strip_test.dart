import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/caption_quota_strip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Anuphan')
      ..addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-SemiBold.ttf'));
    await fonts.load();
  });
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets('shows the current Starter quota in a compact strip',
      (tester) async {
    await tester.pumpWidget(_host(
      plan: 'STARTER',
      quota: const RealClipCaptionQuota(
        limit: 50,
        usedThisMonth: 12,
        remainingThisMonth: 38,
      ),
    ));

    expect(find.text('Starter'), findsOneWidget);
    expect(find.text('แคปชั่น AI คงเหลือ'), findsOneWidget);
    expect(find.text('38 / 50 ครั้ง', findRichText: true), findsOneWidget);
    expect(find.text('ใช้ไป 12 ครั้ง'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, closeTo(0.76, 0.0001));
    expect(progress.semanticsLabel, 'แคปชั่น AI เหลือ 38 จาก 50 ครั้ง');
    expect(
      tester
          .getSize(find.byKey(
            const ValueKey('uploader-ai-caption-quota-strip'),
          ))
          .height,
      lessThanOrEqualTo(96),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the supplied Pro quota rather than a fixed plan limit',
      (tester) async {
    await tester.pumpWidget(_host(
      plan: 'PRO',
      quota: const RealClipCaptionQuota(
        limit: 120,
        usedThisMonth: 3,
        remainingThisMonth: 117,
      ),
    ));

    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('117 / 120 ครั้ง', findRichText: true), findsOneWidget);
    expect(find.text('ใช้ไป 3 ครั้ง'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value,
      closeTo(0.975, 0.0001),
    );
  });

  testWidgets('shows exhausted quota and keeps actual use after a downgrade',
      (tester) async {
    await tester.pumpWidget(_host(
      plan: 'STARTER',
      quota: const RealClipCaptionQuota(
        limit: 50,
        usedThisMonth: 63,
        remainingThisMonth: 0,
      ),
    ));

    expect(find.text('0 / 50 ครั้ง', findRichText: true), findsOneWidget);
    expect(find.text('ใช้ไป 63 ครั้ง'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps purchased credits visible when monthly quota is exhausted',
      (tester) async {
    await tester.pumpWidget(_host(
      plan: 'STARTER',
      quota: const RealClipCaptionQuota(
        limit: 50,
        usedThisMonth: 50,
        remainingThisMonth: 0,
        addonRemaining: 8,
        availableGenerations: 8,
      ),
    ));
    expect(find.text('0 / 50 ครั้ง', findRichText: true), findsOneWidget);
    expect(find.text('+ เครดิตเติม 8 ครั้ง'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not divide by zero when a limit is unavailable',
      (tester) async {
    await tester.pumpWidget(_host(
      plan: 'BASIC',
      quota: const RealClipCaptionQuota(
        limit: 0,
        usedThisMonth: 12,
        remainingThisMonth: 0,
      ),
    ));

    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('fits narrow width and enlarged text in ${themeMode.name} mode',
        (tester) async {
      await tester.pumpWidget(_host(
        plan: 'STARTER',
        quota: const RealClipCaptionQuota(
          limit: 50,
          usedThisMonth: 12,
          remainingThisMonth: 38,
        ),
        width: 280,
        textScaler: const TextScaler.linear(2),
        themeMode: themeMode,
      ));

      expect(find.text('Starter'), findsOneWidget);
      expect(find.text('38 / 50 ครั้ง', findRichText: true), findsOneWidget);
      expect(find.text('ใช้ไป 12 ครั้ง'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(
              const ValueKey('uploader-ai-caption-quota-strip'),
            ))
            .width,
        280,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _host({
  required String plan,
  required RealClipCaptionQuota quota,
  double width = 340,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
}) {
  AppTheme.applyThemeMode(themeMode);
  return MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: themeMode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: CaptionQuotaStrip(plan: plan, quota: quota),
        ),
      ),
    ),
  );
}
