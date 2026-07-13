import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows package comparison, quotas, and Pro team access',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileScreen(
            languageController: PostDeeLanguageController(),
            themeController: PostDeeThemeController(),
            onOpenTemplates: () {},
            onDeleteAccount: () {},
          ),
        ),
      ),
    );

    // Three tier cards with the real prices from the design handoff. The list
    // is lazy, so scroll to each card, then read nearby texts with
    // skipOffstage: false (cards can sit partially outside the viewport).
    Finder cachedText(String text) => find.text(text, skipOffstage: false);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-plan-free'), skipOffstage: false),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(cachedText('แพ็กเกจ PostDee'), findsOneWidget);
    expect(cachedText('0 บาท'), findsOneWidget);
    // Free is the current tier by default.
    expect(cachedText('แพ็กเกจปัจจุบัน'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-plan-starter'), skipOffstage: false),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(cachedText('199 ฿/ด.'), findsOneWidget);
    expect(cachedText('แนะนำ'), findsOneWidget);
    expect(cachedText('อัปเกรด'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-plan-pro'), skipOffstage: false),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(cachedText('299 ฿/ด.'), findsOneWidget);
    expect(cachedText('โควต้าตัดต่อ AI'), findsNothing);
  });

  testWidgets('shows AI editing quota only for the Pro plan', (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [],
      subscription: const SubscriptionStatusResult(
        userId: 'pro-user',
        plan: 'PRO',
        status: 'ACTIVE',
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: true,
      ),
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('โควต้าตัดต่อ AI'),
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    expect(find.text('โควต้าตัดต่อ AI'), findsOneWidget);
    expect(find.text('175'), findsOneWidget);
    expect(find.text('/ 200 นาที'), findsOneWidget);
  });

  testWidgets('shows connected social platforms from the API', (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    // Connections now live on their own screen behind the profile menu row.
    await _openConnectionsScreen(tester);

    expect(
      find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK')),
      findsOneWidget,
    );
    expect(find.text('@seller_one'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testWidgets('shows the live connected count in the account summary pill',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile-connected-summary-pill')),
      findsOneWidget,
    );
    expect(find.text('1/4 เชื่อมต่อ'), findsOneWidget);
  });

  testWidgets('updates the summary pill after refreshing connections',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      refreshedConnections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    expect(find.text('0/4 เชื่อมต่อ'), findsOneWidget);

    await _openConnectionsScreen(tester);

    await tester.tap(find.byKey(const ValueKey('profile-platforms-refresh')));
    await tester.pumpAndSettle();

    // Back on the profile tab, the summary pill reflects the new count.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('1/4 เชื่อมต่อ'), findsOneWidget);
  });

  testWidgets('connecting a platform opens its PostPeer connect URL',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      connectLink: SocialConnectLinkResult(
        connectUrl: Uri.parse('https://postpeer.test/connect/tiktok'),
        expiresAt: DateTime.utc(2026, 6, 26, 9, 10),
      ),
    );
    Uri? launched;

    await tester.pumpWidget(
      _hostProfile(
        apiClient: apiClient,
        launchConnectUrl: (uri) async {
          launched = uri;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await _openConnectionsScreen(tester);

    final tiktokConnect =
        find.byKey(const ValueKey('profile-platform-connect-TIKTOK'));
    expect(tester.widget<FilledButton>(tiktokConnect).onPressed, isNotNull);

    await tester.tap(tiktokConnect);
    await tester.pumpAndSettle();

    expect(apiClient.connectCalls, ['TIKTOK']);
    expect(launched, Uri.parse('https://postpeer.test/connect/tiktok'));
  });

  testWidgets('refreshing pulls connected status from PostPeer',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      refreshedConnections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    await _openConnectionsScreen(tester);

    await tester.tap(find.byKey(const ValueKey('profile-platforms-refresh')));
    await tester.pumpAndSettle();

    expect(apiClient.refreshCalls, 1);
    expect(
      find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK')),
      findsOneWidget,
    );
    expect(find.text('@seller_one'), findsOneWidget);
  });

  testWidgets('shows the signed-in account instead of test profile copy',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileScreen(
            languageController: PostDeeLanguageController(),
            themeController: PostDeeThemeController(),
            onOpenTemplates: () {},
            onDeleteAccount: () {},
          ),
        ),
      ),
    );

    expect(find.text('PostDee Seller'), findsOneWidget);
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(find.text('บัญชีทดลองสำหรับทดสอบ UI และ flow หลักของ PostDee'),
        findsNothing);
    expect(find.text('โหมดทดสอบ'), findsNothing);
    expect(find.text('พร้อมลอง UI'), findsNothing);
  });

  testWidgets('does not add fake AI editing minutes from top-up',
      (tester) async {
    await tester.pumpWidget(
      _hostProfile(
        apiClient: _FakeSocialApiClient(
          connections: const [],
          subscription: const SubscriptionStatusResult(
            userId: 'pro-user',
            plan: 'PRO',
            status: 'ACTIVE',
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
        ),
      ),
    );

    final topUpButton =
        find.widgetWithText(OutlinedButton, 'เติม 120 นาที · 49 บาท');

    await tester.scrollUntilVisible(
      topUpButton,
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    await tester.tap(topUpButton);
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('320'), findsNothing);
  });
}

