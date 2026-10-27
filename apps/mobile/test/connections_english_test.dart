import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';

const _nonce = 'abcdefghijklmnopqrstuvwxyz0123456789_-ABCDE';

class _Api extends PostDeeApiClient {
  List<SocialConnectionResult> connections = const [];
  Object? readError;
  Object? refreshError;
  Object? connectError;
  Object? disconnectError;
  Future<List<SocialConnectionResult>>? readGate;
  Future<SocialConnectLinkResult>? connectGate;
  Future<void>? disconnectGate;
  SocialConnectLinkResult? link;
  int reads = 0;
  int refreshes = 0;
  final connects = <String>[];
  final disconnects = <String>[];
  final nonces = <String>[];

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async {
    reads++;
    if (readError != null) throw readError!;
    return readGate == null ? connections : await readGate!;
  }

  @override
  Future<List<SocialConnectionResult>> refreshSocialConnections() async {
    refreshes++;
    if (refreshError != null) throw refreshError!;
    return connections;
  }

  @override
  Future<SocialConnectionsRefreshResult> refreshSocialConnectionsWithAttempt(
      {required String nonce}) async {
    nonces.add(nonce);
    if (refreshError != null) throw refreshError!;
    return SocialConnectionsRefreshResult(
        connections: connections, connectAttemptConsumed: true);
  }

  @override
  Future<SocialConnectLinkResult> createSocialConnectionLink(String platform,
      {String? returnTarget}) async {
    connects.add(platform);
    if (connectError != null) throw connectError!;
    return connectGate != null
        ? await connectGate!
        : link ??
            SocialConnectLinkResult(
                connectUrl: switch (platform) {
                  'YOUTUBE_SHORTS' =>
                    'https://accounts.google.com/o/oauth2/auth',
                  'INSTAGRAM_REELS' =>
                    'https://www.instagram.com/oauth/authorize',
                  'FACEBOOK_REELS' => 'https://www.facebook.com/dialog/oauth',
                  _ => 'https://www.tiktok.com/v2/auth/authorize',
                },
                nonce: _nonce,
                expiresAt: DateTime.now().add(const Duration(minutes: 15)));
  }

  @override
  Future<void> disconnectSocialConnection(String platform) async {
    disconnects.add(platform);
    await disconnectGate;
    if (disconnectError != null) throw disconnectError!;
  }
}

ConnectionsScreen _screen(_Api api,
        {ConnectUrlLauncher? launch, ValueChanged<int>? changed}) =>
    ConnectionsScreen(
        key: const ValueKey('english-connections'),
        apiClient: api,
        launchConnectUrl: launch ?? (_) async => false,
        onConnectionsChanged: changed);

Widget _app(ConnectionsScreen screen,
    {Locale locale = const Locale('en'),
    double scale = 1,
    bool dark = false,
    bool withBack = false}) {
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return MaterialApp(
    locale: locale,
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            disableAnimations: true, textScaler: TextScaler.linear(scale)),
        child: child!),
    home: withBack ? const Scaffold() : screen,
    initialRoute: withBack ? '/connections' : null,
    routes: withBack ? {'/connections': (_) => screen} : const {},
  );
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectEnglish(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? text.textSpan?.toPlainText() ?? '',
        isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
  expect(tester.takeException(), isNull);
}

void _readable(WidgetTester tester, Finder label) {
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5));
}

const _platforms = {
  'TIKTOK': 'TikTok',
  'YOUTUBE_SHORTS': 'YouTube Shorts',
  'INSTAGRAM_REELS': 'Instagram Reels',
  'FACEBOOK_REELS': 'Facebook Reels',
};

