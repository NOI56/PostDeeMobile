import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _stepNames = ['เลือกคลิป', 'เขียนแคปชัน', 'เลือกช่องทาง', 'ตรวจทาน'];
const _stepKeys = [
  'uploader-step-video',
  'uploader-step-caption',
  'uploader-step-platforms',
  'uploader-step-review',
];
const _nextLabels = [
  'ถัดไป: เขียนแคปชัน',
  'ถัดไป: เลือกช่องทาง',
  'ถัดไป: ตรวจทาน',
];

String _stepLabel(int index) =>
    'ขั้นตอนที่ ${index + 1} จาก 4 · ${_stepNames[index]}';

class _SubmissionCalls {
  var readiness = 0;
  var uploads = 0;
  var posts = 0;

  void expectNoSubmission() {
    expect(readiness, 0);
    expect(uploads, 0);
    expect(posts, 0);
  }
}

Future<_SubmissionCalls> _openWizard(
  WidgetTester tester, {
  bool hasAccountIdentity = true,
  double textScale = 1,
}) async {
  final directory = Directory.systemTemp.createTempSync('postdee-nav-cues-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final video = File('${directory.path}${Platform.pathSeparator}seller.mp4')
    ..writeAsBytesSync(List<int>.filled(64, 1));
  final calls = _SubmissionCalls();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: UploaderScreen(
          fullScreen: true,
          draftStore: TestPublishDraftStore(),
          loadSocialConnections: () async => [
            SocialConnectionResult(
              platform: 'TIKTOK',
              connected: true,
              externalAccountId: hasAccountIdentity ? 'seller-tiktok' : null,
            ),
          ],
          pickVideo: () async => PickedVideoFile(
            name: 'seller.mp4',
            path: video.path,
            sizeBytes: video.lengthSync(),
            width: 1080,
            height: 1920,
          ),
          checkPublishingReadiness: () async {
            calls.readiness += 1;
            throw StateError('navigation must not prepare publishing');
          },
          createUpload: (_) async {
            calls.uploads += 1;
            throw StateError('navigation must not upload');
          },
          createPost: (_) async {
            calls.posts += 1;
            throw StateError('navigation must not publish');
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

Future<void> _pickVideo(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('uploader-video-preview-picker')));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
  await tester.pumpAndSettle();
}

Future<void> _selectTikTok(WidgetTester tester) async {
  final channel = find.byKey(const ValueKey('uploader-platform-TIKTOK'));
  await tester.scrollUntilVisible(
    channel,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(channel);
  await tester.pumpAndSettle();
  await tester.tap(channel);
  await tester.pumpAndSettle();
}

void _expectCompleted(Set<int> completed) {
  for (var index = 0; index < 4; index += 1) {
    final indicator = find.byKey(ValueKey('uploader-progress-complete-$index'));
    expect(
        indicator, completed.contains(index) ? findsOneWidget : findsNothing);
  }
}

void _expectProgressSemantics(
  WidgetTester tester, {
  required int currentStep,
  required Set<int> completed,
}) {
  for (var index = 0; index < 4; index += 1) {
    final node = tester.getSemantics(
      find.byKey(ValueKey('uploader-progress-$index')),
    );
    expect(
      node.label,
      '${_stepLabel(index)}${completed.contains(index) ? ' เสร็จแล้ว' : ''}',
    );
    expect(
      node,
      isSemantics(
        isButton: true,
        hasTapAction: true,
        isSelected: index == currentStep,
      ),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('names the current stage and the next destination in every stage',
      (tester) async {
    final calls = await _openWizard(tester);
    for (var index = 0; index < 4; index += 1) {
      await goToUploaderStep(tester, index);
      expect(find.text(_stepLabel(index)), findsOneWidget);
      if (index < 3) {
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('uploader-wizard-next')),
            matching: find.text(_nextLabels[index]),
          ),
          findsOneWidget,
        );
        expect(
            find.byKey(const ValueKey('publish-review-confirm')), findsNothing);
      } else {
        expect(
            find.byKey(const ValueKey('uploader-wizard-next')), findsNothing);
        expect(find.byKey(const ValueKey('publish-review-confirm')),
            findsOneWidget);
      }
    }
    calls.expectNoSubmission();
  });

  testWidgets(
      'skipping to review leaves empty stages incomplete and announces selection',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final calls = await _openWizard(tester);
      await goToUploaderStep(tester, 3);
      _expectCompleted({});
      _expectProgressSemantics(tester, currentStep: 3, completed: {});
      calls.expectNoSubmission();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'completed checks follow valid work and back keeps the clip caption and channel',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final calls = await _openWizard(tester);
      await _pickVideo(tester);
      await _next(tester);
      _expectCompleted({0});
      await tester.enterText(
        find.byKey(const ValueKey('uploader-caption-field')),
        'แคปชันที่เก็บไว้',
      );
      await _next(tester);
      _expectCompleted({0, 1});
      await _selectTikTok(tester);
      await _next(tester);
      _expectCompleted({0, 1, 2});
      _expectProgressSemantics(tester, currentStep: 3, completed: {0, 1, 2});

      await tester.tap(find.byKey(const ValueKey('uploader-wizard-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('uploader-platform-settings-TIKTOK')),
        findsOneWidget,
      );
      _expectCompleted({0, 1});
      await tester.tap(find.byKey(const ValueKey('uploader-wizard-back')));
      await tester.pumpAndSettle();
      final caption = tester.widget<TextField>(
        find.byKey(const ValueKey('uploader-caption-field')),
      );
      expect(caption.controller!.text, 'แคปชันที่เก็บไว้');
      _expectCompleted({0});
      await tester.tap(find.byKey(const ValueKey('uploader-wizard-back')));
      await tester.pumpAndSettle();
      expect(find.text('seller.mp4'), findsOneWidget);
      _expectCompleted({});
      calls.expectNoSubmission();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'clearing a previous caption removes its check without clearing other work',
      (tester) async {
    final calls = await _openWizard(tester);
    await _pickVideo(tester);
    await goToUploaderStep(tester, 1);
    await tester.enterText(
      find.byKey(const ValueKey('uploader-caption-field')),
      'ข้อความเดิม',
    );
    await goToUploaderStep(tester, 2);
    await _selectTikTok(tester);
    await goToUploaderStep(tester, 3);
    _expectCompleted({0, 1, 2});
    await goToUploaderStep(tester, 1);
    await tester.enterText(
      find.byKey(const ValueKey('uploader-caption-field')),
      '  \n  ',
    );
    await goToUploaderStep(tester, 3);
    _expectCompleted({0, 2});
    calls.expectNoSubmission();
  });

  testWidgets(
      'a selected destination without account identity stays incomplete',
      (tester) async {
    final calls = await _openWizard(tester, hasAccountIdentity: false);
    await _pickVideo(tester);
    await goToUploaderStep(tester, 1);
    await tester.enterText(
      find.byKey(const ValueKey('uploader-caption-field')),
      'พร้อมเขียนแคปชัน',
    );
    await goToUploaderStep(tester, 2);
    await _selectTikTok(tester);
    await goToUploaderStep(tester, 3);
    _expectCompleted({0, 1});
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('publish-review-confirm')),
          )
          .onPressed,
      isNull,
    );
    calls.expectNoSubmission();
  });

  testWidgets(
      '320dp at 200 percent text keeps all new headers and action labels usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = await _openWizard(tester, textScale: 2);
    for (var index = 0; index < 4; index += 1) {
      await goToUploaderStep(tester, index);
      expect(tester.takeException(), isNull);
      final header = find.byKey(ValueKey(_stepKeys[index]));
      expect(find.text(_stepLabel(index)), findsOneWidget);
      final headerRect = tester.getRect(header);
      expect(headerRect.left, greaterThanOrEqualTo(0));
      expect(headerRect.right, lessThanOrEqualTo(320));
      final action = find.byKey(ValueKey(
        index < 3 ? 'uploader-wizard-next' : 'publish-review-confirm',
      ));
      final actionRect = tester.getRect(action);
      expect(actionRect.left, greaterThanOrEqualTo(0));
      expect(actionRect.right, lessThanOrEqualTo(320));
      expect(actionRect.bottom, lessThanOrEqualTo(900));
      if (index < 3) {
        expect(
          find.descendant(of: action, matching: find.text(_nextLabels[index])),
          findsOneWidget,
        );
      }
    }
    calls.expectNoSubmission();
  });
}
