import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/ai_editing/ai_editing_screen.dart';
import 'package:postdee_mobile/features/ai_editing/beat_music_picker.dart';
import 'package:postdee_mobile/features/ai_editing/capcut_editor_screen.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';

PickedVideoFile _createPickedVideoFixture(String name) {
  final directory = Directory.systemTemp.createTempSync('postdee-editor-');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  final file = File('${directory.path}${Platform.pathSeparator}$name');
  file.writeAsBytesSync(List<int>.filled(2048, 1));

  return PickedVideoFile(
    name: name,
    path: file.path,
    sizeBytes: file.lengthSync(),
    width: 1080,
    height: 1920,
  );
}

BurnedSubtitleResult _createRenderedVideoFixture(
  String name, {
  bool colorFilterSkipped = false,
}) {
  final picked = _createPickedVideoFixture(name);
  final file = File(picked.path);
  return BurnedSubtitleResult(
    file: file,
    fileName: name,
    sizeBytes: file.lengthSync(),
    colorFilterSkipped: colorFilterSkipped,
  );
}

AiEditPrepareResult _createPrepareFixture() => const AiEditPrepareResult(
      quota: AiEditQuota(
        limitMinutes: 60,
        usedMinutes: 1,
        remainingMinutes: 59,
      ),
      recipe: AiEditRecipeResult(
        version: 1,
        status: 'ready',
        renderMode: 'mobile-ffmpeg',
        transcript: AiEditTranscriptResult(
          text: 'รีวิวสินค้าชิ้นนี้ดีมาก',
          language: 'th',
          durationSeconds: 45,
          segments: [
            ClipTranscriptSegment(
              text: 'รีวิวสินค้าชิ้นนี้ดีมาก',
              start: 0,
              end: 10,
            ),
            ClipTranscriptSegment(
              text: 'ราคาคุ้มมาก',
              start: 11,
              end: 20,
            ),
          ],
          words: [],
          model: 'test',
        ),
        subtitles: AiEditSubtitlesResult(
          enabled: true,
          segments: [
            ClipTranscriptSegment(
              text: 'รีวิวสินค้าชิ้นนี้ดีมาก',
              start: 0,
              end: 10,
            ),
          ],
          style: AiEditSubtitleStyleResult(
            mode: 'bold',
            color: '#FFFFFF',
            wordsPerLine: 3,
            position: 'bottom',
          ),
        ),
        cutRanges: [AiEditCut(start: 10, end: 11)],
        silenceRanges: [AiEditCut(start: 10, end: 11)],
        fillerRanges: [],
        capabilities: {
          'subtitle': AiEditCapabilityStatusResult(
            enabled: true,
            state: 'applied',
            message: 'ใส่ซับแล้ว',
          ),
          'silence': AiEditCapabilityStatusResult(
            enabled: true,
            state: 'applied',
            message: 'ตัดช่วงเงียบแล้ว',
          ),
          'filler': AiEditCapabilityStatusResult(
            enabled: true,
            state: 'hinted',
            message: 'ไม่พบคำฟุ่มเฟือย',
          ),
          'color': AiEditCapabilityStatusResult(
            enabled: true,
            state: 'hinted',
            message: 'ให้มือถือปรับสี',
          ),
        },
      ),
    );

AiEditPrepareResult _createNoOpPrepareFixture() => const AiEditPrepareResult(
      quota: AiEditQuota(
        limitMinutes: 60,
        usedMinutes: 1,
        remainingMinutes: 59,
      ),
      recipe: AiEditRecipeResult(
        version: 1,
        status: 'ready',
        renderMode: 'mobile-ffmpeg',
        transcript: AiEditTranscriptResult(
          text: '',
          language: 'th',
          durationSeconds: 20,
          segments: [],
          words: [],
          model: 'test',
        ),
        subtitles: AiEditSubtitlesResult(
          enabled: false,
          segments: [],
          style: AiEditSubtitleStyleResult(
            mode: 'bold',
            color: '#FFFFFF',
            wordsPerLine: 3,
            position: 'bottom',
          ),
        ),
        cutRanges: [],
        silenceRanges: [],
        fillerRanges: [],
        capabilities: {},
      ),
    );

AiEditPrepareResult _createAnalysisPrepareFixture() =>
    const AiEditPrepareResult(
      quota: AiEditQuota(
        limitMinutes: 60,
        usedMinutes: 1,
        remainingMinutes: 59,
      ),
      recipe: AiEditRecipeResult(
        version: 1,
        status: 'ready',
        renderMode: 'mobile-ffmpeg',
        transcript: AiEditTranscriptResult(
          text: 'เอ่อ รีวิวสินค้า แบบว่า คุ้มมาก',
          language: 'th',
          durationSeconds: 45,
          segments: [
            ClipTranscriptSegment(text: 'เอ่อ รีวิวสินค้า', start: 0, end: 3),
            ClipTranscriptSegment(text: 'แบบว่า คุ้มมาก', start: 4, end: 8),
          ],
          words: [
            AiEditTranscriptWordResult(word: 'เอ่อ', start: 3, end: 3.5),
            AiEditTranscriptWordResult(word: 'แบบว่า', start: 8, end: 8.5),
          ],
          model: 'test',
        ),
        subtitles: AiEditSubtitlesResult(
          enabled: false,
          segments: [],
          style: AiEditSubtitleStyleResult(
            mode: 'bold',
            color: '#FFFFFF',
            wordsPerLine: 3,
            position: 'bottom',
          ),
        ),
        cutRanges: [
          AiEditCut(start: 10, end: 12),
          AiEditCut(start: 20, end: 22),
          AiEditCut(start: 10.5, end: 11),
          AiEditCut(start: 20.5, end: 21),
        ],
        silenceRanges: [
          AiEditCut(start: 10, end: 12),
          AiEditCut(start: 20, end: 22),
        ],
        fillerRanges: [
          AiEditCut(start: 10.5, end: 11),
          AiEditCut(start: 20.5, end: 21),
        ],
        capabilities: {
          'silence': AiEditCapabilityStatusResult(
            enabled: true,
            state: 'applied',
            message: 'พบช่วงเงียบ 2 ช่วง',
          ),
          'filler': AiEditCapabilityStatusResult(
            enabled: true,
            state: 'applied',
            message: 'พบคำฟุ่มเฟือย 2 คำ',
          ),
        },
      ),
    );

