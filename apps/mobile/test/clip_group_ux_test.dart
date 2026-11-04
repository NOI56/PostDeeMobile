import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_localizations.dart';
import 'package:postdee_mobile/features/uploader/clip_group_review_screen.dart';
import 'package:postdee_mobile/features/uploader/clip_group_submission.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';

const _owner = 'group-ux-owner';
final _now = DateTime.utc(2026, 11, 8, 10);

ClipGroupDraft _group() => ClipGroupDraft(
        id: 'ux-group',
        ownerUserId: _owner,
        sourceDraftId: 'source',
        title: 'Three-minute video',
        sharedCaption: 'Seller caption',
        deliveryMode: ClipGroupDeliveryMode.immediate,
        createdAt: _now,
        updatedAt: _now,
        revision: 1,
        items: [
          for (final (id, start, end, platforms) in [
            ('fb1', 0.0, 90.0, {'FACEBOOK_REELS'}),
            (
              'full',
              0.0,
              180.0,
              {'TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS'}
            ),
            ('fb2', 90.0, 180.0, {'FACEBOOK_REELS'}),
          ].indexed.map((entry) => entry.$2))
            ClipGroupItem(
                draftId: id,
                index: id == 'fb1'
                    ? 0
                    : id == 'full'
                        ? 1
                        : 2,
                sourceStartSeconds: start,
                sourceEndSeconds: end,
                platformApiValues: platforms),
        ]);

class _Fixture {
  ClipGroupDraft group = _group();
  final opened = <String>[];
  final edits = <(String, ClipGroupEditSection)>[];
  final drafts = <String, PublishDraft>{};
  int submissions = 0;
  int saves = 0;
  bool english = false;
  SubscriptionStatusResult quota = const SubscriptionStatusResult(
      userId: _owner,
      plan: 'PRO',
      status: 'ACTIVE',
      availablePostUnits: 20,
      remainingPostsThisMonth: 20,
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: false);
  Completer<ClipGroupSubmissionResult>? submissionGate;
  void Function(ClipGroupSubmissionProgress)? report;

