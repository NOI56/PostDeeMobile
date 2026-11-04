import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart' show uploaderMainScroll;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester,
      {TestPublishDraftStore? store,
      bool fullScreen = true,
      double textScale = 1,
      VoidCallback? onUpload,
      VoidCallback? onPost}) async {
    final directory = Directory.systemTemp.createTempSync('postdee-wizard-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final video = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(
            body: UploaderScreen(
          probePublishMedia: probeValidPublishMedia,
          loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
          fullScreen: fullScreen,
          draftStore: store ?? TestPublishDraftStore(),
          loadSocialConnections: () async => const [
            SocialConnectionResult(
                platform: 'TIKTOK',
                connected: true,
                externalAccountId: 'wizard-tiktok')
          ],
          pickVideo: () async => PickedVideoFile(
              name: 'clip.mp4',
              path: video.path,
              sizeBytes: 3,
              width: 1080,
              height: 1920),
          createUpload: (_) async {
            onUpload?.call();
            throw StateError('Navigation must not upload');
          },
          createPost: (_) async {
            onPost?.call();
            throw StateError('Navigation must not publish');
          },
        ))));
    await tester.pumpAndSettle();
  }

  Future<void> step(WidgetTester tester, int index) async {
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final progress = find.byKey(ValueKey('uploader-progress-$index'));
    await tester.ensureVisible(progress);
    await tester.tap(progress);
    await tester.pumpAndSettle();
  }

  Future<void> prepareReview(WidgetTester tester, String caption) async {
    await step(tester, 0);
    final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
    if (picker.evaluate().isEmpty) {
      await tester.scrollUntilVisible(picker, 180,
          scrollable: uploaderMainScroll);
    }
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await step(tester, 1);
    final field = find.byKey(const ValueKey('uploader-caption-field'));
    if (field.evaluate().isEmpty) {
      await tester.scrollUntilVisible(field, 180,
          scrollable: uploaderMainScroll);
    }
    await tester.ensureVisible(field);
    await tester.enterText(field, caption);
    await step(tester, 2);
    final channel = find.byKey(const ValueKey('uploader-platform-TIKTOK'));
    await tester.scrollUntilVisible(channel, 180,
        scrollable: uploaderMainScroll);
    await tester.ensureVisible(channel);
    await tester.pumpAndSettle();
    await tester.tap(channel);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: channel, matching: find.byIcon(Icons.check_circle_rounded)),
        findsOneWidget);
  }

  testWidgets('only one stage is visible and next requires a local clip',
      (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-caption-field')), findsNothing);
    expect(find.byKey(const ValueKey('uploader-schedule-panel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
    expect(find.text('เลือกวิดีโอจากเครื่องก่อน'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('uploader-video-preview-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-step-caption')), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-ai-caption-panel')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('uploader-ai-guidance-field')), findsNothing);
  });

  testWidgets('navigation keeps caption and does not upload or post',
      (tester) async {
    var uploads = 0;
    var posts = 0;
    await open(tester,
        fullScreen: false, onUpload: () => uploads++, onPost: () => posts++);
    await prepareReview(tester, 'แคปชันเดิม');
    await step(tester, 3);
    expect(
        find.byKey(const ValueKey('publish-review-confirm')), findsOneWidget);
    await step(tester, 0);
    await step(tester, 1);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-caption-field')))
            .controller!
            .text,
        'แคปชันเดิม');
    expect(uploads, 0);
    expect(posts, 0);
  });

  testWidgets('back moves to prior stage without clearing work',
      (tester) async {
    await open(tester);
    await step(tester, 1);
    await tester.enterText(
        find.byKey(const ValueKey('uploader-caption-field')), 'เก็บข้อความนี้');
    await tester.tap(find.byKey(const ValueKey('uploader-wizard-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
    await step(tester, 1);
    expect(find.text('เก็บข้อความนี้'), findsOneWidget);
  });

  testWidgets('close asks about unsaved work and cancel keeps caption',
      (tester) async {
    await open(tester);
    await step(tester, 1);
    await tester.enterText(find.byKey(const ValueKey('uploader-caption-field')),
        'ยังไม่ได้บันทึก');
    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-exit-dialog')), findsOneWidget);
    await tester.tap(find.text('แก้ไขต่อ'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่ได้บันทึก'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-exit-dialog')), findsNothing);
  });

  testWidgets('320dp and large text keep every stage and action usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, fullScreen: false, textScale: 2);
    await prepareReview(tester, 'ข้อความตรวจทานบนหน้าจอเล็ก');
    for (var index = 0; index < 4; index++) {
      await step(tester, index);
      expect(tester.takeException(), isNull);
      if (index == 3) {
        expect(find.byKey(const ValueKey('publish-review-confirm')),
            findsOneWidget);
      }
      expect(find.byKey(const ValueKey('uploader-sticky-post-button')),
          findsOneWidget);
    }
  });
}
