import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _expectTextAfterScrolling(
  WidgetTester tester,
  Finder scrollable,
  String text,
) async {
  final finder = find.text(text);

  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      expect(finder, findsOneWidget);
      return;
    }

    await tester.drag(scrollable, const Offset(0, -260));
    await tester.pumpAndSettle();
  }

  expect(finder, findsOneWidget);
}

Future<void> _tapTextAfterScrolling(
  WidgetTester tester,
  Finder scrollable,
  String text,
) async {
  await _expectTextAfterScrolling(tester, scrollable, text);
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

PickedVideoFile _createPickedVideoFixture(
  String name, {
  int sizeBytes = 2048,
}) {
  final directory = Directory.systemTemp.createTempSync('postdee-uploader-');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  final file = File('${directory.path}${Platform.pathSeparator}$name');
  file.writeAsBytesSync(List<int>.filled(sizeBytes, 1));

  return PickedVideoFile(
    name: name,
    path: file.path,
    sizeBytes: file.lengthSync(),
    width: 1080,
    height: 1920,
  );
}

Future<void> _pickVideoFromPreview(WidgetTester tester) async {
  final pickVideoButton =
      find.byKey(const ValueKey('uploader-video-preview-picker'));
  await tester.ensureVisible(pickVideoButton);
  await tester.pumpAndSettle();
  await tester.tap(pickVideoButton);
  await tester.pumpAndSettle();
}

Future<void> _enterUploadCaption(
  WidgetTester tester, {
  String caption = 'Real caption from seller',
}) async {
  final captionField = find.byKey(const ValueKey('uploader-caption-field'));
  await tester.scrollUntilVisible(
    captionField,
    500,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.enterText(captionField, caption);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final uploaderScroll = find.byType(Scrollable).first;

  RealClipCaptionResult buildRealClipCaptionResult({
    String caption = 'Generated SEO caption',
    List<String> hashtags = const ['viral', 'postdee'],
  }) =>
      RealClipCaptionResult(
        caption: caption,
        captionOptions: const ['Generated SEO caption'],
        hooks: const ['Hook one'],
        hashtags: hashtags,
        seoKeywords: const ['short video', 'affiliate seller'],
        searchTitle: 'Best moments from real-demo.mp4',
        source: const RealClipCaptionSource(
          videoS3Key: 'uploads/real-demo.mp4',
          mode: 'AUDIO_ONLY',
          selectedFrameCount: 0,
        ),
        quota: const RealClipCaptionQuota(
          limit: 50,
          usedThisMonth: 1,
          remainingThisMonth: 49,
        ),
      );

  testWidgets('shows the refreshed upload workflow sections', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UploaderScreen(),
        ),
      ),
    );

    expect(find.text('รอเลือกวิดีโอ 9:16'), findsOneWidget);
    expect(find.text('บันทึกฉบับร่าง'), findsNothing);
    expect(find.text('สถานะแพ็กเกจ'), findsNothing);
    expect(find.text('รีเฟรชแพ็กเกจ'), findsNothing);
    expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-quota-strip')), findsNothing);
    expect(find.textContaining('โพสต์: Free 3'), findsNothing);
    expect(find.textContaining('AI: 199 ฟังเสียง'), findsNothing);
    expect(
        find.text('เริ่มจากวิดีโอแนวตั้ง 9:16 ที่ต้องการโพสต์'), findsNothing);
    expect(find.text('1'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('เลือกแพลตฟอร์ม'),
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('เลือกแพลตฟอร์ม'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('uploader-step-platforms')),
      findsNothing,
    );
    expect(find.text('เลือกช่องทาง'), findsNothing);
    expect(
      find.text('เลือกว่าจะลง TikTok, Shorts, Reels หรือ Facebook'),
      findsNothing,
    );
    expect(find.text('2'), findsNothing);
    expect(find.text('พร้อมโพสต์'), findsNothing);
    expect(find.text('ปิดไว้'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('uploader-step-schedule')),
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('ตั้งเวลาโพสต์'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('uploader-step-schedule')), findsOneWidget);
    expect(
      find.text('เวลาไทย (GMT+7) · ตั้งเวลาได้ใน Starter/Pro'),
      findsOneWidget,
    );
    expect(find.text('ตั้งเวลาใช้ได้ใน Starter/Pro'), findsNothing);
    expect(find.text('โพสต์เลยหรือเลือกวันเวลาที่ต้องการ'), findsNothing);
    expect(find.text('3'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('uploader-advanced-tools-section')),
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('uploader-advanced-tools-section')),
      findsOneWidget,
    );
    expect(find.text('UI ก่อน'), findsNothing);
    expect(
      find.text(
        'เปิดเมื่อต้องการตัดคลิปเป็น EP หรือใส่ลายน้ำ ไม่จำเป็นต้องใช้ทุกครั้ง',
      ),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('uploader-step-caption')),
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-step-caption')), findsOneWidget);
    expect(
      find.text('ให้ AI คิดจากคลิปจริง หรือแก้แคปชั่นเองก่อนโพสต์'),
      findsNothing,
    );
    expect(find.text('4'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('โพสต์'),
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('โพสต์'), findsOneWidget);
  });

  testWidgets('shows compact EP trimming tool on the upload screen',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UploaderScreen(),
        ),
      ),
    );

    await _expectTextAfterScrolling(
      tester,
      uploaderScroll,
      'ตัดคลิปเป็น EP',
    );
    expect(
      find.byKey(const ValueKey('uploader-tool-ep-trimmer')),
      findsOneWidget,
    );
    expect(
      find.text('ตรวจความยาวคลิปก่อนโพสต์ และเตรียมร่าง EP.1 / EP.2 ให้'),
      findsNothing,
    );
    expect(find.text('เหมาะกับ Shorts/Reels'), findsNothing);
  });

  testWidgets('shows compact automatic watermark tool on the upload screen',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UploaderScreen(),
        ),
      ),
    );

    await _expectTextAfterScrolling(
      tester,
      uploaderScroll,
      'ใส่ลายน้ำอัตโนมัติ',
    );
    expect(
      find.byKey(const ValueKey('uploader-tool-auto-watermark')),
      findsOneWidget,
    );
    expect(find.text('ฝังโลโก้ร้านลงในวิดีโอก่อนโพสต์'), findsNothing);
    expect(find.text('กันขโมยคลิป'), findsNothing);
  });

  testWidgets('opens upload growth tool detail settings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UploaderScreen(),
        ),
      ),
    );

    final toolTitles = [
      'ตัดคลิปเป็น EP',
      'ใส่ลายน้ำอัตโนมัติ',
    ];

    for (final title in toolTitles) {
      await _tapTextAfterScrolling(tester, uploaderScroll, title);

      expect(find.text('รายละเอียดและตั้งค่า'), findsOneWidget);
      expect(find.text('ตั้งค่า: $title'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('growth-tool-real-status-note')),
        findsOneWidget,
      );
      expect(find.text('ตั้งค่าในเครื่องนี้'), findsOneWidget);
      expect(find.text('ยังไม่เชื่อมระบบจริง'), findsNothing);

      await tester.tap(find.byTooltip('ปิด'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('shows platform choices as a compact single row on phones',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UploaderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final platformTiles = [
      find.byKey(const ValueKey('uploader-platform-TIKTOK')),
      find.byKey(const ValueKey('uploader-platform-YOUTUBE_SHORTS')),
      find.byKey(const ValueKey('uploader-platform-INSTAGRAM_REELS')),
      find.byKey(const ValueKey('uploader-platform-FACEBOOK_REELS')),
    ];

    for (final tile in platformTiles) {
      expect(tile, findsOneWidget);
    }

    final firstTop = tester.getTopLeft(platformTiles.first).dy;
    for (final tile in platformTiles.skip(1)) {
      expect(
        (tester.getTopLeft(tile).dy - firstTop).abs(),
        lessThanOrEqualTo(8),
      );
    }
  });

  testWidgets('does not create uploads from demo metadata before video pick',
      (tester) async {
    final uploadRequests = <CreateUploadRequest>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'seller-pro',
              plan: 'PRO',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true,
            ),
            createUpload: (request) async {
              uploadRequests.add(request);
              return const UploadResult(
                id: 'upload-demo',
                videoS3Key: 'uploads/demo.mp4',
                storageProvider: 'mock',
              );
            },
            uploadVideoFile: (_, __) async {},
            createPost: (request) async => QueuedPostResult(
              id: 'post-demo',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'QUEUED',
            ),
          ),
        ),
      ),
    );

    final captionField = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.scrollUntilVisible(
      captionField,
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    await tester.enterText(captionField, 'Real caption from seller');
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();

    expect(uploadRequests, isEmpty);
    expect(find.textContaining('เลือกวิดีโอ'), findsWidgets);
  });

  testWidgets('keeps templates reachable from upload', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UploaderScreen(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('เทมเพลต'),
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('เทมเพลต'), findsOneWidget);
    expect(find.text('โหลดเทมเพลต'), findsOneWidget);
  });

  testWidgets('fills upload fields from a picked real video file',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async => const PickedVideoFile(
              name: 'real-demo.mp4',
              path: r'C:\videos\real-demo.mp4',
              sizeBytes: 2048,
            ),
          ),
        ),
      ),
    );

    final pickVideoButton =
        find.byKey(const ValueKey('uploader-video-preview-picker'));

    await tester.ensureVisible(pickVideoButton);
    await tester.pumpAndSettle();
    await tester.drag(uploaderScroll, const Offset(0, 160));
    await tester.pumpAndSettle();

    await tester.tap(pickVideoButton);
    await tester.pumpAndSettle();

    expect(find.text('real-demo.mp4'), findsOneWidget);

    await tester.drag(uploaderScroll, const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('รายละเอียดไฟล์', skipOffstage: false), findsNothing);
    expect(
      find.widgetWithText(
        TextField,
        'ชื่อไฟล์วิดีโอ',
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.widgetWithText(
        TextField,
        'พาธไฟล์ในเครื่อง (ถ้ามี)',
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.widgetWithText(
        TextField,
        'ขนาดไฟล์ (bytes)',
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.widgetWithText(TextField, 'กว้าง', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.widgetWithText(TextField, 'สูง', skipOffstage: false),
      findsNothing,
    );
    expect(find.text('mock_video.mp4'), findsNothing);
  });

  testWidgets('inserts a saved template into the upload caption',
      (tester) async {
    final loadCompleter = Completer<List<TextTemplateResult>>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadTemplates: () => loadCompleter.future,
          ),
        ),
      ),
    );

    final captionFinder = find.widgetWithText(TextField, 'แคปชั่น');

    await tester.scrollUntilVisible(
      captionFinder,
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();

    await tester.enterText(captionFinder, 'Main caption');

    await tester.ensureVisible(find.text('โหลดเทมเพลต'));
    await tester.tap(find.text('โหลดเทมเพลต'));
    await tester.pump();

    expect(find.text('กำลังโหลดเทมเพลต...'), findsOneWidget);

    loadCompleter.complete([
      TextTemplateResult(
        id: 'template-1',
        title: 'Affiliate disclosure',
        body: 'This post may contain affiliate links.',
        createdAt: DateTime.parse('2026-06-03T00:00:00.000Z'),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Affiliate disclosure'), findsOneWidget);
    expect(find.text('This post may contain affiliate links.'), findsOneWidget);

    await tester.ensureVisible(find.text('ใส่แคปชั่น'));
    await tester.tap(find.text('ใส่แคปชั่น'));
    await tester.pumpAndSettle();

    final captionField = tester.widget<TextField>(captionFinder);

    expect(
      captionField.controller!.text,
      'Main caption\n\nThis post may contain affiliate links.',
    );
  });

  testWidgets(
      'generates an AI caption from the selected clip and inserts hashtags',
      (tester) async {
    GenerateRealClipCaptionRequest? requestedRequest;
    CreateUploadRequest? createdUploadRequest;
    String? uploadedFilePath;
    List<String>? requestedKeywords;
    final pickedVideo = _createPickedVideoFixture('real-demo.mp4');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async => pickedVideo,
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'starter-user',
              plan: 'STARTER',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: false,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            createUpload: (request) async {
              createdUploadRequest = request;

              return const UploadResult(
                id: 'ai-upload-1',
                videoS3Key: 'uploads/real-demo.mp4',
                storageProvider: 's3',
              );
            },
            uploadVideoFile: (_, file) async {
              uploadedFilePath = file.path;
            },
            generateRealClipCaption: (request) async {
              requestedRequest = request;
              requestedKeywords = ['guidance:${request.guidance}'];

              return buildRealClipCaptionResult();
            },
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('uploader-video-preview-picker')));
    await tester.pumpAndSettle();

    final aiPanel = find.byKey(const ValueKey('uploader-ai-caption-panel'));
    await tester.scrollUntilVisible(
      aiPanel,
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('uploader-ai-guidance-field')),
      'ขอแบบขายจริงใจ',
    );
    await tester.tap(find.byKey(const ValueKey('uploader-ai-generate-button')));
    await tester.pumpAndSettle();

    expect(createdUploadRequest?.fileName, 'real-demo.mp4');
    expect(createdUploadRequest?.sizeBytes, pickedVideo.sizeBytes);
    expect(uploadedFilePath, pickedVideo.path);
    expect(requestedRequest, isNotNull);
    expect(requestedRequest!.videoS3Key, 'uploads/real-demo.mp4');
    expect(requestedRequest!.videoS3Key, isNot(startsWith('local-preview/')));
    expect(requestedKeywords, contains('guidance:ขอแบบขายจริงใจ'));
    expect(requestedRequest!.selectedFrameKeys, isEmpty);
    expect(requestedRequest!.deleteAfterUse, isTrue);

    final captionField = tester.widget<TextField>(
      find.byKey(const ValueKey('uploader-caption-field')),
    );

    expect(captionField.controller!.text, contains('Generated SEO caption'));
    expect(captionField.controller!.text, contains('#viral'));
    expect(captionField.controller!.text, contains('#postdee'));
  });

  testWidgets('Pro AI captions extract and upload frames for the model to see',
      (tester) async {
    GenerateRealClipCaptionRequest? requestedRequest;
    final createUploadRequests = <CreateUploadRequest>[];
    final pickedVideo = _createPickedVideoFixture('pro-demo.mp4');

    final frameDir = Directory.systemTemp.createTempSync('postdee-test-frames-');
    addTearDown(() => frameDir.deleteSync(recursive: true));
    final frame1 = File('${frameDir.path}${Platform.pathSeparator}f1.jpg')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final frame2 = File('${frameDir.path}${Platform.pathSeparator}f2.jpg')
      ..writeAsBytesSync([5, 6, 7, 8]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async => pickedVideo,
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'pro-user',
              plan: 'PRO',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true,
            ),
            extractFrames: (file, {int maxFrames = 3}) async => [frame1, frame2],
            createUpload: (request) async {
              createUploadRequests.add(request);
              final isImage = request.contentType.startsWith('image/');

              return UploadResult(
                id: 'u${createUploadRequests.length}',
                videoS3Key: isImage
                    ? 'uploads/frames/${request.fileName}'
                    : 'uploads/pro-demo.mp4',
                storageProvider: 's3',
              );
            },
            uploadVideoFile: (_, __) async {},
            generateRealClipCaption: (request) async {
              requestedRequest = request;

              return buildRealClipCaptionResult();
            },
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('uploader-video-preview-picker')));
    await tester.pumpAndSettle();

    final aiPanel = find.byKey(const ValueKey('uploader-ai-caption-panel'));
    await tester.scrollUntilVisible(aiPanel, 500, scrollable: uploaderScroll);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-ai-generate-button')));
    await tester.pumpAndSettle();

    // The clip plus two frames were uploaded; frame keys are sent to the model.
    final imageUploads = createUploadRequests
        .where((request) => request.contentType.startsWith('image/'))
        .toList();
    expect(imageUploads, hasLength(2));
    expect(requestedRequest, isNotNull);
    expect(requestedRequest!.selectedFrameKeys, [
      'uploads/frames/frame_1.jpg',
      'uploads/frames/frame_2.jpg',
    ]);
    expect(requestedRequest!.deleteAfterUse, isTrue);
  });

  testWidgets('lets AI infer caption language from the selected clip',
      (tester) async {
    GenerateRealClipCaptionRequest? requestedRequest;
    final pickedVideo = _createPickedVideoFixture('global-demo.mp4');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async => pickedVideo,
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'starter-user',
              plan: 'STARTER',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: false,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            createUpload: (_) async => const UploadResult(
              id: 'global-upload-1',
              videoS3Key: 'uploads/global-demo.mp4',
              storageProvider: 's3',
            ),
            uploadVideoFile: (_, __) async {},
            generateRealClipCaption: (request) async {
              requestedRequest = request;

              return buildRealClipCaptionResult();
            },
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('uploader-video-preview-picker')));
    await tester.pumpAndSettle();

    final aiPanel = find.byKey(const ValueKey('uploader-ai-caption-panel'));
    await tester.scrollUntilVisible(
      aiPanel,
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('uploader-ai-caption-language-field')),
        findsNothing);
    expect(find.byKey(const ValueKey('uploader-ai-target-market-field')),
        findsNothing);
    expect(find.byKey(const ValueKey('uploader-ai-lock-preferences')),
        findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('uploader-ai-guidance-field')),
      'ทำแคปชั่นเป็นภาษาญี่ปุ่นสำหรับตลาดญี่ปุ่น',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-ai-generate-button')));
    await tester.pumpAndSettle();

    expect(requestedRequest, isNotNull);
    expect(requestedRequest!.toJson().containsKey('captionLanguage'), isFalse);
    expect(requestedRequest!.toJson().containsKey('targetMarket'), isFalse);
    expect(requestedRequest!.toJson().containsKey('captionTone'), isFalse);
    expect(
      requestedRequest!.guidance,
      'ทำแคปชั่นเป็นภาษาญี่ปุ่นสำหรับตลาดญี่ปุ่น',
    );
  });

  testWidgets('frames upload AI captions as a real clip workflow',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UploaderScreen(),
        ),
      ),
    );

    final aiPanel = find.byKey(const ValueKey('uploader-ai-caption-panel'));
    await tester.scrollUntilVisible(
      aiPanel,
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('uploader-ai-real-clip-title')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-ai-guidance-field')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-ai-caption-language-field')),
        findsNothing);
    expect(find.byKey(const ValueKey('uploader-ai-target-market-field')),
        findsNothing);
    expect(find.byKey(const ValueKey('uploader-ai-lock-preferences')),
        findsNothing);
    expect(find.byKey(const ValueKey('uploader-ai-tone-viral')), findsNothing);
    expect(find.byKey(const ValueKey('uploader-ai-tone-sales')), findsNothing);
    expect(
        find.byKey(const ValueKey('uploader-ai-prompt-field')), findsNothing);
  });

  testWidgets('requires a selected clip before generating upload AI captions',
      (tester) async {
    var didGenerateCaption = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'starter-user',
              plan: 'STARTER',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            generateCaption: (_) async {
              didGenerateCaption = true;

              return const CaptionResult(
                caption: 'Should not generate',
                hashtags: [],
              );
            },
          ),
        ),
      ),
    );

    final aiPanel = find.byKey(const ValueKey('uploader-ai-caption-panel'));
    await tester.scrollUntilVisible(
      aiPanel,
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-ai-generate-button')));
    await tester.pumpAndSettle();

    expect(didGenerateCaption, isFalse);
    expect(find.text('เลือกคลิปก่อน แล้ว AI จะคิดแคปชั่นจากเสียงในคลิปนั้น'),
        findsOneWidget);
  });

  testWidgets('blocks upload AI captions for users without a paid package',
      (tester) async {
    var didGenerateCaption = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async => const PickedVideoFile(
              name: 'real-demo.mp4',
              path: r'C:\videos\real-demo.mp4',
              sizeBytes: 2048,
            ),
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'basic-user',
              plan: 'BASIC',
              status: 'INACTIVE',
              monthlyPostLimit: 3,
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: true,
              canSchedule: false,
              canUseAiCaptions: false,
              canUseAnalytics: false,
            ),
            generateCaption: (_) async {
              didGenerateCaption = true;

              return const CaptionResult(
                caption: 'Should not generate',
                hashtags: [],
              );
            },
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('uploader-video-preview-picker')));
    await tester.pumpAndSettle();

    final aiPanel = find.byKey(const ValueKey('uploader-ai-caption-panel'));
    await tester.scrollUntilVisible(
      aiPanel,
      500,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-ai-generate-button')));
    await tester.pumpAndSettle();

    expect(didGenerateCaption, isFalse);
    expect(find.textContaining('Starter 199'), findsOneWidget);
  });

  testWidgets('blocks scheduled posts for Basic users before uploading',
      (tester) async {
    var subscriptionChecks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async =>
                _createPickedVideoFixture('basic-scheduled.mp4'),
            loadSubscription: () async {
              subscriptionChecks += 1;

              return const SubscriptionStatusResult(
                userId: 'basic-user',
                plan: 'BASIC',
                status: 'INACTIVE',
                monthlyPostLimit: 3,
                phoneVerified: true,
                requiresPhoneVerification: false,
                canUseFreePostQuota: true,
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              );
            },
          ),
        ),
      ),
    );

    await _pickVideoFromPreview(tester);

    final scheduleButton =
        find.byKey(const ValueKey('uploader-schedule-later'));
    await tester.scrollUntilVisible(
      scheduleButton,
      300,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('uploader-schedule-summary')),
        findsOneWidget);
    await _enterUploadCaption(tester);

    final postButtonFinder = find.widgetWithText(TextButton, 'โพสต์');

    await tester.scrollUntilVisible(
      postButtonFinder,
      500,
      scrollable: uploaderScroll,
    );
    await tester.ensureVisible(postButtonFinder);
    await tester.pumpAndSettle();
    await tester.tap(postButtonFinder);
    await tester.pumpAndSettle();

    expect(subscriptionChecks, 1);
    expect(
      find.text('การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299'),
      findsOneWidget,
    );
    expect(find.text('กำลังโพสต์...'), findsNothing);
  });

  testWidgets(
      'uses quick day chips and custom time control for scheduled posts',
      (tester) async {
    CreatePostRequest? createdPostRequest;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async =>
                _createPickedVideoFixture('quick-scheduled.mp4'),
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'seller-starter',
              plan: 'STARTER',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            createUpload: (_) async => const UploadResult(
              id: 'upload-1',
              videoS3Key: 'uploads/quick-scheduled.mp4',
              storageProvider: 'mock',
            ),
            uploadVideoFile: (_, __) async {},
            createPost: (request) async {
              createdPostRequest = request;

              return QueuedPostResult(
                id: 'post-quick-scheduled',
                videoS3Key: request.videoS3Key,
                platforms: request.platforms,
                status: 'QUEUED',
              );
            },
          ),
        ),
      ),
    );

    await _pickVideoFromPreview(tester);

    final scheduleButton =
        find.byKey(const ValueKey('uploader-schedule-later'));
    await tester.scrollUntilVisible(
      scheduleButton,
      300,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('uploader-schedule-at-field')), findsNothing);
    expect(find.byKey(const ValueKey('uploader-schedule-day-tomorrow')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-schedule-time-1830')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-schedule-time-2000')),
        findsNothing);
    expect(find.byKey(const ValueKey('uploader-schedule-time-custom')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-schedule-summary')),
        findsOneWidget);
    await _enterUploadCaption(tester);

    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();

    expect(createdPostRequest?.scheduledAt, isNotNull);
    expect(createdPostRequest?.scheduledAt?.toLocal().hour, 18);
    expect(createdPostRequest?.scheduledAt?.toLocal().minute, 30);
  });

  testWidgets('notifies when a Starter scheduled post is created successfully',
      (tester) async {
    QueuedPostResult? notifiedPost;
    CreatePostRequest? createdPostRequest;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async =>
                _createPickedVideoFixture('starter-scheduled.mp4'),
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'seller-starter',
              plan: 'STARTER',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            createUpload: (_) async => const UploadResult(
              id: 'upload-1',
              videoS3Key: 'uploads/scheduled.mp4',
              storageProvider: 'mock',
            ),
            uploadVideoFile: (_, __) async {},
            createPost: (request) async {
              createdPostRequest = request;

              return QueuedPostResult(
                id: 'post-scheduled',
                videoS3Key: request.videoS3Key,
                platforms: request.platforms,
                status: 'QUEUED',
              );
            },
            onScheduledPostCreated: (post) {
              notifiedPost = post;
            },
          ),
        ),
      ),
    );

    await _pickVideoFromPreview(tester);

    final scheduleButton =
        find.byKey(const ValueKey('uploader-schedule-later'));
    await tester.scrollUntilVisible(
      scheduleButton,
      300,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();
    await _enterUploadCaption(tester);
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();

    expect(createdPostRequest?.scheduledAt, isNotNull);
    expect(notifiedPost?.id, 'post-scheduled');
  });

  testWidgets('rejects a scheduled post whose time is already in the past',
      (tester) async {
    var createPostCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            // Pin "now" far in the future so the default tomorrow 18:30 schedule
            // counts as being in the past at submit time.
            now: () => DateTime(2100),
            pickVideo: () async =>
                _createPickedVideoFixture('past-scheduled.mp4'),
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'seller-starter',
              plan: 'STARTER',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            createUpload: (_) async => const UploadResult(
              id: 'upload-1',
              videoS3Key: 'uploads/past-scheduled.mp4',
              storageProvider: 'mock',
            ),
            uploadVideoFile: (_, __) async {},
            createPost: (request) async {
              createPostCalls += 1;

              return QueuedPostResult(
                id: 'post-past',
                videoS3Key: request.videoS3Key,
                platforms: request.platforms,
                status: 'QUEUED',
              );
            },
          ),
        ),
      ),
    );

    await _pickVideoFromPreview(tester);

    final scheduleButton =
        find.byKey(const ValueKey('uploader-schedule-later'));
    await tester.scrollUntilVisible(
      scheduleButton,
      300,
      scrollable: uploaderScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();
    await _enterUploadCaption(tester);

    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();

    expect(createPostCalls, 0);
    expect(find.text('เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต'), findsOneWidget);
  });

  testWidgets('keeps plan status hidden before posting', (tester) async {
    var subscriptionChecks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSubscription: () async {
              subscriptionChecks += 1;

              return SubscriptionStatusResult(
                userId: 'seller-user',
                plan: subscriptionChecks == 1 ? 'BASIC' : 'PRO',
                status: subscriptionChecks == 1 ? 'INACTIVE' : 'ACTIVE',
                monthlyPostLimit: subscriptionChecks == 1 ? 3 : null,
                usedPostsThisMonth: subscriptionChecks == 1 ? 2 : null,
                remainingPostsThisMonth: subscriptionChecks == 1 ? 1 : null,
                phoneVerified: subscriptionChecks == 1,
                requiresPhoneVerification: false,
                canUseFreePostQuota: subscriptionChecks == 1,
                canSchedule: subscriptionChecks > 1,
                canUseAiCaptions: subscriptionChecks > 1,
                canUseAnalytics: subscriptionChecks > 1,
              );
            },
          ),
        ),
      ),
    );

    expect(subscriptionChecks, 0);
    expect(find.text('สถานะแพ็กเกจ'), findsNothing);
    expect(find.text('รีเฟรชแพ็กเกจ'), findsNothing);
    expect(find.text('แพ็กเกจ: Basic'), findsNothing);
    expect(find.text('แพ็กเกจ: Pro'), findsNothing);
  });

  testWidgets('keeps phone verification requirement hidden before posting',
      (tester) async {
    var subscriptionChecks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSubscription: () async {
              subscriptionChecks += 1;

              return const SubscriptionStatusResult(
                userId: 'seller-basic',
                plan: 'BASIC',
                status: 'INACTIVE',
                monthlyPostLimit: 3,
                usedPostsThisMonth: 0,
                remainingPostsThisMonth: 0,
                phoneVerified: false,
                requiresPhoneVerification: true,
                canUseFreePostQuota: false,
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              );
            },
          ),
        ),
      ),
    );

    expect(subscriptionChecks, 0);
    expect(
      find.text('ยืนยันเบอร์โทรก่อนใช้โควต้าโพสต์ฟรี 3 ครั้งต่อเดือน'),
      findsNothing,
    );
  });

  testWidgets('asks for phone verification when posting from Basic free plan',
      (tester) async {
    var subscriptionChecks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async => _createPickedVideoFixture('phone-basic.mp4'),
            loadSubscription: () async {
              subscriptionChecks += 1;

              return const SubscriptionStatusResult(
                userId: 'seller-basic',
                plan: 'BASIC',
                status: 'INACTIVE',
                monthlyPostLimit: 3,
                usedPostsThisMonth: 0,
                remainingPostsThisMonth: 0,
                phoneVerified: false,
                requiresPhoneVerification: true,
                canUseFreePostQuota: false,
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              );
            },
          ),
        ),
      ),
    );

    await _pickVideoFromPreview(tester);
    await _enterUploadCaption(tester);

    final postButtonFinder = find.widgetWithText(TextButton, 'โพสต์');

    await tester.scrollUntilVisible(
      postButtonFinder,
      500,
      scrollable: uploaderScroll,
    );
    await tester.ensureVisible(postButtonFinder);
    await tester.pumpAndSettle();
    await tester.tap(postButtonFinder);
    await tester.pumpAndSettle();

    expect(subscriptionChecks, 1);
    expect(
      find.text('ยืนยันเบอร์โทรก่อนโพสต์ฟรี 3 ครั้งต่อเดือน'),
      findsOneWidget,
    );
    expect(find.text('กำลังโพสต์...'), findsNothing);
  });

  testWidgets('shows a friendly plan connection error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            pickVideo: () async => _createPickedVideoFixture('plan-error.mp4'),
            loadSubscription: () async {
              throw const SocketException('Connection refused');
            },
            uploadVideoFile: (_, __) async {},
          ),
        ),
      ),
    );

    await _pickVideoFromPreview(tester);
    await _enterUploadCaption(tester);

    final postButtonFinder = find.widgetWithText(TextButton, 'โพสต์');

    await tester.scrollUntilVisible(
      postButtonFinder,
      500,
      scrollable: uploaderScroll,
    );
    await tester.ensureVisible(postButtonFinder);
    await tester.pumpAndSettle();
    await tester.tap(postButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text('เชื่อมต่อ PostDee API ไม่ได้'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('blocks non 9:16 video dimensions before creating a post',
      (tester) async {
    final videoFile = File('test/uploader_screen_test.dart').absolute;
    var uploadRequests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'seller-starter',
              plan: 'STARTER',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            pickVideo: () async => PickedVideoFile(
              name: 'landscape-demo.mp4',
              path: videoFile.path,
              sizeBytes: videoFile.lengthSync(),
              width: 1920,
              height: 1080,
            ),
            createUpload: (_) async {
              uploadRequests += 1;
              return const UploadResult(
                id: 'upload-landscape',
                videoS3Key: 'uploads/landscape-demo.mp4',
                storageProvider: 'mock',
              );
            },
            uploadVideoFile: (_, __) async {},
            createPost: (request) async => QueuedPostResult(
              id: 'post-landscape',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'QUEUED',
            ),
          ),
        ),
      ),
    );

    final pickVideoButton =
        find.byKey(const ValueKey('uploader-video-preview-picker'));

    await tester.ensureVisible(pickVideoButton);
    await tester.pump();
    await tester.tap(pickVideoButton);
    await tester.pump();

    expect(find.text('landscape-demo.mp4'), findsOneWidget);
    await _enterUploadCaption(tester);

    final postButtonFinder = find.widgetWithText(TextButton, 'โพสต์');

    await tester.ensureVisible(postButtonFinder);
    await tester.pump();
    await tester.tap(postButtonFinder);
    await tester.pump();

    expect(
      find.text('ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920'),
      findsOneWidget,
    );
    expect(uploadRequests, 0);
    expect(find.text('กำลังโพสต์...'), findsNothing);
  });

  testWidgets('posts a clip handed in via initialVideoPath without re-picking',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('postdee-initial-');
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final videoFile =
        File('${directory.path}${Platform.pathSeparator}edited.mp4');
    videoFile.writeAsBytesSync(List<int>.filled(2048, 1));

    CreatePostRequest? postRequest;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            initialVideoPath: videoFile.path,
            initialVideoName: 'edited.mp4',
            initialVideoSizeBytes: 2048,
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'seller-pro',
              plan: 'PRO',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true,
            ),
            createUpload: (_) async => const UploadResult(
              id: 'upload-edited',
              videoS3Key: 'uploads/edited.mp4',
              storageProvider: 'mock',
            ),
            uploadVideoFile: (_, __) async {},
            createPost: (request) async {
              postRequest = request;
              return QueuedPostResult(
                id: 'post-edited',
                videoS3Key: request.videoS3Key,
                platforms: request.platforms,
                status: 'QUEUED',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The handed-over clip is already loaded — no gallery re-pick needed.
    expect(find.text('edited.mp4'), findsWidgets);

    await _enterUploadCaption(tester, caption: 'แคปชั่นคลิปที่ตัดแล้ว');
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();

    expect(postRequest, isNotNull);
    expect(postRequest!.videoS3Key, 'uploads/edited.mp4');
  });
}