  void seed({bool receipt = false}) {
    drafts.clear();
    for (final item in group.items) {
      drafts[item.draftId] = PublishDraft(
          version: publishDraftManifestVersion,
          id: item.draftId,
          ownerUserId: _owner,
          submissionRequestId: 'submit-${item.draftId}',
          createdAt: _now,
          updatedAt: _now,
          videoPath: '/${item.draftId}.mp4',
          videoName: '${item.draftId}.mp4',
          videoSizeBytes: 20,
          caption: 'Seller caption',
          aiGuidance: '',
          watermarkEnabled: false,
          platformApiValues: item.platformApiValues,
          clipGroupId: group.id,
          uploadedMedia: receipt && item.draftId == 'full'
              ? const PublishDraftUploadedMedia(
                  mediaContentFingerprint: 'old-fingerprint',
                  videoS3Key: 'old-key')
              : null);
    }
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: Locale(english ? 'en' : 'th'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: AppTheme.light,
      home: ClipGroupReviewScreen(
        initialGroup: group,
        draftsById: drafts,
        ownerSession: PostDeeAuthSessionStore.instance.captureSession(),
        now: () => _now,
        loadSubscription: () async => quota,
        loadPostQuota: () async => quota,
        onSaveGroup: (proposed) async {
          saves++;
          group = proposed.copyWith(revision: group.revision + 1);
          return group;
        },
        onSaveCaption: (draft, caption) async => draft,
        onEditClip: (draft, section) async {
          edits.add((draft.id, section));
          return draft;
        },
        onReloadGroup: () async => group,
        onSubmit: (confirmed, progress) async {
          submissions++;
          report = progress;
          if (submissionGate != null) return submissionGate!.future;
          return ClipGroupSubmissionResult(
              group: confirmed,
              completed: 0,
              remaining: confirmed.items.length);
        },
        onOpenPost: opened.add,
      ),
    ));
    await tester.pumpAndSettle();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: _owner, idToken: 'ux-token'));
    addTearDown(PostDeeAuthSessionStore.instance.clear);
  });

  testWidgets('episode labels follow each destination without changing order',
      (tester) async {
    final group = _group();
    final labels = <String>[];
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      labels.addAll(
          group.items.map((item) => clipGroupPartLabel(context, group, item)));
      return const SizedBox.shrink();
    })));
    expect(labels, ['ตอน 1/2', 'คลิปเต็ม', 'ตอน 2/2']);
    expect(group.items.map((item) => item.draftId), ['fb1', 'full', 'fb2']);
    expect(group.items.map((item) => item.index), [0, 1, 2]);
  });

  testWidgets(
      'accepted group receipts use plain status and open the original '
      'post for current delivery details and TikTok next steps',
      (tester) async {
    final fixture = _Fixture()..english = true;
    fixture.group = fixture.group.copyWith(items: [
      fixture.group.items[0]
          .copyWith(acceptedPostId: 'post-fb1', acceptedPostStatus: 'QUEUED'),
      fixture.group.items[1].copyWith(
          acceptedPostId: 'post-full', acceptedPostStatus: 'PUBLISHED'),
      fixture.group.items[2]
          .copyWith(acceptedPostId: 'post-fb2', acceptedPostStatus: 'FAILED'),
    ]);
    await fixture.mount(tester);
    expect(find.textContaining('QUEUED'), findsNothing);
    expect(find.textContaining('PUBLISHED'), findsNothing);
    expect(find.textContaining('FAILED'), findsNothing);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Delivery completed'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Delivery failed'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Delivery failed'), findsOneWidget);
    expect(find.textContaining('not confirmation that every video is public'),
        findsOneWidget);
    await _tap(tester, 'clip-group-view-post-full');
    expect(fixture.opened, ['post-full']);
    expect(fixture.submissions, 0);
    expect(fixture.saves, 0);
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: _owner, idToken: 'new-lifecycle'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextButton>(_key('clip-group-view-post-full')).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'progress names settings and upload stages for the active episode',
      (tester) async {
    final fixture = _Fixture()
      ..submissionGate = Completer<ClipGroupSubmissionResult>();
    fixture.seed();
    await fixture.mount(tester);
    await _tap(tester, 'clip-group-next');
    await _tap(tester, 'clip-group-next');
    await tester.tap(_key('clip-group-confirm'));
    await tester.pump();
    await tester.pump();
    fixture.report!(const ClipGroupSubmissionProgress(
        itemIndex: 0,
        completed: 0,
        total: 3,
        stage: ClipGroupSubmissionStage.checking,
        itemDraftId: 'fb1',
        activity: ClipGroupSubmissionActivity.confirmingSettings));
    await tester.pump();
    expect(find.text('กำลังยืนยันการตั้งค่า · ตอน 1/2'), findsOneWidget);
    fixture.report!(const ClipGroupSubmissionProgress(
        itemIndex: 0,
        completed: 0,
        total: 3,
        stage: ClipGroupSubmissionStage.submitting,
        itemDraftId: 'fb1',
        activity: ClipGroupSubmissionActivity.uploadingVideo,
        fraction: .4));
    await tester.pump();
    expect(find.text('กำลังอัปโหลดคลิป · ตอน 1/2'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('clip-group-stage-progress'))
            .value,
        .4);
    fixture.submissionGate!.complete(ClipGroupSubmissionResult(
        group: fixture.group, completed: 0, remaining: 3));
    await tester.pumpAndSettle();
    expect(fixture.submissions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'phone and quota warnings appear early but local draft work remains enabled',
      (tester) async {
    final fixture = _Fixture()
      ..quota = const SubscriptionStatusResult(
          userId: _owner,
          plan: 'FREE',
          status: 'ACTIVE',
          availablePostUnits: 0,
          remainingPostsThisMonth: 0,
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false,
          requiresPhoneVerification: true);
    fixture.seed();
    await fixture.mount(tester);
    expect(_key('clip-group-readiness-notice'), findsOneWidget);
    expect(find.textContaining('ยืนยันเบอร์โทร'), findsWidgets);
    expect(find.text('เก็บชุดคลิปไว้ในเครื่อง'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('clip-group-next')).onPressed,
        isNotNull);
    await _tap(tester, 'clip-group-save');
    expect(fixture.saves, 1);
    expect(fixture.submissions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unknown receipts distinguish new units from recovery without promising a free retry',
      (tester) async {
    final fixture = _Fixture()..english = true;
    fixture.seed(receipt: true);
    await fixture.mount(tester);
    expect(find.text('New submissions use 2 post units'), findsOneWidget);
    expect(
        find.textContaining('Existing accepted requests are not charged again'),
        findsOneWidget);
    expect(find.textContaining('may use post units if not accepted yet'),
        findsOneWidget);
    expect(fixture.submissions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'per-member AI is visible and opens the existing editor without '
      'changing platform membership or clip order', (tester) async {
    final fixture = _Fixture()..english = true;
    fixture.seed();
    final ids = fixture.group.items.map((item) => item.draftId).toList();
    await fixture.mount(tester);
    await tester.scrollUntilVisible(_key('clip-group-ai-fb1'), 150,
        scrollable: find.byType(Scrollable).first);
    await _tap(tester, 'clip-group-ai-fb1');
    expect(fixture.edits, [('fb1', ClipGroupEditSection.caption)]);
    expect(fixture.group.items.map((item) => item.draftId), ids);
    expect(fixture.group.items.first.platformApiValues, {'FACEBOOK_REELS'});
    expect(fixture.submissions, 0);
    expect(tester.takeException(), isNull);
  });
}
