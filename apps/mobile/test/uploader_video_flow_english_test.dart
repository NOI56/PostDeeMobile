import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'uploader_video_english_test.dart';

PublishDraft _savedVideo(PickedVideoFile video,
        {String id = 'saved-video', String caption = 'แคปชันที่ลูกค้าเขียน'}) =>
    PublishDraft(
      version: publishDraftManifestVersion,
      id: id,
      ownerUserId: videoEnglishOwner,
      submissionRequestId: 'submit_${List.filled(64, 'a').join()}',
      createdAt: DateTime.utc(2026, 10, 29),
      updatedAt: DateTime.utc(2026, 10, 29),
      videoPath: video.path,
      videoName: video.name,
      videoSizeBytes: video.sizeBytes,
      videoWidth: video.width,
      videoHeight: video.height,
      caption: caption,
      aiGuidance: 'ใช้คำแนะนำเดิมของลูกค้า',
      watermarkEnabled: false,
      platformApiValues: const {},
    );

Future<void> _mountVideoFlow(
    WidgetTester tester, VideoEnglishFixture fixture,
    {Size size = const Size(430, 900)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await fixture.mount(tester);
}

Future<void> _dialogAction(WidgetTester tester, String label) async {
  final action = find.descendant(
      of: find.byType(AlertDialog), matching: find.text(label));
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _dismissDraftSheet(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('Drafts on this device'))).pop();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: videoEnglishOwner, idToken: 'fake-token'));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('saving the chosen video writes one local draft with raw data',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('บันทึกร่าง.mp4');
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    await tapVideoEnglishControl(tester, 'uploader-save-draft-button');

    expect(fixture.store.saveAttempts, 1);
    expect(fixture.store.savedRequests, hasLength(1));
    final saved = fixture.store.drafts.values.single;
    expect(saved.videoName, 'บันทึกร่าง.mp4');
    expect(saved.videoPath, fixture.picked!.path);
    expect(saved.caption, isEmpty);
    expect(saved.platformApiValues, isEmpty);
    expect(find.byKey(const ValueKey('uploader-draft-saved-indicator')),
        findsOneWidget);
    expect(find.text('บันทึกร่าง.mp4'), findsOneWidget);
    expect(
        find.text('Draft saved on this device · Nothing uploaded or posted, '
            'and no quota used.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty Save draft validation follows locale without a write',
      (tester) async {
    final fixture = VideoEnglishFixture();
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-save-draft-button');
    expect(
        find.text('Choose a video from this device before saving a draft.'),
        findsOneWidget);
    final reads = fixture.quotaReads;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('เลือกวิดีโอจากเครื่องก่อนบันทึกร่าง'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text('Choose a video from this device before saving a draft.'),
        findsOneWidget);
    expect(fixture.store.saveAttempts, 0);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.quotaReads, reads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save and exit saves a selected video once and closes the route',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('คลิปก่อนออก.mp4');
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    await tapVideoEnglishControl(tester, 'uploader-close');
    expect(find.text('Keep this post?'), findsOneWidget);
    await _dialogAction(tester, 'Save and exit');

    expect(find.byType(UploaderScreen), findsNothing);
    expect(find.text('Uploader test home'), findsOneWidget);
    expect(fixture.store.saveAttempts, 1);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.store.drafts.values.single.videoName, 'คลิปก่อนออก.mp4');
    expect(fixture.store.drafts.values.single.videoPath, fixture.picked!.path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an open exit dialog changes locale and Keep editing keeps video',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('คลิปที่ต้องเก็บ.mp4');
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    await tapVideoEnglishControl(tester, 'uploader-close');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('เก็บโพสต์นี้ไว้ไหม?'), findsOneWidget);
    expect(find.text('บันทึกแล้วออก'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Keep this post?'), findsOneWidget);
    await _dialogAction(tester, 'Keep editing');

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(UploaderScreen), findsOneWidget);
    expect(find.text('คลิปที่ต้องเก็บ.mp4'), findsOneWidget);
    expect(fixture.picks, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Leave without saving preserves the previously stored draft',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final original = fixture.makeVideo('คลิปเดิม.mp4');
    final saved = _savedVideo(original);
    fixture.store.drafts[saved.id] = saved;
    fixture.initialDraftId = saved.id;
    fixture.picked = fixture.makeVideo('คลิปใหม่ที่ยังไม่บันทึก.mp4');
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    await tapVideoEnglishControl(tester, 'uploader-close');
    await _dialogAction(tester, 'Leave without saving');

    expect(find.byType(UploaderScreen), findsNothing);
    expect(fixture.store.drafts[saved.id], same(saved));
    expect(saved.videoName, original.name);
    expect(saved.caption, 'แคปชันที่ลูกค้าเขียน');
    expect(saved.aiGuidance, 'ใช้คำแนะนำเดิมของลูกค้า');
    expect(File(original.path).existsSync(), isTrue);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.store.deletes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unchanged restored draft closes without another save prompt',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final saved = _savedVideo(fixture.makeVideo('ร้านของฉัน.mp4'));
    fixture.store.drafts[saved.id] = saved;
    fixture.initialDraftId = saved.id;
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    expect(find.text('Draft opened'), findsOneWidget);
    await tapVideoEnglishControl(tester, 'uploader-close');

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(UploaderScreen), findsNothing);
    expect(fixture.store.loads, 1);
    expect(fixture.store.drafts[saved.id], same(saved));
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed Save and exit stays open and retries without losing video',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('คลิปพื้นที่ไม่พอ.mp4');
    fixture.store.saveError = const FileSystemException('fake disk full');
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    await tapVideoEnglishControl(tester, 'uploader-close');
    await _dialogAction(tester, 'Save and exit');
    expect(find.byType(UploaderScreen), findsOneWidget);
    expect(
        find.text('Could not save the draft. '
            'Check the free space on this device.'),
        findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('บันทึกร่างไม่สำเร็จ ตรวจสอบพื้นที่ว่างในเครื่อง'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('คลิปพื้นที่ไม่พอ.mp4'), findsOneWidget);
    expect(fixture.store.saveAttempts, 1);
    expect(fixture.store.savedRequests, isEmpty);

    fixture.store.saveError = null;
    await tapVideoEnglishControl(tester, 'uploader-close');
    await _dialogAction(tester, 'Save and exit');
    expect(find.byType(UploaderScreen), findsNothing);
    expect(fixture.store.saveAttempts, 2);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.store.drafts.values.single.videoName, fixture.picked!.name);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending local save follows locale and does not dispatch twice',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('กำลังบันทึก.mp4');
    final save = Completer<void>();
    fixture.store.saveGate = save;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!save.isCompleted) save.complete();
    });
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    await tapVideoEnglishControl(tester, 'uploader-save-draft-button');
    expect(find.text('Saving...'), findsOneWidget);
    expect(fixture.store.saveAttempts, 1);
    expect(fixture.store.savedRequests, isEmpty);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กำลังบันทึก...'), findsOneWidget);
    final saveButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('uploader-save-draft-button')));
    expect(saveButton.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('uploader-save-draft-button')));
    await tester.pump();
    expect(fixture.store.saveAttempts, 1);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    save.complete();
    await tester.pumpAndSettle();

    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.store.drafts.values.single.videoName, 'กำลังบันทึก.mp4');
    expect(find.byKey(const ValueKey('uploader-draft-saved-indicator')),
        findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late injected-store save cannot show saved feedback for new owner',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('คลิปเจ้าของเดิม.mp4');
    final save = Completer<void>();
    fixture.store.saveGate = save;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!save.isCompleted) save.complete();
    });
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    await tapVideoEnglishControl(tester, 'uploader-save-draft-button');
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'replacement-owner', idToken: 'new-token'));
    save.complete();
    await tester.pumpAndSettle();

    // Injected stores intentionally bypass the production disk-owner guard.
    // The existing UI feedback still belongs only to the initiating owner.
    expect(fixture.store.saveAttempts, 1);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(find.byKey(const ValueKey('uploader-draft-saved-indicator')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft picker translates metadata while raw customer titles stay',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final first = _savedVideo(fixture.makeVideo('ไฟล์แรก.mp4'),
        id: 'first-video', caption: 'บันทึกร่าง');
    final second = _savedVideo(fixture.makeVideo('เลือกคลิป'),
        id: 'second-video', caption: '');
    fixture.store.drafts.addAll({first.id: first, second.id: second});
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-open-drafts');
    expect(find.text('Drafts on this device'), findsOneWidget);
    expect(find.text('บันทึกร่าง'), findsOneWidget);
    expect(find.text('เลือกคลิป'), findsOneWidget);
    expect(find.text('0 channels · Stored on this device'), findsNWidgets(2));
    final lists = fixture.store.lists;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ฉบับร่างในเครื่อง'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('บันทึกร่าง'), findsOneWidget);
    expect(find.text('เลือกคลิป'), findsOneWidget);
    expect(fixture.store.lists, lists);
    expect(fixture.store.drafts[first.id], same(first));
    expect(fixture.store.drafts[second.id], same(second));
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.store.deletes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel in a live-localized Delete draft dialog keeps the draft',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final saved = _savedVideo(fixture.makeVideo('ยังไม่ลบ.mp4'));
    fixture.store.drafts[saved.id] = saved;
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-open-drafts');
    await tapVideoEnglishControl(tester, 'publish-draft-delete-${saved.id}');
    expect(find.text('Delete this draft?'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ลบฉบับร่างนี้?'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await _dialogAction(tester, 'Cancel');

    expect(fixture.store.deletes, 0);
    expect(fixture.store.drafts[saved.id], same(saved));
    expect(find.byKey(ValueKey('publish-draft-${saved.id}')), findsOneWidget);
    expect(File(saved.videoPath).existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fake delete removes only its active draft and resets selection',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final active = _savedVideo(fixture.makeVideo('ร่างที่ลบ.mp4'));
    final other = _savedVideo(fixture.makeVideo('ร่างที่ยังอยู่.mp4'),
        id: 'another-video');
    fixture.store.drafts.addAll({active.id: active, other.id: other});
    fixture.initialDraftId = active.id;
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-open-drafts');
    await tapVideoEnglishControl(tester, 'publish-draft-delete-${active.id}');
    await tapVideoEnglishControl(tester, 'publish-draft-delete-confirm');

    expect(fixture.store.deletes, 1);
    expect(fixture.store.drafts.keys, [other.id]);
    expect(fixture.store.drafts[other.id], same(other));
    expect(find.byKey(ValueKey('publish-draft-${active.id}')), findsNothing);
    await _dismissDraftSheet(tester);
    expect(find.text('Draft deleted'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-video-preview-picker')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-video-preview-open')),
        findsNothing);
    expect(fixture.store.savedRequests, isEmpty);
    // The fake store never deletes actual files or calls a remote API.
    expect(File(active.videoPath).existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fake delete failure retains the draft and translates on render',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final saved = _savedVideo(fixture.makeVideo('ลบไม่สำเร็จ.mp4'));
    fixture.store.drafts[saved.id] = saved;
    fixture.store.deleteError = const FileSystemException('fake delete failure');
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    await tapVideoEnglishControl(tester, 'uploader-open-drafts');
    await tapVideoEnglishControl(tester, 'publish-draft-delete-${saved.id}');
    await tapVideoEnglishControl(tester, 'publish-draft-delete-confirm');
    expect(find.byKey(ValueKey('publish-draft-${saved.id}')), findsOneWidget);
    await _dismissDraftSheet(tester);
    expect(find.text('Could not delete the draft.'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ลบฉบับร่างไม่สำเร็จ'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not delete the draft.'), findsOneWidget);
    expect(fixture.store.deletes, 1);
    expect(fixture.store.drafts[saved.id], same(saved));
    expect(File(saved.videoPath).existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing initial draft leaves English draft controls available',
      (tester) async {
    final fixture = VideoEnglishFixture()..initialDraftId = 'removed-draft';
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    expect(
        find.text('This draft could not be opened. It may have been deleted. '
            'Choose another draft or create a new post.'),
        findsOneWidget);
    expect(fixture.store.loads, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.metadataReads, isEmpty);
    final openDrafts = tester.widget<TextButton>(
        find.byKey(const ValueKey('uploader-open-drafts')));
    expect(openDrafts.onPressed, isNotNull);
    await tapVideoEnglishControl(tester, 'uploader-open-drafts');
    expect(find.text('No drafts on this device yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing draft video is not replaced with fabricated selection',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final video = fixture.makeVideo('วิดีโอที่หายไป.mp4');
    final saved = _savedVideo(video);
    fixture.store.drafts[saved.id] = saved;
    fixture.initialDraftId = saved.id;
    File(video.path).deleteSync();
    addTearDown(fixture.dispose);
    await _mountVideoFlow(tester, fixture);
    expect(find.text("This draft's video could not be found on this device."),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-video-preview-open')),
        findsNothing);
    expect(find.text('Choose a video first'), findsOneWidget);
    expect(fixture.store.drafts[saved.id], same(saved));
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.metadataReads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending draft restoration follows locale and keeps raw fields',
      (tester) async {
    final fixture = VideoEnglishFixture(locale: const Locale('th'));
    final saved = _savedVideo(fixture.makeVideo('เลือกคลิป'), caption: 'บันทึกร่าง');
    fixture.store.drafts[saved.id] = saved;
    fixture.initialDraftId = saved.id;
    final load = Completer<PublishDraft?>();
    fixture.store.loadGate = load.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!load.isCompleted) load.complete(null);
    });
    await _mountVideoFlow(tester, fixture);
    expect(find.text('กำลังเปิดฉบับร่าง...'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Opening draft...'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-video-preview-open')),
        findsNothing);
    load.complete(saved);
    await tester.pumpAndSettle();

    expect(find.text('Draft opened'), findsOneWidget);
    expect(find.text('เลือกคลิป'), findsOneWidget);
    expect(fixture.store.loads, 1);
    expect(fixture.store.drafts[saved.id], same(saved));
    expect(saved.caption, 'บันทึกร่าง');
    expect(saved.aiGuidance, 'ใช้คำแนะนำเดิมของลูกค้า');
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late initial draft cannot restore after the owner changes',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final saved = _savedVideo(fixture.makeVideo('คลิปบัญชีก่อนหน้า.mp4'));
    fixture.initialDraftId = saved.id;
    final load = Completer<PublishDraft?>();
    fixture.store.loadGate = load.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!load.isCompleted) load.complete(null);
    });
    await _mountVideoFlow(tester, fixture);
    expect(find.text('Opening draft...'), findsOneWidget);
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'replacement-owner', idToken: 'new-token'));
    load.complete(saved);
    await tester.pumpAndSettle();

    expect(find.text('Your account has changed. Please reopen Drafts.'),
        findsOneWidget);
    expect(find.text('คลิปบัญชีก่อนหน้า.mp4'), findsNothing);
    expect(find.byKey(const ValueKey('uploader-video-preview-open')),
        findsNothing);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.metadataReads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late initial draft after disposal cannot reopen the uploader',
      (tester) async {
    final fixture = VideoEnglishFixture();
    final saved = _savedVideo(fixture.makeVideo('คลิปหน้าที่ปิดแล้ว.mp4'));
    fixture.initialDraftId = saved.id;
    final load = Completer<PublishDraft?>();
    fixture.store.loadGate = load.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!load.isCompleted) load.complete(null);
    });
    await _mountVideoFlow(tester, fixture);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    load.complete(saved);
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen), findsNothing);
    expect(find.text('คลิปหน้าที่ปิดแล้ว.mp4'), findsNothing);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.metadataReads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'populated draft picker and Delete cancel fit 320dp 2x (dark=$dark)',
        (tester) async {
      final fixture = VideoEnglishFixture(dark: dark, scale: 2);
      final saved =
          _savedVideo(fixture.makeVideo('สินค้า.mp4'), caption: 'ร้าน');
      fixture.store.drafts[saved.id] = saved;
      addTearDown(fixture.dispose);
      await _mountVideoFlow(tester, fixture, size: const Size(320, 740));
      await tapVideoEnglishControl(tester, 'uploader-open-drafts');
      for (final label in [
        'Drafts on this device',
        'Not uploaded, not sent to platforms, and no quota used.',
        'The app copies your video and cover into app storage on this device. '
            'Drafts do not sync across devices and may be included in system backups.',
        'ร้าน',
        '0 channels · Stored on this device',
      ]) {
        await revealVideoEnglishControl(tester, find.text(label));
        expectVideoEnglishReadable(tester, find.text(label));
        expect(find.text(label).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final delete =
          find.byKey(ValueKey('publish-draft-delete-${saved.id}'));
      await revealVideoEnglishControl(tester, delete);
      expect(delete.hitTestable(), findsOneWidget);
      await tapVideoEnglishControl(
          tester, 'publish-draft-delete-${saved.id}');

      for (final label in [
        'Delete this draft?',
        'The video and cover stored with this draft will be deleted from app storage.',
        'Cancel',
        'Delete draft',
      ]) {
        await revealVideoEnglishControl(tester, find.text(label));
        expectVideoEnglishReadable(tester, find.text(label));
        expect(find.text(label).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final confirm =
          find.byKey(const ValueKey('publish-draft-delete-confirm'));
      expect(confirm.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await _dialogAction(tester, 'Cancel');

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(ValueKey('publish-draft-${saved.id}')), findsOneWidget);
      expect(fixture.store.deletes, 0);
      expect(fixture.store.drafts[saved.id], same(saved));
      expect(fixture.store.savedRequests, isEmpty);
      expect(File(saved.videoPath).existsSync(), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
