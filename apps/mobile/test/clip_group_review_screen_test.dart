import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_review_screen.dart';
import 'package:postdee_mobile/features/uploader/clip_group_submission.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';

const _owner = 'group-review-owner';
final _now = DateTime(2026, 11, 4, 10);
const _quota = SubscriptionStatusResult(
    userId: _owner,
    plan: 'PRO',
    status: 'ACTIVE',
    monthlyPostLimit: 250,
    remainingPostsThisMonth: 10,
    usedPostsThisMonth: 240,
    availablePostUnits: 10,
    canSchedule: true,
    canUseAiCaptions: true,
    canUseAnalytics: false);

PublishDraft _draft(String id,
        {String caption = 'แคปชั่นหลัก', bool receipt = false}) =>
    PublishDraft(
        version: publishDraftManifestVersion,
        id: id,
        ownerUserId: _owner,
        submissionRequestId: 'submit_$id',
        createdAt: _now,
        updatedAt: _now,
        videoPath: '/$id.mp4',
        videoName: '$id.mp4',
        videoSizeBytes: 100,
        caption: caption,
        captionNeedsReview: true,
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: {id == 'ig' ? 'INSTAGRAM_REELS' : 'YOUTUBE_SHORTS'},
        clipGroupId: 'group',
        uploadedMedia: receipt
            ? const PublishDraftUploadedMedia(
                mediaContentFingerprint: 'fingerprint', videoS3Key: 'old-key')
            : null);

ClipGroupDraft _group() => ClipGroupDraft(
        id: 'group',
        ownerUserId: _owner,
        sourceDraftId: 'source',
        title: 'คลิปของฉัน',
        sharedCaption: 'แคปชั่นหลัก',
        deliveryMode: ClipGroupDeliveryMode.immediate,
        createdAt: _now,
        updatedAt: _now,
        items: [
          ClipGroupItem(
              draftId: 'yt1',
              index: 0,
              sourceStartSeconds: 0,
              sourceEndSeconds: 180,
              platformApiValues: {'YOUTUBE_SHORTS'}),
          ClipGroupItem(
              draftId: 'yt2',
              index: 1,
              sourceStartSeconds: 180,
              sourceEndSeconds: 360,
              platformApiValues: {'YOUTUBE_SHORTS'}),
          ClipGroupItem(
              draftId: 'ig',
              index: 2,
              sourceStartSeconds: 0,
              sourceEndSeconds: 360,
              platformApiValues: {'INSTAGRAM_REELS'}),
        ]);

