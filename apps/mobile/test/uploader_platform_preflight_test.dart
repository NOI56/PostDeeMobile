import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_preflight.dart';
import 'package:postdee_mobile/features/uploader/publish_media_probe.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

void main() {
  late Directory directory;
  late File video;
  late TestPublishDraftStore store;
  late AuthSession previous;
  late List<CreatePostRequest> posts;
  late List<String> effects;
  var checks = 0;
  const subscription = SubscriptionStatusResult(
      userId: 'test-user',
      plan: 'PRO',
      status: 'ACTIVE',
      phoneVerified: true,
      canSchedule: true,
      requiresPhoneVerification: false,
      canUseAiCaptions: true,
      canUseAnalytics: true);
  const validMedia = PublishMediaMetadata(
      durationSeconds: 10,
      width: 720,
      height: 1280,
      sizeBytes: 3,
      hasVideo: true,
      hasAudio: true,
      videoCodec: 'h264',
      audioCodec: 'aac',
      fps: 30,
      sampleRate: 48000,
      channels: 2,
      container: 'mp4');

  List<SocialPublishingConnectionReadiness> readiness(
          {SocialPublishingState state = SocialPublishingState.connected,
          String? revision}) =>
      [
        SocialPublishingConnectionReadiness(
            platform: 'YOUTUBE_SHORTS',
            connectionId: 'youtube-local',
            connectionRevision: revision,
            state: state)
      ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'test-user'));
    directory = Directory.systemTemp.createTempSync('platform-preflight-');
    video = File('${directory.path}/video.mp4')..writeAsBytesSync([1, 2, 3]);
    store = TestPublishDraftStore();
    posts = [];
    effects = [];
    checks = 0;
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.signIn(previous);
    directory.deleteSync(recursive: true);
  });

  Widget app(
          {PublishMediaMetadata media = validMedia,
          Future<List<SocialPublishingConnectionReadiness>> Function()?
              loadReadiness,
          String? connectionRevision,
          String? initialDraftId,
          PublishMediaProbe? probe,
          UploaderPostRecovery? recoverPostSubmission,
          UploaderPostCreator? createPost}) =>
      MaterialApp(
          home: Scaffold(
              body: UploaderScreen(
        draftStore: store,
        initialDraftId: initialDraftId,
        initialVideoPath: initialDraftId == null ? video.path : null,
        initialVideoName: 'video.mp4',
        initialVideoSizeBytes: 3,
        initialVideoWidth: 720,
        initialVideoHeight: 1280,
        loadSubscription: () async => subscription,
        recoverPostSubmission: recoverPostSubmission,
        loadSocialConnections: () async => [
          SocialConnectionResult(
              platform: 'YOUTUBE_SHORTS',
              connected: true,
              connectionRevision: connectionRevision,
              connectionId: 'youtube-local',
              displayName: 'ร้านทดสอบ')
        ],
        loadSocialPublishingReadiness: () async {
          checks++;
          return await (loadReadiness?.call() ?? Future.value(readiness()));
        },
        probePublishMedia: probe ??
            (_) async {
              effects.add('probe');
              return media;
            },
        checkPublishingReadiness: () async {},
        createUpload: (_) async {
          effects.add('upload');
          return const UploadResult(
              id: 'upload',
              videoS3Key: 'uploads/video.mp4',
              storageProvider: 'mock');
        },
        uploadVideoFile: (_, __) async {
          effects.add('file');
        },
        createPost: createPost ??
            (request) async {
              posts.add(request);
              effects.add('post');
              return QueuedPostResult(
                  id: 'post',
                  status: 'QUEUED',
                  videoS3Key: request.videoS3Key,
                  platforms: request.platforms);
            },
      )));

  Future<void> openSettings(WidgetTester tester,
      {String caption = 'คลิปสินค้า'}) async {
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await tester.enterText(
        find.byKey(const ValueKey('uploader-caption-field')), caption);
    await goToUploaderStep(tester, 2);
    final channel =
        find.byKey(const ValueKey('uploader-platform-YOUTUBE_SHORTS'));
    await tester.ensureVisible(channel);
    await tester.tap(channel);
    await tester.pumpAndSettle();
    final settings =
        find.byKey(const ValueKey('uploader-platform-settings-YOUTUBE_SHORTS'));
    await tester.ensureVisible(settings);
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();
  }

  Future<void> finishSettings(WidgetTester tester) async {
    for (final key in [
      'uploader-youtube-made-for-kids-no',
      'uploader-youtube-synthetic-no',
      'uploader-youtube-guidelines-certified'
    ]) {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    await tester
        .tap(find.byKey(const ValueKey('uploader-platform-settings-save')));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await goToUploaderStep(tester, 3);
    final button = find.byKey(const ValueKey('publish-review-confirm'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('YouTube suggests title without accepting content declarations',
      (tester) async {
    await tester.pumpWidget(app());
    await openSettings(tester,
        caption: '  ชื่อ <สินค้า> ใหม่\nรายละเอียดเพิ่มเติม');
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('uploader-youtube-title-preview')))
            .data,
        'ชื่อ สินค้า ใหม่');
    expect(
        tester
            .widget<CheckboxListTile>(find
                .byKey(const ValueKey('uploader-youtube-guidelines-certified')))
            .value,
        isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('uploader-platform-settings-save')))
            .onPressed,
        isNull);
  });

  testWidgets('a caption exceeding the YouTube byte limit never uploads',
      (tester) async {
    await tester.pumpWidget(app());
    await openSettings(tester, caption: 'ก' * 1700);
    await finishSettings(tester);
    await submit(tester);
    expect(posts, isEmpty);
    expect(effects, isEmpty);
    expect(find.textContaining('5,000'), findsWidgets);
  });

  testWidgets('a 181 second YouTube clip stops before remote upload',
      (tester) async {
    await tester.pumpWidget(app(
        media: const PublishMediaMetadata(
            durationSeconds: 181,
            width: 720,
            height: 1280,
            sizeBytes: 3,
            hasVideo: true,
            videoCodec: 'h264',
            fps: 30,
            container: 'mp4')));
    await openSettings(tester);
    await finishSettings(tester);
    await submit(tester);
    expect(posts, isEmpty);
    expect(effects, ['probe']);
    expect(find.textContaining('3 นาที'), findsWidgets);
    expect(store.drafts, isNotEmpty);
  });

  testWidgets(
      'new reconnect requirement stops before media and preserves draft',
      (tester) async {
    await tester.pumpWidget(app(
        loadReadiness: () async => readiness(
            state: checks >= 2
                ? SocialPublishingState.reconnectRequired
                : SocialPublishingState.connected)));
    await openSettings(tester);
    await finishSettings(tester);
    await submit(tester);
    expect(posts, isEmpty);
    expect(effects, isEmpty);
    expect(find.textContaining('เชื่อม'), findsWidgets);
    expect(store.drafts, isNotEmpty);
  });

  testWidgets('relink during upload blocks POST and keeps upload receipt',
      (tester) async {
    await tester.pumpWidget(app(
        loadReadiness: () async =>
            readiness(revision: (checks >= 3 ? 'b' : 'a') * 64)));
    await openSettings(tester);
    await finishSettings(tester);
    await submit(tester);
    expect(posts, isEmpty);
    expect(effects, ['probe', 'upload', 'file']);
    expect(store.drafts.values.single.uploadedMedia, isNotNull);
  });

  testWidgets(
      'initial list and readiness must describe the same account revision',
      (tester) async {
    await tester.pumpWidget(app(
        connectionRevision: 'a' * 64,
        loadReadiness: () async => readiness(revision: 'b' * 64)));
    await openSettings(tester);
    await finishSettings(tester);
    expect(
        find.textContaining('บัญชี YouTube Shorts เปลี่ยนแล้ว'), findsWidgets);
    await goToUploaderStep(tester, 3);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('publish-review-confirm')))
            .onPressed,
        isNull);
    expect(effects, isEmpty);
  });

  testWidgets('an API rollback downgrades previously verified permissions',
      (tester) async {
    await tester.pumpWidget(app(loadReadiness: () async {
      if (checks > 1) throw const ApiException('missing', statusCode: 404);
      return readiness(state: SocialPublishingState.ready);
    }));
    await openSettings(tester);
    await finishSettings(tester);
    await submit(tester);
    expect(posts, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('publish-flow-finish')));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    expect(find.textContaining('ยังยืนยันสิทธิ์เผยแพร่ไม่ได้'), findsWidgets);
    expect(find.textContaining('สิทธิ์เผยแพร่พร้อม · ตรวจแล้ว'), findsNothing);
  });

  Future<PublishDraft> legacyUploadedDraft() async {
    final first = await store.saveDraft(PublishDraftSaveRequest(
        id: 'legacy',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        videoFile: video,
        videoName: 'video.mp4',
        videoSizeBytes: 3,
        videoWidth: 720,
        videoHeight: 1280,
        caption: 'ก' * 1700,
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: {'YOUTUBE_SHORTS'},
        platformSettings: const PlatformPublishSettings()));
    return store.saveDraft(PublishDraftSaveRequest(
        id: first.id,
        createdAt: first.createdAt,
        updatedAt: first.updatedAt,
        videoFile: video,
        videoName: first.videoName,
        videoSizeBytes: 3,
        videoWidth: 720,
        videoHeight: 1280,
        caption: first.caption,
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: first.platformApiValues,
        platformSettings: first.platformSettings,
        uploadedMedia: PublishDraftUploadedMedia(
            mediaContentFingerprint: first.mediaContentFingerprint!,
            videoS3Key: 'uploads/old.mp4')));
  }

  testWidgets(
      'legacy accepted upload recovers its result without new guards or POST',
      (tester) async {
    final draft = await legacyUploadedDraft();
    CreatePostRequest? recovered;
    await tester.pumpWidget(app(
        initialDraftId: draft.id,
        loadReadiness: () async =>
            readiness(state: SocialPublishingState.reconnectRequired),
        recoverPostSubmission: (request) async {
          recovered = request;
          return QueuedPostResult(
              id: 'already-accepted',
              status: 'PUBLISHED',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              idempotentReplay: true);
        }));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-recover-submission')));
    await tester.pumpAndSettle();
    expect(recovered?.clientRequestId, draft.submissionRequestId);
    expect(recovered?.videoS3Key, 'uploads/old.mp4');
    expect(recovered?.caption, draft.caption);
    expect(recovered?.platformSettings, {
      'YOUTUBE_SHORTS': {'visibility': 'private'}
    });
    expect(find.textContaining('already-accepted'), findsWidgets);
    expect(find.textContaining('ส่งสำเร็จ'), findsWidgets);
    expect(posts, isEmpty);
    expect(effects, isEmpty);
    expect(store.drafts[draft.id]!.uploadedMedia!.videoMetadata, isNull);
  });

  testWidgets(
      'unaccepted legacy upload keeps receipt and cannot silently create a post',
      (tester) async {
    final draft = await legacyUploadedDraft();
    await tester.pumpWidget(app(
        initialDraftId: draft.id, recoverPostSubmission: (_) async => null));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-recover-submission')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ยังไม่พบรายการ'), findsWidgets);
    expect(posts, isEmpty);
    expect(effects, isEmpty);
    expect(
        store.drafts[draft.id]!.submissionRequestId, draft.submissionRequestId);
    expect(
        store.drafts[draft.id]!.uploadedMedia!.videoS3Key, 'uploads/old.mp4');
  });

  testWidgets('recovering a failed submission retains the original draft',
      (tester) async {
    final draft = await legacyUploadedDraft();
    await tester.pumpWidget(app(
        initialDraftId: draft.id,
        recoverPostSubmission: (request) async => QueuedPostResult(
            id: 'failed-original',
            status: 'FAILED',
            videoS3Key: request.videoS3Key,
            platforms: request.platforms,
            idempotentReplay: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-recover-submission')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ส่งไม่สำเร็จ'), findsWidgets);
    expect(
        store.drafts[draft.id]!.submissionRequestId, draft.submissionRequestId);
    expect(posts, isEmpty);
    expect(effects, isEmpty);
  });

  testWidgets('recovery discards a response after the signed-in owner changes',
      (tester) async {
    final draft = await legacyUploadedDraft();
    final response = Completer<QueuedPostResult?>();
    await tester.pumpWidget(app(
        initialDraftId: draft.id,
        recoverPostSubmission: (_) => response.future));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-recover-submission')));
    await tester.pump();
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'another-owner'));
    await tester.pump();
    response.complete(QueuedPostResult(
        id: 'private-old-owner',
        status: 'PUBLISHED',
        videoS3Key: 'uploads/old.mp4',
        platforms: ['YOUTUBE_SHORTS'],
        idempotentReplay: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('private-old-owner'), findsNothing);
    expect(store.drafts[draft.id], isNotNull);
    expect(posts, isEmpty);
    expect(effects, isEmpty);
  });

  testWidgets('retry retains verified media and the original submission ID',
      (tester) async {
    await tester.pumpWidget(app(createPost: (request) async {
      posts.add(request);
      throw const SocketException('lost response');
    }));
    await openSettings(tester);
    await finishSettings(tester);
    await submit(tester);
    await tester.tap(find.byKey(const ValueKey('publish-flow-retry')));
    await tester.pumpAndSettle();
    expect(posts, hasLength(2));
    expect(posts.last.clientRequestId, posts.first.clientRequestId);
    expect(effects.where((effect) => effect == 'probe'), hasLength(1));
    expect(effects.where((effect) => effect == 'upload'), hasLength(1));
    expect(store.drafts.values.single.uploadedMedia!.videoMetadata, isNotNull);
  });

  testWidgets('native metadata completed for an old owner never starts upload',
      (tester) async {
    final metadata = Completer<PublishMediaMetadata>();
    await tester.pumpWidget(app(probe: (_) {
      effects.add('probe');
      return metadata.future;
    }));
    await openSettings(tester);
    await finishSettings(tester);
    await goToUploaderStep(tester, 3);
    final button = find.byKey(const ValueKey('publish-review-confirm'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(effects, ['probe']);
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'another-owner'));
    metadata.complete(validMedia);
    await tester.pumpAndSettle();
    expect(posts, isEmpty);
    expect(effects, ['probe']);
    expect(store.drafts, isNotEmpty);
  });
}
