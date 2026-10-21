import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_defaults_store.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _saveKey = ValueKey('uploader-platform-settings-save');
const _cancelKey = ValueKey('uploader-platform-settings-cancel');
const _revision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _pro = SubscriptionStatusResult(
  userId: 'test-user',
  plan: 'PRO',
  status: 'ACTIVE',
  phoneVerified: true,
  requiresPhoneVerification: false,
  canSchedule: true,
  canUseAiCaptions: true,
  canUseAnalytics: true,
);
const _connections = [
  SocialConnectionResult(
    platform: 'YOUTUBE_SHORTS',
    connected: true,
    connectionId: 'local-youtube',
    connectionRevision: _revision,
    externalAccountId: 'youtube-seller',
    displayName: 'ร้าน YouTube ทดสอบ',
  ),
  SocialConnectionResult(
    platform: 'TIKTOK',
    connected: true,
    connectionId: 'local-tiktok',
    connectionRevision: _revision,
    externalAccountId: 'tiktok-seller',
    displayName: 'ร้าน TikTok ทดสอบ',
  ),
  SocialConnectionResult(
    platform: 'INSTAGRAM_REELS',
    connected: true,
    connectionId: 'local-instagram',
    connectionRevision: _revision,
    externalAccountId: 'instagram-seller',
    displayName: 'ร้าน Instagram ทดสอบ',
  ),
  SocialConnectionResult(
    platform: 'FACEBOOK_REELS',
    connected: true,
    connectionId: 'local-facebook',
    connectionRevision: _revision,
    externalAccountId: 'facebook-page',
    displayName: 'เพจ Facebook ทดสอบ',
  ),
];

class _DefaultsStore implements PlatformPublishDefaultsStore {
  PlatformPublishDefaults? value;
  bool useScopedValues = false;
  final values = <String, PlatformPublishDefaults>{};
  Future<PlatformPublishDefaults?> Function(PlatformPublishDefaultsScope scope)?
      onLoad;
  Future<void>? saveGate;
  Completer<void>? saveStarted;
  Object? saveError;
  final loads = <PlatformPublishDefaultsScope>[];
  final saves =
      <({PlatformPublishDefaultsScope scope, PlatformPublishDefaults value})>[];

  @override
  Future<PlatformPublishDefaults?> load(PlatformPublishDefaultsScope scope) {
    loads.add(scope);
    return onLoad?.call(scope) ??
        Future.value(useScopedValues ? values[scope.storageKey] : value);
  }

  @override
  Future<void> save(
    PlatformPublishDefaultsScope scope,
    PlatformPublishDefaults defaults, {
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) return;
    saveStarted?.complete();
    if (saveGate != null) await saveGate;
    if (isCurrent != null && !isCurrent()) return;
    if (saveError != null) throw saveError!;
    saves.add((scope: scope, value: defaults));
    value = defaults;
    values[scope.storageKey] = defaults;
  }

