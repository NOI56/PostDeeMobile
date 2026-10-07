import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

class _FailingDraftStore extends TestPublishDraftStore {
  bool failSave = true;
  int attempts = 0;

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    attempts++;
    if (failSave) throw const FileSystemException('No free disk space');
    return super.saveDraft(request);
  }
}

class _ExitFixture {
  _ExitFixture({TestPublishDraftStore? store})
      : store = store ?? TestPublishDraftStore() {
    final directory =
        Directory.systemTemp.createTempSync('postdee-wizard-exit-');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    video = File('${directory.path}${Platform.pathSeparator}draft-clip.mp4')
      ..writeAsBytesSync(List<int>.filled(512, 1));
  }

  late final File video;
  final TestPublishDraftStore store;
  int apiWrites = 0;

  Widget app() => MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: SafeArea(
                        child: UploaderScreen(
                          fullScreen: true,
                          draftStore: store,
                          loadSocialConnections: () async => const [],
                          createUpload: (_) async {
                            apiWrites++;
                            throw StateError('Draft exit must never upload');
                          },
                          uploadVideoFile: (_, __) async {
                            apiWrites++;
                          },
                          createPost: (_) async {
                            apiWrites++;
                            throw StateError('Draft exit must never publish');
                          },
                          generateRealClipCaption: (_) async {
                            apiWrites++;
                            throw StateError('Draft exit must never run AI');
                          },
                          initialVideoPath: video.path,
                          initialVideoName: 'draft-clip.mp4',
                          initialVideoSizeBytes: video.lengthSync(),
                          initialVideoWidth: 1080,
                          initialVideoHeight: 1920,
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('เปิดหน้าสร้างโพสต์'),
              ),
            ),
          ),
        ),
      );
}

Future<void> _open(WidgetTester tester, _ExitFixture fixture) async {
  await tester.pumpWidget(fixture.app());
  await tester.tap(find.text('เปิดหน้าสร้างโพสต์'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('uploader-close')), findsOneWidget);
}

Future<void> _enterCaption(WidgetTester tester, String caption) async {
  await goToUploaderStep(tester, 1);
  final field = find.byKey(const ValueKey('uploader-caption-field'));
  await tester.ensureVisible(field);
  await tester.enterText(field, caption);
  await tester.pumpAndSettle();
}

String _caption(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('uploader-caption-field')))
    .controller!
    .text;

Future<void> _closeDirty(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('uploader-close')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('uploader-exit-dialog')), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets(
      'save then exit preserves the clip and caption locally without API writes',
      (tester) async {
    final fixture = _ExitFixture();
    await _open(tester, fixture);
    await _enterCaption(tester, 'โพสต์ที่ยังทำไม่เสร็จ');
    await _closeDirty(tester);
    await tester.tap(find.text('บันทึกแล้วออก'));
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen), findsNothing);
    expect(find.text('เปิดหน้าสร้างโพสต์'), findsOneWidget);
    expect(fixture.store.savedRequests, hasLength(1));
    final saved = fixture.store.drafts.values.single;
    expect(saved.caption, 'โพสต์ที่ยังทำไม่เสร็จ');
    expect(saved.videoPath, fixture.video.path);
    expect(File(saved.videoPath).existsSync(), isTrue);
    expect(fixture.apiWrites, 0);
  });

  testWidgets('cancel exit keeps the current caption and stays in the wizard',
      (tester) async {
    final fixture = _ExitFixture();
    await _open(tester, fixture);
    await _enterCaption(tester, 'ต้องการแก้ต่อ');
    await _closeDirty(tester);
    await tester.tap(find.text('แก้ไขต่อ'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('uploader-exit-dialog')), findsNothing);
    expect(find.byType(UploaderScreen), findsOneWidget);
    expect(_caption(tester), 'ต้องการแก้ต่อ');
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.apiWrites, 0);
  });

  testWidgets('discarding unsaved edits preserves the previous saved draft',
      (tester) async {
    final fixture = _ExitFixture();
    await _open(tester, fixture);
    await _enterCaption(tester, 'ข้อความร่างที่บันทึกไว้');
    await tester.tap(find.byKey(const ValueKey('uploader-save-draft-button')));
    await tester.pumpAndSettle();
    expect(fixture.store.savedRequests, hasLength(1));
    final savedId = fixture.store.drafts.keys.single;
    await _enterCaption(tester, 'แก้ใหม่แต่ยังไม่บันทึก');
    await _closeDirty(tester);
    await tester.tap(find.text('ออกโดยไม่บันทึก'));
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen), findsNothing);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.store.drafts[savedId]!.caption, 'ข้อความร่างที่บันทึกไว้');
    expect(fixture.apiWrites, 0);
  });

  testWidgets(
      'a draft save failure blocks exit and can be retried without losing text',
      (tester) async {
    final store = _FailingDraftStore();
    final fixture = _ExitFixture(store: store);
    await _open(tester, fixture);
    await _enterCaption(tester, 'ข้อความที่ต้องไม่หายเมื่อบันทึกพลาด');
    await _closeDirty(tester);
    await tester.tap(find.text('บันทึกแล้วออก'));
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-exit-dialog')), findsNothing);
    expect(_caption(tester), 'ข้อความที่ต้องไม่หายเมื่อบันทึกพลาด');
    await tester.drag(
        find.byKey(const ValueKey('uploader-scroll')), const Offset(0, 2500));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกร่างไม่สำเร็จ ตรวจสอบพื้นที่ว่างในเครื่อง'),
        findsOneWidget);
    expect(store.attempts, 1);
    expect(store.drafts, isEmpty);

    store.failSave = false;
    await _closeDirty(tester);
    await tester.tap(find.text('บันทึกแล้วออก'));
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen), findsNothing);
    expect(store.attempts, 2);
    expect(store.drafts.values.single.caption,
        'ข้อความที่ต้องไม่หายเมื่อบันทึกพลาด');
    expect(fixture.apiWrites, 0);
  });

  testWidgets(
      'system back moves to the previous step while preserving the caption',
      (tester) async {
    final fixture = _ExitFixture();
    await _open(tester, fixture);
    await _enterCaption(tester, 'เก็บข้อความตอนย้อนกลับ');
    await goToUploaderStep(tester, 3);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('uploader-step-platforms')), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-exit-dialog')), findsNothing);

    await goToUploaderStep(tester, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
    await goToUploaderStep(tester, 1);
    expect(_caption(tester), 'เก็บข้อความตอนย้อนกลับ');
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.apiWrites, 0);
  });

  testWidgets(
      'closing an unchanged saved draft exits without asking to save again',
      (tester) async {
    final fixture = _ExitFixture();
    await _open(tester, fixture);
    await _enterCaption(tester, 'บันทึกครบแล้ว');
    await tester.tap(find.byKey(const ValueKey('uploader-save-draft-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('uploader-exit-dialog')), findsNothing);
    expect(find.byType(UploaderScreen), findsNothing);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.store.drafts.values.single.caption, 'บันทึกครบแล้ว');
    expect(fixture.apiWrites, 0);
  });
}
