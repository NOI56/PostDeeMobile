import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/ai_editing_screen.dart';
import 'package:postdee_mobile/features/ai_editing/capcut_editor_screen.dart';
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

void main() {
  testWidgets('uploads the picked clip before opening the editor',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('editor-real.mp4');
    CreateUploadRequest? createdUploadRequest;
    String? uploadedFilePath;
    String? transcribedVideoS3Key;

    await tester.pumpWidget(
      MaterialApp(
        home: AiEditingScreen(
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
          transcribeClip: (videoS3Key) async {
            transcribedVideoS3Key = videoS3Key;

            return const ClipTranscriptResult(
              text: 'Editor transcript',
              segments: [
                ClipTranscriptSegment(
                  text: 'Editor transcript',
                  start: 0,
                  end: 2,
                ),
              ],
              durationSeconds: 2,
            );
          },
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.video_library_outlined));
    await tester.pumpAndSettle();

    expect(createdUploadRequest?.fileName, 'editor-real.mp4');
    expect(createdUploadRequest?.sizeBytes, pickedVideo.sizeBytes);
    expect(createdUploadRequest?.width, 1080);
    expect(createdUploadRequest?.height, 1920);
    expect(uploadedFilePath, pickedVideo.path);
    expect(find.byType(CapCutEditorScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.closed_caption_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.pumpAndSettle();

    expect(transcribedVideoS3Key, 'uploads/editor-real.mp4');
    expect(transcribedVideoS3Key, isNot(startsWith('local-preview/')));
  });

  testWidgets('picking a style on the entry opens the editor with it applied',
      (tester) async {
    final pickedVideo = _createPickedVideoFixture('styled.mp4');

    await tester.pumpWidget(
      MaterialApp(
        home: AiEditingScreen(
          pickVideo: () async => pickedVideo,
          createUpload: (_) async => const UploadResult(
            id: 'u1',
            videoS3Key: 'uploads/styled.mp4',
            storageProvider: 's3',
          ),
          uploadVideoFile: (_, __) async {},
          transcribeClip: (_) async => const ClipTranscriptResult(
            text: 'hi',
            segments: [ClipTranscriptSegment(text: 'hi', start: 0, end: 2)],
            durationSeconds: 2,
          ),
        ),
      ),
    );

    // The 10 style examples are listed on the entry screen.
    expect(find.text('ป้ายยาฉับไว'), findsOneWidget);

    await tester.tap(find.text('ป้ายยาฉับไว'));
    await tester.pumpAndSettle();

    // Opened the editor and auto-applied the style (banner shows the estimate).
    expect(find.byType(CapCutEditorScreen), findsOneWidget);
    expect(find.textContaining('จะเหลือ'), findsOneWidget);
  });
}