  @override
  Future<void> clearForDeletedAccount(String ownerUserId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File video;
  late File replacement;
  late TestPublishDraftStore drafts;
  late _DefaultsStore defaults;
  late AuthSession previous;
  late ThemeMode previousTheme;
  late int creatorLoads;
  late List<SocialConnectionResult> connections;

  setUpAll(() async {
    final fonts = FontLoader('Anuphan');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts
          .addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
    }
    await fonts.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
      userId: 'test-user',
      idToken: 'test-token',
    ));
    previousTheme = AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    AppTheme.applyThemeMode(ThemeMode.light);
    directory = Directory.systemTemp.createTempSync('remember-settings-');
    video = File('${directory.path}/first.mp4')..writeAsBytesSync([1, 2, 3]);
    replacement = File('${directory.path}/second.mp4')
      ..writeAsBytesSync([4, 5, 6]);
    drafts = TestPublishDraftStore();
    defaults = _DefaultsStore();
    creatorLoads = 0;
    connections = _connections;
  });

  tearDown(() {
    PostDeeAuthSessionStore.instance.signIn(previous);
    AppTheme.applyThemeMode(previousTheme);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Widget uploader({String? initialDraftId}) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UploaderScreen(
            draftStore: drafts,
            platformPublishDefaultsStore: defaults,
            initialDraftId: initialDraftId,
            initialVideoPath: initialDraftId == null ? video.path : null,
            initialVideoName: 'first.mp4',
            initialVideoSizeBytes: 3,
            initialVideoWidth: 720,
            initialVideoHeight: 1280,
            loadSubscription: () async => _pro,
            loadSocialConnections: () async => connections,
            loadSocialPublishingReadiness: () async => [
              for (final connection in connections)
                SocialPublishingConnectionReadiness(
                  platform: connection.platform,
                  state: SocialPublishingState.connected,
                  connectionId: connection.connectionId,
                  connectionRevision: connection.connectionRevision,
                ),
            ],
            loadTikTokPublishingOptions: () async {
              creatorLoads += 1;
              return const TikTokPublishingOptionsResult(
                connectionId: 'local-tiktok',
                creatorInfoRevision: _revision,
                creatorInfo: TikTokCreatorInfo(
                  creatorAvatarUrl: '',
                  creatorUsername: 'seller',
                  creatorNickname: 'ร้าน TikTok ล่าสุด',
                  privacyLevelOptions: [TikTokPrivacyLevel.selfOnly],
                  commentDisabled: false,
                  duetDisabled: false,
                  stitchDisabled: false,
                  maxVideoPostDurationSec: 600,
                ),
              );
            },
            pickVideo: () async => PickedVideoFile(
              name: 'second.mp4',
              path: replacement.path,
              sizeBytes: 3,
              width: 720,
              height: 1280,
              durationSeconds: 10,
            ),
            probePublishMedia: probeValidPublishMedia,
          ),
        ),
      );

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> selectPlatform(WidgetTester tester, String platform,
      {String caption = 'คลิปใหม่ของร้าน'}) async {
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await tester.enterText(
        find.byKey(const ValueKey('uploader-caption-field')), caption);
    await goToUploaderStep(tester, 2);
    await tapKey(tester, ValueKey('uploader-platform-$platform'));
  }

  Future<void> openSettings(WidgetTester tester,
          [String platform = 'YOUTUBE_SHORTS']) =>
      tapKey(tester, ValueKey('uploader-platform-settings-$platform'));

  Future<void> freshUploader(WidgetTester tester,
      {String platform = 'YOUTUBE_SHORTS',
      String caption = 'ชื่อคลิปถัดไป'}) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, platform, caption: caption);
    await openSettings(tester, platform);
  }

  bool selected(WidgetTester tester, String key) => find
      .descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byIcon(Icons.radio_button_checked_rounded),
      )
      .evaluate()
      .isNotEmpty;

  YouTubeVisibility? youtubeVisibility(WidgetTester tester) => tester
      .state<FormFieldState<YouTubeVisibility>>(
          find.byKey(const ValueKey('uploader-youtube-visibility')))
      .value;

  bool youtubeCertified(WidgetTester tester) => tester
      .widget<CheckboxListTile>(
          find.byKey(const ValueKey('uploader-youtube-guidelines-certified')))
      .value!;

  Future<void> chooseVisibility(
      WidgetTester tester, YouTubeVisibility visibility) async {
    await tapKey(tester, const ValueKey('uploader-youtube-visibility'));
    final label = switch (visibility) {
      YouTubeVisibility.private => 'ส่วนตัว (Private)',
      YouTubeVisibility.unlisted => 'ไม่เป็นสาธารณะ (Unlisted)',
      YouTubeVisibility.public => 'สาธารณะ (Public)',
    };
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> completeYouTube(WidgetTester tester,
      {bool synthetic = false}) async {
    await tapKey(tester, const ValueKey('uploader-youtube-made-for-kids-no'));
    await tapKey(
        tester,
        ValueKey(synthetic
            ? 'uploader-youtube-synthetic-yes'
            : 'uploader-youtube-synthetic-no'));
    await tapKey(
        tester, const ValueKey('uploader-youtube-guidelines-certified'));
  }

  void expectFreshYouTubeContent(WidgetTester tester, String title) {
    expect(find.text(title), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-youtube-title')), findsNothing);
    expect(selected(tester, 'uploader-youtube-synthetic-yes'), isFalse);
    expect(selected(tester, 'uploader-youtube-synthetic-no'), isFalse);
    expect(youtubeCertified(tester), isFalse);
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
  }

  testWidgets(
      'new composer remembers YouTube visibility and audience, not clip declarations',
      (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    await chooseVisibility(tester, YouTubeVisibility.unlisted);
    await tapKey(tester, const ValueKey('uploader-youtube-title-edit'));
    await tester.enterText(find.byKey(const ValueKey('uploader-youtube-title')),
        'ชื่อเฉพาะของคลิปแรก');
    await completeYouTube(tester, synthetic: true);
    await tapKey(tester, _saveKey);
    expect(defaults.saves, hasLength(1));

    await freshUploader(tester);
    expect(youtubeVisibility(tester), YouTubeVisibility.unlisted);
    expect(selected(tester, 'uploader-youtube-made-for-kids-no'), isTrue);
    expectFreshYouTubeContent(tester, 'ชื่อคลิปถัดไป');
  });

  testWidgets('Cancel never writes changed platform defaults', (tester) async {
    phoneSize(tester);
    defaults.value = PlatformPublishDefaults.fromSettings(
        SocialPlatform.youtubeShorts,
        const PlatformPublishSettings(
            youtubeVisibility: YouTubeVisibility.unlisted,
            youtubeMadeForKids: false));
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    await chooseVisibility(tester, YouTubeVisibility.public);
    await tapKey(tester, const ValueKey('uploader-youtube-made-for-kids-yes'));
    await tapKey(tester, _cancelKey);
    expect(defaults.saves, isEmpty);

    await freshUploader(tester);
    expect(youtubeVisibility(tester), YouTubeVisibility.unlisted);
    expect(selected(tester, 'uploader-youtube-made-for-kids-no'), isTrue);
    expect(defaults.saves, isEmpty);
  });

  testWidgets('closing the settings sheet never writes edited defaults',
      (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    await chooseVisibility(tester, YouTubeVisibility.public);
    await completeYouTube(tester);
    await tester.tap(find.byTooltip('ปิด').last);
    await tester.pumpAndSettle();
    expect(defaults.saves, isEmpty);
    await freshUploader(tester);
    expect(youtubeVisibility(tester), YouTubeVisibility.private);
    expect(selected(tester, 'uploader-youtube-made-for-kids-no'), isFalse);
  });

  for (final platform in ['INSTAGRAM_REELS', 'FACEBOOK_REELS']) {
    testWidgets('$platform remembers delivery options but clears AI answers',
        (tester) async {
      phoneSize(tester);
      final instagram = platform == 'INSTAGRAM_REELS';
      final prefix = instagram ? 'instagram' : 'facebook';
      await tester.pumpWidget(uploader());
      await selectPlatform(tester, platform);
      await openSettings(tester, platform);
      await tapKey(
          tester,
          ValueKey(instagram
              ? 'uploader-instagram-share-to-feed'
              : 'uploader-facebook-page-draft'));
      await tapKey(tester, ValueKey('uploader-$prefix-ai-yes'));
      await tapKey(tester, _saveKey);
      expect(defaults.saves, hasLength(1));

      await freshUploader(tester, platform: platform);
      if (instagram) {
        expect(
            tester
                .widget<SwitchListTile>(find
                    .byKey(const ValueKey('uploader-instagram-share-to-feed')))
                .value,
            isFalse);
      } else {
        expect(selected(tester, 'uploader-facebook-page-draft'), isTrue);
      }
      expect(selected(tester, 'uploader-$prefix-ai-yes'), isFalse);
      expect(selected(tester, 'uploader-$prefix-ai-no'), isFalse);
    });
  }

  for (final jumpToReview in [false, true]) {
    testWidgets(
        'remembered Instagram feed choice applies without opening settings via ${jumpToReview ? 'progress' : 'Next'}',
        (tester) async {
      phoneSize(tester);
      defaults.value = PlatformPublishDefaults.fromSettings(
          SocialPlatform.instagramReels,
          const PlatformPublishSettings(instagramShareToFeed: false));
      await tester.pumpWidget(uploader());
      await selectPlatform(tester, 'INSTAGRAM_REELS');
      if (jumpToReview) {
        await goToUploaderStep(tester, 3);
      } else {
        await tapKey(tester, const ValueKey('uploader-wizard-next'));
      }
      expect(
          find.byKey(const ValueKey('uploader-step-review')), findsOneWidget);
      expect(find.textContaining('Reels อย่างเดียว'), findsWidgets);
      expect(find.textContaining('Reels + ฟีด'), findsNothing);
      expect(defaults.loads, hasLength(1));
      expect(defaults.saves, isEmpty);
    });
  }

  testWidgets('saving a new draft still loads preferences in optional settings',
      (tester) async {
    phoneSize(tester);
    defaults.value = PlatformPublishDefaults.fromSettings(
        SocialPlatform.instagramReels,
        const PlatformPublishSettings(instagramShareToFeed: false));
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'INSTAGRAM_REELS');
    await tapKey(tester, const ValueKey('uploader-save-draft-button'));
    expect(drafts.savedRequests, hasLength(1));
    await openSettings(tester, 'INSTAGRAM_REELS');
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('uploader-instagram-share-to-feed')))
            .value,
        isFalse);
    await tapKey(tester, _cancelKey);
    await goToUploaderStep(tester, 3);
    expect(find.textContaining('Reels อย่างเดียว'), findsWidgets);
    expect(defaults.saves, isEmpty);
  });

  testWidgets('a new draft saved before channel selection still loads defaults',
      (tester) async {
    phoneSize(tester);
    defaults.value = PlatformPublishDefaults.fromSettings(
        SocialPlatform.instagramReels,
        const PlatformPublishSettings(instagramShareToFeed: false));
    await tester.pumpWidget(uploader());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await tester.enterText(find.byKey(const ValueKey('uploader-caption-field')),
        'คลิปใหม่ของร้าน');
    await tapKey(tester, const ValueKey('uploader-save-draft-button'));
    expect(drafts.savedRequests, hasLength(1));
    await goToUploaderStep(tester, 2);
    await tapKey(tester, const ValueKey('uploader-platform-INSTAGRAM_REELS'));
    await goToUploaderStep(tester, 3);
    expect(find.textContaining('Reels อย่างเดียว'), findsWidgets);
    expect(defaults.loads, hasLength(1));
    expect(defaults.saves, isEmpty);
  });

  testWidgets('remembered TikTok Direct cannot silently fall back to Inbox',
      (tester) async {
    phoneSize(tester);
    defaults.value = PlatformPublishDefaults.fromSettings(
        SocialPlatform.tiktok,
        const PlatformPublishSettings(
            tiktokPublishMode: TikTokPublishMode.directPost));
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'TIKTOK');
    await goToUploaderStep(tester, 3);
    expect(find.textContaining('ยังไม่พร้อมโพสต์ตรง'), findsWidgets);
    expect(find.textContaining('ส่งเป็นร่างเข้า TikTok'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('publish-review-confirm')))
            .onPressed,
        isNull);
    expect(defaults.saves, isEmpty);
  });

  testWidgets('a timed-out defaults read unlocks review controls safely',
      (tester) async {
    phoneSize(tester);
    final pending = Completer<PlatformPublishDefaults?>();
    defaults.onLoad = (_) => pending.future;
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'INSTAGRAM_REELS');
    final next = find.byKey(const ValueKey('uploader-wizard-next'));
    final scroll = tester.state<ScrollableState>(uploaderMainScroll);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(next);
    await tester.pump();
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-step-body-2')), findsOneWidget);
    final notice = find.text(
        'โหลดค่าที่จำไว้ไม่สำเร็จ กรุณาเปิดตั้งค่าช่องทางเพื่อตรวจสอบก่อน');
    expect(notice.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    pending.complete(PlatformPublishDefaults.fromSettings(
        SocialPlatform.instagramReels,
        const PlatformPublishSettings(instagramShareToFeed: false)));
    await tester.pumpAndSettle();
    expect(find.text('แชร์ในฟีด'), findsOneWidget);
    expect(find.text('ไม่แชร์ในฟีด'), findsNothing);
    expect(defaults.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved choices for this clip win over a later defaults read',
      (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    await chooseVisibility(tester, YouTubeVisibility.unlisted);
    await completeYouTube(tester, synthetic: true);
    await tapKey(tester, _saveKey);
    final loadsAfterSave = defaults.loads.length;
    defaults.value = PlatformPublishDefaults.fromSettings(
        SocialPlatform.youtubeShorts,
        const PlatformPublishSettings(
            youtubeVisibility: YouTubeVisibility.public,
            youtubeMadeForKids: true));

    await openSettings(tester);
    expect(defaults.loads, hasLength(loadsAfterSave));
    expect(youtubeVisibility(tester), YouTubeVisibility.unlisted);
    expect(selected(tester, 'uploader-youtube-made-for-kids-no'), isTrue);
    expect(selected(tester, 'uploader-youtube-synthetic-yes'), isTrue);
    expect(youtubeCertified(tester), isTrue);
  });

  testWidgets('a failed defaults read leaves the clip settings usable',
      (tester) async {
    phoneSize(tester);
    defaults.onLoad = (_) async => throw StateError('private-storage-error');
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    expect(find.text('โหลดค่าที่จำไว้ไม่สำเร็จ ตั้งค่าสำหรับคลิปนี้ได้ตามปกติ'),
        findsOneWidget);
    expect(find.textContaining('private-storage-error'), findsNothing);
    await completeYouTube(tester);
    await tapKey(tester, _saveKey);
    expect(defaults.saves, hasLength(1));
    await openSettings(tester);
    expect(youtubeCertified(tester), isTrue);
  });

  testWidgets('a failed defaults write keeps the applied current-clip choices',
      (tester) async {
    phoneSize(tester);
    defaults.saveError = StateError('private-storage-error');
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    await chooseVisibility(tester, YouTubeVisibility.unlisted);
    await completeYouTube(tester, synthetic: true);
    await tapKey(tester, _saveKey);
    expect(
        find.text('ใช้การตั้งค่ากับคลิปนี้แล้ว แต่จำค่าไว้ครั้งถัดไปไม่สำเร็จ'),
        findsOneWidget);
    expect(find.textContaining('private-storage-error'), findsNothing);
    await openSettings(tester);
    expect(youtubeVisibility(tester), YouTubeVisibility.unlisted);
    expect(selected(tester, 'uploader-youtube-synthetic-yes'), isTrue);
    expect(youtubeCertified(tester), isTrue);
    expect(defaults.saves, isEmpty);
  });

  testWidgets('cancelled pending defaults never reopen or mutate the sheet',
      (tester) async {
    phoneSize(tester);
    final pending = Completer<PlatformPublishDefaults?>();
    defaults.onLoad = (_) => pending.future;
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    final settings =
        find.byKey(const ValueKey('uploader-platform-settings-YOUTUBE_SHORTS'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('uploader-platform-defaults-loading')),
        findsOneWidget);
    await tester.tap(find.byKey(_cancelKey));
    await tester.pump(const Duration(milliseconds: 400));
    pending.complete(PlatformPublishDefaults.fromSettings(
        SocialPlatform.youtubeShorts,
        const PlatformPublishSettings(
            youtubeVisibility: YouTubeVisibility.public,
            youtubeMadeForKids: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(_saveKey), findsNothing);
    expect(defaults.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old defaults response is discarded across sign-in lifecycles',
      (tester) async {
    phoneSize(tester);
    final pending = Completer<PlatformPublishDefaults?>();
    defaults.onLoad = (_) => pending.future;
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    final settings =
        find.byKey(const ValueKey('uploader-platform-settings-YOUTUBE_SHORTS'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('uploader-platform-defaults-loading')),
        findsOneWidget);
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'another-owner', idToken: 'another-token'));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'test-user', idToken: 'new-sign-in-token'));
    pending.complete(PlatformPublishDefaults.fromSettings(
        SocialPlatform.youtubeShorts,
        const PlatformPublishSettings(
            youtubeVisibility: YouTubeVisibility.public,
            youtubeMadeForKids: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-youtube-visibility')),
        findsNothing);
    final save = find.byKey(_saveKey);
    if (save.evaluate().isNotEmpty) {
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    }
    expect(defaults.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending defaults write cannot survive a new sign-in lifecycle',
      (tester) async {
    phoneSize(tester);
    final pending = Completer<void>();
    final started = Completer<void>();
    defaults.saveGate = pending.future;
    defaults.saveStarted = started;
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    await completeYouTube(tester);
    await tester.tap(find.byKey(_saveKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(started.isCompleted, isTrue);
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'another-owner', idToken: 'another-token'));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'test-user', idToken: 'new-sign-in-token'));
    pending.complete();
    await tester.pumpAndSettle();
    expect(defaults.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final failSave in [false, true]) {
    testWidgets(
        'an explicit defaults save ${failSave ? 'can fail safely' : 'finishes'} after closing the composer',
        (tester) async {
      phoneSize(tester);
      final pending = Completer<void>();
      final started = Completer<void>();
      defaults.saveGate = pending.future;
      defaults.saveStarted = started;
      defaults.saveError =
          failSave ? StateError('private-storage-error') : null;
      await tester.pumpWidget(uploader());
      await selectPlatform(tester, 'YOUTUBE_SHORTS');
      await openSettings(tester);
      await completeYouTube(tester);
      await tester.tap(find.byKey(_saveKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(started.isCompleted, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();
      expect(defaults.saves, hasLength(failSave ? 0 : 1));
      if (!failSave) {
        expect(defaults.saves.single.scope.ownerUserId, 'test-user');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('restored drafts keep their settings ahead of reusable defaults',
      (tester) async {
    phoneSize(tester);
    defaults.value = PlatformPublishDefaults.fromSettings(
        SocialPlatform.youtubeShorts,
        const PlatformPublishSettings(
            youtubeVisibility: YouTubeVisibility.public,
            youtubeMadeForKids: true));
    final saved = await drafts.saveDraft(PublishDraftSaveRequest(
      id: 'youtube-draft',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      videoFile: video,
      videoName: 'first.mp4',
      videoSizeBytes: 3,
      videoWidth: 720,
      videoHeight: 1280,
      caption: 'แคปชั่นของร่างเดิม',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: {'YOUTUBE_SHORTS'},
      platformSettings: const PlatformPublishSettings(
        youtubeTitle: 'ชื่อที่ตั้งในร่างเดิม',
        youtubeVisibility: YouTubeVisibility.unlisted,
        youtubeMadeForKids: false,
        youtubeContainsSyntheticMedia: true,
        youtubeCommunityGuidelinesCertified: true,
      ),
    ));
    await tester.pumpWidget(uploader(initialDraftId: saved.id));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    await openSettings(tester);
    expect(defaults.loads, isEmpty);
    expect(youtubeVisibility(tester), YouTubeVisibility.unlisted);
    expect(selected(tester, 'uploader-youtube-made-for-kids-no'), isTrue);
    expect(selected(tester, 'uploader-youtube-synthetic-yes'), isTrue);
    expect(youtubeCertified(tester), isFalse);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-youtube-title')))
            .controller!
            .text,
        'ชื่อที่ตั้งในร่างเดิม');
  });

  testWidgets(
      'remembered TikTok Direct still requests fresh publishing choices',
      (tester) async {
    phoneSize(tester);
    defaults.value = PlatformPublishDefaults.fromSettings(
        SocialPlatform.tiktok,
        const PlatformPublishSettings(
          tiktokPublishMode: TikTokPublishMode.directPost,
          tiktokPrivacyLevel: TikTokPrivacyLevel.selfOnly,
          tiktokCreatorInfoRevision: _revision,
          tiktokAllowComment: true,
          tiktokAllowDuet: true,
          tiktokAllowStitch: true,
          tiktokIsAigc: true,
          tiktokMusicUsageConfirmed: true,
          tiktokVideoDurationSeconds: 10,
        ));
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'TIKTOK');
    await openSettings(tester, 'TIKTOK');
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('uploader-tiktok-mode-direct')))
            .selected,
        isTrue);
    expect(creatorLoads, 1);
    expect(
        tester
            .state<FormFieldState<TikTokPrivacyLevel>>(
                find.byKey(const ValueKey('uploader-tiktok-privacy')))
            .value,
        isNull);
    for (final key in [
      'uploader-tiktok-allow-comment',
      'uploader-tiktok-allow-duet',
      'uploader-tiktok-allow-stitch',
      'uploader-tiktok-aigc',
      'uploader-tiktok-music-consent',
    ]) {
      expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey(key))).value,
          isFalse);
    }
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
  });

  testWidgets('replacing the clip clears content-specific YouTube answers',
      (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    await chooseVisibility(tester, YouTubeVisibility.unlisted);
    await tapKey(tester, const ValueKey('uploader-youtube-title-edit'));
    await tester.enterText(find.byKey(const ValueKey('uploader-youtube-title')),
        'ชื่อเฉพาะของคลิปแรก');
    await completeYouTube(tester, synthetic: true);
    await tapKey(tester, _saveKey);
    await goToUploaderStep(tester, 0);
    await tapKey(tester, const ValueKey('uploader-video-preview-picker'));
    await goToUploaderStep(tester, 2);
    await openSettings(tester);
    expect(youtubeVisibility(tester), YouTubeVisibility.unlisted);
    expect(selected(tester, 'uploader-youtube-made-for-kids-no'), isTrue);
    expectFreshYouTubeContent(tester, 'คลิปใหม่ของร้าน');
  });

  testWidgets('replacing a clip cannot carry settings into a different channel',
      (tester) async {
    phoneSize(tester);
    defaults.useScopedValues = true;
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS');
    await openSettings(tester);
    await chooseVisibility(tester, YouTubeVisibility.unlisted);
    await completeYouTube(tester, synthetic: true);
    await tapKey(tester, _saveKey);
    final originalScope = defaults.saves.single.scope;
    connections = [
      for (final connection in _connections)
        if (connection.platform != 'YOUTUBE_SHORTS') connection,
      const SocialConnectionResult(
        platform: 'YOUTUBE_SHORTS',
        connected: true,
        connectionId: 'another-youtube-connection',
        connectionRevision: _revision,
        externalAccountId: 'another-youtube-seller',
        displayName: 'อีกช่อง YouTube',
      ),
    ];
    await tapKey(
        tester, const ValueKey('uploader-refresh-publishing-readiness'));
    await goToUploaderStep(tester, 0);
    await tapKey(tester, const ValueKey('uploader-video-preview-picker'));
    await goToUploaderStep(tester, 2);
    await openSettings(tester);
    expect(defaults.loads.last, isNot(originalScope));
    expect(youtubeVisibility(tester), YouTubeVisibility.private);
    expect(selected(tester, 'uploader-youtube-made-for-kids-no'), isFalse);
    expect(selected(tester, 'uploader-youtube-made-for-kids-yes'), isFalse);
    expectFreshYouTubeContent(tester, 'คลิปใหม่ของร้าน');
    expect(defaults.saves, hasLength(1));
  });
}
