import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_edit.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'uploader_video_english_test.dart';

final _now = DateTime(2026, 11, 5, 10);
const _groupId = 'reviewed-group';
const _partIds = ['reviewed-part-0', 'reviewed-part-1'];
const _platform = 'INSTAGRAM_REELS';

class _TrackingStore extends VideoEnglishDrafts {
  final events = <String>[];
  final deletionCheckpoints = <String, String?>{};

  @override
  Future<ClipGroupDraft> saveClipGroup(ClipGroupDraft group,
      {required int? expectedRevision}) async {
    final before = groups[group.id];
    final saved =
        await super.saveClipGroup(group, expectedRevision: expectedRevision);
    for (final item in saved.items) {
      if (item.isAccepted &&
          before?.items
                  .where((old) => old.draftId == item.draftId)
                  .firstOrNull
                  ?.isAccepted !=
              true) {
        events.add('checkpoint:${item.draftId}');
      }
    }
    return saved;
  }

  @override
  Future<void> deleteDraft(String id) async {
    deletionCheckpoints[id] = groups[_groupId]
        ?.items
        .where((item) => item.draftId == id)
        .firstOrNull
        ?.acceptedPostId;
    events.add('delete:$id');
    return super.deleteDraft(id);
  }
}

class _Fixture extends VideoEnglishFixture {
  _Fixture() {
    initialDraftId = 'reviewed-source';
    quota = _quota(10);
  }

  final _trackedStore = _TrackingStore();
  @override
  _TrackingStore get store => _trackedStore;
  final uploadRequests = <CreateUploadRequest>[];
  final uploadedKeys = <String>[];
  final postRequests = <CreatePostRequest>[];
  final recoveryRequests = <CreatePostRequest>[];
  final aiRequests = <GenerateRealClipCaptionRequest>[];
  final uploadedPaths = <String>[];
  Completer<RealClipCaptionResult>? aiGate;
  final acceptedOnServer = <String, QueuedPostResult>{};
  bool loseSecondResponse = false;
  bool recoverFound = true;
  bool corruptCreateResponse = false;
  bool corruptRecoveryResponse = false;
  DateTime currentTime = _now;

  static SubscriptionStatusResult _quota(int remaining) =>
      SubscriptionStatusResult(
        userId: videoEnglishOwner,
        plan: 'PRO',
        status: 'ACTIVE',
        monthlyPostLimit: 250,
        usedPostsThisMonth: 250 - remaining,
        remainingPostsThisMonth: remaining,
        availablePostUnits: remaining,
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: false,
        phoneVerified: true,
        requiresPhoneVerification: false,
      );

  Future<void> seed({bool scheduled = true}) async {
    for (final id in ['reviewed-source', ..._partIds]) {
      final video = makeVideo('$id.mp4', duration: 10);
      final partIndex = _partIds.indexOf(id);
      await store.saveDraft(PublishDraftSaveRequest(
        id: id,
        createdAt: _now,
        updatedAt: _now,
        videoFile: File(video.path),
        videoName: video.name,
        videoSizeBytes: video.sizeBytes,
        videoWidth: video.width,
        videoHeight: video.height,
        caption: 'Caption for the reviewed set',
        captionNeedsReview: true,
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: const {_platform},
        scheduledAt: scheduled && partIndex >= 0
            ? _now.add(Duration(days: 1 + partIndex, hours: partIndex)).toUtc()
            : null,
        clipGroupId: _groupId,
        isClipGroupSource: partIndex < 0,
      ));
    }
    await store.saveClipGroup(
        ClipGroupDraft(
          id: _groupId,
          ownerUserId: videoEnglishOwner,
          sourceDraftId: 'reviewed-source',
          title: 'Reviewed set',
          sharedCaption: 'Caption for the reviewed set',
          deliveryMode: scheduled
              ? ClipGroupDeliveryMode.scheduled
              : ClipGroupDeliveryMode.immediate,
          items: [
            for (var i = 0; i < _partIds.length; i++)
              ClipGroupItem(
                draftId: _partIds[i],
                index: i,
                sourceStartSeconds: i * 10.0,
                sourceEndSeconds: (i + 1) * 10.0,
                platformApiValues: const {_platform},
                scheduledAt: scheduled
                    ? _now.add(Duration(days: 1 + i, hours: i)).toUtc()
                    : null,
              ),
          ],
          createdAt: _now,
          updatedAt: _now,
        ),
        expectedRevision: null);
    store.events.clear();
  }