Future<void> _start(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

void _roundTrip(TestWidgetsFlutterBinding binding) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed
  ]) {
    binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  setUp(() => PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: 'english-connections-owner', idToken: 'fixture-token')));
  tearDown(PostDeeAuthSessionStore.instance.clear);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets('English connections title and verified count are translated',
      (tester) async {
    await tester.pumpWidget(_app(_screen(_Api())));
    await tester.pumpAndSettle();
    expect(find.text('Connect channels'), findsOneWidget);
    expect(find.text('Connected 0/4 channels'), findsOneWidget);
    expect(find.text('Social channels'), findsOneWidget);
    expect(find.text('Secure sign-in'), findsOneWidget);
    expect(find.text('Connect once. Post one video to all your channels.'),
        findsOneWidget);
    expect(
        find.text('Connect your social accounts to post to your own channels.'),
        findsOneWidget);
    expect(
        find.text(
            'Opens in a trusted system browser. PostDee does not receive your password. When finished, tap Open PostDee. If you do not return automatically, close the window or return to the app, then refresh the status.'),
        findsOneWidget);
    expect(find.byTooltip('Refresh connection status'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets('stored connection failure changes language without another read',
      (tester) async {
    final api = _Api()..readError = StateError('private upstream diagnostic');
    final screen = _screen(api);
    await tester.pumpWidget(_app(screen, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจสอบช่องทางไม่ได้'), findsOneWidget);
    await tester.pumpWidget(_app(screen));
    await tester.pumpAndSettle();
    expect(find.text('Could not verify channels'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private upstream diagnostic'), findsNothing);
    expect(api.reads, 1);
    _expectEnglish(tester);
  });

  testWidgets('English disconnect confirmation can go Back without mutations',
      (tester) async {
    final api = _Api()
      ..connections = const [
        SocialConnectionResult(
            platform: 'TIKTOK', connected: true, displayName: '@seller')
      ];
    await tester.pumpWidget(_app(_screen(api)));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-platform-disconnect-TIKTOK'));
    expect(find.text('Disconnect TikTok?'), findsOneWidget);
    expect(
        find.textContaining(
            'Disconnecting does not cancel jobs already submitted.'),
        findsOneWidget);
    await _tap(tester, _key('disconnect-cancel'));
    expect(api.disconnects, isEmpty);
    expect(api.connects, isEmpty);
    _expectEnglish(tester);
  });

  for (final count in [1, 2, 4]) {
    testWidgets('English count includes $count supported channels only',
        (tester) async {
      final api = _Api()
        ..connections = [
          for (final platform in _platforms.keys.take(count))
            SocialConnectionResult(platform: platform, connected: true),
          const SocialConnectionResult(
              platform: 'SHOPEE_VIDEO', connected: true),
          const SocialConnectionResult(
              platform: 'LAZADA_VIDEO', connected: true),
        ];
      final counts = <int>[];
      await tester.pumpWidget(_app(_screen(api, changed: counts.add)));
      await tester.pumpAndSettle();
      expect(find.text('Connected $count/4 channels'), findsOneWidget);
      expect(counts, [count]);
      expect(find.text('Shopee Video'), findsNothing);
      expect(find.text('Lazada Video'), findsNothing);
      _expectEnglish(tester);
    });
  }

  testWidgets('English loading does not claim disconnected accounts',
      (tester) async {
    final gate = Completer<List<SocialConnectionResult>>();
    final api = _Api()..readGate = gate.future;
    await tester.pumpWidget(_app(_screen(api)));
    await tester.pump();
    expect(find.text('Checking channels...'), findsOneWidget);
    expect(find.text('Connected 0/4 channels'), findsNothing);
    for (final platform in _platforms.keys) {
      expect(
          tester
              .widget<OutlinedButton>(
                  _key('profile-platform-status-unknown-$platform'))
              .onPressed,
          isNull);
    }
    gate.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('Connected 0/4 channels'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets(
      'English retry verifies real accounts after an unavailable status',
      (tester) async {
    final api = _Api()..readError = StateError('private read failure');
    await tester.pumpWidget(_app(_screen(api)));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not load channel status. Check your internet connection and try again.'),
        findsOneWidget);
    api.readError = null;
    api.connections = const [
      SocialConnectionResult(
          platform: 'TIKTOK', connected: true, displayName: '@seller')
    ];
    await _tap(tester, _key('profile-platforms-retry'));
    expect(api.reads, 2);
    expect(api.refreshes, 0);
    expect(find.text('Connected 1/4 channels'), findsOneWidget);
    expect(find.text('@seller'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets(
      'raw Thai display names and active disconnect dialog follow locale changes',
      (tester) async {
    const name = '@ร้านของฉัน';
    final api = _Api()
      ..connections = const [
        SocialConnectionResult(
            platform: 'TIKTOK', connected: true, displayName: name)
      ];
    final screen = _screen(api);
    await tester.pumpWidget(_app(screen));
    await tester.pumpAndSettle();
    final label = tester.widget<Text>(find.descendant(
        of: _key('profile-platform-disconnect-TIKTOK'),
        matching: find.text('Disconnect')));
    expect(label.semanticsLabel, 'Disconnect TikTok $name');
    await _tap(tester, _key('profile-platform-disconnect-TIKTOK'));
    await tester.pumpWidget(_app(screen, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('ตัดการเชื่อมต่อ TikTok?'), findsOneWidget);
    expect(find.textContaining(name), findsWidgets);
    await tester.pumpWidget(_app(screen));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect TikTok?'), findsOneWidget);
    expect(find.textContaining(name), findsWidgets);
    await _tap(tester, _key('disconnect-cancel'));
    expect(find.text(name), findsOneWidget);
    expect(api.reads, 1);
    expect(api.refreshes, 0);
    expect(api.connects, isEmpty);
    expect(api.disconnects, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English pending disconnect sends once and reloads confirmed status',
      (tester) async {
    final gate = Completer<void>();
    final api = _Api()
      ..disconnectGate = gate.future
      ..connections = const [
        SocialConnectionResult(
            platform: 'TIKTOK', connected: true, displayName: '@seller')
      ];
    final counts = <int>[];
    await tester.pumpWidget(_app(_screen(api, changed: counts.add)));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-platform-disconnect-TIKTOK'));
    await _start(tester, _key('disconnect-confirm'));
    expect(api.disconnects, ['TIKTOK']);
    expect(
        tester.widget<IconButton>(_key('profile-platforms-refresh')).onPressed,
        isNull);
    api.connections = const [];
    gate.complete();
    await tester.pumpAndSettle();
    expect(api.disconnects, ['TIKTOK']);
    expect(api.reads, 2);
    expect(counts, [1, 0]);
    expect(find.text('Connected 0/4 channels'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets(
      'English disconnect failure keeps existing account and does not retry',
      (tester) async {
    final api = _Api()
      ..disconnectError = StateError('private disconnect reason')
      ..connections = const [
        SocialConnectionResult(
            platform: 'TIKTOK', connected: true, displayName: '@seller')
      ];
    await tester.pumpWidget(_app(_screen(api)));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-platform-disconnect-TIKTOK'));
    await _tap(tester, _key('disconnect-confirm'));
    expect(
        find.text('Could not disconnect. Please try again.'), findsOneWidget);
    expect(find.textContaining('private disconnect reason'), findsNothing);
    expect(find.text('@seller'), findsOneWidget);
    expect(api.disconnects, ['TIKTOK']);
    expect(api.reads, 1);
    _expectEnglish(tester);
  });

  testWidgets(
      'English Connecting semantics names the busy channel and locks repeats',
      (tester) async {
    final gate = Completer<SocialConnectLinkResult>();
    final api = _Api()..connectGate = gate.future;
    await tester.pumpWidget(_app(_screen(api)));
    await tester.pumpAndSettle();
    await _start(tester, _key('profile-platform-connect-TIKTOK'));
    final text = tester.widget<Text>(find.descendant(
        of: _key('profile-platform-connect-TIKTOK'),
        matching: find.text('Connect')));
    expect(text.semanticsLabel, 'Connecting TikTok');
    for (final platform in _platforms.keys) {
      expect(
          tester
              .widget<FilledButton>(_key('profile-platform-connect-$platform'))
              .onPressed,
          isNull);
    }
    expect(api.connects, ['TIKTOK']);
    gate.complete(SocialConnectLinkResult(
        connectUrl: 'https://www.tiktok.com/auth',
        nonce: _nonce,
        expiresAt: DateTime.now().add(const Duration(minutes: 15))));
    await tester.pumpAndSettle();
    expect(find.text('Could not connect your account. Please try again.'),
        findsOneWidget);
    expect(api.connects, ['TIKTOK']);
    expect(
        tester
            .widget<Text>(find.descendant(
                of: _key('profile-platform-connect-TIKTOK'),
                matching: find.text('Connect')))
            .semanticsLabel,
        'Connect TikTok');
    _expectEnglish(tester);
  });

  for (final returnFromBrowser in [false, true]) {
    testWidgets(
        'English OAuth ${returnFromBrowser ? 'return' : 'manual refresh'} verifies through one pending nonce',
        (tester) async {
      final api = _Api();
      final launches = <Uri>[];
      final counts = <int>[];
      await tester.pumpWidget(
          _app(_screen(api, changed: counts.add, launch: (uri) async {
        launches.add(uri);
        return true;
      })));
      await tester.pumpAndSettle();
      await _tap(tester, _key('profile-platform-connect-TIKTOK'));
      expect(launches, hasLength(1));
      expect(
          find.text(
              'Sign-in opened in your system browser. When finished, tap Open PostDee. If you do not return automatically, close the window or return to the app, then refresh the status.'),
          findsOneWidget);
      expect(find.text('Connected 0/4 channels'), findsOneWidget);
      expect(counts, [0]);
      api.connections = const [
        SocialConnectionResult(
            platform: 'TIKTOK', connected: true, displayName: '@verified')
      ];
      if (returnFromBrowser) {
        _roundTrip(tester.binding);
        await tester.pumpAndSettle();
      } else {
        await _tap(tester, _key('profile-platforms-refresh'));
      }
      expect(api.nonces, [_nonce]);
      expect(api.refreshes, 0);
      expect(counts, [0, 1]);
      expect(find.text('Connected 1/4 channels'), findsOneWidget);
      await _tap(tester, _key('profile-platforms-refresh'));
      expect(api.nonces, [_nonce]);
      expect(api.refreshes, 1);
      expect(api.connects, ['TIKTOK']);
      _expectEnglish(tester);
    });
  }

  for (final errorCase in const {
    'SOCIAL_ACCOUNT_ALREADY_LINKED':
        'This social account is linked to another PostDee account. Disconnect it from the original account first, or choose a different social account.',
    'SOCIAL_CONNECTION_ATTEMPT_INVALID':
        'This connection request has expired or has already been used. Connect the channel again.',
    'SOCIAL_CONNECTION_ATTEMPT_EXPIRED':
        'This connection request has expired or has already been used. Connect the channel again.',
    'SOCIAL_CONNECTION_COMPLETION_AMBIGUOUS':
        'More than one account was recently connected. Connect one account at a time.',
    'OTHER_CONFLICT':
        'Could not verify this connection. Connect the channel again.',
  }.entries) {
    testWidgets('English connect ${errorCase.key} hides private diagnostics',
        (tester) async {
      final api = _Api()
        ..connectError = ApiException('private-external-id',
            code: errorCase.key, statusCode: 409);
      var launches = 0;
      await tester.pumpWidget(_app(_screen(api, launch: (_) async {
        launches++;
        return false;
      })));
      await tester.pumpAndSettle();
      await _tap(tester, _key('profile-platform-connect-TIKTOK'));
      expect(find.text(errorCase.value), findsOneWidget);
      expect(find.textContaining('private-external-id'), findsNothing);
      expect(launches, 0);
      expect(api.connects, ['TIKTOK']);
      _expectEnglish(tester);
    });
  }

  testWidgets(
      'English refresh API conflict changes language without extra requests',
      (tester) async {
    final api = _Api()
      ..refreshError = const ApiException('private-id',
          code: 'SOCIAL_ACCOUNT_ALREADY_LINKED', statusCode: 409);
    final screen = _screen(api);
    await tester.pumpWidget(_app(screen, locale: const Locale('th')));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-platforms-refresh'));
    await tester.pumpWidget(_app(screen));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'This social account is linked to another PostDee account. Disconnect it from the original account first, or choose a different social account.'),
        findsOneWidget);
    expect(api.reads, 1);
    expect(api.refreshes, 1);
    expect(api.nonces, isEmpty);
    _expectEnglish(tester);
  });

  for (final rawApi in [false, true]) {
    testWidgets(
        'English ${rawApi ? 'unmapped API reason' : 'unexpected connect failure'} is preserved safely',
        (tester) async {
      final api = _Api()
        ..connectError = rawApi
            ? const ApiException('Provider is temporarily unavailable.',
                statusCode: 503)
            : StateError('private failure');
      await tester.pumpWidget(_app(_screen(api)));
      await tester.pumpAndSettle();
      await _tap(tester, _key('profile-platform-connect-TIKTOK'));
      expect(
          find.text(rawApi
              ? 'Provider is temporarily unavailable.'
              : 'Could not connect your account. Please try again.'),
          findsOneWidget);
      expect(find.textContaining('private failure'), findsNothing);
      expect(api.connects, ['TIKTOK']);
      _expectEnglish(tester);
    });
  }

  for (final uri in [
    'https://evil.invalid/auth',
    'http://www.tiktok.com/auth',
    'https://user@www.tiktok.com/auth'
  ]) {
    testWidgets('English unsafe link refuses launch: $uri', (tester) async {
      final api = _Api()
        ..link = SocialConnectLinkResult(
            connectUrl: uri,
            nonce: _nonce,
            expiresAt: DateTime.now().add(const Duration(minutes: 15)));
      var launches = 0;
      await tester.pumpWidget(_app(_screen(api, launch: (_) async {
        launches++;
        return false;
      })));
      await tester.pumpAndSettle();
      await _tap(tester, _key('profile-platform-connect-TIKTOK'));
      expect(find.text('This connection link is not safe. Please try again.'),
          findsOneWidget);
      expect(launches, 0);
      expect(api.connects, ['TIKTOK']);
      _expectEnglish(tester);
    });
  }

  for (final invalid in [
    'missing nonce',
    'invalid nonce',
    'missing expiry',
    'expired'
  ]) {
    testWidgets('English rejects $invalid without launching the browser',
        (tester) async {
      final api = _Api()
        ..link = SocialConnectLinkResult(
            connectUrl: 'https://www.tiktok.com/auth',
            nonce: invalid == 'missing nonce'
                ? null
                : invalid == 'invalid nonce'
                    ? 'bad'
                    : _nonce,
            expiresAt: invalid == 'missing expiry'
                ? null
                : DateTime.now()
                    .add(Duration(minutes: invalid == 'expired' ? -1 : 15)));
      var launches = 0;
      await tester.pumpWidget(_app(_screen(api, launch: (_) async {
        launches++;
        return false;
      })));
      await tester.pumpAndSettle();
      await _tap(tester, _key('profile-platform-connect-TIKTOK'));
      expect(
          find.text(
              'Could not start a secure connection. Try again, or ask the administrator to update the system.'),
          findsOneWidget);
      expect(launches, 0);
      expect(api.connects, ['TIKTOK']);
      _expectEnglish(tester);
    });
  }

  for (final fails in [false, true]) {
    testWidgets(
        'English owner switch rejects a stale ${fails ? 'failure' : 'account'}',
        (tester) async {
      final gate = Completer<List<SocialConnectionResult>>();
      final api = _Api()..readGate = gate.future;
      final counts = <int>[];
      await tester.pumpWidget(_app(_screen(api, changed: counts.add)));
      await tester.pump();
      api.readGate = null;
      api.connections = const [
        SocialConnectionResult(
            platform: 'TIKTOK', connected: true, displayName: '@current-owner')
      ];
      PostDeeAuthSessionStore.instance.signIn(
          const AuthSession(userId: 'current-owner', idToken: 'new-token'));
      if (fails) {
        gate.completeError(StateError('old private failure'));
      } else {
        gate.complete(const [
          SocialConnectionResult(
              platform: 'TIKTOK', connected: true, displayName: '@old-owner')
        ]);
      }
      await tester.pumpAndSettle();
      expect(find.text('@current-owner'), findsOneWidget);
      expect(find.text('@old-owner'), findsNothing);
      expect(find.text('Could not verify channels'), findsNothing);
      expect(api.reads, 2);
      expect(counts, [1]);
      _expectEnglish(tester);
    });
  }

  testWidgets('English owner change cancels a pending connect before launch',
      (tester) async {
    final gate = Completer<SocialConnectLinkResult>();
    final api = _Api()..connectGate = gate.future;
    var launches = 0;
    await tester.pumpWidget(_app(_screen(api, launch: (_) async {
      launches++;
      return true;
    })));
    await tester.pumpAndSettle();
    await _start(tester, _key('profile-platform-connect-TIKTOK'));
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'new-connect-owner', idToken: 'new-token'));
    gate.complete(SocialConnectLinkResult(
        connectUrl: 'https://www.tiktok.com/auth',
        nonce: _nonce,
        expiresAt: DateTime.now().add(const Duration(minutes: 15))));
    await tester.pumpAndSettle();
    expect(launches, 0);
    expect(api.reads, 2);
    expect(api.connects, ['TIKTOK']);
    expect(api.disconnects, isEmpty);
    _expectEnglish(tester);
  });

  testWidgets('English sign-out notice changes language without another read',
      (tester) async {
    final api = _Api()
      ..connections = const [
        SocialConnectionResult(
            platform: 'TIKTOK', connected: true, displayName: '@previous-owner')
      ];
    final screen = _screen(api);
    await tester.pumpWidget(_app(screen, locale: const Locale('th')));
    await tester.pumpAndSettle();
    PostDeeAuthSessionStore.instance.clear();
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(screen));
    await tester.pumpAndSettle();
    expect(find.text('Please sign in again to check your channels.'),
        findsOneWidget);
    expect(find.text('@previous-owner'), findsNothing);
    expect(api.reads, 1);
    _expectEnglish(tester);
  });

  testWidgets('plain MaterialApp retains Thai connection fallback',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: _screen(_Api())));
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมต่อช่องทาง'), findsOneWidget);
    expect(find.text('เชื่อมต่อแล้ว 0/4 ช่องทาง'), findsOneWidget);
    expect(find.text('Connect channels'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English transient refresh preserves the pending nonce until acknowledged',
      (tester) async {
    final api = _Api();
    var launches = 0;
    await tester.pumpWidget(_app(_screen(api, launch: (_) async {
      launches++;
      return true;
    })));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-platform-connect-TIKTOK'));
    api.refreshError =
        const ApiException('private network failure', statusCode: 503);
    await _tap(tester, _key('profile-platforms-refresh'));
    expect(find.text('Could not verify channels'), findsOneWidget);
    expect(api.nonces, [_nonce]);
    api.refreshError = null;
    await _tap(tester, _key('profile-platforms-retry'));
    api.connections = const [
      SocialConnectionResult(platform: 'TIKTOK', connected: true)
    ];
    await _tap(tester, _key('profile-platforms-refresh'));
    expect(api.nonces, [_nonce, _nonce]);
    expect(find.text('Connected 1/4 channels'), findsOneWidget);
    expect(api.reads, 2);
    expect(api.refreshes, 0);
    await _tap(tester, _key('profile-platforms-refresh'));
    expect(api.nonces, [_nonce, _nonce]);
    expect(api.refreshes, 1);
    expect(api.connects, ['TIKTOK']);
    expect(launches, 1);
    _expectEnglish(tester);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'English all-four Awaiting status labels fit 320dp 2x ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<List<SocialConnectionResult>>();
      final api = _Api()..readGate = gate.future;
      await tester
          .pumpWidget(_app(_screen(api), scale: 2, dark: dark, withBack: true));
      await tester.pump(const Duration(milliseconds: 300));
      _readable(tester, find.text('Connect channels'));
      _readable(tester, find.text('Checking channels...'));
      for (final platform in _platforms.keys) {
        final action = _key('profile-platform-status-unknown-$platform');
        _readable(
            tester,
            find.descendant(
                of: action, matching: find.text('Awaiting status')));
        expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
      }
      _expectEnglish(tester);
      gate.complete(const []);
      await tester.pumpAndSettle();
      expect(api.reads, 1);
      expect(api.connects, isEmpty);
      expect(api.disconnects, isEmpty);
    });

    for (final connected in [false, true]) {
      testWidgets(
          'English all-four ${connected ? 'disconnect' : 'connect'} controls fit 320dp 2x ${dark ? 'dark' : 'light'} mode',
          (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _Api()
          ..connections = [
            if (connected)
              for (final platform in _platforms.keys)
                SocialConnectionResult(
                    platform: platform,
                    connected: true,
                    displayName: '@seller_with_a_long_display_name_$platform'),
          ];
        await tester.pumpWidget(
            _app(_screen(api), scale: 2, dark: dark, withBack: true));
        await tester.pumpAndSettle();
        _readable(tester, find.text('Connect channels'));
        _readable(
            tester, find.text('Connected ${connected ? 4 : 0}/4 channels'));
        for (final entry in _platforms.entries) {
          final action = _key(
              'profile-platform-${connected ? 'disconnect' : 'connect'}-${entry.key}');
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          _readable(tester, find.text(entry.value));
          if (connected) {
            _readable(tester,
                find.text('@seller_with_a_long_display_name_${entry.key}'));
          }
          _readable(
              tester,
              find.descendant(
                  of: action,
                  matching: find.text(connected ? 'Disconnect' : 'Connect')));
          await _tap(tester, action);
          if (connected) {
            _readable(tester, find.text('Disconnect ${entry.value}?'));
            _readable(
                tester,
                find.descendant(
                    of: _key('disconnect-cancel'),
                    matching: find.text('Back')));
            _readable(
                tester,
                find.descendant(
                    of: _key('disconnect-confirm'),
                    matching: find.text('Disconnect')));
            _expectEnglish(tester);
            await _tap(tester, _key('disconnect-cancel'));
          }
          _expectEnglish(tester);
          if (!connected) {
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
          }
        }
        expect(api.disconnects, isEmpty);
        expect(api.connects, connected ? isEmpty : _platforms.keys.toList());
      });
    }
  }
}
