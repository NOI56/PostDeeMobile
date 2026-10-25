import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/post_quota_strip.dart';

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

  for (final sample in [
    (plan: 'BASIC', label: 'Basic', limit: 3, used: 1, remaining: 2),
    (plan: 'STARTER', label: 'Starter', limit: 120, used: 13, remaining: 107),
    (plan: 'PRO', label: 'Pro', limit: 250, used: 8, remaining: 242),
  ]) {
    testWidgets('${sample.label} shows supplied monthly posting units',
        (tester) async {
      await tester.pumpWidget(_host(_subscription(
        plan: sample.plan,
        limit: sample.limit,
        used: sample.used,
        remaining: sample.remaining,
      )));

      expect(find.text('โพสต์คงเหลือ'), findsOneWidget);
      expect(find.text(sample.label), findsOneWidget);
      expect(
          find.text('${sample.remaining} / ${sample.limit} หน่วย',
              findRichText: true),
          findsOneWidget);
      expect(find.text('ใช้ไป ${sample.used} หน่วย'), findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('uploader-post-quota-progress')));
      expect(progress.value, closeTo(sample.remaining / sample.limit, 0.0001));
      expect(progress.semanticsLabel,
          'โพสต์เหลือ ${sample.remaining} จาก ${sample.limit} หน่วย');
      expect(
          tester
              .getSize(find.byKey(const ValueKey('uploader-post-quota-strip')))
              .height,
          lessThanOrEqualTo(96));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'keeps purchased posting units separate from exhausted monthly use',
      (tester) async {
    await tester.pumpWidget(_host(_subscription(
        plan: 'STARTER', limit: 120, used: 120, remaining: 0, addon: 18)));

    expect(find.text('0 / 120 หน่วย', findRichText: true), findsOneWidget);
    expect(find.text('ใช้ไป 120 หน่วย'), findsOneWidget);
    expect(find.text('+ เครดิตเติม 18 หน่วย'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('uploader-post-quota-progress')))
            .value,
        0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Basic phone gate explains zero remaining without showing bank',
      (tester) async {
    await tester.pumpWidget(_host(_subscription(
        plan: 'BASIC',
        limit: 3,
        used: 0,
        remaining: 0,
        addon: 100,
        requiresPhoneVerification: true)));

    expect(find.text('0 / 3 หน่วย', findRichText: true), findsOneWidget);
    expect(find.text('ใช้ไป 0 หน่วย'), findsOneWidget);
    expect(find.text('ยืนยันเบอร์เพื่อใช้โควตาฟรี'), findsOneWidget);
    expect(find.textContaining('เครดิตเติม'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Basic never presents retained paid units as spendable',
      (tester) async {
    await tester.pumpWidget(_host(_subscription(
        plan: 'BASIC', limit: 3, used: 1, remaining: 2, addon: 100)));

    expect(find.text('2 / 3 หน่วย', findRichText: true), findsOneWidget);
    expect(find.textContaining('เครดิตเติม'), findsNothing);
    expect(find.text('ยืนยันเบอร์เพื่อใช้โควตาฟรี'), findsNothing);
  });

  testWidgets('preserves actual used units after a plan downgrade',
      (tester) async {
    await tester.pumpWidget(_host(
        _subscription(plan: 'STARTER', limit: 120, used: 180, remaining: 0)));

    expect(find.text('ใช้ไป 180 หน่วย'), findsOneWidget);
    expect(find.text('0 / 120 หน่วย', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing monthly data never becomes fabricated zero quota',
      (tester) async {
    for (final subscription in [
      _subscription(limit: null),
      _subscription(used: null),
      _subscription(remaining: null),
    ]) {
      await tester.pumpWidget(_host(subscription));
      expect(find.text('โพสต์คงเหลือ'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('0 /', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('zero limit stays finite', (tester) async {
    await tester.pumpWidget(
        _host(_subscription(plan: 'BASIC', limit: 0, used: 0, remaining: 0)));
    expect(find.text('0 / 0 หน่วย', findRichText: true), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('uploader-post-quota-progress')))
            .value,
        0);
    expect(tester.takeException(), isNull);
  });

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('narrow large text fits in ${themeMode.name} mode',
        (tester) async {
      for (final subscription in [
        _subscription(
            plan: 'PRO', limit: 250, used: 25, remaining: 225, addon: 100),
        _subscription(
            plan: 'BASIC',
            limit: 3,
            used: 0,
            remaining: 0,
            requiresPhoneVerification: true),
      ]) {
        await tester.pumpWidget(_host(subscription,
            width: 280,
            textScaler: const TextScaler.linear(2),
            themeMode: themeMode));
        expect(
            tester
                .getSize(
                    find.byKey(const ValueKey('uploader-post-quota-strip')))
                .width,
            280);
        expect(tester.takeException(), isNull);
      }
    });
  }
}

SubscriptionStatusResult _subscription({
  String plan = 'STARTER',
  int? limit = 120,
  int? used = 13,
  int? remaining = 107,
  int addon = 0,
  bool requiresPhoneVerification = false,
}) =>
    SubscriptionStatusResult(
      userId: 'owner-a',
      plan: plan,
      status: 'ACTIVE',
      monthlyPostLimit: limit,
      usedPostsThisMonth: used,
      remainingPostsThisMonth: remaining,
      addonPostUnits: addon,
      canSchedule: plan != 'BASIC',
      canUseAiCaptions: plan != 'BASIC',
      canUseAnalytics: plan == 'PRO',
      requiresPhoneVerification: requiresPhoneVerification,
    );

Widget _host(
  SubscriptionStatusResult subscription, {
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
                child: PostQuotaStrip(subscription: subscription)))),
  );
}
