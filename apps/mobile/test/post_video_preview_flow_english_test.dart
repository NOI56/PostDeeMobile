import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';

import 'post_video_preview_english_test.dart'
    show PreviewEnglishFixture, loadPreviewEnglishFonts;

const _owner =
    AuthSession(userId: 'english-flow-owner', idToken: 'owner-token');
final _url = Uri.parse(
    'https://private-media.test/merchant-video.mp4?signature=private-test-value');

PreviewEnglishFixture _fixture({bool network = true}) {
  final fixture = PreviewEnglishFixture();
  if (network) fixture.networkUrl = _url;
  addTearDown(fixture.dispose);
  return fixture;
}

Future<void> _close(WidgetTester tester, PreviewEnglishFixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Release fake native requests only after unmount, then drain disposal before
  // restoring the global video platform for the next case.
  for (final gate in [
    fixture.platform.firstCreationGate,
    fixture.platform.volumeGate,
    fixture.platform.seekGate
  ]) {
    if (gate != null && !gate.isCompleted) gate.complete();
  }
  await fixture.close(tester);
}

void _hideUrl() {
  expect(find.textContaining('private-media.test'), findsNothing);
  expect(find.textContaining('private-test-value'), findsNothing);
}

Future<void> _drain(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  late AuthSession previous;
  setUpAll(loadPreviewEnglishFonts);
  setUp(() {
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance.signIn(_owner);
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.signIn(previous);
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets(
      'English owned network failure retries the same URL without autoplay',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    fixture.videoName = 'ยังเปิดคลิปไม่ได้';
    fixture.platform.failFirstInitialization = true;
    await fixture.mount(tester);
    expect(find.text('Could not open this video'), findsOneWidget);
    expect(
        find.text(
            'Go back and check the post status to open the latest preview.'),
        findsOneWidget);
    expect(find.text('ยังเปิดคลิปไม่ได้'), findsOneWidget,
        reason: 'The filename is user data, even when it matches app copy.');
    _hideUrl();
    await tester.tap(find.byKey(const ValueKey('post-video-preview-retry')));
    await tester.pumpAndSettle();
    expect(fixture.platform.sources.map((source) => source.uri).toList(),
        [_url.toString(), _url.toString()]);
    expect(fixture.platform.played, isEmpty);
    await _drain(tester);
    expect(fixture.platform.disposeCounts[1], 1);
    expect(find.byKey(const ValueKey('post-video-preview-player')),
        findsOneWidget);
    _hideUrl();
    await fixture.close(tester);
    expect(fixture.platform.disposeCounts, {1: 1, 2: 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English owner expiry removes playback and retry for its whole sign-in lifetime',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    await fixture.mount(tester);
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(
        const AuthSession(userId: 'other-owner', idToken: 'other-token'));
    sessions.signIn(_owner);
    await tester.pumpAndSettle();
    expect(find.text('Your account has changed. Reopen the video.'),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('post-video-preview-player')), findsNothing);
    expect(
        find.byKey(const ValueKey('post-video-preview-retry')), findsNothing);
    expect(find.byKey(const ValueKey('post-video-preview-play')), findsNothing);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Your account has changed. Reopen the video.'),
        findsOneWidget);
    expect(fixture.platform.sources, hasLength(1));
    await _drain(tester);
    expect(fixture.platform.disposeCounts, {1: 1});
    expect(fixture.platform.played, isEmpty);
    _hideUrl();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English volume timeout keeps controls recoverable without playing',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    await fixture.mount(tester);
    final gate = Completer<void>();
    fixture.platform.volumeGate = gate;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-mute')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Could not adjust the preview volume. Try again.'),
        findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Could not adjust the preview volume. Try again.'),
        findsOneWidget);
    final volume = find.byKey(const ValueKey('post-video-preview-volume'));
    expect(tester.widget<Slider>(volume).onChanged, isNotNull);
    final requests = fixture.platform.volumes.length;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ยังปรับเสียงไม่ได้ ลองอีกครั้ง'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not adjust the preview volume. Try again.'),
        findsOneWidget);
    expect(fixture.platform.volumes, hasLength(requests));
    expect(fixture.platform.sources, hasLength(1));
    fixture.platform.volumeGate = null;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-mute')));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(volume).value, 0);
    expect(fixture.platform.played, isEmpty);
    _hideUrl();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English network initialization keeps its 15 second timeout and rejects late player',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    final gate = Completer<void>();
    fixture.platform.firstCreationGate = gate;
    await fixture.mount(tester, settle: false);
    await tester.pump(const Duration(seconds: 14));
    expect(find.text('Opening video…'), findsOneWidget);
    expect(find.text('Could not open this video'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Could not open this video'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-video-preview-retry')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('preview-english-player-2')), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    await _drain(tester);
    expect(
        find.byKey(const ValueKey('preview-english-player-1')), findsNothing);
    expect(
        find.byKey(const ValueKey('preview-english-player-2')), findsOneWidget);
    expect(fixture.platform.sources.map((source) => source.uri),
        everyElement(_url.toString()));
    expect(fixture.platform.disposeCounts[1], 1);
    expect(fixture.platform.played, isEmpty);
    _hideUrl();
    await fixture.close(tester);
    expect(fixture.platform.disposeCounts, {1: 1, 2: 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English owner revocation during initialization cannot revive a late network player',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    final gate = Completer<void>();
    fixture.platform.firstCreationGate = gate;
    await fixture.mount(tester, settle: false);
    PostDeeAuthSessionStore.instance.signOut();
    PostDeeAuthSessionStore.instance.signIn(_owner);
    await tester.pump();
    expect(find.text('Your account has changed. Reopen the video.'),
        findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    await _drain(tester);
    expect(
        find.byKey(const ValueKey('post-video-preview-player')), findsNothing);
    expect(
        find.byKey(const ValueKey('post-video-preview-retry')), findsNothing);
    expect(fixture.platform.sources, hasLength(1));
    expect(fixture.platform.disposeCounts, {1: 1});
    expect(fixture.platform.played, isEmpty);
    _hideUrl();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English owner revocation hides a pending volume request and disposes once',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    await fixture.mount(tester);
    final gate = Completer<void>();
    fixture.platform.volumeGate = gate;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-mute')));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signOut();
    await tester.pump();
    expect(find.text('Your account has changed. Reopen the video.'),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('post-video-preview-volume')), findsNothing);
    expect(find.text(fixture.videoName), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    await _drain(tester);
    expect(fixture.platform.disposeCounts, {1: 1});
    expect(fixture.platform.played, isEmpty);
    _hideUrl();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English play timeout cannot start late after restoring preview volume',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    await fixture.mount(tester);
    fixture.platform.failNextVolume = true;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-mute')));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    fixture.platform.volumeGate = gate;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Could not play this video. Try again.'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Could not play this video. Try again.'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(fixture.platform.played, isEmpty);
    expect(find.byTooltip('Play video'), findsOneWidget);
    expect(fixture.platform.sources, hasLength(1));
    _hideUrl();
    expect(tester.takeException(), isNull);
  });

  testWidgets('English seek timeout releases pending controls without autoplay',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    await fixture.mount(tester);
    final gate = Completer<void>();
    fixture.platform.seekGate = gate;
    final seek = find.byKey(const ValueKey('post-video-preview-seek'));
    final slider = tester.widget<Slider>(seek);
    slider.onChangeStart!(20000);
    slider.onChanged!(20000);
    slider.onChangeEnd!(20000);
    await tester.pump();
    expect(tester.widget<Slider>(seek).onChanged, isNull);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Could not play this video. Try again.'), findsOneWidget);
    expect(tester.widget<Slider>(seek).onChanged, isNotNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(fixture.platform.seeks, [const Duration(seconds: 20)]);
    expect(fixture.platform.played, isEmpty);
    expect(find.byTooltip('Play video'), findsOneWidget);
    _hideUrl();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English background return never resumes a pending play continuation',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    addTearDown(() => _resume(tester));
    await fixture.mount(tester);
    fixture.platform.failNextVolume = true;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-mute')));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    fixture.platform.volumeGate = gate;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    _resume(tester);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(fixture.platform.played, isEmpty);
    expect(find.byTooltip('Play video'), findsOneWidget);
    expect(fixture.platform.sources, hasLength(1));
    _hideUrl();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English unbound local preview keeps its owner-independent lifetime',
      (tester) async {
    final fixture = _fixture(network: false);
    addTearDown(() => _close(tester, fixture));
    addTearDown(() => _resume(tester));
    await fixture.mount(tester);
    PostDeeAuthSessionStore.instance.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Watch video'), findsOneWidget);
    expect(find.text(fixture.videoName), findsOneWidget);
    expect(
        find.text('Your account has changed. Reopen the video.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    expect(fixture.platform.played, [1]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    _resume(tester);
    await tester.pump();
    expect(find.byTooltip('Play video'), findsOneWidget);
    expect(fixture.platform.played, [1]);
    expect(fixture.platform.sources, hasLength(1));
    await fixture.close(tester);
    expect(fixture.platform.disposeCounts, {1: 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English network keeps credential refresh but revokes a new sign-in lifetime',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    await fixture.mount(tester);
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.updateCredentials(const AuthSession(
        userId: 'english-flow-owner', idToken: 'refreshed-token'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-video-preview-player')),
        findsOneWidget);
    expect(fixture.platform.disposeCounts, isEmpty);
    sessions.signIn(_owner);
    await tester.pumpAndSettle();
    expect(find.text('Your account has changed. Reopen the video.'),
        findsOneWidget);
    await _drain(tester);
    expect(fixture.platform.disposeCounts, {1: 1});
    expect(fixture.platform.sources, hasLength(1));
    expect(fixture.platform.played, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English network decoder failure keeps private URLs hidden on retry',
      (tester) async {
    final fixture = _fixture();
    addTearDown(() => _close(tester, fixture));
    await fixture.mount(tester);
    tester
        .widget<Slider>(find.byKey(const ValueKey('post-video-preview-volume')))
        .onChangeEnd!(.4);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    fixture.platform.events[1]!.addError(
        PlatformException(code: 'fake-expired-url', message: _url.toString()));
    await tester.pumpAndSettle();
    await _drain(tester);
    expect(find.text('Could not open this video'), findsOneWidget);
    _hideUrl();
    await tester.tap(find.byKey(const ValueKey('post-video-preview-retry')));
    await tester.pumpAndSettle();
    expect(fixture.platform.sources.map((source) => source.uri).toList(),
        [_url.toString(), _url.toString()]);
    expect(
        fixture.platform.volumes
            .where((call) => call.playerId == 2 && call.volume == .4),
        isNotEmpty);
    expect(fixture.platform.played, [1]);
    expect(find.byTooltip('Play video'), findsOneWidget);
    await fixture.close(tester);
    expect(fixture.platform.disposeCounts, {1: 1, 2: 1});
    expect(tester.takeException(), isNull);
  });

  for (final value in [
    'javascript:alert(1)',
    'https://user:secret@private-media.test/owned-video',
    'file:///private/owned-video.mp4'
  ]) {
    testWidgets(
        'English network URL policy rejects $value without native access',
        (tester) async {
      final fixture = _fixture()..networkUrl = Uri.parse(value);
      addTearDown(() => _close(tester, fixture));
      await fixture.mount(tester);
      expect(find.text('Could not open this video'), findsOneWidget);
      expect(
          find.text(
              'Go back and check the post status to open the latest preview.'),
          findsOneWidget);
      expect(find.textContaining(value), findsNothing);
      expect(fixture.platform.sources, isEmpty);
      expect(fixture.platform.played, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
