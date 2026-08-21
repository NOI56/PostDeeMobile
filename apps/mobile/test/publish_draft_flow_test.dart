import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryPublishDraftStore implements PublishDraftStore {
  _MemoryPublishDraftStore([
    Iterable<PublishDraft> initial = const [],
    this.persistedVideoFile,
    this.saveError,
  ]) {
    for (final draft in initial) {
      drafts[draft.id] = draft;
    }
  }

  final Map<String, PublishDraft> drafts = {};
  final File? persistedVideoFile;
  final Object? saveError;
  final List<PublishDraftSaveRequest> savedRequests = [];
  final List<String> deletedIds = [];

  @override
  Future<void> deleteDraft(String draftId) async {
    deletedIds.add(draftId);
    drafts.remove(draftId);
  }

  @override
  Future<void> deleteAllDrafts() async {
    deletedIds.addAll(drafts.keys);
    drafts.clear();
  }

  @override
  Future<List<PublishDraft>> listDrafts() async {
    final values = drafts.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  @override
  Future<PublishDraft?> loadDraft(String draftId) async => drafts[draftId];

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    if (saveError case final error?) throw error;
    savedRequests.add(request);
    final storedVideo = persistedVideoFile ?? request.videoFile;
    final draft = PublishDraft(
      version: publishDraftManifestVersion,
      id: request.id,
      ownerUserId: 'firebase-user-a',
      submissionRequestId: _testSubmissionRequestId(request.id),
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      videoPath: storedVideo.path,
      videoName: request.videoName,
      videoSizeBytes: storedVideo.lengthSync(),
      videoWidth: request.videoWidth,
      videoHeight: request.videoHeight,
      caption: request.caption,
      aiGuidance: request.aiGuidance,
      watermarkEnabled: request.watermarkEnabled,
      platformApiValues: request.platformApiValues,
      platformSettings: request.platformSettings,
      scheduledAt: request.scheduledAt,
    );
    drafts[draft.id] = draft;
    return draft;
  }
}

String _testSubmissionRequestId(String seed) {
  final encoded = seed.codeUnits
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  final digest = (encoded + List.filled(64, '0').join()).substring(0, 64);
  return 'submit_$digest';
}

Future<List<SocialConnectionResult>> _youtubeConnected() async => const [
      SocialConnectionResult(
        platform: 'YOUTUBE_SHORTS',
        connected: true,
        externalAccountId: 'youtube-seller',
      ),
    ];

File _videoFixture() {
  final directory = Directory.systemTemp.createTempSync('publish-draft-flow-');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return File('${directory.path}${Platform.pathSeparator}clip.mp4')
    ..writeAsBytesSync(List<int>.filled(512, 1));
}

Widget _app({
  required File video,
  required PublishDraftStore draftStore,
  Future<List<SocialConnectionResult>> Function()? loadConnections,
  Future<SubscriptionStatusResult> Function()? loadSubscription,
  Future<void> Function()? checkReadiness,
  Future<UploadResult> Function(CreateUploadRequest request)? createUpload,
  Future<void> Function(UploadResult upload, File file)? uploadVideo,
  Future<QueuedPostResult> Function(CreatePostRequest request)? createPost,
  DateTime Function()? now,
}) {
  return MaterialApp(
    home: Scaffold(
      body: UploaderScreen(
        draftStore: draftStore,
        loadSocialConnections: loadConnections ?? _youtubeConnected,
        loadSubscription: loadSubscription,
        checkPublishingReadiness: checkReadiness,
        createUpload: createUpload,
        uploadVideoFile: uploadVideo,
        createPost: createPost,
        now: now ?? DateTime.now,
        initialVideoPath: video.path,
        initialVideoName: 'clip.mp4',
        initialVideoSizeBytes: video.lengthSync(),
        initialVideoWidth: 1080,
        initialVideoHeight: 1920,
      ),
    ),
  );
}

Future<void> _tapDraftButton(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('uploader-save-draft-button'));
  expect(button, findsOneWidget);
  expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

