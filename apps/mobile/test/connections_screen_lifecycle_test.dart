import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';

const _disconnected = [
  SocialConnectionResult(platform: 'TIKTOK', connected: false),
];
const _connected = [
  SocialConnectionResult(
    platform: 'TIKTOK',
    connected: true,
    displayName: '@connected_seller',
  ),
];

void main() {
  final sessionStore = PostDeeAuthSessionStore.instance;

  setUp(() {
    sessionStore
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token-a'));
  });

  tearDown(sessionStore.clear);

  testWidgets('opening a browser alone does not mark an account connected',
      (tester) async {
    final api = _SocialApi();
    await _showConnections(tester, api: api);

    await _connect(tester);

    expect(api.refreshCalls, 0);
    expect(find.text('@connected_seller'), findsNothing);
    expect(find.byKey(const ValueKey('profile-platform-connect-TIKTOK')),
        findsOneWidget);
  });

  testWidgets('refreshes provider status once after leaving and returning',
      (tester) async {
    final api = _SocialApi();
    await _showConnections(tester, api: api);
    await _connect(tester);

    _leaveAndReturn(tester);
    await tester.pumpAndSettle();

    expect(api.refreshCalls, 1);
    expect(find.text('@connected_seller'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK')),
        findsOneWidget);

    _leaveAndReturn(tester);
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 1);
  });

  testWidgets('does not refresh for a focus change or unrelated app resume',
      (tester) async {
    final api = _SocialApi();
    await _showConnections(tester, api: api);
    _leaveAndReturn(tester);
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 0);

    await _connect(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 0);
  });

  testWidgets('coalesces repeated returns while checking the provider',
      (tester) async {
    final response = Completer<List<SocialConnectionResult>>();
    final api = _SocialApi(refresh: () => response.future);
    await _showConnections(tester, api: api);
    await _connect(tester);

    _leaveAndReturn(tester);
    await tester.pump();
    _leaveAndReturn(tester);
    await tester.pump();
    expect(api.refreshCalls, 1);
    expect(
        find.byKey(const ValueKey('profile-platforms-refresh')), findsNothing);

    response.complete(_connected);
    await tester.pumpAndSettle();
    expect(find.text('@connected_seller'), findsOneWidget);
  });

  testWidgets('waits for launch confirmation if resume arrives first',
      (tester) async {
    final opened = Completer<bool>();
    final api = _SocialApi();
    await _showConnections(tester, api: api, launch: (_) => opened.future);
    await tester
        .tap(find.byKey(const ValueKey('profile-platform-connect-TIKTOK')));
    await tester.pump();

    _leaveAndReturn(tester);
    await tester.pump();
    expect(api.refreshCalls, 0);

    opened.complete(true);
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 1);
  });

  testWidgets(
      'failed browser launch shows an error and leaves no pending check',
      (tester) async {
    final api = _SocialApi();
    await _showConnections(tester, api: api, launch: (_) async => false);
    await _connect(tester);

    expect(find.text('เปิดหน้าเชื่อมบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง'),
        findsOneWidget);
    _leaveAndReturn(tester);
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 0);
  });

  testWidgets(
      'canceled consent can be checked manually and retried with a new URL',
      (tester) async {
    final api = _SocialApi(refresh: () async => _disconnected);
    final launched = <Uri>[];
    await _showConnections(tester, api: api, launch: (url) async {
      launched.add(url);
      return true;
    });
    await _connect(tester);
    _leaveAndReturn(tester);
    await tester.pumpAndSettle();
    expect(find.text('@connected_seller'), findsNothing);
    expect(api.refreshCalls, 1);

    await tester.tap(find.byKey(const ValueKey('profile-platforms-refresh')));
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 2);
    await _connect(tester);
    expect(launched.map((url) => url.path), ['/connect/1', '/connect/2']);
  });

  testWidgets('does not open a late connect URL after the session changes',
      (tester) async {
    final link = Completer<SocialConnectLinkResult>();
    final api = _SocialApi(link: () => link.future);
    var launchCalls = 0;
    await _showConnections(tester, api: api, launch: (_) async {
      launchCalls++;
      return true;
    });
    await tester
        .tap(find.byKey(const ValueKey('profile-platform-connect-TIKTOK')));
    await tester.pump();

    sessionStore
        .signIn(const AuthSession(userId: 'seller-b', idToken: 'token-b'));
    link.complete(SocialConnectLinkResult(
      connectUrl: Uri.parse('https://postpeer.test/connect/old-session'),
    ));
    await tester.pumpAndSettle();

    expect(launchCalls, 0);
    _leaveAndReturn(tester);
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 0);
  });

  testWidgets(
      'invalidates pending checks even on a new sign-in of the same user',
      (tester) async {
    final api = _SocialApi();
    await _showConnections(tester, api: api);
    await _connect(tester);
    sessionStore
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token-new'));

    _leaveAndReturn(tester);
    await tester.pumpAndSettle();

    expect(api.refreshCalls, 0);
    expect(find.text('@connected_seller'), findsNothing);
  });

  testWidgets('discards a provider response after sign-out', (tester) async {
    final response = Completer<List<SocialConnectionResult>>();
    final api = _SocialApi(refresh: () => response.future);
    await _showConnections(tester, api: api);
    await _connect(tester);
    _leaveAndReturn(tester);
    await tester.pump();
    expect(api.refreshCalls, 1);

    sessionStore.clear();
    response.complete(_connected);
    await tester.pumpAndSettle();

    expect(find.text('@connected_seller'), findsNothing);
  });

  testWidgets('clears the pending check when the connection screen is disposed',
      (tester) async {
    final api = _SocialApi();
    await _showConnections(tester, api: api);
    await _connect(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    _leaveAndReturn(tester);
    await tester.pumpAndSettle();

    expect(api.refreshCalls, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _showConnections(
  WidgetTester tester, {
  required _SocialApi api,
  ConnectUrlLauncher? launch,
}) async {
  tester.view.physicalSize = const Size(420, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(MaterialApp(
    home: ConnectionsScreen(
      apiClient: api,
      launchConnectUrl: launch ?? (_) async => true,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _connect(WidgetTester tester) async {
  await tester
      .tap(find.byKey(const ValueKey('profile-platform-connect-TIKTOK')));
  await tester.pumpAndSettle();
}

void _leaveAndReturn(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

class _SocialApi extends PostDeeApiClient {
  _SocialApi({this.link, this.refresh});

  final Future<SocialConnectLinkResult> Function()? link;
  final Future<List<SocialConnectionResult>> Function()? refresh;
  var refreshCalls = 0;
  var linkCalls = 0;

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async =>
      _disconnected;

  @override
  Future<SocialConnectLinkResult> createSocialConnectionLink(String platform) {
    linkCalls++;
    return link?.call() ??
        Future.value(SocialConnectLinkResult(
          connectUrl: Uri.parse('https://postpeer.test/connect/$linkCalls'),
        ));
  }

  @override
  Future<List<SocialConnectionResult>> refreshSocialConnections() {
    refreshCalls++;
    return refresh?.call() ?? Future.value(_connected);
  }
}
