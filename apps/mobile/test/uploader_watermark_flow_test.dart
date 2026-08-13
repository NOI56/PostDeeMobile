import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/shared/growth_tool_settings_store.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:postdee_mobile/features/uploader/watermark_video_processor.dart';

Future<List<SocialConnectionResult>> _loadConnectedSocialConnections() async =>
    const [
      SocialConnectionResult(platform: 'TIKTOK', connected: true),
      SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: true),
    ];

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));

    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _waitUntilDeleted(Directory directory) async {
  for (var attempt = 0; attempt < 100 && directory.existsSync(); attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _EnabledWatermarkSettingsStore implements PostDeeGrowthToolSettingsStore {
  _EnabledWatermarkSettingsStore({required this.onLoad});

  final ValueChanged<String> onLoad;

  @override
  Future<GrowthToolSettings?> loadSettings(String toolId) async {
    onLoad(toolId);

    return const GrowthToolSettings(
      isEnabled: true,
      enabledOptionIds: {
        'shop_logo',
        'watermark_position_size',
        'preview_before_post',
      },
    );
  }

  @override
  Future<void> saveSettings(String toolId, GrowthToolSettings settings) async {}
}

class _TrackedWatermarkedVideoResult extends WatermarkedVideoResult {
  _TrackedWatermarkedVideoResult({
    required super.file,
    required super.fileName,
    required super.sizeBytes,
    required super.temporaryDirectory,
  });

  bool cleanupCalled = false;

  @override
  Future<void> cleanupTemporaryFiles() async {
    cleanupCalled = true;
    await super.cleanupTemporaryFiles();
  }
}

void main() {
  testWidgets('cleans watermark output after an upload error', (tester) async {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'postdee-watermark-error-test-',
    );
    addTearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    final inputFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}postdee-input.mp4',
    )..writeAsBytesSync([1, 2, 3]);
    final watermarkWorkingDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}watermark-output',
    )..createSync();
    final watermarkedFile = File(
      '${watermarkWorkingDirectory.path}${Platform.pathSeparator}postdee-watermarked.mp4',
    )..writeAsBytesSync([1, 2, 3, 4, 5]);
    var existedDuringUpload = false;
    late final _TrackedWatermarkedVideoResult watermarkResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSocialConnections: _loadConnectedSocialConnections,
            checkPublishingReadiness: () async {},
            growthToolSettingsStore: _EnabledWatermarkSettingsStore(
              onLoad: (_) {},
            ),
            pickVideo: () async => PickedVideoFile(
              name: 'seller-demo.mp4',
              path: inputFile.path,
              sizeBytes: inputFile.lengthSync(),
              width: 1080,
              height: 1920,
            ),
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
            watermarkVideo: (_) async =>
                watermarkResult = _TrackedWatermarkedVideoResult(
                  file: watermarkedFile,
                  fileName: 'seller-demo-watermarked.mp4',
                  sizeBytes: watermarkedFile.lengthSync(),
                  temporaryDirectory: watermarkWorkingDirectory,
                ),
            createUpload: (_) async => const UploadResult(
              id: 'upload-watermarked',
              videoS3Key: 'uploads/watermarked.mp4',
              storageProvider: 'mock',
            ),
            uploadVideoFile: (_, __) async {
              existedDuringUpload =
                  watermarkWorkingDirectory.existsSync() &&
                  watermarkedFile.existsSync();
              throw const ApiException(
                'upload failed',
                statusCode: HttpStatus.internalServerError,
              );
            },
            createPost: (_) async => throw StateError('must not create post'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('uploader-video-preview-picker')),
    );
    await _pumpUntilFound(tester, find.text('seller-demo.mp4'));
    final captionField = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.scrollUntilVisible(
      captionField,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(captionField, 'Watermark upload error');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('uploader-sticky-post-button')),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pump();
    await tester.runAsync(() => _waitUntilDeleted(watermarkWorkingDirectory));

    expect(existedDuringUpload, isTrue);
    expect(watermarkResult.cleanupCalled, isTrue);
    expect(watermarkWorkingDirectory.existsSync(), isFalse);
    expect(inputFile.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('watermarks a selected video before uploading when enabled', (
    tester,
  ) async {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'postdee-watermark-flow-test-',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));

    final inputFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}postdee-input.mp4',
    )..writeAsBytesSync([1, 2, 3]);
    final watermarkWorkingDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}watermark-output',
    )..createSync();
    final watermarkedFile = File(
      '${watermarkWorkingDirectory.path}${Platform.pathSeparator}postdee-watermarked.mp4',
    )..writeAsBytesSync([1, 2, 3, 4, 5]);
    final watermarkedFileSize = watermarkedFile.lengthSync();
    File? processedInputFile;
    String? processedFileName;
    CreateUploadRequest? createdUploadRequest;
    File? uploadedFile;
    String? loadedToolId;
    var subscriptionChecks = 0;
    var existedDuringUpload = false;
    late final _TrackedWatermarkedVideoResult watermarkResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSocialConnections: _loadConnectedSocialConnections,
            checkPublishingReadiness: () async {},
            growthToolSettingsStore: _EnabledWatermarkSettingsStore(
              onLoad: (toolId) => loadedToolId = toolId,
            ),
            pickVideo: () async => PickedVideoFile(
              name: 'seller-demo.mp4',
              path: inputFile.path,
              sizeBytes: inputFile.lengthSync(),
            ),
            loadSubscription: () async {
              subscriptionChecks += 1;

              return const SubscriptionStatusResult(
                userId: 'seller-pro',
                plan: 'PRO',
                status: 'ACTIVE',
                phoneVerified: true,
                requiresPhoneVerification: false,
                canUseFreePostQuota: false,
                canSchedule: true,
                canUseAiCaptions: true,
                canUseAnalytics: true,
              );
            },
            watermarkVideo: (request) async {
              processedInputFile = request.inputFile;
              processedFileName = request.fileName;

              return watermarkResult = _TrackedWatermarkedVideoResult(
                file: watermarkedFile,
                fileName: 'seller-demo-watermarked.mp4',
                sizeBytes: watermarkedFileSize,
                temporaryDirectory: watermarkWorkingDirectory,
              );
            },
            createUpload: (request) async {
              createdUploadRequest = request;

              return const UploadResult(
                id: 'upload-watermarked',
                videoS3Key: 'uploads/watermarked.mp4',
                storageProvider: 'mock',
              );
            },
            uploadVideoFile: (_, file) async {
              existedDuringUpload =
                  watermarkWorkingDirectory.existsSync() &&
                  watermarkedFile.existsSync();
              uploadedFile = file;
            },
            createPost: (request) async => QueuedPostResult(
              id: 'post-watermarked',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'QUEUED',
            ),
          ),
        ),
      ),
    );

    final pickVideoButton = find.byKey(
      const ValueKey('uploader-video-preview-picker'),
    );
    await tester.ensureVisible(pickVideoButton);
    await tester.pump();
    await tester.tap(pickVideoButton);
    await _pumpUntilFound(tester, find.text('seller-demo.mp4'));
    expect(find.text('seller-demo.mp4'), findsOneWidget);

    final captionField = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.scrollUntilVisible(
      captionField,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(captionField, 'Watermarked seller caption');
    await tester.pumpAndSettle();

    final postButton = find.descendant(
      of: find.byKey(const ValueKey('uploader-sticky-post-button')),
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(postButton).onPressed, isNotNull);
    await tester.tap(postButton);
    // Confirm on the publish-review screen (design screen #7).
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await _pumpUntilFound(
      tester,
      find.textContaining('ใส่ลายน้ำแล้ว'),
      maxPumps: 40,
    );
    await tester.runAsync(() => _waitUntilDeleted(watermarkWorkingDirectory));

    expect(subscriptionChecks, 1);
    expect(loadedToolId, 'auto_watermark');
    expect(processedInputFile?.path, inputFile.path);
    expect(processedFileName, 'seller-demo.mp4');
    expect(uploadedFile?.path, watermarkedFile.path);
    expect(existedDuringUpload, isTrue);
    expect(watermarkResult.cleanupCalled, isTrue);
    expect(watermarkWorkingDirectory.existsSync(), isFalse);
    expect(inputFile.existsSync(), isTrue);
    expect(createdUploadRequest?.fileName, 'seller-demo-watermarked.mp4');
    expect(createdUploadRequest?.sizeBytes, watermarkedFileSize);
    expect(find.textContaining('ใส่ลายน้ำแล้ว'), findsOneWidget);
  });
}
