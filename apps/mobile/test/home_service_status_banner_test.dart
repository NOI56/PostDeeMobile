import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:postdee_mobile/features/home/home_service_status_banner.dart';

ServiceIncidentResult _incident({
  String id = 'incident-1',
  String stage = 'IDENTIFIED',
  List<String> platforms = const ['TIKTOK'],
}) =>
    ServiceIncidentResult(
      id: id,
      title: 'TikTok ส่งคลิปช้ากว่าปกติ',
      message: 'โพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ ไม่ต้องส่งซ้ำ',
      platforms: platforms,
      stage: stage,
      updatedAt: DateTime(2026, 10, 28, 14, 5),
    );

Widget _app(Widget body, {Locale locale = const Locale('th')}) => MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: body),
    );

HomeScreen _home(HomeServiceStatusLoader loadServiceStatus) => HomeScreen(
      loadServiceStatus: loadServiceStatus,
      loadSubscription: () async => const SubscriptionStatusResult(
        userId: 'status-owner',
        plan: 'BASIC',
        status: 'ACTIVE',
        remainingPostsThisMonth: 3,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false,
      ),
      loadRecentPosts: () async => const <PostSummaryResult>[],
      loadDrafts: () async => const [],
      loadConnections: () async => const <SocialConnectionResult>[],
      loadScheduledPosts: () async => const <PostSummaryResult>[],
      loadLinkProfile: () async => null,
      onCreatePost: () async {},
      now: () => DateTime(2026, 10, 28, 15),
    );

void main() {
  group('Home service status banner', () {
    setUp(() => PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'status-owner', idToken: 'token')));
    tearDown(PostDeeAuthSessionStore.instance.clear);

    testWidgets('shows open notices at the top of Home', (tester) async {
      await tester.pumpWidget(_app(_home(() async => [_incident()])));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('service-incident-incident-1')),
          findsOneWidget);
      expect(find.text('TikTok ส่งคลิปช้ากว่าปกติ'), findsOneWidget);
      expect(find.text('โพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ ไม่ต้องส่งซ้ำ'),
          findsOneWidget);
      expect(find.text('พบสาเหตุแล้ว · กำลังแก้ไข'), findsOneWidget);
      expect(find.text('กระทบ TikTok · อัปเดต 14:05 น.'), findsOneWidget);
      final bannerTop = tester
          .getTopLeft(find.byKey(const ValueKey('service-incident-incident-1')))
          .dy;
      expect(bannerTop, lessThan(tester.getTopLeft(find.text('แพ็กเกจฟรี')).dy));
    });

    testWidgets('stays hidden when there is no notice or the read fails',
        (tester) async {
      await tester.pumpWidget(_app(_home(() async => const [])));
      await tester.pumpAndSettle();
      expect(find.byType(HomeServiceStatusBanner), findsOneWidget);
      expect(find.byKey(const ValueKey('service-incident-incident-1')),
          findsNothing);

      await tester.pumpWidget(_app(_home(() async => throw StateError('offline'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('service-incident-incident-1')),
          findsNothing);
      expect(find.textContaining('ลองใหม่'), findsNothing);
    });

    testWidgets('pull refresh picks up a resolved notice without a Home error',
        (tester) async {
      var incidents = [_incident()];
      var failNext = false;
      await tester.pumpWidget(_app(_home(() async {
        if (failNext) throw StateError('offline');
        return incidents;
      })));
      await tester.pumpAndSettle();
      expect(find.text('TikTok ส่งคลิปช้ากว่าปกติ'), findsOneWidget);

      failNext = true;
      await tester
          .widget<RefreshIndicator>(
              find.byKey(const ValueKey('home-pull-refresh')))
          .onRefresh();
      await tester.pumpAndSettle();
      // A failed status read keeps the last known notice and is not a Home failure.
      expect(find.text('TikTok ส่งคลิปช้ากว่าปกติ'), findsOneWidget);
      expect(find.text('อัปเดตข้อมูลล่าสุดแล้ว'), findsOneWidget);

      failNext = false;
      incidents = [];
      await tester
          .widget<RefreshIndicator>(
              find.byKey(const ValueKey('home-pull-refresh')))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('TikTok ส่งคลิปช้ากว่าปกติ'), findsNothing);
    });

    testWidgets('names the whole app and dates older updates in English',
        (tester) async {
      await tester.pumpWidget(_app(
        HomeServiceStatusBanner(
          isActive: true,
          now: () => DateTime(2026, 10, 29, 9),
          loadStatus: () async =>
              [_incident(stage: 'MONITORING', platforms: const [])],
        ),
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Fixed · monitoring'), findsOneWidget);
      expect(find.text('Whole app · updated 28/10 14:05'), findsOneWidget);
    });
  });
}
