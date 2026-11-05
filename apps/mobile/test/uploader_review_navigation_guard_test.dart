import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, {bool withClip = true}) async {
    final directory = Directory.systemTemp.createTempSync('review-guard-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final clip = File('${directory.path}/clip.mp4')..writeAsBytesSync([1]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      fullScreen: true,
      draftStore: TestPublishDraftStore(),
      initialVideoPath: withClip ? clip.path : null,
      initialVideoName: 'clip.mp4',
      initialVideoWidth: 1080,
      initialVideoHeight: 1920,
      initialVideoSizeBytes: 1,
      loadTemplates: () async => const [],
      loadSocialConnections: () async => const [],
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      loadPostQuota: () async => const SubscriptionStatusResult(
          userId: 'test-user',
          plan: 'BASIC',
          status: 'INACTIVE',
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false),
      createUpload: (_) async => throw StateError('navigation must not upload'),
      createPost: (_) async => throw StateError('navigation must not publish'),
    ))));
    await tester.pumpAndSettle();
  }

  Future<void> step(WidgetTester tester, int index) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final control = find.byKey(ValueKey('uploader-progress-$index'));
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  testWidgets('review shortcut reveals missing clip instead of an empty review',
      (tester) async {
    await open(tester, withClip: false);
    await step(tester, 3);
    expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
    expect(find.text('เลือกวิดีโอจากเครื่องก่อน'), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-review-confirm')), findsNothing);
  });

  testWidgets('review shortcut focuses caption before checking destinations',
      (tester) async {
    await open(tester);
    await step(tester, 3);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-caption-field')))
            .focusNode!
            .hasFocus,
        isTrue);
    expect(find.text('เพิ่มแคปชันก่อนไปต่อ'), findsOneWidget);
  });

  testWidgets('review shortcut and Next enforce the same channel validation',
      (tester) async {
    await open(tester);
    await step(tester, 1);
    await tester.enterText(find.byKey(const ValueKey('uploader-caption-field')),
        'ข้อความที่ต้องเก็บไว้');
    await step(tester, 2);
    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมและเลือกอย่างน้อย 1 ช่องทางก่อน'), findsOneWidget);
    await step(tester, 3);
    expect(
        find.byKey(const ValueKey('uploader-step-platforms')), findsOneWidget);
    expect(find.text('เชื่อมและเลือกอย่างน้อย 1 ช่องทางก่อน'), findsOneWidget);
    await step(tester, 1);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-caption-field')))
            .controller!
            .text,
        'ข้อความที่ต้องเก็บไว้');
    expect(tester.takeException(), isNull);
  });
}