const _proSubscription = SubscriptionStatusResult(
  userId: 'seller-pro',
  plan: 'PRO',
  status: 'ACTIVE',
  phoneVerified: true,
  requiresPhoneVerification: false,
  canUseFreePostQuota: false,
  canSchedule: true,
  canUseAiCaptions: true,
  canUseAnalytics: true,
);

PublishDraft _readyDraft(File video, {String id = 'draft-ready'}) =>
    PublishDraft(
      version: publishDraftManifestVersion,
      id: id,
      ownerUserId: 'firebase-user-a',
      submissionRequestId: _testSubmissionRequestId(id),
      createdAt: DateTime.utc(2026, 8, 11, 1),
      updatedAt: DateTime.utc(2026, 8, 11, 2),
      videoPath: video.path,
      videoName: 'clip.mp4',
      videoSizeBytes: video.lengthSync(),
      videoWidth: 1080,
      videoHeight: 1920,
      caption: 'โพสต์จากฉบับร่าง',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: const {'YOUTUBE_SHORTS'},
    );

Future<void> _openDraft(
  WidgetTester tester,
  String id,
) async {
  await tester.tap(find.byKey(const ValueKey('uploader-open-drafts')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('publish-draft-$id')));
  await tester.pumpAndSettle();
}

Future<void> _completeYouTubeSettings(WidgetTester tester) async {
  final settings = find.byKey(
    const ValueKey('uploader-platform-settings-YOUTUBE_SHORTS'),
  );
  if (settings.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, 3000));
    await tester.pumpAndSettle();
    for (var attempt = 0;
        attempt < 12 && settings.evaluate().isEmpty;
        attempt += 1) {
      await tester.drag(scrollable, const Offset(0, -260));
      await tester.pumpAndSettle();
    }
  }
  expect(settings, findsOneWidget);
  await tester.ensureVisible(settings);
  await tester.pumpAndSettle();
  await tester.tap(settings);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('uploader-youtube-title')),
    'YouTube draft test',
  );
  for (final key in const [
    ValueKey('uploader-youtube-made-for-kids-no'),
    ValueKey('uploader-youtube-synthetic-no'),
    ValueKey('uploader-youtube-guidelines-certified'),
  ]) {
    final control = find.byKey(key);
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }
  final save = find.byKey(const ValueKey('uploader-platform-settings-save'));
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  await tester.tap(save);
  await tester.pumpAndSettle();
  expect(find.text('ส่วนตัว · พร้อม'), findsOneWidget);
}

