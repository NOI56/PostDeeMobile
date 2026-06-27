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

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-package-comparison')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-free')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-starter')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-pro')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-quota-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-plan-quota-starter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-plan-quota-pro')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-post-quota-summary')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('profile-ai-caption-quota-summary')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('profile-team-access-pro')), findsOneWidget);
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

    final tiktokDisconnect =
        find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK'));
    await tester.scrollUntilVisible(
      tiktokDisconnect,
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    expect(tiktokDisconnect, findsOneWidget);
    expect(find.text('@seller_one'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets);
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

    final tiktokConnect =
        find.byKey(const ValueKey('profile-platform-connect-TIKTOK'));
    await tester.scrollUntilVisible(
      tiktokConnect,
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    expect(tester.widget<OutlinedButton>(tiktokConnect).onPressed, isNotNull);

    await tester.tap(tiktokConnect);
    await tester.pumpAndSettle();

    expect(apiClient.connectCalls, ['TIKTOK']);
    expect(launched, Uri.parse('https://postpeer.test/connect/tiktok'));
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
  _FakeSocialApiClient({required this.connections, this.connectLink});

  List<SocialConnectionResult> connections;
  final SocialConnectLinkResult? connectLink;
  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async =>
      connections;

  @override
  Future<SocialConnectLinkResult> createSocialConnectionLink(
      String platform) async {
    connectCalls.add(platform);
    final link = connectLink;
    if (link == null) {
      throw const ApiException(
        'PostPeer account linking is not configured yet',
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
