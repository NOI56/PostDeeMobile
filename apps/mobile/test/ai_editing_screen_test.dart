import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_audio_extractor.dart';
import 'package:postdee_mobile/features/ai_editing/ai_editing_screen.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_visual_proxy_extractor.dart';
import 'package:postdee_mobile/features/ai_editing/beat_music_picker.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_draft_store.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:video_player/video_player.dart';

PickedVideoFile _createPickedVideoFixture(
  String name, {
  double durationSeconds = 150,
}) {
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
    durationSeconds: durationSeconds,
  );
}

Future<void> _setTargetDuration(
  WidgetTester tester,
  double seconds,
) async {
  final slider = tester.widget<Slider>(
    find.byKey(const ValueKey('ai-duration-slider')),
  );
  slider.onChanged!(seconds);
  await tester.pumpAndSettle();
}

class _MemorySubtitleDraftStore implements SubtitleDraftStore {
  SubtitleProject? saved;

  @override
  Future<void> deleteDraft(String projectId) async => saved = null;

  @override
  Future<SubtitleProject?> loadDraft(String projectId) async => saved;

  @override
  Future<void> saveDraft(SubtitleProject project) async => saved = project;
}

Future<AiEditAudioArtifact> _extractAudioFixture(File source) {
  final directory = Directory.systemTemp.createTempSync(
    'postdee-editor-audio-',
  );
  final file = File(
    '${directory.path}${Platform.pathSeparator}postdee-ai-edit-audio.m4a',
  );
  file.writeAsBytesSync(List<int>.filled(512, 7));
  return Future.value(
    AiEditAudioArtifact(file: file, workingDirectory: directory),
  );
}