Future<void> _submitDraft(WidgetTester tester) async {
  await _completeYouTubeSettings(tester);
  final postButton = find.byKey(const ValueKey('uploader-sticky-post-button'));
  await tester.ensureVisible(postButton);
  await tester.tap(postButton);
  await tester.pumpAndSettle();
  final confirm = find.byKey(const ValueKey('publish-review-confirm'));
  expect(confirm, findsOneWidget);
  expect(
    tester.widget<FilledButton>(confirm).onPressed,
    isNotNull,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .join(' | '),
  );
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

Future<void> _prepareFreshSubmission(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.drag(scrollable, const Offset(0, 3000));
  await tester.pumpAndSettle();
  final selectAll = find.byKey(
    const ValueKey('uploader-select-all-platforms'),
  );
  for (var attempt = 0;
      attempt < 10 && selectAll.evaluate().isEmpty;
      attempt += 1) {
    await tester.drag(scrollable, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(selectAll);
  await tester.pumpAndSettle();
  await tester.tap(selectAll);
  await tester.pumpAndSettle();

  await tester.drag(scrollable, const Offset(0, 3000));
  await tester.pumpAndSettle();
  final caption = find.byKey(const ValueKey('uploader-caption-field'));
  for (var attempt = 0;
      attempt < 12 && caption.evaluate().isEmpty;
      attempt += 1) {
    await tester.drag(scrollable, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
  expect(caption, findsOneWidget);
  await tester.ensureVisible(caption);
  await tester.pumpAndSettle();
  await tester.enterText(caption, 'โพสต์ที่บันทึกอัตโนมัติก่อนส่ง');
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'saves locally without connections, readiness, upload, queue, or quota',
    (tester) async {
      final video = _videoFixture();
      final store = _MemoryPublishDraftStore();
      var subscriptionCalls = 0;
      var readinessCalls = 0;
      var uploadCreateCalls = 0;
      var uploadCalls = 0;
      var postCalls = 0;

      await tester.pumpWidget(
        _app(
          video: video,
          draftStore: store,
          loadConnections: () async => throw StateError('offline'),
          loadSubscription: () async {
            subscriptionCalls += 1;
            throw StateError('must not run');
          },
          checkReadiness: () async {
            readinessCalls += 1;
            throw StateError('must not run');
          },
          createUpload: (request) async {
            uploadCreateCalls += 1;
            throw StateError('must not run');
          },
          uploadVideo: (upload, file) async {
            uploadCalls += 1;
            throw StateError('must not run');
          },
          createPost: (request) async {
            postCalls += 1;
            throw StateError('must not run');
          },
          now: () => DateTime.utc(2026, 8, 11, 3),
        ),
      );
      await tester.pumpAndSettle();

      await _tapDraftButton(tester);

      expect(
        store.savedRequests,
        hasLength(1),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data)
            .whereType<String>()
            .join(' | '),
      );
      expect(store.savedRequests.single.caption, isEmpty);
      expect(store.savedRequests.single.platformApiValues, isEmpty);
      expect(subscriptionCalls, 0);
      expect(readinessCalls, 0);
      expect(uploadCreateCalls, 0);
      expect(uploadCalls, 0);
      expect(postCalls, 0);
      expect(find.textContaining('บันทึกร่างในเครื่องแล้ว'), findsOneWidget);
      expect(find.textContaining('ยังไม่อัปโหลด'), findsWidgets);
    },
  );

  testWidgets('uses the app-owned video copy for later draft updates',
      (tester) async {
    final video = _videoFixture();
    final persistentDirectory =
        Directory.systemTemp.createTempSync('publish-draft-persistent-');
    addTearDown(() {
      if (persistentDirectory.existsSync()) {
        persistentDirectory.deleteSync(recursive: true);
      }
    });
    final persistentVideo =
        File('${persistentDirectory.path}${Platform.pathSeparator}video.mp4')
          ..writeAsBytesSync(List<int>.filled(512, 2));
    final store = _MemoryPublishDraftStore(const [], persistentVideo);

    await tester.pumpWidget(
      _app(
        video: video,
        draftStore: store,
        now: () => DateTime.utc(2026, 8, 11, 3),
      ),
    );
    await tester.pumpAndSettle();

    await _tapDraftButton(tester);
    await _tapDraftButton(tester);

    expect(store.savedRequests, hasLength(2));
    expect(store.savedRequests.last.videoFile.path, persistentVideo.path);
  });

  testWidgets('opens, restores, updates, and deletes the same local draft',
      (tester) async {
    final video = _videoFixture();
    final draft = PublishDraft(
      version: publishDraftManifestVersion,
      id: 'draft-existing',
      ownerUserId: 'firebase-user-a',
      submissionRequestId: _testSubmissionRequestId('draft-existing'),
      createdAt: DateTime.utc(2026, 8, 11, 1),
      updatedAt: DateTime.utc(2026, 8, 11, 2),
      videoPath: video.path,
      videoName: 'clip.mp4',
      videoSizeBytes: video.lengthSync(),
      videoWidth: 1080,
      videoHeight: 1920,
      caption: 'แคปชันที่เก็บไว้',
      aiGuidance: 'ขายแบบเป็นกันเอง',
      watermarkEnabled: false,
      platformApiValues: const {'YOUTUBE_SHORTS'},
      scheduledAt: DateTime.utc(2026, 8, 12, 11, 30),
    );
    final store = _MemoryPublishDraftStore([draft]);

    await tester.pumpWidget(
      _app(
        video: video,
        draftStore: store,
        now: () => DateTime.utc(2026, 8, 11, 3),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-open-drafts')));
    await tester.pumpAndSettle();
    expect(find.text('ฉบับร่างในเครื่อง'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('publish-draft-draft-existing')));
    await tester.pumpAndSettle();

    final captionFinder = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.scrollUntilVisible(
      captionFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final caption = tester.widget<TextField>(captionFinder);
    expect(caption.controller!.text, 'แคปชันที่เก็บไว้');
    await _tapDraftButton(tester);
    expect(store.savedRequests.single.id, 'draft-existing');
    expect(
      store.savedRequests.single.platformApiValues,
      {'YOUTUBE_SHORTS'},
    );
    expect(
      store.savedRequests.single.createdAt,
      DateTime.utc(2026, 8, 11, 1),
    );

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-open-drafts')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('publish-draft-delete-draft-existing')),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('publish-draft-delete-confirm')));
    await tester.pumpAndSettle();

    expect(store.deletedIds, ['draft-existing']);
    expect(find.text('ยังไม่มีฉบับร่างในเครื่อง'), findsOneWidget);

    Navigator.of(
      tester.element(find.text('ยังไม่มีฉบับร่างในเครื่อง')),
    ).pop();
    await tester.pumpAndSettle();
    await _tapDraftButton(tester);
    expect(store.savedRequests, hasLength(1));
    expect(find.textContaining('เลือกวิดีโอจากเครื่องก่อน'), findsOneWidget);
  });

  testWidgets('restored past schedule is blocked before any upload starts',
      (tester) async {
    final video = _videoFixture();
    final draft = PublishDraft(
      version: publishDraftManifestVersion,
      id: 'draft-past',
      ownerUserId: 'firebase-user-a',
      submissionRequestId: _testSubmissionRequestId('draft-past'),
      createdAt: DateTime.utc(2026, 8, 10),
      updatedAt: DateTime.utc(2026, 8, 10, 1),
      videoPath: video.path,
      videoName: 'clip.mp4',
      videoSizeBytes: video.lengthSync(),
      videoWidth: 1080,
      videoHeight: 1920,
      caption: 'พร้อมโพสต์แต่เวลาหมดอายุ',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: const {'YOUTUBE_SHORTS'},
      scheduledAt: DateTime.utc(2026, 8, 10, 2),
    );
    final store = _MemoryPublishDraftStore([draft]);
    var readinessCalls = 0;
    var uploadCalls = 0;

    await tester.pumpWidget(
      _app(
        video: video,
        draftStore: store,
        now: () => DateTime.utc(2026, 8, 11, 3),
        checkReadiness: () async => readinessCalls += 1,
        createUpload: (request) async {
          uploadCalls += 1;
          throw StateError('must not run');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-open-drafts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-draft-draft-past')));
    await tester.pumpAndSettle();
    expect(find.textContaining('เวลาเดิมผ่านไปแล้ว'), findsOneWidget);

    final postButton =
        find.byKey(const ValueKey('uploader-sticky-post-button'));
    await tester.ensureVisible(postButton);
    await tester.pumpAndSettle();
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(readinessCalls, 0);
    expect(uploadCalls, 0);
    expect(find.textContaining('เลือกเวลาใหม่'), findsWidgets);
  });

  testWidgets('keeps the active draft when publishing fails', (tester) async {
    final video = _videoFixture();
    final store = _MemoryPublishDraftStore([_readyDraft(video)]);

    await tester.pumpWidget(
      _app(
        video: video,
        draftStore: store,
        loadSubscription: () async => _proSubscription,
        checkReadiness: () async {},
        createUpload: (_) async => const UploadResult(
          id: 'upload-1',
          videoS3Key: 'uploads/clip.mp4',
          storageProvider: 'mock',
        ),
        uploadVideo: (_, __) async {},
        createPost: (_) async => throw const ApiException(
          'Publishing unavailable',
          code: 'SOCIAL_PUBLISHING_UNAVAILABLE',
          statusCode: HttpStatus.serviceUnavailable,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDraft(tester, 'draft-ready');
    await _submitDraft(tester);

    expect(store.deletedIds, isEmpty);
    expect(await store.loadDraft('draft-ready'), isNotNull);
  });

  testWidgets(
    'retries a transient network failure with the same submission request id',
    (tester) async {
      final video = _videoFixture();
      final store = _MemoryPublishDraftStore([_readyDraft(video)]);
      final requests = <CreatePostRequest>[];

      await tester.pumpWidget(
        _app(
          video: video,
          draftStore: store,
          loadSubscription: () async => _proSubscription,
          checkReadiness: () async {},
          createUpload: (_) async => const UploadResult(
            id: 'upload-retryable',
            videoS3Key: 'uploads/retryable.mp4',
            storageProvider: 'mock',
          ),
          uploadVideo: (_, __) async {},
          createPost: (request) async {
            requests.add(request);
            if (requests.length == 1) {
              throw const SocketException('response lost after commit');
            }
            return QueuedPostResult(
              id: 'post-after-retry',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'QUEUED',
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await _openDraft(tester, 'draft-ready');
      await _submitDraft(tester);

      expect(
        find.byKey(const ValueKey('publish-flow-error')),
        findsOneWidget,
      );
      expect(find.text('เชื่อมต่อ PostDee API ไม่ได้'), findsOneWidget);
      expect(find.byKey(const ValueKey('publish-flow-retry')), findsOneWidget);
      expect(requests, hasLength(1));
      expect(await store.loadDraft('draft-ready'), isNotNull);

      await tester.tap(find.byKey(const ValueKey('publish-flow-retry')));
      await tester.pumpAndSettle();

      expect(requests, hasLength(2));
      expect(requests[1].clientRequestId, requests[0].clientRequestId);
      expect(find.byKey(const ValueKey('publish-flow-done')), findsOneWidget);
      expect(store.drafts, isEmpty);
    },
  );

  testWidgets(
    'requires an explicit confirmation before starting a new publish attempt',
    (tester) async {
      final video = _videoFixture();
      final originalDraft = _readyDraft(video);
      final store = _MemoryPublishDraftStore([originalDraft]);
      var createUploadCalls = 0;
      var createPostCalls = 0;

      await tester.pumpWidget(
        _app(
          video: video,
          draftStore: store,
          loadSubscription: () async => _proSubscription,
          checkReadiness: () async {},
          createUpload: (_) async {
            createUploadCalls += 1;
            return const UploadResult(
              id: 'upload-ambiguous',
              videoS3Key: 'uploads/ambiguous.mp4',
              storageProvider: 'mock',
            );
          },
          uploadVideo: (_, __) async {},
          createPost: (_) async {
            createPostCalls += 1;
            throw const ApiException(
              'The previous publish attempt failed',
              code: 'IDEMPOTENT_POST_FAILED',
              statusCode: HttpStatus.conflict,
            );
          },
          now: () => DateTime.utc(2026, 8, 11, 3),
        ),
      );
      await tester.pumpAndSettle();
      await _openDraft(tester, originalDraft.id);
      await _submitDraft(tester);

      expect(
        find.byKey(const ValueKey('postdee-system-status-sheet')),
        findsOneWidget,
      );
      await tester.tap(find.text('กลับไปตรวจสอบ'));
      await tester.pumpAndSettle();

      final startNewAttempt = find.byKey(
        const ValueKey('uploader-start-new-publish-attempt'),
      );
      final postAction = find.descendant(
        of: find.byKey(const ValueKey('uploader-sticky-post-button')),
        matching: find.byType(TextButton),
      );
      expect(startNewAttempt, findsOneWidget);
      expect(tester.widget<TextButton>(postAction).onPressed, isNull);
      expect(createUploadCalls, 1);
      expect(createPostCalls, 1);
      await tester.tap(postAction, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(createUploadCalls, 1);
      expect(createPostCalls, 1);
      expect(await store.loadDraft(originalDraft.id), isNotNull);
      expect(store.drafts, hasLength(1));

      await tester.ensureVisible(startNewAttempt);
      await tester.tap(startNewAttempt);
      await tester.pumpAndSettle();

      expect(find.textContaining('อาจโพสต์ซ้ำได้'), findsOneWidget);
      expect(store.drafts, hasLength(1));

      await tester.tap(
        find.byKey(const ValueKey('publish-new-attempt-confirm')),
      );
      await tester.pumpAndSettle();

      expect(store.drafts, hasLength(2));
      expect(await store.loadDraft(originalDraft.id), isNotNull);
      final newDraft = store.drafts.values.singleWhere(
        (draft) => draft.id != originalDraft.id,
      );
      expect(newDraft.submissionRequestId,
          isNot(originalDraft.submissionRequestId));
      expect(startNewAttempt, findsNothing);
      expect(tester.widget<TextButton>(postAction).onPressed, isNotNull);
      expect(find.textContaining('สร้างร่างสำหรับรายการโพสต์ใหม่แล้ว'),
          findsOneWidget);
    },
  );

  testWidgets('deletes the active draft only after a post enters the queue',
      (tester) async {
    final video = _videoFixture();
    final store = _MemoryPublishDraftStore([_readyDraft(video)]);

    await tester.pumpWidget(
      _app(
        video: video,
        draftStore: store,
        loadSubscription: () async => _proSubscription,
        checkReadiness: () async {},
        createUpload: (_) async => const UploadResult(
          id: 'upload-1',
          videoS3Key: 'uploads/clip.mp4',
          storageProvider: 'mock',
        ),
        uploadVideo: (_, __) async {},
        createPost: (request) async => QueuedPostResult(
          id: 'post-1',
          videoS3Key: request.videoS3Key,
          platforms: request.platforms,
          status: 'QUEUED',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDraft(tester, 'draft-ready');
    await _submitDraft(tester);

    expect(store.deletedIds, ['draft-ready']);
    expect(await store.loadDraft('draft-ready'), isNull);
    expect(find.byKey(const ValueKey('publish-flow-done')), findsOneWidget);
  });

  testWidgets('reports real publishing milestones to the progress screen',
      (tester) async {
    final video = _videoFixture();
    final store = _MemoryPublishDraftStore([_readyDraft(video)]);
    final readiness = Completer<void>();
    final subscription = Completer<SubscriptionStatusResult>();
    final uploadCreated = Completer<UploadResult>();
    final videoUploaded = Completer<void>();
    final postCreated = Completer<QueuedPostResult>();

    await tester.pumpWidget(
      _app(
        video: video,
        draftStore: store,
        loadSubscription: () => subscription.future,
        checkReadiness: () => readiness.future,
        createUpload: (_) => uploadCreated.future,
        uploadVideo: (_, __) => videoUploaded.future,
        createPost: (_) => postCreated.future,
      ),
    );
    await tester.pumpAndSettle();
    await _openDraft(tester, 'draft-ready');
    await _completeYouTubeSettings(tester);

    final postButton = find.byKey(
      const ValueKey('uploader-sticky-post-button'),
    );
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('กำลังตรวจสอบระบบโพสต์'), findsOneWidget);
    expect(find.text('18% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);

    readiness.complete();
    await tester.pumpAndSettle();
    expect(find.text('กำลังตรวจสอบแพ็กเกจ'), findsOneWidget);
    expect(find.text('28% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);

    subscription.complete(_proSubscription);
    await tester.pumpAndSettle();
    expect(find.text('กำลังอัปโหลดวิดีโอ'), findsOneWidget);
    expect(find.text('50% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);

    uploadCreated.complete(
      const UploadResult(
        id: 'upload-progress',
        videoS3Key: 'uploads/progress.mp4',
        storageProvider: 'mock',
      ),
    );
    await tester.pumpAndSettle();
    videoUploaded.complete();
    await tester.pumpAndSettle();
    expect(find.text('กำลังสร้างคิวโพสต์'), findsOneWidget);
    expect(find.text('90% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);

    postCreated.complete(
      const QueuedPostResult(
        id: 'post-progress',
        videoS3Key: 'uploads/progress.mp4',
        platforms: ['YOUTUBE_SHORTS'],
        status: 'QUEUED',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('publish-flow-done')), findsOneWidget);
  });

  testWidgets('keeps the draft when the server returns an unknown post status',
      (tester) async {
    final video = _videoFixture();
    final store = _MemoryPublishDraftStore([_readyDraft(video)]);

    await tester.pumpWidget(
      _app(
        video: video,
        draftStore: store,
        loadSubscription: () async => _proSubscription,
        checkReadiness: () async {},
        createUpload: (_) async => const UploadResult(
          id: 'upload-unknown',
          videoS3Key: 'uploads/unknown.mp4',
          storageProvider: 'mock',
        ),
        uploadVideo: (_, __) async {},
        createPost: (request) async => QueuedPostResult(
          id: 'post-unknown',
          videoS3Key: request.videoS3Key,
          platforms: request.platforms,
          status: 'UNKNOWN_REMOTE_STATE',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDraft(tester, 'draft-ready');
    await _submitDraft(tester);

    expect(store.deletedIds, isEmpty);
    expect(await store.loadDraft('draft-ready'), isNotNull);
    expect(find.byKey(const ValueKey('publish-flow-done')), findsNothing);
  });

  testWidgets(
      'stops before readiness and upload when automatic draft save fails',
      (tester) async {
    final video = _videoFixture();
    final store = _MemoryPublishDraftStore(
      const [],
      null,
      const FileSystemException('disk unavailable'),
    );
    var readinessCalls = 0;
    var createUploadCalls = 0;
    var createPostCalls = 0;

    await tester.pumpWidget(
      _app(
        video: video,
        draftStore: store,
        loadSubscription: () async => _proSubscription,
        checkReadiness: () async => readinessCalls += 1,
        createUpload: (_) async {
          createUploadCalls += 1;
          throw StateError('must not run');
        },
        createPost: (_) async {
          createPostCalls += 1;
          throw StateError('must not run');
        },
      ),
    );
    await tester.pumpAndSettle();
    await _prepareFreshSubmission(tester);
    await _submitDraft(tester);

    expect(readinessCalls, 0);
    expect(createUploadCalls, 0);
    expect(createPostCalls, 0);
  });

  testWidgets(
    'reuses the persisted request id after a lost response and app restart',
    (tester) async {
      final video = _videoFixture();
      final store = _MemoryPublishDraftStore();
      final requests = <CreatePostRequest>[];
      var uploadNumber = 0;

      Future<UploadResult> createUpload(CreateUploadRequest request) async {
        uploadNumber += 1;
        return UploadResult(
          id: 'upload-$uploadNumber',
          videoS3Key: 'uploads/retry-$uploadNumber.mp4',
          storageProvider: 'mock',
        );
      }

      Future<QueuedPostResult> firstCreatePost(
        CreatePostRequest request,
      ) async {
        requests.add(request);
        throw const SocketException('response lost after commit');
      }

      await tester.pumpWidget(
        _app(
          video: video,
          draftStore: store,
          loadSubscription: () async => _proSubscription,
          checkReadiness: () async {},
          createUpload: createUpload,
          uploadVideo: (_, __) async {},
          createPost: firstCreatePost,
        ),
      );
      await tester.pumpAndSettle();
      await _prepareFreshSubmission(tester);
      await _submitDraft(tester);

      expect(requests, hasLength(1));
      expect(store.drafts, hasLength(1));
      final persistedDraft = store.drafts.values.single;
      expect(
          requests.single.clientRequestId, persistedDraft.submissionRequestId);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _app(
          video: video,
          draftStore: store,
          loadSubscription: () async => _proSubscription,
          checkReadiness: () async {},
          createUpload: createUpload,
          uploadVideo: (_, __) async {},
          createPost: (request) async {
            requests.add(request);
            return QueuedPostResult(
              id: 'post-1',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'QUEUED',
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await _openDraft(tester, persistedDraft.id);
      await _submitDraft(tester);

      expect(requests, hasLength(2));
      expect(requests[1].clientRequestId, requests[0].clientRequestId);
      expect(requests[1].videoS3Key, isNot(requests[0].videoS3Key));
      expect(store.drafts, isEmpty);
    },
  );
}
