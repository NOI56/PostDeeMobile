import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_audio_extractor.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _action = ValueKey('uploader-ai-generate-button');

RealClipCaptionResult _generated() => RealClipCaptionResult.fromJson({
      'caption': 'แคปชั่นจากเสียง',
      'captionOptions': <String>[],
      'hooks': <String>[],
      'hashtags': <String>[],
      'seoKeywords': <String>[],
      'searchTitle': '',
      'source': {
        'videoS3Key': 'uploads/owner-a/audio/clip.m4a',
        'mode': 'AUDIO_ONLY',
        'selectedFrameCount': 0
      },
      'quota': {
        'limit': 50,
        'usedThisMonth': 13,
        'remainingThisMonth': 37,
        'addonRemaining': 0,
        'availableGenerations': 37,
        'usageRefreshPending': false,
      },
    });

AiEditAudioArtifact _audioFixture({int sizeBytes = 512}) {
  final directory = Directory.systemTemp.createTempSync('caption-audio-');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  final file = File('${directory.path}/postdee-ai-edit-audio.m4a')
    ..writeAsBytesSync(List.filled(sizeBytes, 7));
  return AiEditAudioArtifact(file: file, workingDirectory: directory);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
  });

  Future<
      ({
        List<CreateUploadRequest> uploads,
        List<GenerateRealClipCaptionRequest> requests
      })> generateWith(
    WidgetTester tester, {
    required UploaderAudioExtractor extractCaptionAudio,
    // Above the 15,000,000-byte Gemini inline budget by default.
    int videoSizeBytes = 20000000,
  }) async {
    final uploads = <CreateUploadRequest>[];
    final requests = <GenerateRealClipCaptionRequest>[];
    final directory = Directory.systemTemp.createTempSync('caption-audio-ui-');
    final video = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: UploaderScreen(
          loadCaptionQuota: () async => const CaptionQuotaResult(
              plan: 'STARTER',
              quota: RealClipCaptionQuota(
                  limit: 50,
                  usedThisMonth: 12,
                  remainingThisMonth: 38,
                  addonRemaining: 0,
                  availableGenerations: 38)),
          draftStore: TestPublishDraftStore(ownerUserId: 'owner-a'),
          probePublishMedia: probeValidPublishMedia,
          loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
          initialVideoPath: video.path,
          initialVideoName: 'clip.mp4',
          initialVideoSizeBytes: videoSizeBytes,
          initialVideoWidth: 1080,
          initialVideoHeight: 1920,
          loadSocialConnections: () async => const [],
          enableRevenueCatBilling: false,
          loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'owner-a',
              plan: 'STARTER',
              status: 'ACTIVE',
              canUseAiCaptions: true,
              canSchedule: true,
              canUseAnalytics: false),
          extractCaptionAudio: extractCaptionAudio,
          createUpload: (request) async {
            uploads.add(request);
            return UploadResult(
                id: 'upload-${uploads.length}',
                videoS3Key: request.contentType == 'audio/mp4'
                    ? 'uploads/owner-a/audio/clip.m4a'
                    : 'uploads/owner-a/video/clip.mp4',
                storageProvider: 'mock');
          },
          uploadVideoFile: (_, __) async {},
          generateRealClipCaption: (request) async {
            requests.add(request);
            return _generated();
          },
        ))));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await tester.scrollUntilVisible(find.byKey(_action), 200,
        scrollable: uploaderMainScroll);
    await tester.ensureVisible(find.byKey(_action));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    return (uploads: uploads, requests: requests);
  }

  testWidgets('a clip Gemini can take whole is still uploaded as video',
      (tester) async {
    var extractions = 0;
    final result = await generateWith(
      tester,
      videoSizeBytes: 15000000,
      extractCaptionAudio: (_) async {
        extractions += 1;
        return _audioFixture();
      },
    );

    expect(extractions, 0);
    expect(result.uploads.single.purpose, 'ai-caption-video');
    expect(result.requests.single.videoS3Key, 'uploads/owner-a/video/clip.mp4');
  });

  testWidgets('a clip too big to send whole uploads only its audio',
      (tester) async {
    final audio = _audioFixture();
    final result = await generateWith(tester,
        extractCaptionAudio: (_) async => audio);

    expect(result.uploads, hasLength(1));
    expect(result.uploads.single.contentType, 'audio/mp4');
    expect(result.uploads.single.purpose, 'ai-edit-audio');
    expect(result.uploads.single.fileName, 'postdee-ai-edit-audio.m4a');
    expect(result.requests.single.audioS3Key, 'uploads/owner-a/audio/clip.m4a');
    expect(result.requests.single.toJson().containsKey('videoS3Key'), isFalse);
    expect(audio.file.existsSync(), isFalse);
  });

  testWidgets('falls back to the video upload when audio extraction fails',
      (tester) async {
    final result = await generateWith(tester,
        extractCaptionAudio: (_) async => throw const AiEditAudioExtractionException(
            AiEditAudioExtractionFailure.noAudioStream));

    expect(result.uploads.single.purpose, 'ai-caption-video');
    expect(result.requests.single.videoS3Key, 'uploads/owner-a/video/clip.mp4');
    expect(result.requests.single.audioS3Key, isNull);
  });

  testWidgets('explains instead of uploading audio over the caption limit',
      (tester) async {
    final audio = _audioFixture(sizeBytes: 15000001);
    final result = await generateWith(tester,
        extractCaptionAudio: (_) async => audio);

    expect(result.uploads, isEmpty);
    expect(result.requests, isEmpty);
    expect(audio.file.existsSync(), isFalse);
    expect(
      find.text('คลิปยาวเกินไปสำหรับ AI แคปชั่น ลองตัดให้สั้นลงแล้วลองใหม่'),
      findsOneWidget,
    );
  });

  test('GenerateRealClipCaptionRequest sends audio as audioS3Key', () {
    expect(
      const GenerateRealClipCaptionRequest(
        audioS3Key: 'uploads/owner-a/audio/clip.m4a',
        deleteAfterUse: true,
      ).toJson(),
      {'audioS3Key': 'uploads/owner-a/audio/clip.m4a', 'deleteAfterUse': true},
    );
  });
}