SubscriptionStatusResult _subscriptionFixture(String plan) =>
    SubscriptionStatusResult(
      userId: 'editor-user',
      plan: plan,
      status: plan == 'PRO' ? 'ACTIVE' : 'INACTIVE',
      canSchedule: plan != 'BASIC',
      canUseAiCaptions: plan != 'BASIC',
      canUseAnalytics: plan == 'PRO',
    );

Widget _testApp(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );

Future<void> _openAdvancedPanel(
    WidgetTester tester, String capabilityId) async {
  final disclosure = find.byKey(
    ValueKey('ai-advanced-disclosure-$capabilityId'),
    skipOffstage: false,
  );
  await tester.scrollUntilVisible(
    disclosure,
    350,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(disclosure);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows remaining AI editing minutes on setup', (tester) async {
    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          loadAiEditQuota: () async => const AiEditQuota(
            limitMinutes: 200,
            usedMinutes: 17,
            remainingMinutes: 183,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ai-edit-quota-indicator')), findsOneWidget);
    expect(find.text('เหลือ 183 นาที'), findsOneWidget);
    expect(find.text('Pro · ใช้แล้ว 17/200 นาที'), findsOneWidget);
  });

  testWidgets('updates remaining minutes after a metered AI edit',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('quota-update.mp4');
    final renderedVideo = _createRenderedVideoFixture('quota-result.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          loadAiEditQuota: () async => const AiEditQuota(
            limitMinutes: 200,
            usedMinutes: 0,
            remainingMinutes: 200,
          ),
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'quota-upload',
            videoS3Key: 'uploads/quota-update.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async => renderedVideo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('เหลือ 200 นาที'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
    expect(find.text('เหลือ 59 นาที'), findsOneWidget);
    expect(find.text('Pro · ใช้แล้ว 1/60 นาที'), findsOneWidget);
  });

  testWidgets('matches the AI setup screen from PostDee.dc.html',
      (tester) async {
    await tester.pumpWidget(_testApp(const AiEditingScreen()));

    expect(find.text('ตัดต่อด้วย AI'), findsOneWidget);
    expect(find.text('โหมดตั้งค่าขั้นสูง'), findsOneWidget);
    expect(find.text('เพิ่มวิดีโอ'), findsOneWidget);
    expect(find.text('ความยาวที่อยากได้'), findsOneWidget);
    expect(find.text('30 วิ'), findsOneWidget);
    expect(find.text('1 นาที'), findsOneWidget);
    expect(find.text('กำหนดเอง'), findsOneWidget);
    expect(find.text('ให้ AI จัดการให้'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ตัดต่อ · จังหวะ', skipOffstage: false),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('ตัดต่อ · จังหวะ'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-capability-silence')), findsOneWidget);

    final processButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('ai-process-button')),
    );
    expect(processButton.onPressed, isNull);
    expect(find.text('เพิ่มวิดีโอก่อน'), findsOneWidget);

    // The old style gallery is no longer mixed into this setup screen.
    expect(find.text('ป้ายยาฉับไว'), findsNothing);
  });

  testWidgets('keeps a selected clip on the setup screen until processing',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('selected-clip.mp4');
    var createUploadCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async {
            createUploadCalls += 1;
            return const UploadResult(
              id: 'not-used-yet',
              videoS3Key: 'uploads/selected-clip.mp4',
              storageProvider: 's3',
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();

    expect(find.text('selected-clip.mp4'), findsOneWidget);
    expect(find.byType(CapCutEditorScreen), findsNothing);
    expect(createUploadCalls, 0);
    expect(find.text('ให้ AI ตัดต่อให้เลย'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('ai-process-button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('ai-remove-video')));
    await tester.pumpAndSettle();
    expect(find.text('selected-clip.mp4'), findsNothing);
    expect(find.byKey(const ValueKey('ai-add-video')), findsOneWidget);
  });

  testWidgets('shows progress while reading a selected video', (tester) async {
    final pickedVideo = _createPickedVideoFixture('slow-clip.mp4');
    final picker = Completer<PickedVideoFile?>();

    await tester.pumpWidget(
      _testApp(AiEditingScreen(pickVideo: () => picker.future)),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pump();

    expect(find.text('กำลังอ่านวิดีโอ...'), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('ai-add-video'))).onTap,
      isNull,
    );

    picker.complete(pickedVideo);
    await tester.pumpAndSettle();
    expect(find.text('slow-clip.mp4'), findsOneWidget);
    expect(find.text('กำลังอ่านวิดีโอ...'), findsNothing);
  });

  testWidgets('checks Pro entitlement before creating an upload',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('basic-user-clip.mp4');
    var createUploadCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          loadSubscription: () async => _subscriptionFixture('BASIC'),
          createUpload: (_) async {
            createUploadCalls += 1;
            return const UploadResult(
              id: 'must-not-upload',
              videoS3Key: 'uploads/must-not-upload.mp4',
              storageProvider: 'r2',
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(createUploadCalls, 0);
    expect(
      find.text('การตัดต่ออัตโนมัติต้องใช้แพ็กเกจ Pro'),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('postdee-system-status-sheet')),
      findsOneWidget,
    );
    expect(find.text('ปลดล็อก AI ตัดต่อด้วย Pro'), findsOneWidget);
    expect(find.text('ดูแพ็กเกจ Pro'), findsOneWidget);
    expect(find.text('ไว้ก่อน'), findsOneWidget);

    await tester.tap(find.text('ดูแพ็กเกจ Pro'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกแพ็กเกจ'), findsOneWidget);
  });

  testWidgets('renders then stays on the AI result review screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pickedVideo = _createPickedVideoFixture('editor-real.mp4');
    final renderedVideo = _createRenderedVideoFixture('ai-result.mp4');
    CreateUploadRequest? createdUploadRequest;
    String? uploadedFilePath;
    AiEditPrepareRequest? prepareRequest;
    BurnSubtitleRequest? renderRequest;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (request) async {
            createdUploadRequest = request;
            return const UploadResult(
              id: 'editor-upload-1',
              videoS3Key: 'uploads/editor-real.mp4',
              storageProvider: 's3',
            );
          },
          uploadVideoFile: (_, file) async {
            uploadedFilePath = file.path;
          },
          prepareEdit: (request) async {
            prepareRequest = request;
            return _createPrepareFixture();
          },
          burnVideo: (request) async {
            renderRequest = request;
            return renderedVideo;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    expect(createdUploadRequest, isNull);

    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(createdUploadRequest?.fileName, 'editor-real.mp4');
    expect(createdUploadRequest?.sizeBytes, pickedVideo.sizeBytes);
    expect(createdUploadRequest?.width, 1080);
    expect(createdUploadRequest?.height, 1920);
    expect(uploadedFilePath, pickedVideo.path);
    expect(prepareRequest?.videoS3Key, 'uploads/editor-real.mp4');
    expect(renderRequest?.inputFile.path, pickedVideo.path);
    expect(find.byType(CapCutEditorScreen), findsNothing);
    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
    expect(find.text('AI ตัดต่อให้แล้ว'), findsOneWidget);
    expect(find.text('ไปหน้าโพสต์'), findsOneWidget);
    expect(find.text('ตัดต่อเพิ่ม'), findsOneWidget);
  });

  testWidgets('review explains when device rendering skips the color filter',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('color-fallback.mp4');
    final renderedVideo = _createRenderedVideoFixture(
      'color-fallback-result.mp4',
      colorFilterSkipped: true,
    );

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'color-fallback-upload',
            videoS3Key: 'uploads/color-fallback.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async => renderedVideo,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ai-color-filter-skipped')), findsOneWidget);
    expect(
      find.text('อุปกรณ์นี้ไม่รองรับการปรับสี จึงข้ามเฉพาะโทนสี'),
      findsOneWidget,
    );
  });

  testWidgets('automatically previews a removed AI feature and can add it back',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('original.mp4');
    final firstResult = _createRenderedVideoFixture('ai-result-1.mp4');
    final secondResult = _createRenderedVideoFixture('ai-result-2.mp4');
    final thirdResult = _createRenderedVideoFixture('ai-result-3.mp4');
    final renderRequests = <BurnSubtitleRequest>[];

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u1',
            videoS3Key: 'uploads/original.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (request) async {
            renderRequests.add(request);
            return switch (renderRequests.length) {
              1 => firstResult,
              2 => secondResult,
              _ => thirdResult,
            };
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final silenceSwitch = find.byKey(
      const ValueKey('ai-review-capability-silence'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      silenceSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(silenceSwitch);
    await tester.pumpAndSettle();

    expect(renderRequests, hasLength(2));
    expect(find.byKey(const ValueKey('ai-review-update')), findsNothing);
    expect(renderRequests.last.inputFile.path, pickedVideo.path);
    expect(
      renderRequests.last.preserveTempDirectoryPaths,
      contains(firstResult.file.parent.path),
    );
    expect(
      renderRequests.last.silenceRanges.any(
        (range) => range.start == 10 && range.end == 11,
      ),
      isFalse,
    );
    await tester.scrollUntilVisible(
      find.text('ai-result-2.mp4', skipOffstage: false),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('ai-result-2.mp4'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-review-post')), findsOneWidget);

    await tester.scrollUntilVisible(
      silenceSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(silenceSwitch);
    await tester.pumpAndSettle();

    expect(renderRequests, hasLength(3));
    expect(
      renderRequests.last.silenceRanges.any(
        (range) => range.start == 10 && range.end == 11,
      ),
      isTrue,
    );
    expect(
      find.text('ai-result-3.mp4', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('blocks overlapping changes while an automatic preview renders',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('pending-preview.mp4');
    final firstResult = _createRenderedVideoFixture('pending-preview-1.mp4');
    final secondResult = _createRenderedVideoFixture('pending-preview-2.mp4');
    final pendingPreview = Completer<BurnedSubtitleResult>();
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-pending-preview',
            videoS3Key: 'uploads/pending-preview.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) {
            renderCalls += 1;
            return renderCalls == 1
                ? Future.value(firstResult)
                : pendingPreview.future;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final silenceCheckbox = find.byKey(
      const ValueKey('ai-review-capability-silence'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      silenceCheckbox,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(silenceCheckbox);
    await tester.pump();

    expect(renderCalls, 2);
    expect(
      find.byKey(
        const ValueKey('ai-review-preview-updating'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(silenceCheckbox).onChanged, isNull);
    expect(
      find.text('pending-preview-1.mp4', skipOffstage: false),
      findsOneWidget,
    );

    pendingPreview.complete(secondResult);
    await tester.pumpAndSettle();

    expect(renderCalls, 2);
    expect(
      find.text('pending-preview-2.mp4', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('keeps the previous result when updating the clip fails',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('original-failure.mp4');
    final firstResult = _createRenderedVideoFixture('safe-old-result.mp4');
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-failure',
            videoS3Key: 'uploads/original-failure.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async {
            renderCalls += 1;
            if (renderCalls > 1) {
              throw const SubtitleBurnException('เรนเดอร์รอบใหม่ไม่สำเร็จ');
            }
            return firstResult;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final silenceSwitch = find.byKey(
      const ValueKey('ai-review-capability-silence'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      silenceSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(silenceSwitch);
    await tester.pumpAndSettle();

    expect(find.textContaining('ผลลัพธ์เดิมยังอยู่'), findsOneWidget);
    expect(
        find.text('safe-old-result.mp4', skipOffstage: false), findsOneWidget);
    expect(
      tester.widget<Checkbox>(silenceSwitch).value,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('ai-review-post'), skipOffstage: false),
      findsOneWidget,
    );
    expect(renderCalls, 2);
  });

  testWidgets('prepares a fresh recipe after changing setup', (tester) async {
    final pickedVideo = _createPickedVideoFixture('setup-change.mp4');
    final firstResult = _createRenderedVideoFixture('setup-result-1.mp4');
    final secondResult = _createRenderedVideoFixture('setup-result-2.mp4');
    final prepareRequests = <AiEditPrepareRequest>[];
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-setup-change',
            videoS3Key: 'uploads/setup-change.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (request) async {
            prepareRequests.add(request);
            return _createPrepareFixture();
          },
          burnVideo: (_) async {
            renderCalls += 1;
            return renderCalls == 1 ? firstResult : secondResult;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้งค่าใหม่'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-duration-60')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(prepareRequests, hasLength(2));
    expect(prepareRequests.first.durationSeconds, 30);
    expect(prepareRequests.last.durationSeconds, 60);
    expect(find.text('setup-result-2.mp4'), findsOneWidget);
  });

  testWidgets('returns to the previous result when new setup rendering fails',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('setup-failure.mp4');
    final firstResult = _createRenderedVideoFixture('previous-safe-result.mp4');
    final recoveredResult = _createRenderedVideoFixture('recovered-result.mp4');
    final renderRequests = <BurnSubtitleRequest>[];
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-setup-failure',
            videoS3Key: 'uploads/setup-failure.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (request) async {
            renderCalls += 1;
            renderRequests.add(request);
            if (renderCalls == 2) {
              throw const SubtitleBurnException('สร้างผลงานใหม่ไม่สำเร็จ');
            }
            return renderCalls == 1 ? firstResult : recoveredResult;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้งค่าใหม่'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-duration-60')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
    expect(find.text('previous-safe-result.mp4'), findsOneWidget);
    expect(find.textContaining('ผลลัพธ์เดิมยังอยู่'), findsOneWidget);

    final silenceSwitch = find.byKey(
      const ValueKey('ai-review-capability-silence'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      silenceSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(silenceSwitch);
    await tester.pumpAndSettle();

    expect(renderRequests, hasLength(3));
    expect(
      renderRequests.last.silenceRanges.any(
        (range) => range.start == 30 && range.end == 45,
      ),
      isTrue,
      reason: 'review rerender must keep the accepted 30-second setup',
    );
  });

  testWidgets('reuses a prepared recipe when local rendering is retried',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('retry-render.mp4');
    final renderedVideo = _createRenderedVideoFixture('retry-success.mp4');
    var prepareCalls = 0;
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-retry-render',
            videoS3Key: 'uploads/retry-render.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async {
            prepareCalls += 1;
            return _createPrepareFixture();
          },
          burnVideo: (_) async {
            renderCalls += 1;
            if (renderCalls == 1) {
              throw const SubtitleBurnException('เครื่องเรนเดอร์ไม่สำเร็จ');
            }
            return renderedVideo;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();
    tester
        .widget<ElevatedButton>(
          find.byKey(const ValueKey('ai-process-button')),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(prepareCalls, 1);
    expect(renderCalls, 2);
    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
  });

  testWidgets('uses the original clip when every real AI edit is removed',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('keep-original.mp4');
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-keep-original',
            videoS3Key: 'uploads/keep-original.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createNoOpPrepareFixture(),
          burnVideo: (_) async {
            renderCalls += 1;
            throw const SubtitleBurnException('ไม่มีการแก้ไขให้เรนเดอร์');
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    final colorSwitch = find.byKey(
      const ValueKey('ai-capability-color'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      colorSwitch,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(colorSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(renderCalls, 0);
    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
    expect(find.text('keep-original.mp4'), findsOneWidget);
  });

  testWidgets('review status follows automatic preview removal and restore',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('review-status.mp4');
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-review-status',
            videoS3Key: 'uploads/review-status.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async {
            renderCalls += 1;
            return _createRenderedVideoFixture('review-$renderCalls.mp4');
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final silenceSwitch = find.byKey(
      const ValueKey('ai-review-capability-silence'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      silenceSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('อยู่ในพรีวิว · เอาติ๊กออกเพื่อดูแบบไม่ใช้'),
      findsWidgets,
    );

    await tester.tap(silenceSwitch);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'นำออกจากพรีวิวแล้ว · ติ๊กเพื่อเอากลับ',
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      silenceSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(silenceSwitch);
    await tester.pumpAndSettle();
    expect(renderCalls, 3);
    expect(
      find.text(
        'อยู่ในพรีวิว · เอาติ๊กออกเพื่อดูแบบไม่ใช้',
        skipOffstage: false,
      ),
      findsWidgets,
    );
  });

  testWidgets('review summarizes detected silence filler words and saved time',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('analysis-summary.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-analysis-summary',
            videoS3Key: 'uploads/analysis-summary.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createAnalysisPrepareFixture(),
          burnVideo: (_) async =>
              _createRenderedVideoFixture('analysis-summary-result.mp4'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final summary = find.byKey(
      const ValueKey('ai-review-analysis-summary'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      summary,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.textContaining('2 ช่วง')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.textContaining('2 คำ')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summary,
        matching: find.textContaining(RegExp(r'4(?:\.0)? วินาที')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('review analysis summary keeps explicit zero states',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('analysis-zero.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-analysis-zero',
            videoS3Key: 'uploads/analysis-zero.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createNoOpPrepareFixture(),
          burnVideo: (_) async =>
              _createRenderedVideoFixture('analysis-zero-result.mp4'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final summary = find.byKey(
      const ValueKey('ai-review-analysis-summary'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      summary,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.textContaining('0 ช่วง')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.textContaining('0 คำ')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summary,
        matching: find.textContaining(RegExp(r'0(?:\.0)? วินาที')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps a removed review feature disabled in new setup',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('removed-setting.mp4');
    final prepareRequests = <AiEditPrepareRequest>[];
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-removed-setting',
            videoS3Key: 'uploads/removed-setting.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (request) async {
            prepareRequests.add(request);
            return _createPrepareFixture();
          },
          burnVideo: (_) async {
            renderCalls += 1;
            return _createRenderedVideoFixture(
              'removed-setting-$renderCalls.mp4',
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final silenceSwitch = find.byKey(
      const ValueKey('ai-review-capability-silence'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      silenceSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(silenceSwitch);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('ตั้งค่าใหม่', skipOffstage: false),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้งค่าใหม่'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-duration-60')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(prepareRequests, hasLength(2));
    expect(prepareRequests.last.capabilities['silence'], isFalse);
  });

  testWidgets(
      'review actions open posting and manual editing with latest result',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('original-actions.mp4');
    final renderedVideo = _createRenderedVideoFixture('latest-ai-result.mp4');

    Widget buildScreen() => _testApp(
          AiEditingScreen(
            key: UniqueKey(),
            pickVideo: () async => pickedVideo,
            createUpload: (_) async => const UploadResult(
              id: 'u-actions',
              videoS3Key: 'uploads/original-actions.mp4',
              storageProvider: 's3',
            ),
            uploadVideoFile: (_, __) async {},
            prepareEdit: (_) async => _createPrepareFixture(),
            burnVideo: (_) async => renderedVideo,
          ),
        );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildScreen());
    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-review-post')));
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen), findsOneWidget);
    final uploader = tester.widget<UploaderScreen>(find.byType(UploaderScreen));
    expect(uploader.initialVideoPath, renderedVideo.file.path);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildScreen());
    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-review-edit-more')));
    await tester.pumpAndSettle();

    expect(find.byType(CapCutEditorScreen), findsOneWidget);
    final editor = tester.widget<CapCutEditorScreen>(
      find.byType(CapCutEditorScreen),
    );
    expect(editor.videoFile?.path, renderedVideo.file.path);
    expect(editor.initialStyle, isNull);
  });

  testWidgets(
      'keeps AI hook disabled in production and excludes it from prepare',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final pickedVideo = _createPickedVideoFixture('production-hook-lock.mp4');
    AiEditPrepareRequest? prepareRequest;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-production-hook-lock',
            videoS3Key: 'uploads/production-hook-lock.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (request) async {
            prepareRequest = request;
            return _createPrepareFixture();
          },
          burnVideo: (_) async =>
              _createRenderedVideoFixture('production-hook-result.mp4'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();

    final hookSwitch = find.byKey(
      const ValueKey('ai-capability-hook'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      hookSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai-capability-badge-hook')),
      findsOneWidget,
    );
    expect(tester.getSize(hookSwitch).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(hookSwitch),
      isSemantics(
        label: 'ไฮไลต์ 3 วิแรก',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasToggledState: true,
        isToggled: false,
        hasTapAction: false,
      ),
    );
    expect(
      find.byKey(
        const ValueKey('ai-advanced-disclosure-hook'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('ai-advanced-hook'),
        skipOffstage: false,
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(prepareRequest?.capabilities['hook'], isFalse);
    expect(
      find.byKey(
        const ValueKey('ai-review-capability-hook'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets(
      'keeps beat sync disabled in production and excludes it from prepare',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final pickedVideo = _createPickedVideoFixture('production-beat-lock.mp4');
    AiEditPrepareRequest? prepareRequest;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-production-beat-lock',
            videoS3Key: 'uploads/production-beat-lock.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (request) async {
            prepareRequest = request;
            return _createPrepareFixture();
          },
          burnVideo: (_) async =>
              _createRenderedVideoFixture('production-beat-result.mp4'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();

    final beatSwitch = find.byKey(
      const ValueKey('ai-capability-beatsync'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      beatSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('เร็ว ๆ นี้'), findsOneWidget);
    expect(tester.getSize(beatSwitch).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(beatSwitch),
      isSemantics(
        label: 'ตัดจังหวะตามบีตเพลง',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasToggledState: true,
        isToggled: false,
        hasTapAction: false,
      ),
    );
    expect(
      find.byKey(
        const ValueKey('ai-advanced-disclosure-beatsync'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('ai-advanced-beatsync'),
        skipOffstage: false,
      ),
      findsNothing,
    );

    expect(find.text('ให้ AI ตัดต่อให้เลย'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(prepareRequest?.capabilities['beatsync'], isFalse);
    expect(prepareRequest?.settings.music?.source, 'original');
    semantics.dispose();
  });

  testWidgets('keeps the internal hook preview off and visibly experimental',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _testApp(
        const AiEditingScreen(enableExperimentalAiHook: true),
      ),
    );

    final hookSwitch = find.byKey(
      const ValueKey('ai-capability-hook'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      hookSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('ทดลอง'), findsOneWidget);
    expect(
      tester.getSemantics(hookSwitch),
      isSemantics(
        label: 'ไฮไลต์ 3 วิแรก',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );
    expect(
      find.text('โหมดทดสอบส่งคำขอแบบวางแผนเท่านั้น ยังไม่แก้คลิปจริง'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('shows honest music choices under beat-sync advanced settings',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        const AiEditingScreen(
          enableExperimentalBeatSync: true,
          musicCatalog: [],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();
    await _openAdvancedPanel(tester, 'beatsync');

    final beatAdvanced = find.byKey(
      const ValueKey('ai-advanced-beatsync'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      beatAdvanced,
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('เพลงสำหรับตัดตามบีต'), findsOneWidget);
    expect(find.text('AI เลือกให้'), findsOneWidget);
    expect(find.text('คลัง PostDee'), findsOneWidget);
    expect(find.text('อัปโหลดเพลงของฉัน'), findsOneWidget);
    expect(find.text('ใช้เสียงจากวิดีโอ'), findsOneWidget);
    expect(find.text('กำลังเตรียม'), findsNothing);
    expect(find.text('เร็ว ๆ นี้'), findsWidgets);
    expect(
      find.byKey(const ValueKey('ai-beatsync-catalog-empty')),
      findsNothing,
      reason: 'an empty catalog should not distract from the selected source',
    );

    final aiSource = find.byKey(const ValueKey('ai-beatsync-source-ai'));
    final catalogSource =
        find.byKey(const ValueKey('ai-beatsync-source-catalog'));
    final originalSource =
        find.byKey(const ValueKey('ai-beatsync-source-original'));
    expect(aiSource, findsOneWidget);
    expect(catalogSource, findsOneWidget);
    expect(tester.getSize(originalSource).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(aiSource),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: false,
      ),
    );
    expect(
      tester.getSemantics(originalSource),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );

    final balancedIntensity = find.byKey(
      const ValueKey('ai-beatsync-intensity-balanced'),
    );
    expect(tester.getSize(balancedIntensity).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(balancedIntensity),
      isSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('only enables catalog tracks with verified usage rights',
      (tester) async {
    const approvedTrack = PostDeeMusicTrack(
      id: 'approved-sale-track',
      title: 'Seller Spark',
      moodLabel: 'สนุก',
      bpm: 120,
      durationSeconds: 45,
      licenseLabel: 'Commercial license',
      rightsVerified: true,
      supportedPlatforms: [
        'TikTok',
        'YouTube Shorts',
        'Instagram Reels',
        'Facebook Reels',
        'Shopee Video',
        'Lazada Video',
      ],
    );
    const pendingTrack = PostDeeMusicTrack(
      id: 'pending-track',
      title: 'Pending Review',
      moodLabel: 'ชิล',
      bpm: 92,
      durationSeconds: 30,
      licenseLabel: 'รอตรวจเอกสาร',
      rightsVerified: false,
    );
    const partialTrack = PostDeeMusicTrack(
      id: 'partial-track',
      title: 'Partial Rights',
      moodLabel: 'สนุก',
      bpm: 110,
      durationSeconds: 32,
      licenseLabel: 'Commercial partial',
      rightsVerified: true,
      supportedPlatforms: ['TikTok', 'YouTube Shorts'],
    );

    await tester.pumpWidget(
      _testApp(
        const AiEditingScreen(
          enableExperimentalBeatSync: true,
          musicCatalog: [approvedTrack, pendingTrack, partialTrack],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();
    await _openAdvancedPanel(tester, 'beatsync');

    final catalogSource = find.byKey(
      const ValueKey('ai-beatsync-source-catalog'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      catalogSource,
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(catalogSource);
    await tester.pumpAndSettle();

    final approvedFinder = find.byKey(
      const ValueKey('ai-beatsync-track-approved-sale-track'),
    );
    final pendingFinder = find.byKey(
      const ValueKey('ai-beatsync-track-pending-track'),
    );
    final partialFinder = find.byKey(
      const ValueKey('ai-beatsync-track-partial-track'),
    );
    expect(
      find.text('ตรวจสอบสิทธิ์ครบทุกแพลตฟอร์ม • Commercial license'),
      findsOneWidget,
    );
    expect(find.text('ยังไม่พร้อมใช้งาน • รอตรวจเอกสาร'), findsOneWidget);
    expect(
      find.text('สิทธิ์ยังไม่ครบทุกแพลตฟอร์ม • TikTok, YouTube Shorts'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: pendingFinder,
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: partialFinder,
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
    );

    await tester.tap(approvedFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(approvedFinder).color, AppTheme.mint);
    expect(tester.widget<Material>(pendingFinder).color, AppTheme.glassDeep);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending owned music does not block CTA and is normalized',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('music-source-video.mp4');
    final renderedVideo = _createRenderedVideoFixture('music-result.mp4');
    final pickedMusic = PickedBeatMusicFile(
      name: 'seller-owned.mp3',
      path: pickedVideo.path,
      sizeBytes: 1024,
    );
    AiEditPrepareRequest? prepareRequest;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          enableExperimentalBeatSync: true,
          pickVideo: () async => pickedVideo,
          pickMusic: () async => pickedMusic,
          createUpload: (_) async => const UploadResult(
            id: 'u-music-source',
            videoS3Key: 'uploads/music-source-video.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (request) async {
            prepareRequest = request;
            return _createPrepareFixture();
          },
          burnVideo: (_) async => renderedVideo,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();
    await _openAdvancedPanel(tester, 'beatsync');

    final myMusicSource = find.byKey(
      const ValueKey('ai-beatsync-source-my-music'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      myMusicSource,
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(myMusicSource);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-beatsync-music-picker')));
    await tester.pumpAndSettle();
    expect(find.text('seller-owned.mp3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-beatsync-device-pending-note')),
      findsNothing,
      reason: 'the experimental warning should appear only once at the top',
    );
    expect(
      find.byKey(const ValueKey('ai-beatsync-experimental-note')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('ai-process-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('ตัดต่อโดยยังไม่ใส่เพลง'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final music = prepareRequest?.settings.music;
    expect(prepareRequest?.capabilities['beatsync'], isFalse);
    expect(music?.source, 'original');
    expect(music?.beatIntensity, 'balanced');
    expect(music?.volume, closeTo(0.25, 0.001));
    expect(music?.ducking.enabled, isTrue);
    expect(music?.trackId, isNull);
    expect(
      find.byKey(
        const ValueKey('ai-review-capability-beatsync'),
        skipOffstage: false,
      ),
      findsNothing,
      reason: 'planned beat-sync must not be shown as already applied',
    );
  });

  testWidgets('restores music volume from a saved catalog preset',
      (tester) async {
    const approvedTrack = PostDeeMusicTrack(
      id: 'preset-track',
      title: 'Preset Track',
      moodLabel: 'สนุก',
      bpm: 118,
      durationSeconds: 40,
      licenseLabel: 'All-platform commercial license',
      rightsVerified: true,
      supportedPlatforms: [
        'TikTok',
        'YouTube Shorts',
        'Instagram Reels',
        'Facebook Reels',
        'Shopee Video',
        'Lazada Video',
      ],
    );
    await tester.pumpWidget(
      _testApp(
        const AiEditingScreen(
          enableExperimentalBeatSync: true,
          musicCatalog: [approvedTrack],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();
    await _openAdvancedPanel(tester, 'beatsync');

    final catalogSource = find.byKey(
      const ValueKey('ai-beatsync-source-catalog'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      catalogSource,
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(catalogSource);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ai-beatsync-track-preset-track')),
    );
    await tester.pumpAndSettle();

    final sliderFinder = find.byKey(
      const ValueKey('ai-beatsync-volume-slider'),
      skipOffstage: false,
    );
    tester.widget<Slider>(sliderFinder).onChanged!(0.42);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ชุดตั้งค่า (Preset)', skipOffstage: false),
      520,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    tester
        .widget<TextButton>(
          find.widgetWithText(
            TextButton,
            'บันทึกชุดนี้',
            skipOffstage: false,
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      sliderFinder,
      -520,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    tester.widget<Slider>(sliderFinder).onChanged!(0.08);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ชุดตั้งค่า (Preset)', skipOffstage: false),
      520,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    tester
        .widget<OutlinedButton>(
          find.widgetWithText(
            OutlinedButton,
            'ใช้',
            skipOffstage: false,
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      sliderFinder,
      -520,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliderFinder).value, closeTo(0.42, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('silence and filler settings use the advanced accordion',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_testApp(const AiEditingScreen()));

    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();
    await _openAdvancedPanel(tester, 'silence');

    expect(
      find.byKey(const ValueKey('ai-advanced-silence'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-filler'), skipOffstage: false),
      findsNothing,
    );

    for (final preset in const ['natural', 'balanced', 'compact']) {
      final chip = find.byKey(
        ValueKey('ai-silence-preset-$preset'),
        skipOffstage: false,
      );
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    }
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('ai-silence-preset-balanced')),
      ),
      isSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );

    await _openAdvancedPanel(tester, 'filler');
    expect(
      find.byKey(const ValueKey('ai-advanced-silence'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-filler'), skipOffstage: false),
      findsOneWidget,
    );

    for (final word in const ['เอ่อ', 'อ่า', 'แบบว่า', 'คือว่า', 'ประมาณว่า']) {
      final chip = find.byKey(
        ValueKey('ai-filler-word-$word'),
        skipOffstage: false,
      );
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(chip),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
    }
    semantics.dispose();
  });

  testWidgets(
      'sends silence preset and selected filler words while blocking an empty selection',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('pace-settings.mp4');
    AiEditPrepareRequest? prepareRequest;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-pace-settings',
            videoS3Key: 'uploads/pace-settings.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (request) async {
            prepareRequest = request;
            return _createPrepareFixture();
          },
          burnVideo: (_) async =>
              _createRenderedVideoFixture('pace-settings-result.mp4'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();

    await _openAdvancedPanel(tester, 'silence');
    await tester.tap(
      find.byKey(const ValueKey('ai-silence-preset-natural')),
    );
    await tester.pumpAndSettle();

    await _openAdvancedPanel(tester, 'filler');
    const fillerWords = ['เอ่อ', 'อ่า', 'แบบว่า', 'คือว่า', 'ประมาณว่า'];
    for (final word in fillerWords) {
      final chip = find.byKey(
        ValueKey('ai-filler-word-$word'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        chip,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('ai-process-button')),
          )
          .onPressed,
      isNull,
      reason: 'filler removal must not run without at least one selected word',
    );

    for (final word in const ['เอ่อ', 'แบบว่า']) {
      final chip = find.byKey(
        ValueKey('ai-filler-word-$word'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        chip,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('ai-process-button')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(prepareRequest?.settings.silencePreset, 'natural');
    expect(prepareRequest?.settings.fillerWords, ['เอ่อ', 'แบบว่า']);
  });

  testWidgets('advanced accordion opens one capability at a time',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_testApp(const AiEditingScreen()));

    final advancedToggle = find.byKey(const ValueKey('ai-advanced-toggle'));
    expect(tester.getSize(advancedToggle).height, greaterThanOrEqualTo(44));
    await tester.tap(advancedToggle);
    await tester.pumpAndSettle();

    final zoomDisclosure = find.byKey(
      const ValueKey('ai-advanced-disclosure-zoom'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      zoomDisclosure,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(zoomDisclosure).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(zoomDisclosure),
      isSemantics(
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
      ),
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-zoom'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-color'), skipOffstage: false),
      findsNothing,
    );

    await tester.tap(zoomDisclosure);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(zoomDisclosure),
      isSemantics(
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-zoom'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-color'), skipOffstage: false),
      findsNothing,
    );
    expect(find.text('ความแรงซูม'), findsOneWidget);
    expect(find.text('ความเร็วคลิป'), findsOneWidget);

    await _openAdvancedPanel(tester, 'color');
    expect(
      find.byKey(const ValueKey('ai-advanced-zoom'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-color'), skipOffstage: false),
      findsOneWidget,
    );

    final colorDisclosure = find.byKey(
      const ValueKey('ai-advanced-disclosure-color'),
      skipOffstage: false,
    );
    expect(
      tester.getSemantics(colorDisclosure),
      isSemantics(
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );
    await tester.ensureVisible(colorDisclosure);
    await tester.pumpAndSettle();
    await tester.tap(colorDisclosure);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ai-advanced-color'), skipOffstage: false),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('supports a custom duration capped at 180 seconds',
      (tester) async {
    await tester.pumpWidget(_testApp(const AiEditingScreen()));

    await tester.tap(find.byKey(const ValueKey('ai-duration-custom')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('ai-custom-duration-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ai-custom-duration-field')),
      '999',
    );
    await tester.pumpAndSettle();
    expect(find.text('180'), findsOneWidget);
    expect(find.text('วินาที'), findsOneWidget);
  });

  testWidgets('advanced layout fits the 390px reference phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(const AiEditingScreen()));
    await tester.tap(find.byKey(const ValueKey('ai-advanced-toggle')));
    await tester.pumpAndSettle();

    await _openAdvancedPanel(tester, 'silence');
    expect(
      find.byKey(const ValueKey('ai-advanced-silence'), skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await _openAdvancedPanel(tester, 'filler');
    expect(
      find.byKey(const ValueKey('ai-advanced-filler'), skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('ชุดตั้งค่า (Preset)', skipOffstage: false),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('ชุดตั้งค่า (Preset)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