/// Taps the "เชื่อมต่อช่องทาง" menu row to push the connections screen.
Future<void> _openConnectionsScreen(WidgetTester tester) async {
  await tester.tap(find.text('เชื่อมต่อช่องทาง'));
  await tester.pumpAndSettle();
}

Widget _hostProfile({
  PostDeeApiClient? apiClient,
  Future<bool> Function(Uri uri)? launchConnectUrl,
}) {
  return MaterialApp(
    locale: const Locale('th'),
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: PostDeeLocalizations.supportedLocales,
    home: Scaffold(
      body: ProfileScreen(
        languageController: PostDeeLanguageController(),
        themeController: PostDeeThemeController(),
        onOpenTemplates: () {},
        onDeleteAccount: () {},
        apiClient: apiClient,
        launchConnectUrl: launchConnectUrl,
      ),
    ),
  );
}

class _FakeSocialApiClient extends PostDeeApiClient {
  _FakeSocialApiClient({
    required this.connections,
    this.connectLink,
    this.refreshedConnections,
    this.subscription,
  });

  List<SocialConnectionResult> connections;
  final SocialConnectLinkResult? connectLink;
  final List<SocialConnectionResult>? refreshedConnections;
  final SubscriptionStatusResult? subscription;
  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];
  int refreshCalls = 0;

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async =>
      subscription ??
      const SubscriptionStatusResult(
        userId: 'basic-user',
        plan: 'BASIC',
        status: 'INACTIVE',
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false,
      );

  @override
  Future<AiEditQuota> fetchAiEditQuota() async => const AiEditQuota(
        limitMinutes: 200,
        usedMinutes: 25,
        remainingMinutes: 175,
      );

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async =>
      connections;

  @override
  Future<List<SocialConnectionResult>> refreshSocialConnections() async {
    refreshCalls++;
    connections = refreshedConnections ?? connections;
    return connections;
  }

  @override
  Future<SocialConnectLinkResult> createSocialConnectionLink(
      String platform) async {
    connectCalls.add(platform);
    final link = connectLink;
    if (link == null) {
      throw const ApiException(
        'Social account linking is not available. Please try again later.',
        statusCode: 503,
      );
    }
    return link;
  }

  @override
  Future<void> disconnectSocialConnection(String platform) async {
    disconnectCalls.add(platform);
    connections = [
      for (final connection in connections)
        if (connection.platform == platform)
          SocialConnectionResult(platform: platform, connected: false)
        else
          connection,
    ];
  }
}
