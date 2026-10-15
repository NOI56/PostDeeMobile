import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _revision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _pro = SubscriptionStatusResult(
    userId: 'test-user',
    plan: 'PRO',
    status: 'ACTIVE',
    phoneVerified: true,
    requiresPhoneVerification: false,
    canUseFreePostQuota: false,
    canSchedule: true,
    canUseAiCaptions: true,
    canUseAnalytics: true);

TikTokPublishingOptionsResult _options({
  List<TikTokPrivacyLevel> privacy = const [
    TikTokPrivacyLevel.publicToEveryone,
    TikTokPrivacyLevel.mutualFollowFriends,
    TikTokPrivacyLevel.selfOnly
  ],
  String revision = _revision,
}) =>
    TikTokPublishingOptionsResult(
        connectionId: 'local-tiktok',
        creatorInfoRevision: revision,
        creatorInfo: TikTokCreatorInfo(
            creatorAvatarUrl: '',
            creatorUsername: 'seller',
            creatorNickname: 'คนขายทดสอบ',
            privacyLevelOptions: privacy,
            commentDisabled: false,
            duetDisabled: true,
            stitchDisabled: false,
            maxVideoPostDurationSec: 3600));

void main() {
  late Directory root;
  late File source;
  late File prepared;
  late AuthSession previous;
  late TestPublishDraftStore store;
  late List<String> events;
  late List<CreatePostRequest> requests;
  var optionLoads = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'test-user'));
    root = Directory.systemTemp.createTempSync('direct-post-widget-');
    source = File('${root.path}/source.mp4')..writeAsBytesSync([1, 2, 3]);
    prepared = File('${root.path}/prepared.mp4')
      ..writeAsBytesSync([4, 5, 6, 7]);
    store = TestPublishDraftStore();
    events = [];
    requests = [];
    optionLoads = 0;
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.signIn(previous);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Widget app(
          {Future<TikTokPublishingOptionsResult> Function()? options,
          UploaderPostCreator? post,
          double? duration = 1.25,
          String? initialDraftId}) =>
      MaterialApp(
          home: Scaffold(
              body: UploaderScreen(
        probePublishMedia: probeValidPublishMedia,
        loadSocialPublishingReadiness: () async => const [
          SocialPublishingConnectionReadiness(
              platform: 'TIKTOK', state: SocialPublishingState.connected,
              connectionId: 'local-tiktok', connectionRevision: _revision),
        ],
        draftStore: store,
        initialDraftId: initialDraftId,
        initialVideoPath: initialDraftId == null ? source.path : null,
        initialVideoName: initialDraftId == null ? 'source.mp4' : null,
        initialVideoSizeBytes: 3,
        initialVideoWidth: 720,
        initialVideoHeight: 1280,
        loadSubscription: () async => _pro,
        loadSocialConnections: () async => const [
          SocialConnectionResult(
              platform: 'TIKTOK',
              connected: true,
              connectionId: 'local-tiktok',
              connectionRevision: _revision,
              externalAccountId: 'seller',
              displayName: 'ชื่อบัญชีจากรายการเดิม')
        ],
        loadTikTokPublishingOptions: () async {
          optionLoads++;
          return await (options?.call() ?? Future.value(_options()));
        },
        checkPublishingReadiness: () async {},
        prepareTikTokVideo: (request) async {
          events.add('prepare');
          expect(request.maxDurationSeconds, 600);
          return TikTokPreparedVideoResult(
              file: prepared,
              fileName: 'ready.mp4',
              sizeBytes: 4,
              width: 720,
              height: 1280,
              durationSeconds: duration);
        },
        createUpload: (_) async {
          events.add('upload');
          return const UploadResult(
              id: 'upload',
              videoS3Key: 'uploads/ready.mp4',
              storageProvider: 'mock');
        },
        uploadVideoFile: (_, __) async {
          events.add('file');
        },
        createPost: post ??
            (request) async {
              requests.add(request);
              events.add('post');
              return QueuedPostResult(
                  id: 'post',
                  videoS3Key: request.videoS3Key,
                  platforms: request.platforms,
                  status: 'PUBLISHING');
            },
      )));

  Future<void> openSettings(WidgetTester tester,
      {String captionText = 'Direct clip'}) async {
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.ensureVisible(caption);
    await tester.enterText(caption, captionText);
    await goToUploaderStep(tester, 2);
    final platform = find.byKey(const ValueKey('uploader-platform-TIKTOK'));
    await tester.ensureVisible(platform);
    await tester.tap(platform);
    await tester.pumpAndSettle();
    final settings =
        find.byKey(const ValueKey('uploader-platform-settings-TIKTOK'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
  }

  Future<void> choosePrivacy(WidgetTester tester, String privacy) async {
    final dropdown = find.byKey(const ValueKey('uploader-tiktok-privacy'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(privacy).last);
    await tester.pumpAndSettle();
  }

  Future<void> chooseDirect(WidgetTester tester,
      {String privacy = 'เฉพาะฉัน'}) async {
    final direct = find.byKey(const ValueKey('uploader-tiktok-mode-direct'));
    await tester.ensureVisible(direct);
    await tester.tap(direct);
    await tester.pumpAndSettle();
    await choosePrivacy(tester, privacy);
    final music = find.byKey(const ValueKey('uploader-tiktok-music-consent'));
    await tester.ensureVisible(music);
    await tester.tap(music);
    await tester.pumpAndSettle();
  }

  Future<void> saveSettings(WidgetTester tester) async {
    final save = find.byKey(const ValueKey('uploader-platform-settings-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await goToUploaderStep(tester, 3);
    final confirm = find.byKey(const ValueKey('publish-review-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
  }

  testWidgets('Direct starts without privacy, interactions or consent selected',
      (tester) async {
    await tester.pumpWidget(app());
    await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('uploader-tiktok-mode-direct')));
    await tester.pumpAndSettle();
    final privacy = tester.widget<DropdownButtonFormField<TikTokPrivacyLevel>>(
        find.byKey(const ValueKey('uploader-tiktok-privacy')));
    expect(privacy.initialValue, isNull);
    for (final name in ['comment', 'duet', 'stitch']) {
      final control = tester.widget<CheckboxListTile>(
          find.byKey(ValueKey('uploader-tiktok-allow-$name')));
      expect(control.value, isFalse);
      expect(control.onChanged == null, name == 'duet');
    }
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('uploader-tiktok-music-consent')))
            .value,
        isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('uploader-platform-settings-save')))
            .onPressed,
        isNull);
    expect(find.text('คนขายทดสอบ'), findsWidgets);
    expect(optionLoads, 1);
  });

  testWidgets(
      'sends exact Direct settings with verified duration and fresh info',
      (tester) async {
    await tester.pumpWidget(app());
    await openSettings(tester);
    await chooseDirect(tester);
    await saveSettings(tester);
    await submit(tester);
    expect(events, ['prepare', 'upload', 'file', 'post']);
    expect(optionLoads, 4);
    expect(requests.single.platformSettings['TIKTOK'], {
      'publishMode': 'DIRECT_POST',
      'privacyLevel': 'SELF_ONLY',
      'disableComment': true,
      'disableDuet': true,
      'disableStitch': true,
      'brandContentToggle': false,
      'brandOrganicToggle': false,
      'isAigc': false,
      'videoDurationSeconds': 1.25,
      'musicUsageConfirmed': true,
      'brandedContentPolicyConfirmed': false,
      'creatorInfoRevision': _revision,
    });
    expect(store.savedRequests.last.uploadedMedia!.videoDurationSeconds, 1.25);
    expect(find.text('กำลังส่ง'), findsWidgets);
  });

  for (final caption in ['a' * 2201, '😀' * 1101]) {
    testWidgets(
        'Direct caption ${caption.length} UTF16 units stops before submission effects',
        (tester) async {
      await tester.pumpWidget(app());
      await openSettings(tester, captionText: caption);
      await chooseDirect(tester);
      await saveSettings(tester);
      expect(optionLoads, 1, reason: 'the settings sheet reads creator info');
      await submit(tester);
      expect(optionLoads, 1,
          reason: 'submission must not request creator info');
      expect(events, isEmpty);
      expect(requests, isEmpty);
      expect(store.savedRequests, isEmpty);
      expect(
          find.text('แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร'), findsWidgets);
    });
  }

  testWidgets('Direct accepts a caption of exactly 2200 UTF16 units',
      (tester) async {
    final caption = 'a' * 2200;
    await tester.pumpWidget(app());
    await openSettings(tester, captionText: caption);
    await chooseDirect(tester);
    await saveSettings(tester);
    await submit(tester);
    expect(requests.single.caption, caption);
    expect(events, ['prepare', 'upload', 'file', 'post']);
    expect(optionLoads, 4);
  });

  testWidgets('latest privacy restrictions stop before preparation and upload',
      (tester) async {
    await tester.pumpWidget(app(
        options: () async => optionLoads == 1
            ? _options()
            : _options(privacy: const [TikTokPrivacyLevel.selfOnly])));
    await openSettings(tester);
    await chooseDirect(tester, privacy: 'ทุกคน');
    await saveSettings(tester);
    await submit(tester);
    expect(optionLoads, 2);
    expect(events, isEmpty);
    expect(requests, isEmpty);
    expect(store.drafts, hasLength(1));
  });

  testWidgets('review uses the latest creator nickname and selected audience',
      (tester) async {
    await tester.pumpWidget(app());
    await openSettings(tester);
    await chooseDirect(tester);
    await saveSettings(tester);
    await goToUploaderStep(tester, 3);
    expect(find.text('คนขายทดสอบ'), findsWidgets);
    expect(find.text('ชื่อบัญชีจากรายการเดิม'), findsNothing);
    expect(find.textContaining('โพสต์ตรง · เฉพาะฉัน'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('old prepared receipt without duration is preserved before save',
      (tester) async {
    const receipt = PublishDraftUploadedMedia(
        mediaContentFingerprint: 'old-prepared-fingerprint',
        videoS3Key: 'uploads/old-prepared.mp4',
        videoPreparationPolicy: tikTokVideoPreparationPolicy);
    final draft = PublishDraft(
        version: publishDraftManifestVersion,
        id: 'old-prepared',
        ownerUserId: 'test-user',
        submissionRequestId: 'submit_${'c' * 64}',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
        videoPath: source.path,
        videoName: 'source.mp4',
        videoSizeBytes: 3,
        videoWidth: 720,
        videoHeight: 1280,
        caption: 'Old prepared clip',
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: const {'TIKTOK'},
        uploadedMedia: receipt);
    store.drafts[draft.id] = draft;
    await tester.pumpWidget(app(initialDraftId: draft.id));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    final settings =
        find.byKey(const ValueKey('uploader-platform-settings-TIKTOK'));
    await Scrollable.ensureVisible(tester.element(settings), alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();
    await chooseDirect(tester);
    await saveSettings(tester);
    await submit(tester);
    expect(events, isEmpty);
    expect(requests, isEmpty);
    expect(store.savedRequests, isEmpty);
    expect(store.drafts[draft.id], same(draft));
    expect(store.drafts[draft.id]!.uploadedMedia, same(receipt));
    expect(
        store.drafts[draft.id]!.submissionRequestId, draft.submissionRequestId);
    expect(find.textContaining('ยังไม่มีข้อมูลระยะเวลา'), findsWidgets);
  });

  testWidgets('a Direct render without duration proof cannot upload',
      (tester) async {
    await tester.pumpWidget(app(duration: null));
    await openSettings(tester);
    await chooseDirect(tester);
    await saveSettings(tester);
    await submit(tester);
    expect(events, ['prepare']);
    expect(requests, isEmpty);
  });

  testWidgets(
      'commercial choices and privacy exclusions require explicit consent',
      (tester) async {
    await tester.pumpWidget(app());
    await openSettings(tester);
    await chooseDirect(tester);
    final commercial = find.byKey(const ValueKey('uploader-tiktok-commercial'));
    await tester.ensureVisible(commercial);
    await tester.tap(commercial);
    await tester.pumpAndSettle();
    final thirdParty =
        find.byKey(const ValueKey('uploader-tiktok-third-party'));
    expect(tester.widget<CheckboxListTile>(thirdParty).onChanged, isNull);
    expect(find.textContaining('ตั้งเป็นเฉพาะฉันไม่ได้'), findsOneWidget);
    final ownBrand = find.byKey(const ValueKey('uploader-tiktok-own-brand'));
    await tester.ensureVisible(ownBrand);
    await tester.tap(ownBrand);
    await tester.pumpAndSettle();
    expect(find.textContaining('ป้ายเนื้อหาโปรโมต'), findsOneWidget);
    await choosePrivacy(tester, 'ทุกคน');
    await tester.ensureVisible(thirdParty);
    await tester.tap(thirdParty);
    await tester.pumpAndSettle();
    final privacy = tester.widget<DropdownButton<TikTokPrivacyLevel>>(
        find.byType(DropdownButton<TikTokPrivacyLevel>));
    expect(
        privacy.items!
            .singleWhere((item) => item.value == TikTokPrivacyLevel.selfOnly)
            .enabled,
        isFalse);
    expect(find.textContaining('Paid partnership'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('uploader-tiktok-brand-consent')))
            .value,
        isFalse);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('uploader-tiktok-music-consent')))
            .value,
        isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('uploader-platform-settings-save')))
            .onPressed,
        isNull);
  });

  testWidgets('caption edit clears fresh consent and requires settings again',
      (tester) async {
    await tester.pumpWidget(app());
    await openSettings(tester);
    await chooseDirect(tester);
    await saveSettings(tester);
    await goToUploaderStep(tester, 1);
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.ensureVisible(caption);
    await tester.enterText(caption, 'A changed publishing intent');
    await submit(tester);
    expect(events, isEmpty);
    expect(requests, isEmpty);
  });

  for (final gate in [3, 4]) {
    testWidgets('connection revision change at gate $gate cannot create a post',
        (tester) async {
      await tester.pumpWidget(app(
          options: () async => optionLoads == gate
              ? _options(
                  revision:
                      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
              : _options()));
      await openSettings(tester);
      await chooseDirect(tester);
      await saveSettings(tester);
      await submit(tester);
      expect(requests, isEmpty);
      expect(events, gate == 3 ? ['prepare'] : ['prepare', 'upload', 'file']);
      final draft = store.drafts.values.single;
      expect(draft.uploadedMedia != null, gate == 4);
      if (gate == 4) expect(draft.uploadedMedia!.videoDurationSeconds, 1.25);
    });
  }

  testWidgets('owner change during fresh options prevents all remote effects',
      (tester) async {
    await tester.pumpWidget(app(options: () async {
      if (optionLoads == 2) {
        PostDeeAuthSessionStore.instance
            .signIn(const AuthSession(userId: 'other-owner'));
      }
      return _options();
    }));
    await openSettings(tester);
    await chooseDirect(tester);
    await saveSettings(tester);
    await submit(tester);
    expect(events, isEmpty);
    expect(requests, isEmpty);
  });

  testWidgets(
      'retry reuses verified duration and the same request without upload',
      (tester) async {
    await tester.pumpWidget(app(post: (request) async {
      requests.add(request);
      throw const SocketException('response lost');
    }));
    await openSettings(tester);
    await chooseDirect(tester);
    await saveSettings(tester);
    await submit(tester);
    await tester.tap(find.byKey(const ValueKey('publish-flow-retry')));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.last.clientRequestId, requests.first.clientRequestId);
    expect(requests.last.platformSettings, requests.first.platformSettings);
    expect(events.where((event) => event == 'prepare'), hasLength(1));
    expect(events.where((event) => event == 'upload'), hasLength(1));
    expect(optionLoads, 6);
    final saved = store.drafts.values.single;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(initialDraftId: saved.id));
    await tester.pumpAndSettle();
    await submit(tester);
    expect(requests, hasLength(2), reason: 'restoring cannot restore consent');
    expect(store.drafts[saved.id]!.uploadedMedia!.videoDurationSeconds, 1.25);
    expect(
        store.drafts[saved.id]!.submissionRequestId, saved.submissionRequestId);
  });
}
