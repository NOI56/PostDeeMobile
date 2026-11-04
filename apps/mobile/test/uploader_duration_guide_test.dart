import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_duration_guide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/uploader_wizard_test_navigation.dart';
import 'uploader_video_english_test.dart';

const _revision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

SocialConnectionResult _connection({
  bool connected = true,
  String? id = 'local-tiktok',
  String? revision = _revision,
}) =>
    SocialConnectionResult(
      platform: 'TIKTOK',
      connected: connected,
      connectionId: id,
      connectionRevision: revision,
      externalAccountId: 'creator',
      displayName: 'บัญชี TikTok',
    );

TikTokPublishingOptionsResult _options({
  int maximum = 180,
  String connectionId = 'local-tiktok',
  String revision = _revision,
}) =>
    TikTokPublishingOptionsResult(
      connectionId: connectionId,
      creatorInfoRevision: revision,
      creatorInfo: TikTokCreatorInfo(
        creatorAvatarUrl: '',
        creatorUsername: 'creator',
        creatorNickname: 'บัญชี TikTok',
        privacyLevelOptions: const [TikTokPrivacyLevel.selfOnly],
        commentDisabled: false,
        duetDisabled: false,
        stitchDisabled: false,
        maxVideoPostDurationSec: maximum,
      ),
    );

/// Both loaders are injected separately so an advisory read cannot satisfy
/// Direct Post's independently loaded privacy choices and consent.
class _Fixture extends VideoEnglishFixture {
  _Fixture() : super(locale: const Locale('th'));

  List<SocialConnectionResult> connections = [_connection()];
  Future<TikTokPublishingOptionsResult> Function()? durationLoader;
  int durationLoads = 0;
  int directOptionLoads = 0;

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await super.mount(tester, settle: settle);
    await _revealGuide(tester, settle: settle);
  }

  @override
  UploaderScreen screen() => UploaderScreen(
        fullScreen: true,
        draftStore: store,
        enableRevenueCatBilling: false,
        initialVideoPath: initialVideo?.path,
        initialVideoName: initialVideo?.name,
        initialVideoSizeBytes: initialVideo?.sizeBytes,
        initialVideoWidth: initialVideo?.width,
        initialVideoHeight: initialVideo?.height,
        initialVideoDurationSeconds: initialVideo?.durationSeconds,
        loadTemplates: () async => const [],
        loadSubscription: () async => quota,
        loadPostQuota: () async => quota,
        loadCaptionQuota: () async => const CaptionQuotaResult(
          plan: 'PRO',
          quota: RealClipCaptionQuota(
              limit: 120, usedThisMonth: 0, remainingThisMonth: 120),
        ),
        loadSocialConnections: () async {
          connectionReads++;
          return connections;
        },
        loadSocialPublishingReadiness: () async => [
          for (final connection
              in connections.where((value) => value.connected))
            SocialPublishingConnectionReadiness(
              platform: connection.platform,
              state: SocialPublishingState.connected,
              connectionId: connection.connectionId,
              connectionRevision: connection.connectionRevision,
            ),
        ],
        loadTikTokDurationOptions: () async {
          durationLoads++;
          return durationLoader == null ? _options() : await durationLoader!();
        },
        loadTikTokPublishingOptions: () async {
          directOptionLoads++;
          return _options();
        },
        probePublishMedia: probeValidPublishMedia,
        checkPublishingReadiness: () async {},
        createUpload: (_) async {
          apiWrites++;
          throw StateError('Advisory guide must not create an upload');
        },
        uploadVideoFile: (_, __) async {
          apiWrites++;
          throw StateError('Advisory guide must not upload a file');
        },
        createPost: (_) async {
          apiWrites++;
          throw StateError('Advisory guide must not create a post');
        },
      );
}

Finder get _tikTokRow => find.byKey(const ValueKey('video-duration-TIKTOK'));

Finder _withinTikTok(String text) =>
    find.descendant(of: _tikTokRow, matching: find.text(text));

