import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/cover_editor_screen.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

PickedVideoFile _pickedVideo() {
  final directory = Directory.systemTemp.createTempSync('postdee-cover-flow-');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  final file = File('${directory.path}${Platform.pathSeparator}clip.mp4')
    ..writeAsBytesSync(List<int>.filled(2048, 1));
  return PickedVideoFile(
    name: 'clip.mp4',
    path: file.path,
    sizeBytes: file.lengthSync(),
    width: 1080,
    height: 1920,
  );
}

Future<void> _pickVideo(WidgetTester tester) async {
  final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
  await tester.ensureVisible(picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
}

Future<void> _enterCaption(WidgetTester tester) async {
  final caption = find.byKey(const ValueKey('uploader-caption-field'));
  await tester.scrollUntilVisible(
    caption,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(caption, 'โพสต์พร้อมหน้าปก');
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opens the cover editor and previews the saved cover',
      (tester) async {
    final pickedVideo = _pickedVideo();
    final coverFile = File('assets/images/brand/postdee_mark.png').absolute;
    CoverEditorRequest? editorRequest;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSocialConnections: () => SynchronousFuture(
              const [
                SocialConnectionResult(
                  platform: 'INSTAGRAM_REELS',
                  connected: true,
                ),
              ],
            ),
            pickVideo: () async => pickedVideo,
            openCoverEditor: (context, request) async {
              editorRequest = request;
              return CoverEditorResult(
                localImagePath: coverFile.path,
                sizeBytes: coverFile.lengthSync(),
                design: const CoverDesign(coverFrameTimeMs: 4500),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _pickVideo(tester);
    await tester.tap(find.byKey(const ValueKey('uploader-cover-edit-button')));
    await tester.pumpAndSettle();

    expect(editorRequest?.videoFile.path, pickedVideo.path);
    expect(editorRequest?.platforms.single.apiValue, 'INSTAGRAM_REELS');
    expect(
      find.byKey(const ValueKey('uploader-cover-preview-image')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('uploader-cover-time')), findsOneWidget);
  });

  testWidgets('uploads a custom cover and submits its metadata for Instagram',
      (tester) async {
    final pickedVideo = _pickedVideo();
    final coverFile = File('assets/images/brand/postdee_mark.png').absolute;
    final uploadRequests = <CreateUploadRequest>[];
    final uploadedPaths = <String>[];
    CreatePostRequest? postRequest;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            loadSocialConnections: () => SynchronousFuture(
              const [
                SocialConnectionResult(
                  platform: 'INSTAGRAM_REELS',
                  connected: true,
                ),
              ],
            ),
            checkPublishingReadiness: () async {},
            pickVideo: () async => pickedVideo,
            openCoverEditor: (context, request) async => CoverEditorResult(
              localImagePath: coverFile.path,
              sizeBytes: coverFile.lengthSync(),
              design: const CoverDesign(coverFrameTimeMs: 4500),
            ),
            loadSubscription: () => SynchronousFuture(
              const SubscriptionStatusResult(
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
            ),
            createUpload: (request) {
              uploadRequests.add(request);
              final isCover = request.contentType == 'image/jpeg';
              return SynchronousFuture(
                UploadResult(
                  id: isCover ? 'cover-upload' : 'video-upload',
                  videoS3Key: isCover
                      ? 'uploads/seller/postdee-cover.jpg'
                      : 'uploads/seller/clip.mp4',
                  storageProvider: 'mock',
                ),
              );
            },
            uploadVideoFile: (_, file) {
              uploadedPaths.add(file.path);
              return SynchronousFuture<void>(null);
            },
            createPost: (request) {
              postRequest = request;
              return SynchronousFuture(
                QueuedPostResult(
                  id: 'post-with-cover',
                  videoS3Key: request.videoS3Key,
                  platforms: request.platforms,
                  status: 'QUEUED',
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _pickVideo(tester);
    await tester.tap(find.byKey(const ValueKey('uploader-cover-edit-button')));
    await tester.pumpAndSettle();
    await _enterCaption(tester);
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('publish-review-cover-image')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('publish-review-cover-time')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    for (var attempt = 0; attempt < 10 && postRequest == null; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(uploadRequests, hasLength(2));
    expect(uploadRequests.last.contentType, 'image/jpeg');
    expect(uploadRequests.last.width, 1080);
    expect(uploadRequests.last.height, 1920);
    expect(uploadedPaths, containsAll([pickedVideo.path, coverFile.path]));
    expect(postRequest?.coverImageS3Key, 'uploads/seller/postdee-cover.jpg');
    expect(postRequest?.coverFrameTimeMs, 4500);
  });
}
