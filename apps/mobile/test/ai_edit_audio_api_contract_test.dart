import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('AI edit audio upload serializes its narrow purpose', () {
    expect(
      const CreateUploadRequest(
        fileName: 'postdee-ai-edit.m4a',
        contentType: 'audio/mp4',
        sizeBytes: 1024,
        purpose: 'ai-edit-audio',
      ).toJson(),
      containsPair('purpose', 'ai-edit-audio'),
    );
  });

  test('AI edit prepare serializes audio and the requested result length', () {
    final json = const AiEditPrepareRequest(
      audioS3Key: 'uploads/seller/id/clip.m4a',
      durationSeconds: 60,
      targetDurationSeconds: 30,
    ).toJson();

    expect(json, containsPair('audioS3Key', 'uploads/seller/id/clip.m4a'));
    expect(json, containsPair('targetDurationSeconds', 30.0));
    expect(json.containsKey('videoS3Key'), isFalse);
  });

  test('AI edit prepare serializes ordered audio chunks', () {
    final json = const AiEditPrepareRequest(
      audioChunks: [
        AiEditAudioChunkRequest(
          audioS3Key: 'uploads/seller/id/chunk-000.m4a',
          startSeconds: 0,
        ),
        AiEditAudioChunkRequest(
          audioS3Key: 'uploads/seller/id/chunk-001.m4a',
          startSeconds: 30,
        ),
      ],
      durationSeconds: 60,
      targetDurationSeconds: 30,
    ).toJson();

    expect(json['audioChunks'], [
      {
        'audioS3Key': 'uploads/seller/id/chunk-000.m4a',
        'startSeconds': 0.0,
      },
      {
        'audioS3Key': 'uploads/seller/id/chunk-001.m4a',
        'startSeconds': 30.0,
      },
    ]);
    expect(json.containsKey('audioS3Key'), isFalse);
    expect(json.containsKey('videoS3Key'), isFalse);
  });

  test('AI edit replan serializes the cached transcript and new result length',
      () {
    final json = const AiEditPlanRequest(
      durationSeconds: 150,
      targetDurationSeconds: 60,
      segments: [
        ClipTranscriptSegment(
          text: 'ช่วงที่ดีที่สุด',
          start: 30,
          end: 90,
        ),
      ],
    ).toJson();

    expect(json, containsPair('targetDurationSeconds', 60.0));
    expect(json['segments'], hasLength(1));
  });

  test('AI edit visual plan serializes the owned whole-clip proxy key', () {
    final json = const AiEditPlanRequest(
      durationSeconds: 150,
      targetDurationSeconds: 45,
      segments: [],
      visualProxyS3Key: 'uploads/seller/id/visual-proxy.mp4',
    ).toJson();

    expect(
      json,
      containsPair(
        'visualProxyS3Key',
        'uploads/seller/id/visual-proxy.mp4',
      ),
    );
  });

  test('AI edit prepare keeps the legacy video-only request compatible', () {
    final json = const AiEditPrepareRequest(
      videoS3Key: 'uploads/seller/id/clip.mp4',
      durationSeconds: 60,
    ).toJson();

    expect(json, containsPair('videoS3Key', 'uploads/seller/id/clip.mp4'));
    expect(json.containsKey('audioS3Key'), isFalse);
  });

  test('AI edit prepare requires exactly one media key', () {
    expect(
      () => AiEditPrepareRequest(durationSeconds: 60),
      throwsAssertionError,
    );
    expect(
      () => AiEditPrepareRequest(
        audioS3Key: 'uploads/seller/id/clip.m4a',
        videoS3Key: 'uploads/seller/id/clip.mp4',
        durationSeconds: 60,
      ),
      throwsAssertionError,
    );
    expect(
      () => AiEditPrepareRequest(
        audioS3Key: 'uploads/seller/id/clip.m4a',
        audioChunks: const [
          AiEditAudioChunkRequest(
            audioS3Key: 'uploads/seller/id/chunk-000.m4a',
            startSeconds: 0,
          ),
        ],
        durationSeconds: 60,
      ),
      throwsAssertionError,
    );
  });

  test('cleanupAiEditAudio posts the owned temporary audio key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final apiClient = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        authHeaders: PostDeeApiAuthHeaders(
          authTokenProvider: () async => null,
          mockUserId: 'seller-test',
          mockSubscriptionPlan: 'PRO',
        ),
      );
      final cleanupFuture = apiClient.cleanupAiEditAudio(
        'uploads/seller-test/id/clip.m4a',
      );
      final request = await server.first;
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>;

      expect(request.method, 'POST');
      expect(request.uri.path, '/ai-edits/audio/cleanup');
      expect(body, {
        'audioS3Key': 'uploads/seller-test/id/clip.m4a',
      });

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok'}));
      await request.response.close();
      await cleanupFuture;
    } finally {
      await server.close(force: true);
    }
  });

  test('cleanupAiEditVisualProxy posts the owned temporary video key',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final apiClient = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        authHeaders: PostDeeApiAuthHeaders(
          authTokenProvider: () async => null,
          mockUserId: 'seller-test',
          mockSubscriptionPlan: 'PRO',
        ),
      );
      final cleanupFuture = apiClient.cleanupAiEditVisualProxy(
        'uploads/seller-test/id/visual-proxy.mp4',
      );
      final request = await server.first;
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>;

      expect(request.method, 'POST');
      expect(request.uri.path, '/ai-edits/visual-proxy/cleanup');
      expect(body, {
        'visualProxyS3Key': 'uploads/seller-test/id/visual-proxy.mp4',
      });

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok'}));
      await request.response.close();
      await cleanupFuture;
    } finally {
      await server.close(force: true);
    }
  });
}
