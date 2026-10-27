import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sessions = PostDeeAuthSessionStore.instance;

  setUpAll(() async {
    final fonts = FontLoader('Anuphan');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(
        rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'),
      );
    }
    await fonts.load();
  });

  setUp(() {
    sessions.signIn(const AuthSession(
      userId: 'connection-layout-seller',
      idToken: 'fixture-token',
    ));
  });

  tearDown(() {
    sessions.clear();
    AppTheme.applyThemeMode(ThemeMode.dark);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'connection actions fit 320dp at ${scale}x text in ${mode.name} mode',
          (tester) async {
        await _showConnections(
          tester,
          api: _LayoutSocialApi(),
          mode: mode,
          scale: scale,
        );

        for (final platform in connectablePlatforms) {
          final action = find.byKey(
            ValueKey('profile-platform-connect-${platform.apiValue}'),
          );
          expect(action, findsOneWidget);
          expect(tester.widget<ButtonStyleButton>(action).onPressed, isNotNull);
          final bounds = tester.getRect(action);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('connection actions identify the platform to screen readers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _showConnections(tester, api: _LayoutSocialApi());

      for (final platform in connectablePlatforms) {
        expect(
          find.bySemanticsLabel('เชื่อมต่อ ${platform.label}'),
          findsOneWidget,
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('pending connection keeps its button size and prevents repeats',
      (tester) async {
    final link = Completer<SocialConnectLinkResult>();
    final api = _LayoutSocialApi(link: link.future);
    await _showConnections(tester, api: api);
    final action =
        find.byKey(const ValueKey('profile-platform-connect-TIKTOK'));
    final originalSize = tester.getSize(action);

    await tester.tap(action);
    await tester.pump();

    expect(tester.getSize(action), originalSize);
    expect(tester.widget<ButtonStyleButton>(action).onPressed, isNull);
    expect(
      find.descendant(
          of: action, matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    expect(api.connectCalls, 1);
    expect(tester.takeException(), isNull);

    link.complete(SocialConnectLinkResult(
      connectUrl: Uri.parse('https://postpeer.test/connect/layout-fixture'),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<ButtonStyleButton>(action).onPressed, isNotNull);
  });
}

Future<void> _showConnections(
  WidgetTester tester, {
  required _LayoutSocialApi api,
  ThemeMode mode = ThemeMode.light,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  AppTheme.applyThemeMode(mode);
  await tester.pumpWidget(MaterialApp(
    theme: mode == ThemeMode.light ? AppTheme.light : AppTheme.dark,
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: ConnectionsScreen(
      apiClient: api,
      launchConnectUrl: (_) async => true,
    ),
  ));
  await tester.pumpAndSettle();
}

class _LayoutSocialApi extends PostDeeApiClient {
  _LayoutSocialApi({this.link});

  final Future<SocialConnectLinkResult>? link;
  var connectCalls = 0;

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async => [
        for (final platform in connectablePlatforms)
          SocialConnectionResult(platform: platform.apiValue, connected: false),
      ];

  @override
  Future<SocialConnectLinkResult> createSocialConnectionLink(String platform) {
    connectCalls++;
    return link ??
        Future.value(SocialConnectLinkResult(
          connectUrl: Uri.parse('https://postpeer.test/connect/layout-fixture'),
        ));
  }
}
