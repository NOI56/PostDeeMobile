import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/watermark_video_processor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _pro = SubscriptionStatusResult(
    userId: 'seller',
    plan: 'PRO',
    status: 'ACTIVE',
    phoneVerified: true,
    requiresPhoneVerification: false,
    canUseFreePostQuota: false,
    canSchedule: true,
    canUseAiCaptions: true,
    canUseAnalytics: true);

void main() {
  late Directory root;
  late File source;
  late File prepared;
  late TestPublishDraftStore store;
  late List<String> events;
  late AuthSession initialSession;
  var cleaned = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    initialSession = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'test-user'));
    root = Directory.systemTemp.createTempSync('uploader-tiktok-test-');
    source = File('${root.path}/source.mp4')..writeAsBytesSync([1, 2, 3]);
    prepared = File('${root.path}/prepared.mp4')
      ..writeAsBytesSync([3, 4, 5, 6]);
    store = TestPublishDraftStore();
    events = [];
    cleaned = false;
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    PostDeeAuthSessionStore.instance.signIn(initialSession);
  });

  Future<TikTokPreparedVideoResult> prepare(
      TikTokVideoPreparationRequest request) async {
    events.add('prepare:${request.inputFile.path}');
    return TikTokPreparedVideoResult(
        file: prepared,
        fileName: 'prepared.mp4',
        sizeBytes: 4,
        width: 720,
        height: 1280,
        durationSeconds: 10,
        cleanup: () async {
          cleaned = true;
        });
  }

  Widget app({
    UploaderTikTokVideoPreparer? preparer,
    String? initialDraftId,
    UploaderWatermarkVideoProcessor? watermark,
    UploaderPostCreator? createPost,
  }) =>
      MaterialApp(
          home: Scaffold(
              body: UploaderScreen(
        probePublishMedia: probeValidPublishMedia,
        loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
        draftStore: store,
        initialDraftId: initialDraftId,
        initialVideoPath: initialDraftId == null ? source.path : null,
        initialVideoName: initialDraftId == null ? 'source.mp4' : null,
        initialVideoSizeBytes: initialDraftId == null ? 3 : null,
        initialVideoWidth: 720,
        initialVideoHeight: 1280,
        loadSubscription: () async => _pro,
        loadSocialConnections: () async => const [
          SocialConnectionResult(
              platform: 'TIKTOK',
              connected: true,
              externalAccountId: 'seller-tiktok')
        ],
        checkPublishingReadiness: () async {
          events.add('readiness');
        },
        prepareTikTokVideo: preparer ?? prepare,
        watermarkVideo: watermark,
        createUpload: (request) async {
          events.add(
              'upload:${request.fileName}:${request.width}x${request.height}');
          return const UploadResult(
              id: 'upload',
              videoS3Key: 'uploads/prepared.mp4',
              storageProvider: 'mock');
        },
        uploadVideoFile: (_, file) async {
          events.add('file:${file.path}');
        },
        createPost: createPost ??
            (request) async {
              events.add('post');
              return QueuedPostResult(
                  id: 'post',
                  videoS3Key: request.videoS3Key,
                  platforms: request.platforms,
                  status: 'PUBLISHING');
            },
      )));

  Future<void> submit(WidgetTester tester, {bool restored = false}) async {
    await tester.pumpAndSettle();
    if (!restored) {
      await goToUploaderStep(tester, 1);
      final caption = find.byKey(const ValueKey('uploader-caption-field'));
      await tester.ensureVisible(caption);
      await tester.enterText(caption, 'TikTok preparation');
      await goToUploaderStep(tester, 2);
      final platform = find.byKey(const ValueKey('uploader-platform-TIKTOK'));
      await tester.ensureVisible(platform);
      await tester.tap(platform);
      await tester.pumpAndSettle();
    }
    await goToUploaderStep(tester, 3);
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'prepares TikTok before upload and persists validated receipt for retry',
      (tester) async {
    final requests = <CreatePostRequest>[];
    await tester.pumpWidget(app(createPost: (request) async {
      requests.add(request);
      throw const SocketException('lost response');
    }));
    await submit(tester);
    expect(
        events,
        containsAllInOrder([
          'prepare:${source.path}',
          'upload:prepared.mp4:720x1280',
          'file:${prepared.path}'
        ]));
    expect(cleaned, isTrue);
    final saved = store.drafts.values.single;
    expect(saved.videoPath, source.path);
    expect(saved.uploadedMedia!.videoPreparationPolicy,
        tikTokVideoPreparationPolicy);
    expect(
        requests.single.mediaContentFingerprint, saved.mediaContentFingerprint);
    await tester.tap(find.byKey(const ValueKey('publish-flow-retry')));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.last.clientRequestId, requests.first.clientRequestId);
    expect(events.where((event) => event.startsWith('prepare:')), hasLength(1));
    expect(events.where((event) => event.startsWith('upload:')), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(
        initialDraftId: saved.id,
        createPost: (request) async {
          requests.add(request);
          return QueuedPostResult(
              id: 'recovered',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'PUBLISHING');
        }));
    await submit(tester, restored: true);
    expect(requests, hasLength(3));
    expect(requests.last.clientRequestId, requests.first.clientRequestId);
    expect(events.where((event) => event.startsWith('prepare:')), hasLength(1));
    expect(events.where((event) => event.startsWith('upload:')), hasLength(1));
  });

  testWidgets(
      'Inbox preparation receives the provider 600 second duration ceiling',
      (tester) async {
    int? durationLimit;
    await tester.pumpWidget(app(preparer: (request) async {
      durationLimit = request.maxDurationSeconds;
      return prepare(request);
    }));
    await submit(tester);
    expect(durationLimit, 600);
    expect(events, contains('post'));
  });

  testWidgets(
      'preparation failure stops before uploading and keeps source draft',
      (tester) async {
    await tester.pumpWidget(app(preparer: (_) async {
      throw const TikTokVideoPreparationException(
          'เตรียมคลิปไม่สำเร็จ ยังไม่ได้อัปโหลด');
    }));
    await submit(tester);
    expect(events.where((event) => event.startsWith('upload:')), isEmpty);
    expect(events, isNot(contains('post')));
    expect(store.drafts.values.single.videoPath, source.path);
    expect(source.readAsBytesSync(), [1, 2, 3]);
    expect(find.textContaining('เตรียมคลิปไม่สำเร็จ'), findsWidgets);
  });

  for (final receiptCase in <({String? policy, double? duration})>[
    (policy: null, duration: null),
    (policy: 'tiktok-cfr30-h264-aac-v1', duration: null),
    (policy: tikTokVideoPreparationPolicy, duration: null),
    (policy: tikTokVideoPreparationPolicy, duration: 601),
  ]) {
    final legacyPolicy = receiptCase.policy;
    testWidgets(
        'legacy TikTok receipt ($legacyPolicy, ${receiptCase.duration}s) is blocked before any save can discard it',
        (tester) async {
      final receipt = PublishDraftUploadedMedia(
          mediaContentFingerprint: 'legacy-fingerprint',
          videoPreparationPolicy: legacyPolicy,
          videoDurationSeconds: receiptCase.duration,
          videoS3Key: 'uploads/legacy.mp4');
      final legacy = PublishDraft(
          version: publishDraftManifestVersion,
          id: 'legacy',
          ownerUserId: 'test-user',
          submissionRequestId:
              'submit_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          videoPath: source.path,
          videoName: 'source.mp4',
          videoSizeBytes: 3,
          videoWidth: 720,
          videoHeight: 1280,
          caption: 'legacy',
          aiGuidance: '',
          watermarkEnabled: false,
          platformApiValues: const {'TIKTOK'},
          uploadedMedia: receipt);
      store.drafts[legacy.id] = legacy;
      await tester.pumpWidget(app(initialDraftId: legacy.id));
      await submit(tester, restored: true);
      expect(events, isEmpty);
      expect(store.savedRequests, isEmpty);
      expect(identical(store.drafts[legacy.id], legacy), isTrue);
      expect(store.drafts[legacy.id]!.uploadedMedia, same(receipt));
      await tester.tap(find.text('กลับไปตรวจสอบ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('uploader-start-new-publish-attempt')),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data)
              .whereType<String>()
              .join(' | '));
      final startNew =
          find.byKey(const ValueKey('uploader-start-new-publish-attempt'));
      await tester.ensureVisible(startNew);
      await tester.tap(startNew);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(store.savedRequests, isEmpty);
      expect(store.drafts[legacy.id]!.submissionRequestId,
          legacy.submissionRequestId);
      await tester.tap(startNew);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('publish-new-attempt-confirm')));
      await tester.pumpAndSettle();
      expect(store.savedRequests, hasLength(1));
      expect(store.drafts, hasLength(2));
      final fresh =
          store.drafts.values.singleWhere((draft) => draft.id != legacy.id);
      expect(fresh.uploadedMedia, isNull);
      expect(fresh.submissionRequestId, isNot(legacy.submissionRequestId));
      expect(store.drafts[legacy.id]!.uploadedMedia, same(receipt));
      expect(events, isEmpty);
    });
  }

  testWidgets(
      'owner change during preparation prevents any upload and cleans output',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    final previous = sessionStore.session;
    addTearDown(() => sessionStore.signIn(previous));
    await tester.pumpWidget(app(preparer: (request) async {
      final result = await prepare(request);
      sessionStore.signIn(const AuthSession(userId: 'different-owner'));
      expect(request.isCancelled!(), isTrue);
      return result;
    }));
    await submit(tester);
    expect(events.where((event) => event.startsWith('upload:')), isEmpty);
    expect(events, isNot(contains('post')));
    expect(cleaned, isTrue);
  });

  testWidgets(
      'owner change during prepared cleanup cannot persist the old receipt',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    final previous = sessionStore.session;
    addTearDown(() => sessionStore.signIn(previous));
    await tester.pumpWidget(app(
        preparer: (_) async => TikTokPreparedVideoResult(
              file: prepared,
              fileName: 'prepared.mp4',
              sizeBytes: 4,
              width: 720,
              height: 1280,
              durationSeconds: 10,
              cleanup: () async {
                cleaned = true;
                sessionStore.signIn(
                    const AuthSession(userId: 'different-cleanup-owner'));
              },
            )));
    await submit(tester);
    expect(events.where((event) => event.startsWith('upload:')), hasLength(1));
    expect(cleaned, isTrue);
    expect(events, isNot(contains('post')));
    expect(store.savedRequests, hasLength(1));
    expect(store.savedRequests.single.uploadedMedia, isNull);
    expect(store.drafts.values.every((draft) => draft.uploadedMedia == null),
        isTrue);
  });
}
