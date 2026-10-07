import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_publish_draft_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, {TestPublishDraftStore? store}) async {
    final directory = Directory.systemTemp.createTempSync('postdee-wizard-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final video = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      fullScreen: true,
      draftStore: store ?? TestPublishDraftStore(),
      loadSocialConnections: () async => const [],
      pickVideo: () async => PickedVideoFile(
          name: 'clip.mp4',
          path: video.path,
          sizeBytes: 3,
          width: 1080,
          height: 1920),
    ))));
    await tester.pumpAndSettle();
  }

  Future<void> step(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(ValueKey('uploader-progress-$index')));
    await tester.pumpAndSettle();
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
    expect(
        find.byKey(const ValueKey('uploader-ai-caption-panel')), findsNothing);
  });

  testWidgets('navigation keeps caption and does not upload or post',
      (tester) async {
    var uploads = 0;
    var posts = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      draftStore: TestPublishDraftStore(),
      loadSocialConnections: () async => const [],
      createUpload: (_) async {
        uploads++;
        throw StateError('must not upload');
      },
      createPost: (_) async {
        posts++;
        throw StateError('must not post');
      },
    ))));
    await tester.pumpAndSettle();
    await step(tester, 1);
    await tester.enterText(
        find.byKey(const ValueKey('uploader-caption-field')), 'แคปชันเดิม');
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
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: UploaderScreen(
                draftStore: TestPublishDraftStore(),
                loadSocialConnections: () async => const []))));
    await tester.pumpAndSettle();
    for (var index = 0; index < 4; index++) {
      await step(tester, index);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('uploader-sticky-post-button')),
          findsOneWidget);
    }
  });
}
