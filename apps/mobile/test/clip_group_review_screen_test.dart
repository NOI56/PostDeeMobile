import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_store.dart';
import 'package:postdee_mobile/features/uploader/clip_group_localizations.dart';
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

class _SharedEditor extends StatefulWidget {
  const _SharedEditor({
    required this.controller,
    required this.onBusyChanged,
    required this.enabled,
    required this.onGenerate,
  });
  final TextEditingController controller;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;
  final VoidCallback onGenerate;
  @override
  State<_SharedEditor> createState() => _SharedEditorState();
}

class _SharedEditorState extends State<_SharedEditor> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    // An embedded editor may report its current state while rebuilding.
    widget.onBusyChanged(_busy);
    return Column(children: [
      TextField(
          key: const ValueKey('shared-editor-input'),
          controller: widget.controller,
          enabled: widget.enabled && !_busy),
      TextButton(
          key: const ValueKey('shared-editor-ai-start'),
          onPressed: widget.enabled && !_busy
              ? () {
                  setState(() => _busy = true);
                  widget.onGenerate();
                  widget.onBusyChanged(true);
                }
              : null,
          child: const Text('Generate test caption')),
      TextButton(
          key: const ValueKey('shared-editor-ai-finish'),
          onPressed: _busy
              ? () {
                  widget.controller.text = 'ข้อความจาก AI ของต้นฉบับ';
                  setState(() => _busy = false);
                  widget.onBusyChanged(false);
                }
              : null,
          child: const Text('Finish test caption')),
    ]);
  }
}

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
      Future<SubscriptionStatusResult> Function()? quota,
      Future<ClipGroupDraft> Function(ClipGroupDraft)? saveGroup,
      Future<PublishDraft?> Function(PublishDraft, ClipGroupEditSection)? edit,
      ClipGroupSharedCaptionEditorBuilder? sharedEditor,
      Future<ClipGroupSubmissionResult> Function(ClipGroupDraft)?
          submit}) async {
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
        sharedCaptionEditorBuilder: sharedEditor,
        loadSubscription: () => Future.value(_quota),
        loadPostQuota: quota ?? () => Future.value(_quota),
        onSaveGroup: (group) async {
          saved++;
          if (saveGroup != null) return saveGroup(group);
          persisted = group.copyWith(revision: persisted.revision + 1);
          for (final item in persisted.items) {
            final draft = drafts[item.draftId];
            if (item.usesSharedCaption &&
                !item.isAccepted &&
                draft != null &&
                draft.uploadedMedia == null) {
              drafts[item.draftId] =
                  _draft(item.draftId, caption: persisted.sharedCaption);
            }
          }
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
        onEditClip: edit ?? (draft, section) async => draft,
        onReloadGroup: () async => persisted,
        onSubmit: (group, progress) async {
          submitted++;
          if (submit != null) return submit(group);
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

  Future<void> reveal(WidgetTester tester, String key) async {
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
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await reveal(tester, key);
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('caption page opens the shared editor immediately',
      (tester) async {
    await mount(tester);
    expect(find.text('เขียนแคปชั่นทั้งชุด'), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-group-shared-caption')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('clip-group-shared-caption-toggle')),
        findsNothing);
    expect(find.byKey(const ValueKey('clip-group-clips')), findsOneWidget);
    expect(saved, 0);
    expect(submitted, 0);
  });

  testWidgets(
      'embedded AI is explicit and blocks navigation without disabling itself',
      (tester) async {
    var generations = 0;
    drafts['yt1'] = _draft('yt1', caption: 'ข้อความเฉพาะตอนแรก');
    persisted = persisted.copyWith(items: [
      persisted.items[0].copyWith(usesSharedCaption: false),
      ...persisted.items.skip(1),
    ]);
    await mount(tester,
        sharedEditor:
            (context, controller, onBusy, enabled, onContextChanged) =>
                _SharedEditor(
                    controller: controller,
                    onBusyChanged: onBusy,
                    enabled: enabled,
                    onGenerate: () => generations++));
    expect(generations, 0);
    expect(saved, 0);
    await tester.enterText(find.byKey(const ValueKey('shared-editor-input')),
        'ข้อความที่กำลังพิมพ์');
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tap(tester, 'shared-editor-ai-start');
    expect(generations, 1);
    expect(tester.widget<_SharedEditor>(find.byType(_SharedEditor)).enabled,
        isTrue);
    for (final key in ['clip-group-save', 'clip-group-caption-yt1']) {
      expect(tester.widget<TextButton>(find.byKey(ValueKey(key))).onPressed,
          isNull);
    }
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('clip-group-next')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<PopupMenuButton<ClipGroupEditSection>>(
                find.byKey(const ValueKey('clip-group-edit-yt1')))
            .enabled,
        isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ClipGroupReviewScreen), findsOneWidget);
    expect(saved, 0);
    await tester.fling(find.byKey(const ValueKey('clip-group-scroll')),
        const Offset(0, -2500), 5000);
    await tester.pumpAndSettle();
    await reveal(tester, 'shared-editor-ai-finish');
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('shared-editor-ai-finish')))
            .onPressed,
        isNotNull,
        reason: 'Scrolling must retain the running editor state');
    await tap(tester, 'shared-editor-ai-finish');
    await tap(tester, 'clip-group-save');
    expect(persisted.sharedCaption, 'ข้อความจาก AI ของต้นฉบับ');
    expect(drafts['yt1']!.caption, 'ข้อความเฉพาะตอนแรก');
    expect(persisted.items[0].usesSharedCaption, isFalse);
    expect(generations, 1);
    expect(submitted, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('context-only editor changes are saved exactly once on Back',
      (tester) async {
    late VoidCallback contextChanged;
    await mount(tester,
        sharedEditor: (context, controller, onBusy, enabled, onContextChanged) {
      contextChanged = onContextChanged;
      return const Text('Shared caption context editor');
    });
    final screen = tester
        .widget<ClipGroupReviewScreen>(find.byType(ClipGroupReviewScreen));
    // Exercise Back with a real previous route, as the uploader opens this page.
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context)
                        .push<void>(MaterialPageRoute(builder: (_) => screen)),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(saved, 0, reason: 'Restoring an editor is not a context change');
    contextChanged();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(find.byType(ClipGroupReviewScreen), findsNothing);
    expect(persisted.sharedCaption, 'แคปชั่นหลัก');
    expect(submitted, 0);
  });

  testWidgets('returning a custom clip to shared caption requires confirmation',
      (tester) async {
    drafts['yt1'] = _draft('yt1', caption: 'เฉพาะตอนแรก');
    persisted = persisted.copyWith(items: [
      persisted.items[0].copyWith(usesSharedCaption: false),
      ...persisted.items.skip(1),
    ]);
    await mount(tester);
    await tap(tester, 'clip-group-inherit-yt1');
    await tap(tester, 'clip-group-inherit-cancel');
    expect(persisted.items[0].usesSharedCaption, isFalse);
    expect(drafts['yt1']!.caption, 'เฉพาะตอนแรก');
    expect(saved, 0);
    await tap(tester, 'clip-group-inherit-yt1');
    await tap(tester, 'clip-group-inherit-confirm');
    expect(persisted.items[0].usesSharedCaption, isTrue);
    expect(drafts['yt1']!.caption, persisted.sharedCaption);
  });

  testWidgets(
      'per-clip AI reuses the caption editor only on explicit selection',
      (tester) async {
    final sections = <ClipGroupEditSection>[];
    await mount(tester, edit: (draft, section) async {
      sections.add(section);
      expect(draft.id, 'yt1');
      expect(draft.videoPath, '/yt1.mp4');
      return draft;
    });
    expect(sections, isEmpty);
    await tap(tester, 'clip-group-edit-yt1');
    await tap(tester, 'clip-group-ai-yt1');
    expect(sections, [ClipGroupEditSection.caption]);
    expect(submitted, 0);
  });

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
    await reveal(tester, 'clip-group-shared-caption');
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
          .copyWith(usesSharedCaption: false)
          .copyWith(acceptedPostId: 'existing', acceptedPostStatus: 'QUEUED'),
      persisted.items[1].copyWith(usesSharedCaption: false),
      persisted.items[2]
    ]);
    await mount(tester);
    await reveal(tester, 'clip-group-edit-yt1');
    final first = find.byKey(const ValueKey('clip-group-edit-yt1'));
    expect(tester.widget<PopupMenuButton<ClipGroupEditSection>>(first).enabled,
        isFalse);
    expect(find.byKey(const ValueKey('clip-group-inherit-yt1')), findsNothing);
    expect(find.byKey(const ValueKey('clip-group-inherit-yt2')), findsNothing);
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
  testWidgets('saved parent draft cache updates lock unresolved members',
      (tester) async {
    await mount(tester);
    drafts['yt1'] = _draft('yt1', receipt: true);
    await tap(tester, 'clip-group-save');
    await reveal(tester, 'clip-group-edit-yt1');
    expect(
        tester
            .widget<PopupMenuButton<ClipGroupEditSection>>(
                find.byKey(const ValueKey('clip-group-edit-yt1')))
            .enabled,
        isFalse);
  });
  testWidgets('partial submission refreshes receipts before reviewing the rest',
      (tester) async {
    await mount(tester, submit: (group) async {
      drafts['yt1'] = _draft('yt1', receipt: true);
      persisted = group.copyWith(items: [
        group.items[0],
        group.items[1]
            .copyWith(acceptedPostId: 'post-yt2', acceptedPostStatus: 'QUEUED'),
        group.items[2]
            .copyWith(acceptedPostId: 'post-ig', acceptedPostStatus: 'QUEUED'),
      ]);
      return ClipGroupSubmissionResult(
          group: persisted, completed: 2, remaining: 1);
    });
    await tap(tester, 'clip-group-next');
    await tap(tester, 'clip-group-next');
    await tap(tester, 'clip-group-confirm');
    await tester.tap(find.text('ตรวจรายการที่เหลือ'));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจรายการเดิมและส่งส่วนที่เหลือ'), findsOneWidget);
    expect(find.text('ยืนยันส่ง 1 รายการ'), findsNothing);
  });
  testWidgets(
      'save retries use the committed revision after a member save fails',
      (tester) async {
    final revisions = <int>[];
    await mount(tester, saveGroup: (proposed) async {
      revisions.add(proposed.revision);
      if (proposed.revision != persisted.revision) {
        throw StateError('revision conflict');
      }
      persisted = proposed.copyWith(revision: persisted.revision + 1);
      if (revisions.length == 1) throw StateError('member copy failed');
      return persisted;
    });
    await tester.enterText(
        find.byKey(const ValueKey('clip-group-shared-caption')),
        'ข้อความที่ต้องเก็บไว้เพื่อลองบันทึกอีกครั้ง');
    await tap(tester, 'clip-group-save');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('clip-group-shared-caption')))
            .controller!
            .text,
        'ข้อความที่ต้องเก็บไว้เพื่อลองบันทึกอีกครั้ง');
    await tap(tester, 'clip-group-save');
    expect(revisions, [0, 1]);
    expect(persisted.revision, 2);
    expect(
        persisted.sharedCaption, 'ข้อความที่ต้องเก็บไว้เพื่อลองบันทึกอีกครั้ง');
  });
  testWidgets(
      'English partial result explains a known failure without raw errors',
      (tester) async {
    await mount(tester,
        english: true,
        submit: (group) async => ClipGroupSubmissionResult(
            group: group,
            completed: 0,
            remaining: 3,
            error: const ClipGroupDraftException(
                'หน่วยโพสต์ไม่พอสำหรับรายการที่เหลือ')));
    await tap(tester, 'clip-group-next');
    await tap(tester, 'clip-group-next');
    await tap(tester, 'clip-group-confirm');
    await tester.fling(find.byKey(const ValueKey('clip-group-scroll')),
        const Offset(0, -2000), 5000);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Not enough post units for the remaining items.'),
        findsOneWidget);
    expect(find.textContaining('หน่วยโพสต์ไม่พอ'), findsNothing);
    final context = tester.element(find.byType(ClipGroupReviewScreen));
    expect(clipGroupErrorText(context, StateError('private implementation')),
        'Could not complete this set. Check existing submissions before retrying.');
    expect(
        clipGroupErrorText(
            context, const ClipGroupDraftException('ข้อความที่ยังไม่มีคำแปล')),
        'Could not complete this set. Check existing submissions before retrying.');
    expect(
        clipGroupErrorText(
            context,
            const PublishDraftValidationException(
                'ร่างนี้เคยเริ่มส่งแล้ว กรุณาตรวจผลรายการเดิมก่อนแก้ไข')),
        'This draft already started submitting. Check its existing request before editing.');
    expect(
        clipGroupErrorText(context,
            const ApiException('private provider response', statusCode: 503)),
        'PostDee is temporarily unavailable. Please try again later.');
    for (final problem in ClipGroupSubmissionProblem.values) {
      final message =
          clipGroupErrorText(context, ClipGroupSubmissionException(problem));
      expect(message, isNot(contains('Exception')));
      expect(RegExp(r'[\u0E00-\u0E7F]').hasMatch(message), isFalse);
    }
  });
  testWidgets('failed member editor reloads its committed group revision',
      (tester) async {
    final revisions = <int>[];
    await mount(tester, saveGroup: (proposed) async {
      revisions.add(proposed.revision);
      if (proposed.revision != persisted.revision) {
        throw StateError('revision conflict');
      }
      persisted = proposed.copyWith(revision: persisted.revision + 1);
      return persisted;
    }, edit: (draft, section) async {
      persisted = persisted.copyWith(revision: persisted.revision + 1);
      throw StateError('member save failed after group metadata');
    });
    await tap(tester, 'clip-group-edit-yt1');
    await tester.tap(find.text('ตั้งค่าช่องทาง'));
    await tester.pumpAndSettle();
    await tap(tester, 'clip-group-save');
    expect(revisions, [0, 2]);
    expect(persisted.revision, 3);
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