  Future<String> seedUnknownReceipt(String id) async {
    final draft = store.drafts[id]!;
    final key = 'uploads/unknown-$id.mp4';
    await store.saveDraft(PublishDraftSaveRequest(
      id: draft.id,
      createdAt: draft.createdAt,
      updatedAt: draft.updatedAt,
      videoFile: File(draft.videoPath),
      videoName: draft.videoName,
      videoSizeBytes: draft.videoSizeBytes,
      videoWidth: draft.videoWidth,
      videoHeight: draft.videoHeight,
      caption: draft.caption,
      aiGuidance: draft.aiGuidance,
      watermarkEnabled: draft.watermarkEnabled,
      platformApiValues: draft.platformApiValues,
      scheduledAt: draft.scheduledAt,
      clipGroupId: draft.clipGroupId,
      uploadedMedia: PublishDraftUploadedMedia(
          mediaContentFingerprint: draft.mediaContentFingerprint!,
          videoS3Key: key),
    ));
    return key;
  }

  @override
  UploaderScreen screen() => UploaderScreen(
        fullScreen: true,
        initialDraftId: initialDraftId,
        draftStore: store,
        enableRevenueCatBilling: false,
        now: () => currentTime,
        readVideoMetadata: (_) async => const VideoDimensions(
            width: 1080, height: 1920, durationSeconds: 10),
        probePublishMedia: probeValidPublishMedia,
        loadTemplates: () async => const [],
        loadSubscription: () async => quota,
        loadPostQuota: () async => quota,
        loadCaptionQuota: () async => const CaptionQuotaResult(
            plan: 'PRO',
            quota: RealClipCaptionQuota(
                limit: 120, usedThisMonth: 0, remainingThisMonth: 120)),
        generateRealClipCaption: (request) async {
          aiRequests.add(request);
          return aiGate?.future ??
              RealClipCaptionResult(
                caption: 'Shared caption from the entire original',
                captionOptions: const [
                  'Shared caption from the entire original'
                ],
                hooks: const [],
                hashtags: const [],
                seoKeywords: const [],
                searchTitle: 'Entire original',
                source: RealClipCaptionSource(
                    videoS3Key: request.videoS3Key!,
                    mode: 'AUDIO_ONLY',
                    selectedFrameCount: 0),
                quota: const RealClipCaptionQuota(
                    limit: 120,
                    usedThisMonth: 1,
                    remainingThisMonth: 119,
                    charged: true),
              );
        },
        loadSocialConnections: () async => const [
          SocialConnectionResult(
              platform: _platform,
              connected: true,
              displayName: 'Owned Instagram',
              externalAccountId: 'owned-instagram',
              connectionId: 'owned-instagram-connection',
              connectionRevision: 'instagram-revision'),
        ],
        loadSocialPublishingReadiness: () async => const [
          SocialPublishingConnectionReadiness(
              platform: _platform,
              state: SocialPublishingState.ready,
              connectionId: 'owned-instagram-connection',
              connectionRevision: 'instagram-revision'),
        ],
        checkPublishingReadiness: () async {},
        createUpload: (request) async {
          uploadRequests.add(request);
          store.events.add('upload:${request.fileName}');
          return UploadResult(
              id: 'upload-${uploadRequests.length}',
              videoS3Key: 'uploads/reviewed-${uploadRequests.length}.mp4',
              storageProvider: 'mock');
        },
        uploadVideoFile: (upload, file) async {
          expect(file.existsSync(), isTrue);
          uploadedPaths.add(file.path);
          uploadedKeys.add(upload.videoS3Key);
        },
        createPost: (request) async {
          postRequests.add(request);
          final draft = store.drafts.values.singleWhere(
              (draft) => draft.submissionRequestId == request.clientRequestId);
          expect(draft.uploadedMedia?.videoS3Key, request.videoS3Key);
          store.events.add('post:${draft.id}');
          final post = QueuedPostResult(
              id: 'accepted-${draft.id}',
              videoS3Key: corruptCreateResponse
                  ? 'uploads/unrelated-video.mp4'
                  : request.videoS3Key,
              platforms: request.platforms,
              status: 'QUEUED');
          acceptedOnServer[request.clientRequestId] = post;
          if (loseSecondResponse && draft.id == _partIds[1]) {
            throw const ApiException('Response lost',
                statusCode: 503, code: 'POST_RESPONSE_LOST');
          }
          return post;
        },
        recoverPostSubmission: (request) async {
          recoveryRequests.add(request);
          if (corruptRecoveryResponse) {
            return QueuedPostResult(
                id: 'corrupt-recovered-post',
                videoS3Key: 'uploads/unrelated-video.mp4',
                platforms: request.platforms,
                status: 'QUEUED');
          }
          return recoverFound
              ? acceptedOnServer[request.clientRequestId]
              : null;
        },
      );

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await super.mount(tester, settle: settle);
    await _settle(tester);
    expect(_key('uploader-step-caption'), findsOneWidget);
    expect(_key('clip-group-caption-scopes'), findsOneWidget);
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _settle(WidgetTester tester) async {
  // Media fingerprinting uses real temporary files; let those OS futures run.
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  if (key == 'uploader-ai-open-panel' ||
      key == 'uploader-ai-generate-button') {
    final content = find.byKey(const ValueKey('uploader-ai-card-content'),
        skipOffstage: false);
    if (tester.widget<Offstage>(content).offstage) {
      await tester.ensureVisible(_key('uploader-ai-card-toggle'));
      await tester.tap(_key('uploader-ai-card-toggle'));
      await _settle(tester);
    }
  }
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  final widget = tester.widget(_key(key));
  if (widget is FilledButton) {
    expect(widget.onPressed, isNotNull,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '));
  }
  await tester.tap(_key(key));
  await _settle(tester);
}

Future<void> _reviewToFinalConfirmation(WidgetTester tester) async {
  await _tap(tester, 'uploader-wizard-next');
  expect(_key('uploader-step-platforms'), findsOneWidget);
  await _tap(tester, 'uploader-wizard-next');
  expect(_key('clip-group-review'), findsOneWidget);
  await _tap(tester, 'clip-group-next');
  expect(_key('clip-group-confirm'), findsOneWidget);
}

void _expectSharedAiLocked(WidgetTester tester) {
  final lock = find.ancestor(
      of: _key('uploader-ai-caption-panel'),
      matching: find.byType(AbsorbPointer)).first;
  expect(lock, findsOneWidget);
  expect(tester.widget<AbsorbPointer>(lock).absorbing, isTrue);
  final content = find.byKey(const ValueKey('uploader-ai-card-content'),
      skipOffstage: false);
  expect(tester.widget<Offstage>(content).offstage, isTrue);
  expect(_key('uploader-ai-generate-button'), findsNothing);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(AuthSession.authenticated(
        userId: videoEnglishOwner, idToken: 'group-submission-test'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
  });

  testWidgets(
      'shared AI reads the original and retains custom captions and schedules '
      'without modifying the backup or sending posts', (tester) async {
    final fixture = _Fixture()
      ..quota = const SubscriptionStatusResult(
          userId: videoEnglishOwner,
          plan: 'STARTER',
          status: 'ACTIVE',
          monthlyPostLimit: 250,
          usedPostsThisMonth: 240,
          remainingPostsThisMonth: 10,
          availablePostUnits: 10,
          canSchedule: true,
          canUseAiCaptions: true,
          canUseAnalytics: false);
    addTearDown(fixture.dispose);
    await fixture.seed();
    final group = fixture.store.groups[_groupId]!;
    fixture.store.groups[_groupId] = group.copyWith(items: [
      group.items.first,
      group.items.last.copyWith(usesSharedCaption: false),
    ]);
    final custom = await fixture.store.saveDraft(clipGroupMemberSaveRequest(
        fixture.store.drafts[_partIds.last]!,
        caption: 'My custom ending',
        now: _now));
    final original = fixture.store.drafts['reviewed-source']!;
    final first = fixture.store.drafts[_partIds.first]!;
    await fixture.mount(tester);
    expect(_key('uploader-ai-caption-panel'), findsOneWidget);
    expect(_key('uploader-caption-field'), findsOneWidget);
    expect(fixture.aiRequests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    await _tap(tester, 'uploader-ai-open-panel');
    await tester.ensureVisible(_key('uploader-ai-guidance-input'));
    await tester.enterText(
        _key('uploader-ai-guidance-input'), 'Shared guidance for this set');
    await tester.pumpAndSettle();
    await _tap(tester, 'uploader-ai-generate-button');
    expect(fixture.aiRequests, hasLength(1));
    expect(fixture.aiRequests.single.guidance, 'Shared guidance for this set');
    expect(fixture.uploadedPaths, [original.videoPath]);
    expect(fixture.uploadRequests.single.fileName, original.videoName);
    expect(fixture.postRequests, isEmpty);
    await _tap(tester, 'uploader-shared-ai-apply');
    expect(
        tester
            .widget<TextField>(_key('uploader-caption-field'))
            .controller!
            .text,
        'Shared caption from the entire original');
    await _tap(tester, 'uploader-save-draft-button');
    final saved = fixture.store.groups[_groupId]!;
    expect(saved.sharedCaption, 'Shared caption from the entire original');
    expect(saved.captionContext, isNotNull);
    expect(saved.captionContext!.aiGuidance, 'Shared guidance for this set');
    expect(saved.items.last.usesSharedCaption, isFalse);
    expect(fixture.store.drafts[_partIds.first]!.caption, saved.sharedCaption);
    expect(fixture.store.drafts[_partIds.first]!.submissionRequestId,
        first.submissionRequestId);
    expect(
        fixture.store.drafts[_partIds.first]!.scheduledAt, first.scheduledAt);
    expect(fixture.store.drafts[_partIds.last]!.caption, custom.caption);
    expect(fixture.store.drafts[_partIds.last]!.submissionRequestId,
        custom.submissionRequestId);
    expect(
        fixture.store.drafts[_partIds.last]!.scheduledAt, custom.scheduledAt);
    expect(fixture.store.drafts['reviewed-source'], same(original));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await fixture.mount(tester);
    expect(
        tester
            .widget<TextField>(_key('uploader-caption-field'))
            .controller!
            .text,
        saved.sharedCaption);
    expect(fixture.aiRequests, hasLength(1));
    expect(fixture.postRequests, isEmpty);
    await _tap(tester, 'uploader-ai-open-panel');
    expect(
        tester
            .widget<TextField>(_key('uploader-ai-guidance-field'))
            .controller!
            .text,
        'Shared guidance for this set');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown member receipts keep shared AI unavailable on reopening',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.seedUnknownReceipt(_partIds.first);
    final original = fixture.store.drafts['reviewed-source']!;
    await fixture.mount(tester);
    _expectSharedAiLocked(tester);
    expect(fixture.aiRequests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.store.drafts['reviewed-source'], same(original));
    await _reviewToFinalConfirmation(tester);
    expect(fixture.postRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guidance-only edits save on Back without rewriting the original',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    final original = fixture.store.drafts['reviewed-source']!;
    await fixture.mount(tester);
    await _tap(tester, 'uploader-ai-open-panel');
    await tester.ensureVisible(_key('uploader-ai-guidance-input'));
    await tester.enterText(
        _key('uploader-ai-guidance-input'), 'Keep guidance when going back');
    await tester.pumpAndSettle();
    await _tap(tester, 'uploader-wizard-back');
    expect(_key('uploader-exit-dialog'), findsOneWidget);
    await tester.tap(find.text('Save and exit'));
    await _settle(tester);
    expect(fixture.store.groups[_groupId]!.captionContext!.aiGuidance,
        'Keep guidance when going back');
    expect(fixture.store.drafts['reviewed-source'], same(original));
    expect(fixture.aiRequests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.postRequests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await fixture.mount(tester);
    await _tap(tester, 'uploader-ai-open-panel');
    expect(
        tester
            .widget<TextField>(_key('uploader-ai-guidance-field'))
            .controller!
            .text,
        'Keep guidance when going back');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a receipt appearing while open preserves context and allows recovery '
      'review after a failed local save', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    final original = fixture.store.drafts['reviewed-source']!;
    await fixture.mount(tester);
    expect(_key('uploader-ai-caption-panel'), findsOneWidget);
    final key = await fixture.seedUnknownReceipt(_partIds.first);
    await _tap(tester, 'uploader-save-draft-button');
    _expectSharedAiLocked(tester);
    expect(fixture.store.groups[_groupId]!.captionContext, isNull);
    await _reviewToFinalConfirmation(tester);
    expect(_key('clip-group-confirm'), findsOneWidget);
    expect(fixture.store.groups[_groupId]!.captionContext, isNull);
    expect(
        fixture.store.drafts[_partIds.first]!.uploadedMedia!.videoS3Key, key);
    expect(fixture.store.drafts['reviewed-source'], same(original));
    expect(fixture.aiRequests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.postRequests, isEmpty);
    expect(fixture.recoveryRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'batch writes wait for explicit confirmation and checkpoint each '
      'independent scheduled intent before deleting its draft', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    final expectedIds = [
      for (final id in _partIds) fixture.store.drafts[id]!.submissionRequestId,
    ];
    final expectedTimes = [
      for (final item in fixture.store.groups[_groupId]!.items)
        item.scheduledAt,
    ];
    await fixture.mount(tester);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.postRequests, isEmpty);
    await _reviewToFinalConfirmation(tester);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.postRequests, isEmpty);
    expect(fixture.recoveryRequests, isEmpty);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.postRequests, hasLength(2),
        reason: fixture.store.events.join(' | '));
    expect(fixture.postRequests.map((request) => request.clientRequestId),
        expectedIds);
    expect(expectedIds.toSet(), hasLength(2));
    expect(fixture.postRequests.map((request) => request.scheduledAt),
        expectedTimes);
    expect(fixture.uploadRequests, hasLength(2));
    expect(fixture.uploadedKeys, hasLength(2));
    expect(
        fixture.store.events.where((event) => !event.startsWith('upload:')), [
      'post:${_partIds[0]}',
      'checkpoint:${_partIds[0]}',
      'delete:${_partIds[0]}',
      'post:${_partIds[1]}',
      'checkpoint:${_partIds[1]}',
      'delete:${_partIds[1]}',
    ]);
    expect(fixture.store.deletionCheckpoints, {
      for (final id in _partIds) id: 'accepted-$id',
    });
    expect(fixture.store.groups[_groupId]!.isComplete, isTrue);
    expect(fixture.store.drafts.keys, ['reviewed-source']);
    expect(_key('clip-group-result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a second lost response retains its receipt and reopens with '
      'read-only recovery at zero quota without resubmitting accepted members',
      (tester) async {
    final fixture = _Fixture()..loseSecondResponse = true;
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.postRequests, hasLength(2));
    final failedRequest = fixture.postRequests.last;
    final before = fixture.store.groups[_groupId]!;
    expect(before.items.first.isAccepted, isTrue);
    expect(before.items.last.isAccepted, isFalse);
    expect(fixture.store.drafts.containsKey(_partIds.first), isFalse);
    final unknown = fixture.store.drafts[_partIds.last]!;
    expect(unknown.uploadedMedia?.videoS3Key, failedRequest.videoS3Key);
    expect(unknown.submissionRequestId, failedRequest.clientRequestId);
    expect(fixture.store.deletionCheckpoints.keys, [_partIds.first]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    fixture.quota = _Fixture._quota(0);
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.recoveryRequests, hasLength(1));
    expect(fixture.recoveryRequests.single.toJson(), failedRequest.toJson());
    expect(fixture.postRequests, hasLength(2));
    expect(fixture.uploadRequests, hasLength(2));
    expect(fixture.uploadedKeys, hasLength(2));
    expect(fixture.quota.availablePostUnits, 0);
    expect(fixture.store.groups[_groupId]!.isComplete, isTrue);
    expect(fixture.store.drafts.keys, ['reviewed-source']);
    expect(fixture.store.deletionCheckpoints[_partIds.last],
        'accepted-${_partIds.last}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a later missing member file blocks every upload in the set',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    File(fixture.store.drafts[_partIds.last]!.videoPath).deleteSync();
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.postRequests, isEmpty);
    expect(fixture.uploadedKeys, isEmpty);
    expect(fixture.store.groups[_groupId]!.items.any((item) => item.isAccepted),
        isFalse);
    expect(fixture.store.drafts.keys.toSet(), {'reviewed-source', ..._partIds});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an accepted create response with the wrong video key never '
      'checkpoints, deletes its child, or submits the next member',
      (tester) async {
    final fixture = _Fixture()..corruptCreateResponse = true;
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.postRequests, hasLength(1));
    expect(fixture.uploadRequests, hasLength(1));
    expect(fixture.uploadedKeys, hasLength(1));
    expect(fixture.store.groups[_groupId]!.items.any((item) => item.isAccepted),
        isFalse);
    expect(fixture.store.deletionCheckpoints, isEmpty);
    expect(fixture.store.drafts.keys.toSet(), {'reviewed-source', ..._partIds});
    expect(fixture.store.drafts[_partIds.first]!.uploadedMedia?.videoS3Key,
        fixture.postRequests.single.videoS3Key);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an accepted recovery response with the wrong video key never '
      'checkpoints, deletes its child, or submits the next member',
      (tester) async {
    final fixture = _Fixture()..corruptRecoveryResponse = true;
    addTearDown(fixture.dispose);
    await fixture.seed();
    final expectedKey = await fixture.seedUnknownReceipt(_partIds.first);
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.recoveryRequests, hasLength(1));
    expect(fixture.recoveryRequests.single.videoS3Key, expectedKey);
    expect(fixture.postRequests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.uploadedKeys, isEmpty);
    expect(fixture.store.groups[_groupId]!.items.any((item) => item.isAccepted),
        isFalse);
    expect(fixture.store.deletionCheckpoints, isEmpty);
    expect(fixture.store.drafts.keys.toSet(), {'reviewed-source', ..._partIds});
    expect(fixture.store.drafts[_partIds.first]!.uploadedMedia?.videoS3Key,
        expectedKey);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an explicit not-found lookup retries a future unknown request '
      'with the original identity and upload', (tester) async {
    final fixture = _Fixture()..loseSecondResponse = true;
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.postRequests, hasLength(2));
    final originalUnknown = fixture.postRequests.last;
    expect(fixture.store.drafts[_partIds.last]!.uploadedMedia, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    fixture
      ..recoverFound = false
      ..loseSecondResponse = false;
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.recoveryRequests, hasLength(1));
    expect(fixture.recoveryRequests.single.toJson(), originalUnknown.toJson());
    expect(fixture.postRequests, hasLength(3));
    expect(fixture.postRequests.last.toJson(), originalUnknown.toJson());
    expect(
        fixture.postRequests.where((request) =>
            request.clientRequestId == originalUnknown.clientRequestId),
        hasLength(2));
    expect(fixture.uploadRequests, hasLength(2));
    expect(fixture.uploadedKeys, hasLength(2));
    expect(fixture.store.groups[_groupId]!.isComplete, isTrue);
    expect(fixture.store.drafts.keys, ['reviewed-source']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an expired unknown request may be looked up but a not-found '
      'answer preserves its receipt without submitting again', (tester) async {
    final fixture = _Fixture()..loseSecondResponse = true;
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.postRequests, hasLength(2));
    final originalUnknown = fixture.postRequests.last;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    fixture
      ..currentTime = _now.add(const Duration(days: 4))
      ..quota = _Fixture._quota(0)
      ..recoverFound = false;
    await fixture.mount(tester);
    await _reviewToFinalConfirmation(tester);
    await _tap(tester, 'clip-group-confirm');
    expect(fixture.recoveryRequests, hasLength(1));
    expect(fixture.recoveryRequests.single.toJson(), originalUnknown.toJson());
    expect(fixture.postRequests, hasLength(2));
    expect(fixture.uploadRequests, hasLength(2));
    expect(fixture.uploadedKeys, hasLength(2));
    final group = fixture.store.groups[_groupId]!;
    expect(group.items.first.isAccepted, isTrue);
    expect(group.items.last.isAccepted, isFalse);
    expect(fixture.store.drafts[_partIds.last]!.uploadedMedia?.videoS3Key,
        originalUnknown.videoS3Key);
    expect(fixture.store.drafts[_partIds.last]!.submissionRequestId,
        originalUnknown.clientRequestId);
    expect(fixture.store.deletionCheckpoints.keys, [_partIds.first]);
    expect(tester.takeException(), isNull);
  });
}