void main() {
  late ClipGroupDraft persisted;
  late Map<String, PublishDraft> drafts;
  var submitted = 0;
  var saved = 0;
  DateTime pickedDate = DateTime(2026, 11, 5);
  TimeOfDay pickedTime = const TimeOfDay(hour: 9, minute: 0);
  setUp(() {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(
        AuthSession.authenticated(userId: _owner, idToken: 'group-token'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    persisted = _group();
    drafts = {
      for (final id in ['yt1', 'yt2', 'ig']) id: _draft(id)
    };
    submitted = 0;
    saved = 0;
  });
  Future<void> mount(WidgetTester tester,
      {bool english = false,
      bool dark = false,
      double scale = 1,
      Future<SubscriptionStatusResult> Function()? quota}) async {
    AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    await tester.pumpWidget(MaterialApp(
      locale: Locale(english ? 'en' : 'th'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: ClipGroupReviewScreen(
        initialGroup: persisted,
        draftsById: drafts,
        ownerSession: PostDeeAuthSessionStore.instance.captureSession(),
        now: () => _now,
        loadSubscription: () => Future.value(_quota),
        loadPostQuota: quota ?? () => Future.value(_quota),
        onSaveGroup: (group) async {
          saved++;
          persisted = group.copyWith(revision: persisted.revision + 1);
          return persisted;
        },
        onSaveCaption: (draft, caption) async {
          final updated = _draft(draft.id, caption: caption);
          drafts[draft.id] = updated;
          persisted = persisted.copyWith(items: [
            for (final item in persisted.items)
              item.draftId == draft.id
                  ? item.copyWith(usesSharedCaption: false)
                  : item
          ]);
          return updated;
        },
        onEditClip: (draft, section) async => draft,
        onReloadGroup: () async => persisted,
        onSubmit: (group, progress) async {
          submitted++;
          persisted = group.copyWith(items: [
            for (final item in group.items)
              item.copyWith(
                  acceptedPostId: 'post-${item.draftId}',
                  acceptedPostStatus: 'QUEUED')
          ]);
          return ClipGroupSubmissionResult(
              group: persisted, completed: 3, remaining: 0);
        },
        pickDate: (context, initial, first, last) async => pickedDate,
        pickTime: (context, initial, date) async => pickedTime,
        previewClip: (draft) async {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) {
      await tester.fling(find.byKey(const ValueKey('clip-group-scroll')),
          const Offset(0, 2000), 5000);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 150,
          scrollable: find
              .descendant(
                  of: find.byKey(const ValueKey('clip-group-scroll')),
                  matching: find.byType(Scrollable))
              .first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'all clips stay together and submit only after final confirmation',
      (tester) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('clip-group-review')), findsOneWidget);
    expect(find.text('ใช้ 3 หน่วยโพสต์'), findsOneWidget);
    expect(submitted, 0);
    await tap(tester, 'clip-group-next');
    expect(submitted, 0);
    await tap(tester, 'clip-group-next');
    expect(submitted, 0);
    expect(saved, greaterThanOrEqualTo(2));
    await tap(tester, 'clip-group-confirm');
    expect(submitted, 1);
    expect(find.byKey(const ValueKey('clip-group-result')), findsOneWidget);
  });
  testWidgets('dates and times are independent and survive immediate toggle',
      (tester) async {
    await mount(tester);
    await tap(tester, 'clip-group-next');
    await tap(tester, 'clip-group-mode-scheduled');
    pickedDate = DateTime(2026, 11, 5);
    pickedTime = const TimeOfDay(hour: 9, minute: 15);
    await tap(tester, 'clip-group-date-yt1');
    await tap(tester, 'clip-group-time-yt1');
    pickedDate = DateTime(2026, 11, 7);
    pickedTime = const TimeOfDay(hour: 14, minute: 45);
    await tap(tester, 'clip-group-date-yt2');
    await tap(tester, 'clip-group-time-yt2');
    await tap(tester, 'clip-group-save');
    expect(persisted.items[0].scheduledAt!.toLocal(),
        DateTime(2026, 11, 5, 9, 15));
    expect(persisted.items[1].scheduledAt!.toLocal(),
        DateTime(2026, 11, 7, 14, 45));
    expect(persisted.items[2].scheduledAt, isNull);
    await tap(tester, 'clip-group-mode-immediate');
    await tap(tester, 'clip-group-mode-scheduled');
    await tap(tester, 'clip-group-save');
    expect(persisted.items[0].scheduledAt!.toLocal(),
        DateTime(2026, 11, 5, 9, 15));
    expect(submitted, 0);
  });
  testWidgets(
      'custom caption does not get overwritten by a shared caption update',
      (tester) async {
    await mount(tester);
    await tap(tester, 'clip-group-caption-yt1');
    await tester.enterText(
        find.byKey(const ValueKey('clip-group-caption-input')),
        'ข้อความเฉพาะตอนแรก');
    await tap(tester, 'clip-group-caption-apply');
    await tap(tester, 'clip-group-shared-caption-toggle');
    await tester.enterText(
        find.byKey(const ValueKey('clip-group-shared-caption')),
        'ข้อความหลักใหม่');
    await tap(tester, 'clip-group-save');
    expect(persisted.items[0].usesSharedCaption, isFalse);
    expect(drafts['yt1']!.caption, 'ข้อความเฉพาะตอนแรก');
    expect(persisted.sharedCaption, 'ข้อความหลักใหม่');
  });
  testWidgets('missing member and unavailable quota cannot submit',
      (tester) async {
    drafts.remove('yt2');
    await mount(tester, quota: () async => throw StateError('offline'));
    await tap(tester, 'clip-group-next');
    await tap(tester, 'clip-group-next');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('clip-group-confirm')))
            .onPressed,
        isNull);
    expect(submitted, 0);
  });
  testWidgets('next cannot advance twice while the final quota read is pending',
      (tester) async {
    final pending = Completer<SubscriptionStatusResult>();
    var reads = 0;
    await mount(tester, quota: () {
      reads++;
      return reads == 1 ? Future.value(_quota) : pending.future;
    });
    await tap(tester, 'clip-group-next');
    await tester.tap(find.byKey(const ValueKey('clip-group-next')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('clip-group-next')))
            .onPressed,
        isNull);
    pending.complete(_quota);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clip-group-confirm')), findsOneWidget);
    expect(submitted, 0);
  });
  testWidgets('accepted and unresolved members cannot be edited',
      (tester) async {
    drafts['yt2'] = _draft('yt2', receipt: true);
    persisted = persisted.copyWith(items: [
      persisted.items[0]
          .copyWith(acceptedPostId: 'existing', acceptedPostStatus: 'QUEUED'),
      persisted.items[1],
      persisted.items[2]
    ]);
    await mount(tester);
    final first = find.byKey(const ValueKey('clip-group-edit-yt1'));
    expect(tester.widget<PopupMenuButton<ClipGroupEditSection>>(first).enabled,
        isFalse);
    await tap(tester, 'clip-group-next');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('clip-group-date-yt2')), 150,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('clip-group-scroll')),
                matching: find.byType(Scrollable))
            .first);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('clip-group-date-yt2')))
            .onPressed,
        isNull);
  });
  testWidgets(
      'expired unknown request remains recoverable without fresh quota or plan',
      (tester) async {
    drafts['yt1'] = _draft('yt1', receipt: true);
    persisted = persisted
        .copyWith(deliveryMode: ClipGroupDeliveryMode.scheduled, items: [
      persisted.items[0]
          .copyWith(scheduledAt: _now.subtract(const Duration(days: 1))),
      persisted.items[1]
          .copyWith(acceptedPostId: 'old-yt2', acceptedPostStatus: 'QUEUED'),
      persisted.items[2]
          .copyWith(acceptedPostId: 'old-ig', acceptedPostStatus: 'QUEUED'),
    ]);
    await mount(tester, quota: () async => throw StateError('offline'));
    await tap(tester, 'clip-group-next');
    await tap(tester, 'clip-group-next');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('clip-group-confirm')))
            .onPressed,
        isNotNull);
    await tap(tester, 'clip-group-confirm');
    expect(submitted, 1);
  });
  testWidgets('English dark narrow layout and owner change stay safe',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, english: true, dark: true, scale: 1.7);
    await tap(tester, 'clip-group-next');
    await tap(tester, 'clip-group-next');
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'other-owner', idToken: 'other-token'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('clip-group-confirm')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