Future<AiEditVisualProxyArtifact> _extractVisualProxyFixture(File source) {
  final directory = Directory.systemTemp.createTempSync(
    'postdee-editor-visual-proxy-',
  );
  final file = File(
    '${directory.path}${Platform.pathSeparator}postdee-visual-proxy.mp4',
  );
  file.writeAsBytesSync(List<int>.filled(1024, 9));
  return Future.value(
    AiEditVisualProxyArtifact(file: file, workingDirectory: directory),
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

AiEditPrepareResult _createPrepareFixture({
  AiEditPlanResult plan = const AiEditPlanResult(
    cuts: [],
    summary: '',
    model: 'none',
  ),
  double transcriptDurationSeconds = 45,
}) =>
    AiEditPrepareResult(
      quota: const AiEditQuota(
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
          durationSeconds: transcriptDurationSeconds,
          segments: const [
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
        subtitles: const AiEditSubtitlesResult(
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
        cutRanges: [...plan.cuts, const AiEditCut(start: 10, end: 11)],
        silenceRanges: const [AiEditCut(start: 10, end: 11)],
        fillerRanges: const [],
        plan: plan,
        capabilities: const {
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

Future<void> _pumpUntilPreviewUpdateFinishes(WidgetTester tester) async {
  final updating = find.byKey(
    const ValueKey('ai-review-preview-updating'),
    skipOffstage: false,
  );
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (updating.evaluate().isEmpty) {
      return;
    }
  }
  fail('AI preview update did not finish');
}

class _FakeReviewVideoController extends VideoPlayerController {
  _FakeReviewVideoController({
    required this.fakeDuration,
    this.initializeGate,
    this.disposeGate,
    this.seekGate,
    this.failInitialize = false,
    this.failSeek = false,
  }) : super.asset('fake-review-video.mp4');

  final Duration fakeDuration;
  final Completer<void>? initializeGate;
  final Completer<void>? disposeGate;
  final Completer<void>? seekGate;
  final bool failInitialize;
  final bool failSeek;
  bool disposed = false;
  int activeSeekCount = 0;
  int maxActiveSeekCount = 0;
  final List<String> calls = [];

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    await initializeGate?.future;
    if (failInitialize) {
      throw StateError('fake video initialization failed');
    }
    value = VideoPlayerValue(
      duration: fakeDuration,
      size: const Size(1080, 1920),
      isInitialized: true,
    );
  }

  @override
  Future<void> setLooping(bool looping) async {
    calls.add('loop:$looping');
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    activeSeekCount += 1;
    if (activeSeekCount > maxActiveSeekCount) {
      maxActiveSeekCount = activeSeekCount;
    }
    try {
      await seekGate?.future;
      if (failSeek) {
        throw StateError('fake seek failed');
      }
      value = value.copyWith(position: position);
    } finally {
      activeSeekCount -= 1;
    }
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    calls.add('dispose');
    await disposeGate?.future;
    await super.dispose();
  }
}

void main() {
  testWidgets('shows remaining AI editing minutes on setup', (tester) async {
    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          loadSubscription: () async => _subscriptionFixture('PRO'),
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

  testWidgets('uses the actual Basic entitlement instead of the quota size',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          loadSubscription: () async => _subscriptionFixture('BASIC'),
          loadAiEditQuota: () async => const AiEditQuota(
            limitMinutes: 200,
            usedMinutes: 17,
            remainingMinutes: 183,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('แพ็กเกจ Basic'), findsOneWidget);
    expect(find.text('AI ตัดต่อใช้ได้เฉพาะ Pro'), findsOneWidget);
    expect(find.text('Pro · ใช้แล้ว 17/200 นาที'), findsNothing);
  });

  testWidgets('uses the actual Starter entitlement instead of showing Pro',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          loadSubscription: () async => _subscriptionFixture('STARTER'),
          loadAiEditQuota: () async => const AiEditQuota(
            limitMinutes: 200,
            usedMinutes: 17,
            remainingMinutes: 183,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('แพ็กเกจ Starter'), findsOneWidget);
    expect(find.text('AI ตัดต่อใช้ได้เฉพาะ Pro'), findsOneWidget);
    expect(find.text('Pro · ใช้แล้ว 17/200 นาที'), findsNothing);
  });

  testWidgets('updates remaining minutes after a metered AI edit',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('quota-update.mp4');
    final renderedVideo = _createRenderedVideoFixture('quota-result.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          loadSubscription: () async => _subscriptionFixture('PRO'),
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

  testWidgets('uploads the whole visual proxy before selecting a short plan',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('visual-plan-source.mp4');
    final renderedVideo = _createRenderedVideoFixture('visual-plan-result.mp4');
    final uploadPurposes = <String?>[];
    final planRequests = <AiEditPlanRequest>[];
    final cleanedProxyKeys = <String>[];
    String? localProxyPath;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          initialTargetDurationSeconds: 30,
          extractAudio: _extractAudioFixture,
          extractVisualProxy: (source) async {
            final artifact = await _extractVisualProxyFixture(source);
            localProxyPath = artifact.file.path;
            return artifact;
          },
          cleanupAiEditAudio: (_) async {},
          cleanupAiEditVisualProxy: (key) async => cleanedProxyKeys.add(key),
          pickVideo: () async => pickedVideo,
          createUpload: (request) async {
            uploadPurposes.add(request.purpose);
            final isProxy = request.purpose == 'ai-edit-visual-proxy';
            return UploadResult(
              id: isProxy ? 'visual-upload' : 'audio-upload',
              videoS3Key: isProxy
                  ? 'uploads/seller/visual-proxy.mp4'
                  : 'uploads/seller/audio.m4a',
              storageProvider: 's3',
            );
          },
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          planEdit: (request) async {
            planRequests.add(request);
            return const AiEditPlanResult(
              cuts: [AiEditCut(start: 30, end: 45)],
              summary: 'visual plan',
              model: 'gemini-test-visual',
            );
          },
          burnVideo: (_) async => renderedVideo,
          reviewVideoControllerFactory: (_) => _FakeReviewVideoController(
            fakeDuration: const Duration(seconds: 30),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(uploadPurposes, ['ai-edit-audio', 'ai-edit-visual-proxy']);
    expect(planRequests, hasLength(1));
    expect(
      planRequests.single.visualProxyS3Key,
      'uploads/seller/visual-proxy.mp4',
    );
    expect(planRequests.single.durationSeconds, 45);
    expect(planRequests.single.targetDurationSeconds, 30);
    expect(cleanedProxyKeys, ['uploads/seller/visual-proxy.mp4']);
    expect(File(localProxyPath!).existsSync(), isFalse);
    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
  });

  testWidgets('matches the AI setup screen from PostDee.dc.html',
      (tester) async {
    await tester.pumpWidget(_testApp(const AiEditingScreen(
      initialTargetDurationSeconds: 30,
    )));

    expect(find.text('ตัดต่อด้วย AI'), findsOneWidget);
    expect(find.text('โหมดตั้งค่าขั้นสูง'), findsNothing);
    expect(
      find.byKey(const ValueKey('ai-advanced-toggle')),
      findsNothing,
    );
    expect(find.text('เพิ่มวิดีโอ'), findsOneWidget);
    expect(find.text('ความยาวที่อยากได้'), findsNothing);
    expect(find.text('30 วิ'), findsNothing);
    expect(find.text('1 นาที'), findsNothing);
    expect(find.text('กำหนดเอง'), findsNothing);
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

  testWidgets('shows automatic subtitles before the other AI capabilities',
      (tester) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(const AiEditingScreen(
      initialTargetDurationSeconds: 30,
    )));
    await tester.pumpAndSettle();

    final subtitleCard = find.byKey(const ValueKey('ai-capability-subtitle'));
    final silenceCard = find.byKey(const ValueKey('ai-capability-silence'));

    expect(subtitleCard, findsOneWidget);
    expect(silenceCard, findsOneWidget);
    expect(
      tester.getTopLeft(subtitleCard).dy,
      lessThan(tester.getTopLeft(silenceCard).dy),
    );
  });

  testWidgets('keeps a selected clip on the setup screen until processing',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('selected-clip.mp4');
    var createUploadCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          initialTargetDurationSeconds: 30,
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
    expect(
      find.byKey(const ValueKey('ai-review-edit-more')),
      findsNothing,
    );
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

  testWidgets('defaults every selected video to its full duration',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('choose-duration.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          initialTargetDurationSeconds: null,
          pickVideo: () async => pickedVideo,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ai-duration-step')), findsNothing);
    expect(find.byKey(const ValueKey('ai-duration-30')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();

    var processButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('ai-process-button')),
    );
    expect(processButton.onPressed, isNotNull);
    expect(find.text('ต้นฉบับ 02:30'), findsOneWidget);
    expect(find.text('ไม่ย่อ · ต้นฉบับ 02:30'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-duration-slider')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-duration-30')), findsNothing);
    expect(find.byKey(const ValueKey('ai-duration-60')), findsNothing);
    expect(find.byKey(const ValueKey('ai-duration-custom')), findsNothing);

    await _setTargetDuration(tester, 45);

    processButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('ai-process-button')),
    );
    expect(processButton.onPressed, isNotNull);
    expect(find.text('ให้ AI ย่อเหลือ 00:45'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-remove-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();

    final resetSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-duration-slider')),
    );
    expect(resetSlider.value, resetSlider.max);
    expect(find.text('ไม่ย่อ · ต้นฉบับ 02:30'), findsOneWidget);
    processButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('ai-process-button')),
    );
    expect(processButton.onPressed, isNotNull);
  });

  testWidgets(
      'keeps a long source at the rightmost stop and caps AI shortening at three minutes',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture(
      'ten-minute-source.mp4',
      durationSeconds: 600,
    );

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          initialTargetDurationSeconds: null,
          pickVideo: () async => pickedVideo,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();

    var slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-duration-slider')),
    );
    expect(slider.max, 181);
    expect(slider.value, 181);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('ai-duration-selected-label')),
          )
          .data,
      'ไม่ย่อ · ต้นฉบับ 10:00',
    );
    expect(
      find.text('ช่วงแนะนำ 00:30–01:00'),
      findsOneWidget,
    );
    expect(
      find.text('ต้นฉบับเกิน 03:00 บางช่องทางอาจไม่รับเป็นคลิปสั้น'),
      findsOneWidget,
    );

    slider.onChanged!(180);
    await tester.pumpAndSettle();

    slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-duration-slider')),
    );
    expect(slider.value, 180);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('ai-duration-selected-label')),
          )
          .data,
      'ให้ AI ย่อเหลือ 03:00',
    );
    expect(
      find.text('ต้นฉบับเกิน 03:00 บางช่องทางอาจไม่รับเป็นคลิปสั้น'),
      findsNothing,
    );
  });

  testWidgets('never lets the requested result exceed a short source',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture(
      'twelve-second-source.mp4',
      durationSeconds: 12,
    );

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          initialTargetDurationSeconds: 30,
          pickVideo: () async => pickedVideo,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-duration-slider')),
    );
    expect(slider.max, 12);
    expect(slider.value, 12);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('ai-duration-selected-label')),
          )
          .data,
      'ไม่ย่อ · ต้นฉบับ 00:12',
    );
  });

  testWidgets('rejects a source longer than ten minutes', (tester) async {
    final pickedVideo = _createPickedVideoFixture(
      'too-long-source.mp4',
      durationSeconds: 601,
    );

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(pickVideo: () async => pickedVideo),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();

    expect(find.text('รองรับคลิปต้นฉบับยาวไม่เกิน 10 นาที'), findsOneWidget);
    expect(find.text('too-long-source.mp4'), findsNothing);
    expect(find.byKey(const ValueKey('ai-duration-slider')), findsNothing);
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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

  testWidgets('shows a clear Thai message when AI transcription is unavailable',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('provider-failure.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          loadAiEditQuota: () async => const AiEditQuota(
            limitMinutes: 200,
            usedMinutes: 8,
            remainingMinutes: 192,
          ),
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'provider-failure-upload',
            videoS3Key: 'uploads/provider-failure.mp4',
            storageProvider: 'r2',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async {
            throw const ApiException(
              'AI transcription is temporarily unavailable',
              statusCode: HttpStatus.badGateway,
              code: 'AI_TRANSCRIPTION_PROVIDER_FAILED',
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('ระบบถอดเสียง AI ยังไม่พร้อม กรุณาลองใหม่อีกครั้ง'),
      findsOneWidget,
    );
    expect(find.text('Request failed'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('ai-process-button')),
          )
          .onPressed,
      isNotNull,
    );
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
    var createUploadCalls = 0;
    var uploadCalls = 0;
    final cleanedAudioKeys = <String>[];

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (key) async => cleanedAudioKeys.add(key),
          pickVideo: () async => pickedVideo,
          createUpload: (request) async {
            createUploadCalls += 1;
            createdUploadRequest = request;
            return UploadResult(
              id: 'editor-upload-$createUploadCalls',
              videoS3Key: 'uploads/editor-real-$createUploadCalls.m4a',
              storageProvider: 's3',
            );
          },
          uploadVideoFile: (_, file) async {
            uploadCalls += 1;
            if (uploadCalls == 1) {
              throw const ApiException(
                'Upload URL expired',
                statusCode: HttpStatus.forbidden,
                code: 'UPLOAD_URL_EXPIRED',
              );
            }
            uploadedFilePath = file.path;
          },
          prepareEdit: (request) async {
            prepareRequest = request;
            return _createPrepareFixture(
              plan: const AiEditPlanResult(
                cuts: [AiEditCut(start: 4, end: 5)],
                summary: 'ตัดช่วงที่ไม่เกี่ยวข้อง',
                model: 'test-editor',
              ),
            );
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

    expect(createdUploadRequest?.fileName, 'postdee-ai-edit-audio.m4a');
    expect(createdUploadRequest?.contentType, 'audio/mp4');
    expect(createdUploadRequest?.purpose, 'ai-edit-audio');
    expect(createdUploadRequest?.sizeBytes, 512);
    expect(createdUploadRequest?.width, isNull);
    expect(createdUploadRequest?.height, isNull);
    expect(uploadedFilePath, isNot(pickedVideo.path));
    expect(uploadedFilePath, endsWith('.m4a'));
    expect(File(uploadedFilePath!).existsSync(), isFalse);
    expect(createUploadCalls, 2);
    expect(uploadCalls, 2);
    expect(prepareRequest?.audioS3Key, 'uploads/editor-real-2.m4a');
    expect(prepareRequest?.videoS3Key, isNull);
    expect(prepareRequest?.targetDurationSeconds, 30);
    expect(cleanedAudioKeys, ['uploads/editor-real-2.m4a']);
    expect(renderRequest?.inputFile.path, pickedVideo.path);
    expect(
      renderRequest?.silenceRanges.any(
        (range) => range.start == 4 && range.end == 5,
      ),
      isTrue,
      reason: 'style/prompt plan cuts must be rendered on the mobile output',
    );
    expect(
      find.byKey(const ValueKey('ai-review-edit-more')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
    expect(find.text('AI ตัดต่อให้แล้ว'), findsOneWidget);
    expect(find.text('ไปหน้าโพสต์'), findsOneWidget);
    expect(find.text('ตัดต่อเพิ่ม'), findsNothing);
  });

  testWidgets('uploads ordered audio chunks and cleans every temporary file',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pickedVideo = _createPickedVideoFixture('chunked-source.mp4');
    final renderedVideo = _createRenderedVideoFixture('chunked-result.mp4');
    final uploadRequests = <CreateUploadRequest>[];
    final cleanedAudioKeys = <String>[];
    AiEditPrepareRequest? prepareRequest;
    Directory? chunksDirectory;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          extractAudioChunks: (_) async {
            chunksDirectory = Directory.systemTemp.createTempSync(
              'postdee-editor-audio-chunks-',
            );
            final chunks = <AiEditAudioChunk>[];
            for (var index = 0; index < 2; index += 1) {
              final file = File(
                '${chunksDirectory!.path}${Platform.pathSeparator}'
                'postdee-ai-edit-audio-${index.toString().padLeft(3, '0')}.m4a',
              )..writeAsBytesSync(List<int>.filled(512, index + 1));
              chunks.add(
                AiEditAudioChunk(
                  file: file,
                  startSeconds: index * 25.0,
                ),
              );
            }
            return AiEditAudioChunksArtifact(
              chunks: chunks,
              workingDirectory: chunksDirectory!,
            );
          },
          cleanupAiEditAudio: (key) async => cleanedAudioKeys.add(key),
          createUpload: (request) async {
            uploadRequests.add(request);
            return UploadResult(
              id: 'chunk-upload-${uploadRequests.length}',
              videoS3Key:
                  'uploads/editor/chunk-${uploadRequests.length - 1}.m4a',
              storageProvider: 's3',
            );
          },
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
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    for (var attempt = 0;
        attempt < 100 &&
            find.byKey(const ValueKey('ai-result-review')).evaluate().isEmpty;
        attempt += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      find.byKey(const ValueKey('ai-result-review')),
      findsOneWidget,
    );
    expect(uploadRequests, hasLength(2));
    expect(
      uploadRequests.map((request) => request.purpose),
      everyElement('ai-edit-audio'),
    );
    expect(prepareRequest?.audioS3Key, isNull);
    expect(prepareRequest?.durationSeconds, 150);
    expect(prepareRequest?.targetDurationSeconds, 30);
    expect(
      prepareRequest?.audioChunks?.map((chunk) => chunk.startSeconds).toList(),
      [0, 25],
    );
    expect(
      prepareRequest?.audioChunks?.map((chunk) => chunk.audioS3Key).toList(),
      ['uploads/editor/chunk-0.m4a', 'uploads/editor/chunk-1.m4a'],
    );
    expect(cleanedAudioKeys, [
      'uploads/editor/chunk-0.m4a',
      'uploads/editor/chunk-1.m4a',
    ]);
    expect(chunksDirectory!.existsSync(), isFalse);
  });

  testWidgets(
      'does not create a visual proxy when the user keeps the full source',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture(
      'full-source.mp4',
      durationSeconds: 150,
    );
    final renderedVideo = _createRenderedVideoFixture('full-result.mp4');
    var visualProxyCalls = 0;
    var planCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          initialTargetDurationSeconds: null,
          pickVideo: () async => pickedVideo,
          extractAudio: _extractAudioFixture,
          extractVisualProxy: (source) async {
            visualProxyCalls += 1;
            return _extractVisualProxyFixture(source);
          },
          cleanupAiEditAudio: (_) async {},
          cleanupAiEditVisualProxy: (_) async {},
          createUpload: (request) async => UploadResult(
            id: request.purpose ?? 'upload',
            videoS3Key: 'uploads/${request.fileName}',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(
            transcriptDurationSeconds: 150.8,
          ),
          planEdit: (_) async {
            planCalls += 1;
            return const AiEditPlanResult(
              cuts: [],
              summary: 'ไม่ต้องย่อ',
              model: 'test-plan',
            );
          },
          burnVideo: (_) async => renderedVideo,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(visualProxyCalls, 0);
    expect(planCalls, 0);
    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
  });

  testWidgets('opens Subtitle Studio before render and uses its edited output',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pickedVideo = _createPickedVideoFixture('subtitle-studio.mp4');
    final renderedVideo = _createRenderedVideoFixture('subtitle-edited.mp4');
    final store = _MemorySubtitleDraftStore();
    SubtitleProject? studioInput;
    BurnSubtitleRequest? renderRequest;
    const editedSubtitle =
        'ซับที่แก้แล้วมีข้อความภาษาไทยยาวเกินขอบและต้องแบ่งให้อ่านง่าย';

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          pickVideo: () async => pickedVideo,
          extractAudio: _extractAudioFixture,
          createUpload: (_) async => const UploadResult(
            id: 'subtitle-upload',
            videoS3Key: 'uploads/subtitle-audio.m4a',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          subtitleDraftStore: store,
          subtitleStudioLauncher:
              (context, sourceFile, initialProject, draftStore) async {
            studioInput = initialProject;
            final updatedStyle = SubtitleStyle(
              fontId: 'Anuphan',
              fontWeight: 700,
              fontSize: 30,
              textColor: '#00E5A8',
              activeWordColor: '#FFF45C',
              outlineColor: '#112233',
              outlineWidth: 3,
              shadowColor: '#445566',
              shadowDepth: 4,
              alignment: SubtitleAlignment.middle,
              normalizedX: 0.5,
              normalizedY: 0.5,
              maxLines: 1,
            );
            return initialProject.copyWith(
              cues: [
                initialProject.cues.first.copyWith(text: editedSubtitle),
              ],
              defaultStyle: updatedStyle,
              revision: initialProject.revision + 1,
              updatedAt: DateTime.utc(2026, 7, 22),
            );
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
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(studioInput?.cues.single.text, isNotEmpty);
    expect(renderRequest?.segments, hasLength(1));
    expect(
      renderRequest?.segments.map((segment) => segment.text).join(),
      editedSubtitle,
    );
    expect(renderRequest?.segments.single.text, editedSubtitle);
    expect(renderRequest?.subtitleFontName, 'Anuphan');
    expect(renderRequest?.subtitleFontSize, 30);
    expect(renderRequest?.subtitleTextColor, '#00E5A8');
    expect(renderRequest?.subtitleOutlineColor, '#112233');
    expect(renderRequest?.subtitleOutlineWidth, 3);
    expect(renderRequest?.subtitleShadowColor, '#445566');
    expect(renderRequest?.subtitleShadowDepth, 4);
    expect(
      renderRequest?.subtitleAlignment,
      BurnSubtitleAlignment.middle,
    );
    expect(find.byKey(const ValueKey('ai-result-review')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-review-edit-subtitles')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('ai-review-edit-subtitles')),
      findsOneWidget,
    );
  });

  testWidgets('stops before upload when the selected video has no audio',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('no-audio.mp4');
    var createUploadCalls = 0;
    var prepareCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: (_) async => throw const AiEditAudioExtractionException(
            AiEditAudioExtractionFailure.noAudioStream,
          ),
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          loadAiEditQuota: () async => const AiEditQuota(
            limitMinutes: 200,
            usedMinutes: 0,
            remainingMinutes: 200,
          ),
          createUpload: (_) async {
            createUploadCalls += 1;
            return const UploadResult(
              id: 'must-not-upload',
              videoS3Key: 'uploads/must-not-upload.m4a',
              storageProvider: 's3',
            );
          },
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async {
            prepareCalls += 1;
            return _createPrepareFixture();
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(createUploadCalls, 0);
    expect(prepareCalls, 0);
    expect(find.text('วิดีโอนี้ไม่มีเสียงให้ AI วิเคราะห์'), findsOneWidget);
  });

  testWidgets('review preview shows loading, error, and successful retry',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('retry-original.mp4');
    final renderedVideo = _createRenderedVideoFixture('retry-result.mp4');
    final initializeGate = Completer<void>();
    final controllers = <_FakeReviewVideoController>[];

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-retry-preview',
            videoS3Key: 'uploads/retry-original.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async => renderedVideo,
          reviewVideoControllerFactory: (_) {
            final controller = _FakeReviewVideoController(
              fakeDuration: const Duration(seconds: 20),
              initializeGate: controllers.isEmpty ? initializeGate : null,
              failInitialize: controllers.isEmpty,
            );
            controllers.add(controller);
            return controller;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('ai-review-video-loading')),
      findsOneWidget,
    );
    expect(find.text('กำลังเปิดผล AI...'), findsOneWidget);

    initializeGate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai-review-video-error')),
      findsOneWidget,
    );
    expect(find.text('เปิดผล AI ไม่ได้'), findsOneWidget);
    expect(controllers.first.disposed, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('ai-review-video-retry')),
    );
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    expect(
      find.byKey(const ValueKey('ai-review-seek-slider')),
      findsOneWidget,
    );
    expect(find.text('00:00 / 00:20'), findsOneWidget);
  });

  testWidgets('compares original and AI durations and still posts the AI file',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('compare-original.mp4');
    final renderedVideo = _createRenderedVideoFixture('compare-result.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-compare-preview',
            videoS3Key: 'uploads/compare-original.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async => renderedVideo,
          reviewVideoControllerFactory: (file) => _FakeReviewVideoController(
            fakeDuration: file.path == renderedVideo.file.path
                ? const Duration(seconds: 20)
                : const Duration(seconds: 45),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('ต้นฉบับ 00:45 → ผล AI 00:20 · สั้นลง 25 วิ'),
      findsOneWidget,
    );
    expect(find.text('compare-result.mp4'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('ai-review-file-source')),
          )
          .data,
      'ผล AI',
    );

    await tester.tap(
      find.byKey(const ValueKey('ai-review-source-original')),
    );
    await tester.pumpAndSettle();

    expect(find.text('compare-original.mp4'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('ai-review-file-source')),
          )
          .data,
      'ต้นฉบับ',
    );
    expect(find.text('00:00 / 00:45'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-review-post')));
    await tester.pumpAndSettle();

    final uploader = tester.widget<UploaderScreen>(find.byType(UploaderScreen));
    expect(uploader.initialVideoPath, renderedVideo.file.path);
  });

  testWidgets('updates the review frame while dragging and throttles seeks',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('live-seek-original.mp4');
    final renderedVideo = _createRenderedVideoFixture('live-seek-result.mp4');
    late final _FakeReviewVideoController controller;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-live-seek-preview',
            videoS3Key: 'uploads/live-seek-original.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async => renderedVideo,
          reviewVideoControllerFactory: (_) =>
              controller = _FakeReviewVideoController(
            fakeDuration: const Duration(seconds: 20),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-review-seek-slider')),
    );
    slider.onChangeStart!(2000);
    slider.onChanged!(2000);
    slider.onChanged!(5000);
    slider.onChanged!(8000);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('00:08 / 00:20'), findsOneWidget);
    expect(controller.value.position, const Duration(seconds: 8));
    expect(
      controller.calls.where((call) => call.startsWith('seek:')).toList(),
      ['seek:2000', 'seek:8000'],
    );
    expect(controller.maxActiveSeekCount, 1);

    slider.onChangeEnd!(9000);
    await tester.pumpAndSettle();

    expect(controller.value.position, const Duration(seconds: 9));
    expect(
      controller.calls.where((call) => call.startsWith('seek:')).last,
      'seek:9000',
    );
  });

  testWidgets('waits for an active live seek before the final seek and resume',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('seek-order-original.mp4');
    final renderedVideo = _createRenderedVideoFixture('seek-order-result.mp4');
    final seekGate = Completer<void>();
    late final _FakeReviewVideoController controller;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-seek-order-preview',
            videoS3Key: 'uploads/seek-order-original.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async => renderedVideo,
          reviewVideoControllerFactory: (_) =>
              controller = _FakeReviewVideoController(
            fakeDuration: const Duration(seconds: 20),
            seekGate: seekGate,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-review-video-preview')));
    await tester.pump();
    controller.calls.clear();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-review-seek-slider')),
    );
    slider.onChangeStart!(2000);
    slider.onChanged!(2000);
    slider.onChanged!(5000);
    slider.onChanged!(8000);
    await tester.pump();

    expect(find.text('00:08 / 00:20'), findsOneWidget);
    expect(
      controller.calls.where((call) => call.startsWith('seek:')).toList(),
      ['seek:2000'],
    );
    expect(controller.calls, isNot(contains('play')));

    slider.onChangeEnd!(9000);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.calls, isNot(contains('play')));

    seekGate.complete();
    await tester.pumpAndSettle();

    expect(
      controller.calls.where((call) => call.startsWith('seek:')).toList(),
      ['seek:2000', 'seek:9000'],
    );
    expect(controller.maxActiveSeekCount, 1);
    expect(controller.calls.last, 'play');
  });

  testWidgets('disposes the old player before opening another review source',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('serial-original.mp4');
    final renderedVideo = _createRenderedVideoFixture('serial-result.mp4');
    final disposeGate = Completer<void>();
    final controllers = <_FakeReviewVideoController>[];

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-serial-preview',
            videoS3Key: 'uploads/serial-original.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async => renderedVideo,
          reviewVideoControllerFactory: (_) {
            final controller = _FakeReviewVideoController(
              fakeDuration: const Duration(seconds: 20),
              disposeGate: controllers.isEmpty ? disposeGate : null,
            );
            controllers.add(controller);
            return controller;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('ai-review-source-original')),
    );
    await tester.pump();

    expect(controllers, hasLength(1));
    expect(controllers.first.disposed, isTrue);
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('ai-review-source-ai')),
      ),
      isSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: false,
      ),
    );

    disposeGate.complete();
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    expect(find.text('serial-original.mp4'), findsOneWidget);
  });

  testWidgets('keeps the review available after a transient seek failure',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('seek-original.mp4');
    final renderedVideo = _createRenderedVideoFixture('seek-result.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-seek-preview',
            videoS3Key: 'uploads/seek-original.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async => renderedVideo,
          reviewVideoControllerFactory: (_) => _FakeReviewVideoController(
            fakeDuration: const Duration(seconds: 20),
            failSeek: true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-review-seek-slider')),
    );
    slider.onChangeStart!(10000);
    slider.onChanged!(10000);
    slider.onChangeEnd!(10000);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai-review-video-error')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-review-seek-slider')),
      findsOneWidget,
    );
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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

  testWidgets('reuses a cached preview when an AI feature is added back',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('original.mp4');
    final firstResult = _createRenderedVideoFixture('ai-result-1.mp4');
    final secondResult = _createRenderedVideoFixture('ai-result-2.mp4');
    final renderRequests = <BurnSubtitleRequest>[];

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
            return renderRequests.length == 1 ? firstResult : secondResult;
          },
          reviewVideoControllerFactory: (_) => _FakeReviewVideoController(
            fakeDuration: const Duration(seconds: 30),
          ),
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
    await _pumpUntilPreviewUpdateFinishes(tester);

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
    await _pumpUntilPreviewUpdateFinishes(tester);

    expect(renderRequests, hasLength(2));
    expect(
      find.text('ai-result-1.mp4', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('shows render progress and lets the user cancel preview',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('cancel-preview.mp4');
    final renderResult = Completer<BurnedSubtitleResult>();
    var cancelCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-cancel-preview',
            videoS3Key: 'uploads/cancel-preview.m4a',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (request) async {
            request.onProgress?.call(0.42);
            await request.cancellationToken?.attach(() async {
              cancelCalls += 1;
              if (!renderResult.isCompleted) {
                renderResult.completeError(
                  const SubtitleBurnException('render cancelled'),
                );
              }
            });
            return renderResult.future;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('ai-render-progress')), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-render-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-render-cancel')));
    await tester.pumpAndSettle();

    expect(cancelCalls, 1);
    expect(find.byKey(const ValueKey('ai-render-progress')), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('ai-process-button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('uses a light preview and exports full quality before posting',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('quality-source.mp4');
    final preview = _createRenderedVideoFixture('quality-preview.mp4');
    final export = _createRenderedVideoFixture('quality-export.mp4');
    final requests = <BurnSubtitleRequest>[];

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-quality-preview',
            videoS3Key: 'uploads/quality-preview.m4a',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (request) async {
            requests.add(request);
            return request.renderPurpose == VideoRenderPurpose.preview
                ? preview
                : export;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.renderPurpose, VideoRenderPurpose.preview);
    expect(requests.single.maxVideoDimension, 720);
    expect(requests.single.videoBitrate, '2M');
    expect(requests.single.maxVideoFrameRate, 24);

    await tester.tap(find.byKey(const ValueKey('ai-review-post')));
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    expect(requests.last.renderPurpose, VideoRenderPurpose.export);
    expect(requests.last.maxVideoDimension, isNull);
    expect(requests.last.videoBitrate, isNull);
    expect(requests.last.maxVideoFrameRate, isNull);
    final uploader = tester.widget<UploaderScreen>(find.byType(UploaderScreen));
    expect(uploader.initialVideoPath, export.file.path);
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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

  testWidgets('reuses the transcript and only replans after changing duration',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('setup-change.mp4');
    final firstResult = _createRenderedVideoFixture('setup-result-1.mp4');
    final secondResult = _createRenderedVideoFixture('setup-result-2.mp4');
    final prepareRequests = <AiEditPrepareRequest>[];
    final planRequests = <AiEditPlanRequest>[];
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
          planEdit: (request) async {
            planRequests.add(request);
            return const AiEditPlanResult(
              cuts: [AiEditCut(start: 0, end: 5)],
              summary: 'เลือกช่วงใหม่',
              model: 'test-plan',
            );
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
    await _setTargetDuration(tester, 60);
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(prepareRequests, hasLength(1));
    expect(prepareRequests.first.durationSeconds, 150);
    expect(planRequests, hasLength(1));
    expect(planRequests.single.targetDurationSeconds, 60);
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-setup-failure',
            videoS3Key: 'uploads/setup-failure.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          planEdit: (_) async => const AiEditPlanResult(
            cuts: [],
            summary: 'เลือกช่วงใหม่',
            model: 'test-plan',
          ),
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
    await _setTargetDuration(tester, 60);
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
    expect(find.text('คลิปนี้ไม่ต้องแก้เพิ่ม'), findsOneWidget);
    expect(find.text('keep-original.mp4'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('ai-review-file-source')),
          )
          .data,
      'ต้นฉบับ',
    );
  });

  testWidgets('review status follows automatic preview removal and restore',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('review-status.mp4');
    var renderCalls = 0;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
          reviewVideoControllerFactory: (_) => _FakeReviewVideoController(
            fakeDuration: const Duration(seconds: 30),
          ),
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
    await _pumpUntilPreviewUpdateFinishes(tester);
    expect(renderCalls, 2);
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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

  testWidgets(
      'review shows when a selected capability was checked but not found',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('analysis-not-found.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-analysis-not-found',
            videoS3Key: 'uploads/analysis-not-found.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (_) async => _createPrepareFixture(),
          burnVideo: (_) async =>
              _createRenderedVideoFixture('analysis-not-found-result.mp4'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    final fillerResult = find.byKey(
      const ValueKey('ai-review-not-detected-filler'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      fillerResult,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(fillerResult, findsOneWidget);
    expect(
      find.descendant(of: fillerResult, matching: find.text('คำฟุ่มเฟือย')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: fillerResult,
        matching: find.text('ตรวจแล้ว · ไม่พบ'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fillerResult, matching: find.byType(Checkbox)),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('ai-review-not-detected-silence'),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });

  testWidgets('review analysis does not guess when status data is missing',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('analysis-zero.mp4');

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
      find.descendant(
        of: summary,
        matching: find.text('ไม่มีข้อมูลผลตรวจ'),
      ),
      findsNWidgets(2),
    );
    expect(
      find.byKey(
        const ValueKey('ai-review-not-detected-silence'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('ai-review-not-detected-filler'),
        skipOffstage: false,
      ),
      findsNothing,
      reason: 'Missing status must not be presented as a completed AI check.',
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
    await _setTargetDuration(tester, 60);
    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(prepareRequests, hasLength(2));
    expect(prepareRequests.last.capabilities['silence'], isFalse);
  });

  testWidgets('review action opens posting with the latest AI result',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('original-actions.mp4');
    final renderedVideo = _createRenderedVideoFixture('latest-ai-result.mp4');

    Widget buildScreen() => _testApp(
          AiEditingScreen(
            initialTargetDurationSeconds: 30,
            extractAudio: _extractAudioFixture,
            cleanupAiEditAudio: (_) async {},
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
    expect(
      find.byKey(const ValueKey('ai-review-edit-more')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('ai-review-post')));
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen), findsOneWidget);
    final uploader = tester.widget<UploaderScreen>(find.byType(UploaderScreen));
    expect(uploader.initialVideoPath, renderedVideo.file.path);
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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

    expect(
      find.byKey(const ValueKey('ai-capability-badge-beatsync')),
      findsOneWidget,
    );
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

  testWidgets(
      'hides deferred tools and excludes unavailable capabilities from prepare',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final pickedVideo =
        _createPickedVideoFixture('production-planned-locks.mp4');
    AiEditPrepareRequest? prepareRequest;
    const plannedCapabilities = <String, (String, String)>{
      'reframe': (
        'ปรับเป็น 9:16 อัตโนมัติ',
        'ระบบครอปและติดตามวัตถุในคลิปจริงกำลังพัฒนา',
      ),
      'zoom': (
        'ซูมเข้าตอนสำคัญ',
        'ระบบวิเคราะห์จุดสำคัญและซูมลงในคลิปจริงกำลังพัฒนา',
      ),
      'audio': (
        'ปรับเสียงให้ชัด',
        'ระบบลดเสียงรบกวนและปรับเสียงพูดในคลิปจริงกำลังพัฒนา',
      ),
    };
    const hiddenCapabilities = ['translate', 'pricetag', 'cta', 'watermark'];

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-production-planned-locks',
            videoS3Key: 'uploads/production-planned-locks.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (request) async {
            prepareRequest = request;
            return _createPrepareFixture();
          },
          burnVideo: (_) async =>
              _createRenderedVideoFixture('production-supported-result.mp4'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();

    for (final entry in plannedCapabilities.entries) {
      final capabilitySwitch = find.byKey(
        ValueKey('ai-capability-${entry.key}'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        capabilitySwitch,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('ai-capability-badge-${entry.key}')),
        findsOneWidget,
      );
      expect(find.text(entry.value.$2), findsOneWidget);
      expect(
        tester.getSemantics(capabilitySwitch),
        isSemantics(
          label: entry.value.$1,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: false,
        ),
      );
    }

    for (final capability in hiddenCapabilities) {
      expect(
        find.byKey(
          ValueKey('ai-capability-$capability'),
          skipOffstage: false,
        ),
        findsNothing,
      );
    }

    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    for (final capability in [
      ...plannedCapabilities.keys,
      ...hiddenCapabilities,
    ]) {
      expect(
        prepareRequest?.capabilities[capability],
        isFalse,
        reason: '$capability must stay out of the production render request',
      );
    }
    for (final capability in const [
      'subtitle',
      'silence',
      'filler',
      'color',
    ]) {
      expect(
        prepareRequest?.capabilities[capability],
        isTrue,
        reason: '$capability has a real production renderer',
      );
    }
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
        'Facebook Video',
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
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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
        'Facebook Video',
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
      'subtitle advanced settings only expose options supported by the renderer',
      (tester) async {
    await tester.pumpWidget(_testApp(const AiEditingScreen()));

    await _openAdvancedPanel(tester, 'subtitle');

    final panel = find.byKey(
      const ValueKey('ai-advanced-subtitle'),
      skipOffstage: false,
    );
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('ขนาดตัวอักษร')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text('สีซับเป็นสีขาวพร้อมขอบดำในเวอร์ชันนี้'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text('สั้น (ไม่เกิน 8 ตัวอักษร)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.textContaining('คาราโอเกะ')),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.text('กลาง')),
      findsOneWidget,
      reason: 'the only middle option is subtitle size, not a fake position',
    );
    expect(
      find.byKey(const ValueKey('ai-subtitle-position-center')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-subtitle-position-top')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-subtitle-position-bottom')),
      findsOneWidget,
    );
  });

  testWidgets('sends and renders only truthful subtitle settings',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pickedVideo = _createPickedVideoFixture('subtitle-settings.mp4');
    AiEditPrepareRequest? prepareRequest;
    BurnSubtitleRequest? burnRequest;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u-subtitle-settings',
            videoS3Key: 'uploads/subtitle-settings.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          prepareEdit: (request) async {
            prepareRequest = request;
            return _createPrepareFixture();
          },
          burnVideo: (request) async {
            burnRequest = request;
            return _createRenderedVideoFixture('subtitle-settings-result.mp4');
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();
    await _openAdvancedPanel(tester, 'subtitle');

    final shortText = find.byKey(
      const ValueKey('ai-subtitle-length-short'),
      skipOffstage: false,
    );
    final smallSize = find.byKey(
      const ValueKey('ai-subtitle-size-small'),
      skipOffstage: false,
    );
    final topPosition = find.byKey(
      const ValueKey('ai-subtitle-position-top'),
      skipOffstage: false,
    );
    tester.widget<Semantics>(shortText).properties.onTap!.call();
    tester.widget<Semantics>(smallSize).properties.onTap!.call();
    tester.widget<Semantics>(topPosition).properties.onTap!.call();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-process-button')));
    await tester.pumpAndSettle();

    expect(prepareRequest?.settings.subtitleStyle, 'outline');
    expect(prepareRequest?.settings.subtitleColor, '#FFFFFF');
    expect(prepareRequest?.settings.subtitleWordsPerLine, 1);
    expect(prepareRequest?.settings.subtitlePosition, 'top');
    expect(burnRequest?.subtitleFontSize, 17);
    expect(burnRequest?.subtitleAtBottom, isFalse);
  });

  testWidgets(
      'sends silence preset and selected filler words while blocking an empty selection',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('pace-settings.mp4');
    AiEditPrepareRequest? prepareRequest;

    await tester.pumpWidget(
      _testApp(
        AiEditingScreen(
          extractAudio: _extractAudioFixture,
          cleanupAiEditAudio: (_) async {},
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

  testWidgets('settings accordion opens one capability at a time',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_testApp(const AiEditingScreen()));

    expect(
      find.byKey(const ValueKey('ai-advanced-toggle')),
      findsNothing,
    );

    final silenceDisclosure = find.byKey(
      const ValueKey('ai-advanced-disclosure-silence'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      silenceDisclosure,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(silenceDisclosure).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(silenceDisclosure),
      isSemantics(
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
      ),
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-silence'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-color'), skipOffstage: false),
      findsNothing,
    );

    await tester.tap(silenceDisclosure);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(silenceDisclosure),
      isSemantics(
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-silence'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-advanced-color'), skipOffstage: false),
      findsNothing,
    );
    expect(find.text('ตัดช่วงเงียบเมื่อยาวตั้งแต่'), findsOneWidget);

    await _openAdvancedPanel(tester, 'color');
    expect(
      find.byKey(const ValueKey('ai-advanced-silence'), skipOffstage: false),
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

  testWidgets('uses one timeline slider instead of duration preset buttons',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('custom-duration.mp4');
    await tester.pumpWidget(
      _testApp(AiEditingScreen(
        initialTargetDurationSeconds: null,
        pickVideo: () async => pickedVideo,
      )),
    );

    await tester.tap(find.byKey(const ValueKey('ai-add-video')));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-duration-slider')),
    );
    expect(slider.min, 5);
    expect(slider.max, 150);
    expect(slider.value, 150);
    expect(
        find.byKey(const ValueKey('ai-custom-duration-field')), findsNothing);
    expect(find.text('30 วิ'), findsNothing);
    expect(find.text('1 นาที'), findsNothing);
    expect(find.text('กำหนดเอง'), findsNothing);
  });

  testWidgets('advanced layout fits the 390px reference phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(const AiEditingScreen()));

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
