import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';

const _plan = SubscriptionStatusResult(
  userId: 'home-owner',
  plan: 'PRO',
  status: 'ACTIVE',
  remainingPostsThisMonth: 248,
  canSchedule: true,
  canUseAiCaptions: true,
  canUseAnalytics: true,
);

LinkInBioProfileResult _shop({bool published = true, Uri? url}) =>
    LinkInBioProfileResult(
      storeName: 'ร้านของฉัน',
      slug: 'my-shop',
      links: const [],
      isPublished: published,
      updatedAt: DateTime.utc(2026, 10, 11),
      publicUrl: url,
    );

Widget _app(HomeScreen home, {double scale = 1}) => MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('th'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: home),
    );

HomeScreen _home({
  HomeLinkProfileLoader? shop,
  HomeSubscriptionLoader? plan,
  VoidCallback? openShop,
  VoidCallback? openNotifications,
  Future<void> Function()? createPost,
}) =>
    HomeScreen(
      loadSubscription: plan ?? () async => _plan,
      loadRecentPosts: () async => const [],
      loadDrafts: () async => const [],
      loadConnections: () async => const [],
      loadScheduledPosts: () async => const [],
      loadLinkProfile: shop ?? () async => null,
      onOpenLinkInBio: openShop,
      onOpenNotifications: openNotifications,
      onCreatePost: createPost ?? () async {},
    );

void main() {
  setUp(() => PostDeeAuthSessionStore.instance
      .signIn(const AuthSession(userId: 'home-owner', idToken: 'test-token')));
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets('notification button exposes one enabled accessibility tap',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var opens = 0;
    await tester.pumpWidget(_app(_home(openNotifications: () => opens++)));
    await tester.pumpAndSettle();

    final notifications = find.bySemanticsLabel('แจ้งเตือน');
    final node = tester.getSemantics(notifications);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      node,
      isSemantics(
        label: 'แจ้งเตือน',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(opens, 1);

    await tester.tap(notifications);
    await tester.pumpAndSettle();
    expect(opens, 2);

    await tester.pumpWidget(_app(_home()));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(notifications),
      isSemantics(
        label: 'แจ้งเตือน',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('keeps real quota compact and primary action above recent posts',
      (tester) async {
    var creates = 0;
    await tester.pumpWidget(_app(_home(createPost: () async {
      creates++;
    })));
    await tester.pumpAndSettle();
    expect(find.text('เหลือ 248/250 หน่วย'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-plan-progress-fill')), findsNothing);
    final planRect =
        tester.getRect(find.byKey(const ValueKey('home-plan-summary')));
    expect(planRect.height, lessThanOrEqualTo(64));
    expect(tester.getTopLeft(find.text('เริ่มโพสต์แรกของคุณ')).dy,
        lessThan(tester.getTopLeft(find.text('โพสต์ล่าสุด')).dy));
    await tester.tap(find.text('สร้างโพสต์แรก'));
    await tester.pumpAndSettle();
    expect(creates, 1);
  });

  testWidgets('does not invent remaining units when API omitted quota',
      (tester) async {
    await tester.pumpWidget(_app(_home(
        plan: () async => const SubscriptionStatusResult(
              userId: 'home-owner',
              plan: 'PRO',
              status: 'ACTIVE',
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true,
            ))));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่ทราบหน่วยคงเหลือ'), findsOneWidget);
    expect(find.text('เหลือ 1/250 หน่วย'), findsNothing);
  });

  testWidgets('publishes status only with a server confirmed public URL',
      (tester) async {
    for (final confirmed in [false, true]) {
      await tester.pumpWidget(_app(_home(
          shop: () async => _shop(
              url: confirmed
                  ? Uri.parse('https://example.com/p/my-shop')
                  : null))));
      await tester.pumpAndSettle();
      expect(
          find.text('เผยแพร่แล้ว'), confirmed ? findsOneWidget : findsNothing);
      if (!confirmed) expect(find.text('ยังไม่เผยแพร่'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('shop failure offers retry without claiming no saved shop',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(_app(_home(shop: () async {
      if (++loads == 1) throw StateError('offline');
      return _shop(url: Uri.parse('https://example.com/p/my-shop'));
    })));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจสอบลิงก์ร้านไม่ได้'), findsOneWidget);
    expect(find.text('สร้างหน้าร้าน'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('home-shop-retry')));
    await tester.tap(find.byKey(const ValueKey('home-shop-retry')));
    await tester.pumpAndSettle();
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
    expect(loads, 2);
  });

  testWidgets('late shop completion cannot show the previous owner profile',
      (tester) async {
    final gate = Completer<LinkInBioProfileResult?>();
    var loads = 0;
    await tester.pumpWidget(_app(_home(shop: () {
      return ++loads == 1 ? gate.future : Future.value(null);
    })));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'other-owner', idToken: 'other-token'));
    await tester.pumpAndSettle();
    gate.complete(_shop(url: Uri.parse('https://example.com/p/private-owner')));
    await tester.pumpAndSettle();
    expect(find.text('เผยแพร่แล้ว'), findsNothing);
    expect(find.text('สร้างหน้าร้าน'), findsOneWidget);
  });

  testWidgets('compact home stays readable at narrow width and large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_home(), scale: 2));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('เหลือ 248/250 หน่วย'), findsOneWidget);
  });

  testWidgets('owner change clears plan and ignores a late previous-owner post',
      (tester) async {
    final oldPosts = Completer<List<PostSummaryResult>>();
    var postLoads = 0;
    await tester.pumpWidget(_app(HomeScreen(
      loadSubscription: () async => SubscriptionStatusResult(
        userId: PostDeeAuthSessionStore.instance.session.stableUserId!,
        plan: PostDeeAuthSessionStore.instance.session.stableUserId ==
                'home-owner'
            ? 'PRO'
            : 'BASIC',
        status: 'ACTIVE',
        remainingPostsThisMonth: 3,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false,
      ),
      loadRecentPosts: () =>
          ++postLoads == 1 ? oldPosts.future : Future.value(const []),
      loadDrafts: () async => const [],
      loadConnections: () async => const [],
      loadScheduledPosts: () async => const [],
      loadLinkProfile: () async => null,
      onCreatePost: () async {},
    )));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'second-owner', idToken: 'second-token'));
    await tester.pump();
    oldPosts.complete([
      PostSummaryResult(
        id: 'private-old-post',
        caption: 'ข้อความส่วนตัวบัญชีเดิม',
        videoS3Key: '',
        platforms: const ['TIKTOK'],
        status: 'PUBLISHED',
        createdAt: DateTime.now(),
      )
    ]);
    await tester.pumpAndSettle();
    expect(find.text('ข้อความส่วนตัวบัญชีเดิม'), findsNothing);
    expect(find.text('แพ็กเกจฟรี'), findsOneWidget);
    expect(find.text('แพ็กเกจ Pro'), findsNothing);
    expect(postLoads, 2);
  });
}
