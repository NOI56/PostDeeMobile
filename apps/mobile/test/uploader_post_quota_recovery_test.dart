import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/post_quota_strip.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _ownerA = 'post-quota-recovery-a';
const _ownerB = 'post-quota-recovery-b';

SubscriptionStatusResult _quota({String owner = _ownerA, int used = 12}) =>
    SubscriptionStatusResult(
      userId: owner,
      plan: 'STARTER',
      status: 'ACTIVE',
      monthlyPostLimit: 120,
      usedPostsThisMonth: used,
      remainingPostsThisMonth: 120 - used,
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: false,
    );

void main() {
  late Directory directory;
  late TestPublishDraftStore store;
  late PublishDraft draft;
  late List<String> sideEffects;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(AuthSession.authenticated(
        userId: _ownerA, idToken: 'recovery-token-a'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    directory = Directory.systemTemp.createTempSync('post-quota-recovery-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final video = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    store = TestPublishDraftStore(ownerUserId: _ownerA);
    sideEffects = [];
    final saved = await store.saveDraft(PublishDraftSaveRequest(
      id: 'uploaded-recovery-draft',
      createdAt: DateTime.utc(2026, 10, 25),
      updatedAt: DateTime.utc(2026, 10, 25),
      videoFile: video,
      videoName: 'clip.mp4',
      videoSizeBytes: 512,
      videoWidth: 1080,
      videoHeight: 1920,
      caption: 'แคปชั่นของรายการเดิม',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: {'YOUTUBE_SHORTS', 'FACEBOOK_REELS'},
    ));
    draft = await store.saveDraft(PublishDraftSaveRequest(
      id: saved.id,
      createdAt: saved.createdAt,
      updatedAt: saved.updatedAt,
      videoFile: video,
      videoName: saved.videoName,
      videoSizeBytes: saved.videoSizeBytes,
      videoWidth: saved.videoWidth,
      videoHeight: saved.videoHeight,
      caption: saved.caption,
      aiGuidance: saved.aiGuidance,
      watermarkEnabled: saved.watermarkEnabled,
      platformApiValues: saved.platformApiValues,
      uploadedMedia: PublishDraftUploadedMedia(
        mediaContentFingerprint: saved.mediaContentFingerprint!,
        videoS3Key: 'uploads/$_ownerA/clip/original.mp4',
      ),
    ));
  });

  Future<void> pump(WidgetTester tester,
      {required UploaderSubscriptionLoader loadQuota,
      required UploaderPostRecovery recover}) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UploaderScreen(
          draftStore: store,
          initialDraftId: draft.id,
          loadPostQuota: loadQuota,
          loadSubscription: () async {
            sideEffects.add('subscription-preflight');
            throw StateError('Recovery must not run publishing preflight');
          },
          loadCaptionQuota: () async => const CaptionQuotaResult(
            plan: 'STARTER',
            quota: RealClipCaptionQuota(
                limit: 50, usedThisMonth: 0, remainingThisMonth: 50),
          ),
          loadSocialConnections: () async => const [],
          loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
          probePublishMedia: (file) async {
            sideEffects.add('probe');
            return probeValidPublishMedia(file);
          },
          createUpload: (_) async {
            sideEffects.add('upload');
            throw StateError('Recovery must retain its original upload');
          },
          uploadVideoFile: (_, __) async => sideEffects.add('upload-file'),
          createPost: (_) async {
            sideEffects.add('publish');
            throw StateError('Recovery must never create a new post');
          },
          recoverPostSubmission: recover,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 0);
    expect(find.byType(PostQuotaStrip), findsOneWidget);
  }

  Future<void> recover(WidgetTester tester) async {
    final action = find.byKey(const ValueKey('uploader-recover-submission'));
    await tester.scrollUntilVisible(action, -100,
        scrollable: uploaderMainScroll);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
  }

  QueuedPostResult accepted(String status) => QueuedPostResult(
        id: 'accepted-original',
        status: status,
        videoS3Key: draft.uploadedMedia!.videoS3Key,
        platforms: draft.platformApiValues.toList(),
        idempotentReplay: true,
      );

  testWidgets(
      'recovery leaves pending balance unchanged then refreshes accepted post units from server',
      (tester) async {
    final pending = Completer<QueuedPostResult?>();
    final freshQuota = Completer<SubscriptionStatusResult>();
    var quotaReads = 0;
    final recoveredRequests = <CreatePostRequest>[];
    await pump(tester,
        loadQuota: () => ++quotaReads <= 2
            ? Future.value(_quota())
            : freshQuota.future,
        recover: (request) {
          recoveredRequests.add(request);
          return pending.future;
        });
    expect(find.text('108 / 120 หน่วย'), findsOneWidget);
    expect(quotaReads, 2);

    await recover(tester);
    expect(quotaReads, 2);
    expect(find.text('108 / 120 หน่วย'), findsOneWidget);
    expect(recoveredRequests.single.clientRequestId, draft.submissionRequestId);
    expect(recoveredRequests.single.platforms, hasLength(2));

    pending.complete(accepted('QUEUED'));
    await tester.pumpAndSettle();
    expect(quotaReads, 3);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('uploader-post-quota-loading')), 150,
        scrollable: uploaderMainScroll);
    expect(find.byKey(const ValueKey('uploader-post-quota-loading')),
        findsOneWidget);
    expect(find.byType(PostQuotaStrip), findsNothing);
    freshQuota.complete(_quota(used: 14));
    await tester.pumpAndSettle();
    expect(find.text('106 / 120 หน่วย'), findsOneWidget);
    expect(find.text('ใช้ไป 14 หน่วย'), findsOneWidget);
    expect(find.text('108 / 120 หน่วย'), findsNothing);
    expect(store.drafts[draft.id]!.uploadedMedia!.videoS3Key,
        draft.uploadedMedia!.videoS3Key);
    expect(sideEffects, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a recovered FAILED original keeps its server allocation and receipt without an optimistic refund',
      (tester) async {
    var quotaReads = 0;
    await pump(tester,
        loadQuota: () async => _quota(used: ++quotaReads <= 2 ? 12 : 14),
        recover: (_) async => accepted('FAILED'));
    expect(find.text('108 / 120 หน่วย'), findsOneWidget);
    await recover(tester);
    await tester.pumpAndSettle();
    expect(quotaReads, 3);
    await tester.scrollUntilVisible(find.byType(PostQuotaStrip), 150,
        scrollable: uploaderMainScroll);
    expect(find.text('106 / 120 หน่วย'), findsOneWidget);
    expect(find.text('ใช้ไป 14 หน่วย'), findsOneWidget);
    expect(find.textContaining('ส่งไม่สำเร็จ'), findsWidgets);
    expect(store.drafts[draft.id]!.submissionRequestId,
        draft.submissionRequestId);
    expect(store.drafts[draft.id]!.uploadedMedia, isNotNull);
    expect(sideEffects, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late recovery from the previous owner cannot trigger another quota read or replace the new owner balance',
      (tester) async {
    final pending = Completer<QueuedPostResult?>();
    var quotaReads = 0;
    await pump(tester,
        loadQuota: () async {
          quotaReads++;
          final owner = PostDeeAuthSessionStore.instance.session.stableUserId;
          return owner == _ownerB
              ? _quota(owner: _ownerB, used: 43)
              : _quota();
        },
        recover: (_) => pending.future);
    expect(quotaReads, 2);
    await recover(tester);
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: _ownerB, idToken: 'recovery-token-b'));
    await tester.pumpAndSettle();
    expect(quotaReads, 3);
    expect(find.text('77 / 120 หน่วย'), findsOneWidget);
    pending.complete(accepted('PUBLISHED'));
    await tester.pumpAndSettle();
    expect(quotaReads, 3);
    expect(find.text('77 / 120 หน่วย'), findsOneWidget);
    expect(find.textContaining('accepted-original'), findsNothing);
    expect(sideEffects, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
