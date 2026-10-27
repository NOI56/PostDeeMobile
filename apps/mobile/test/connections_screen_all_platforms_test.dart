import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';

// Provider-shaped test URLs only. No requests reach social platforms.
final _providerUrls = <String, Uri>{
  'TIKTOK': Uri.parse(
    'https://www.tiktok.com/v2/auth/authorize/?client_key=test&state=tiktok%2Bstate',
  ),
  'YOUTUBE_SHORTS': Uri.parse(
    'https://accounts.google.com/o/oauth2/v2/auth?client_id=test&state=youtube%2Bstate',
  ),
  'INSTAGRAM_REELS': Uri.parse(
    'https://www.instagram.com/oauth/authorize?client_id=test&state=instagram%2Bstate',
  ),
  'FACEBOOK_REELS': Uri.parse(
    'https://www.facebook.com/dialog/oauth?client_id=test&state=facebook%2Bstate',
  ),
};

void main() {
  const browserChannel = MethodChannel('postdee/social_connection_browser');
  final sessionStore = PostDeeAuthSessionStore.instance;
  final opened = <MethodCall>[];

  setUp(() {
    sessionStore.signIn(const AuthSession(
      userId: 'seller-all-platforms',
      idToken: 'test-session-token',
    ));
    opened.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(browserChannel, (call) async {
      opened.add(call);
      return true;
    });
  });

  tearDown(() {
    sessionStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(browserChannel, null);
  });

  for (final entry in _providerUrls.entries) {
    testWidgets(
        '${entry.key} opens its unchanged OAuth URL and verifies status on return',
        (tester) async {
      tester.view.physicalSize = const Size(420, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final api = _AllPlatformsApi(entry.key);
      await tester.pumpWidget(MaterialApp(
        home: ConnectionsScreen(apiClient: api),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(
        ValueKey('profile-platform-connect-${entry.key}'),
      ));
      await tester.pumpAndSettle();

      expect(api.connectRequests, [entry.key]);
      expect(opened.single.method, 'openCustomTab');
      expect(opened.single.arguments, entry.value.toString());
      expect(api.refreshCalls, 0);
      expect(find.text(api.displayName), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(api.refreshCalls, 1);
      expect(find.text(api.displayName), findsOneWidget);
      expect(
        find.byKey(ValueKey('profile-platform-disconnect-${entry.key}')),
        findsOneWidget,
      );
      for (final otherPlatform in _providerUrls.keys) {
        if (otherPlatform == entry.key) continue;
        expect(
          find.byKey(ValueKey('profile-platform-connect-$otherPlatform')),
          findsOneWidget,
        );
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}

class _AllPlatformsApi extends PostDeeApiClient {
  _AllPlatformsApi(this.platform);

  final String platform;
  final connectRequests = <String>[];
  var refreshCalls = 0;

  String get displayName => '@seller_${platform.toLowerCase()}';

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async => [
        for (final key in _providerUrls.keys)
          SocialConnectionResult(platform: key, connected: false),
      ];

  @override
  Future<SocialConnectLinkResult> createSocialConnectionLink(
      String requestedPlatform) async {
    connectRequests.add(requestedPlatform);
    return SocialConnectLinkResult(
        connectUrl: _providerUrls[requestedPlatform]!);
  }

  @override
  Future<List<SocialConnectionResult>> refreshSocialConnections() async {
    refreshCalls++;
    return [
      for (final key in _providerUrls.keys)
        SocialConnectionResult(
          platform: key,
          connected: key == platform,
          displayName: key == platform ? displayName : null,
        ),
    ];
  }
}