Future<void> _revealGuide(WidgetTester tester, {bool settle = true}) async {
  final guide = find.byType(VideoDurationGuide);
  await tester.scrollUntilVisible(guide, 200,
      scrollable: uploaderMainScroll,
      duration: const Duration(milliseconds: 50));
  await tester.ensureVisible(guide);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final control = find.byKey(ValueKey(key));
  await tester.ensureVisible(control);
  await tester.pump();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _pumpPendingRequest(WidgetTester tester, _Fixture fixture) async {
  await fixture.mount(tester, settle: false);
  // The fixture connection/readiness reads finish immediately. Do not settle
  // an intentionally pending request's loading animation.
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(fixture.durationLoads, 1);
}

void main() {
  late AuthSession previous;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: videoEnglishOwner, idToken: 'fixture-token'));
  });

  tearDown(() => PostDeeAuthSessionStore.instance.signIn(previous));

  testWidgets('step zero reads the connected creator limit automatically',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);

    expect(find.byKey(const ValueKey('video-duration-guide')), findsOneWidget);
    expect(_withinTikTok('ส่งเป็นร่าง: สูงสุด 600 วินาที'), findsOneWidget);
    expect(_withinTikTok('โพสต์ตรง: สูงสุด 180 วินาที'), findsOneWidget);
    expect(fixture.durationLoads, 1);
    expect(fixture.directOptionLoads, 0);
    expect(fixture.apiWrites, 0);
  });

  testWidgets('a failed advisory lookup stays unknown and can be retried',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.durationLoader = () async {
      if (fixture.durationLoads == 1) throw StateError('Unavailable');
      return _options(maximum: 300);
    };
    await fixture.mount(tester);

    final guide =
        tester.widget<VideoDurationGuide>(find.byType(VideoDurationGuide));
    expect(guide.tikTokMaxDurationSeconds, isNull);
    expect(guide.tikTokLimitFailed, isTrue);
    expect(_withinTikTok('โพสต์ตรง: รอตรวจบัญชี'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-duration-tiktok-retry')),
        findsOneWidget);

    await _tap(tester, 'video-duration-tiktok-retry');
    expect(_withinTikTok('โพสต์ตรง: สูงสุด 300 วินาที'), findsOneWidget);
    expect(fixture.durationLoads, 2);
    expect(fixture.directOptionLoads, 0);
    expect(fixture.apiWrites, 0);
  });

  for (final entry in <String, SocialConnectionResult>{
    'disconnected': _connection(connected: false),
    'missing connection ID': _connection(id: null),
    'missing connection revision': _connection(revision: null),
  }.entries) {
    testWidgets('does not fetch creator data for ${entry.key}', (tester) async {
      final fixture = _Fixture()..connections = [entry.value];
      addTearDown(fixture.dispose);
      await fixture.mount(tester);

      expect(find.byType(VideoDurationGuide), findsOneWidget);
      expect(fixture.durationLoads, 0);
      expect(fixture.directOptionLoads, 0);
      expect(fixture.apiWrites, 0);
      expect(
          tester
              .widget<VideoDurationGuide>(find.byType(VideoDurationGuide))
              .tikTokMaxDurationSeconds,
          isNull);
    });
  }

  for (final entry in <String, TikTokPublishingOptionsResult>{
    'another connection': _options(connectionId: 'other-connection'),
    'another revision': _options(
        revision:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
  }.entries) {
    testWidgets('never displays a cap returned for ${entry.key}',
        (tester) async {
      final fixture = _Fixture()..durationLoader = () async => entry.value;
      addTearDown(fixture.dispose);
      await fixture.mount(tester);

      expect(
          tester
              .widget<VideoDurationGuide>(find.byType(VideoDurationGuide))
              .tikTokMaxDurationSeconds,
          isNull);
      expect(_withinTikTok('โพสต์ตรง: สูงสุด 180 วินาที'), findsNothing);
      expect(fixture.directOptionLoads, 0);
      expect(fixture.apiWrites, 0);
    });
  }

  testWidgets(
      'a delayed previous-owner limit cannot appear after switching owners',
      (tester) async {
    final stale = Completer<TikTokPublishingOptionsResult>();
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.durationLoader = () => fixture.durationLoads == 1
        ? stale.future
        : Future.value(_options(maximum: 300));
    await _pumpPendingRequest(tester, fixture);

    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: 'other-owner', idToken: 'other-fixture-token'));
    await tester.pump();
    stale.complete(_options(maximum: 180));
    await tester.pumpAndSettle();
    await _revealGuide(tester);

    expect(_withinTikTok('โพสต์ตรง: สูงสุด 180 วินาที'), findsNothing);
    expect(
        tester
            .widget<VideoDurationGuide>(find.byType(VideoDurationGuide))
            .tikTokMaxDurationSeconds,
        isNot(180));
    expect(fixture.directOptionLoads, 0);
    expect(fixture.apiWrites, 0);
  });

  testWidgets('a sign out and sign in with the same UID discards the old limit',
      (tester) async {
    final stale = Completer<TikTokPublishingOptionsResult>();
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.durationLoader = () => fixture.durationLoads == 1
        ? stale.future
        : Future.value(_options(maximum: 300));
    await _pumpPendingRequest(tester, fixture);

    PostDeeAuthSessionStore.instance.clear();
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: videoEnglishOwner, idToken: 'new-sign-in-token'));
    await tester.pump();
    stale.complete(_options(maximum: 180));
    await tester.pumpAndSettle();
    await _revealGuide(tester);

    expect(_withinTikTok('โพสต์ตรง: สูงสุด 180 วินาที'), findsNothing);
    expect(
        tester
            .widget<VideoDurationGuide>(find.byType(VideoDurationGuide))
            .tikTokMaxDurationSeconds,
        isNot(180));
    expect(fixture.apiWrites, 0);
  });

  testWidgets('connection refresh cannot be overwritten by its earlier lookup',
      (tester) async {
    const replacementRevision =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final stale = Completer<TikTokPublishingOptionsResult>();
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('clip.mp4', duration: 45);
    fixture.durationLoader = () => fixture.durationLoads == 1
        ? stale.future
        : Future.value(_options(maximum: 300, revision: replacementRevision));
    await _pumpPendingRequest(tester, fixture);
    await goToUploaderStep(tester, 1);
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.ensureVisible(caption);
    await tester.enterText(caption, 'คลิปสำหรับตรวจการรีเฟรชบัญชี');
    await goToUploaderStep(tester, 2);
    fixture.connections = [_connection(revision: replacementRevision)];
    await _tap(tester, 'uploader-refresh-publishing-readiness');
    await goToUploaderStep(tester, 0);
    await _revealGuide(tester);
    expect(_withinTikTok('โพสต์ตรง: สูงสุด 300 วินาที'), findsOneWidget);

    stale.complete(_options(maximum: 180));
    await tester.pumpAndSettle();
    expect(_withinTikTok('โพสต์ตรง: สูงสุด 300 วินาที'), findsOneWidget);
    expect(_withinTikTok('โพสต์ตรง: สูงสุด 180 วินาที'), findsNothing);
    expect(fixture.durationLoads, 2);
    expect(fixture.directOptionLoads, 0);
    expect(fixture.apiWrites, 0);
  });

  testWidgets(
      'caption edits preserve the advisory account limit without refetching',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('clip.mp4', duration: 45);
    await fixture.mount(tester);
    await goToUploaderStep(tester, 1);
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.ensureVisible(caption);
    await tester.enterText(caption, 'แคปชันแรก');
    await tester.pump();
    await tester.enterText(caption, 'แคปชันที่แก้ไข');
    await tester.pump();
    await goToUploaderStep(tester, 0);
    await _revealGuide(tester);

    expect(_withinTikTok('โพสต์ตรง: สูงสุด 180 วินาที'), findsOneWidget);
    expect(fixture.durationLoads, 1);
    expect(fixture.directOptionLoads, 0);
    expect(fixture.apiWrites, 0);
  });

  testWidgets(
      'an advisory read cannot preselect Direct privacy or music consent',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('clip.mp4', duration: 45);
    await fixture.mount(tester);
    await goToUploaderStep(tester, 1);
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.ensureVisible(caption);
    await tester.enterText(caption, 'คลิปสำหรับตรวจเกณฑ์เวลา');
    await goToUploaderStep(tester, 2);
    await _tap(tester, 'uploader-platform-TIKTOK');
    await _tap(tester, 'uploader-platform-settings-TIKTOK');
    expect(fixture.directOptionLoads, 0);
    await _tap(tester, 'uploader-tiktok-mode-direct');

    expect(fixture.directOptionLoads, 1,
        reason: 'Direct settings must load their own fresh capabilities');
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('uploader-tiktok-music-consent')))
            .value,
        isFalse);
    expect(
        tester
            .widget<DropdownButtonFormField<TikTokPrivacyLevel>>(
                find.byKey(const ValueKey('uploader-tiktok-privacy')))
            .initialValue,
        isNull);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('uploader-platform-settings-save')))
            .onPressed,
        isNull);
    expect(fixture.apiWrites, 0);
  });
}
