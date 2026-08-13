import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/config/app_config.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

Future<Map<String, Object?>> _readJsonRequest(HttpRequest request) async {
  final body = utf8.decode(await _readRequestBytes(request));
  if (body.isEmpty) {
    return <String, Object?>{};
  }

  return jsonDecode(body) as Map<String, Object?>;
}

Future<List<int>> _readRequestBytes(HttpRequest request) => request.fold(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );

void _writeJsonResponse(
  HttpResponse response,
  Map<String, Object?> body, {
  int statusCode = HttpStatus.ok,
}) {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}

void main() {
  test('CreatePostRequest serializes optional cover metadata', () {
    final request = CreatePostRequest(
      clientRequestId: 'draft-123',
      caption: 'สินค้าใหม่',
      videoS3Key: 'uploads/seller/video.mp4',
      platforms: const ['TIKTOK', 'INSTAGRAM_REELS'],
      coverImageS3Key: 'uploads/seller/cover.jpg',
      coverFrameTimeMs: 4250,
    );

    expect(request.toJson(), {
      'clientRequestId': 'draft-123',
      'caption': 'สินค้าใหม่',
      'videoS3Key': 'uploads/seller/video.mp4',
      'platforms': ['TIKTOK', 'INSTAGRAM_REELS'],
      'coverImageS3Key': 'uploads/seller/cover.jpg',
      'coverFrameTimeMs': 4250,
    });
    expect(
      const CreatePostRequest(
        clientRequestId: 'draft-456',
        caption: 'ไม่มีภาพปก',
        videoS3Key: 'uploads/seller/video.mp4',
        platforms: ['YOUTUBE_SHORTS'],
      ).toJson(),
      isNot(containsPair('coverImageS3Key', anything)),
    );
  });

  test('ApiHealthResult parses backend health payload', () {
    final health = ApiHealthResult.fromJson({
      'status': 'ok',
      'service': 'postdee-api',
    });

    expect(health.status, 'ok');
    expect(health.service, 'postdee-api');
    expect(health.isOk, isTrue);
  });

  test('checkPublishingReadiness accepts a ready publishing service', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverTask = () async {
      final request = await server.first;

      expect(request.method, 'GET');
      expect(request.uri.path, '/publishing/readiness');
      await request.drain<void>();
      _writeJsonResponse(request.response, {
        'status': 'ok',
        'acceptingPosts': true,
        'platformSettingsVersion': 1,
      });
      await request.response.close();
    }();

    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );

      await client.checkPublishingReadiness();
      await serverTask;
    } finally {
      await server.close(force: true);
    }
  });

  for (final unsupportedVersion in <Object?>[null, 0, 1.0, '1']) {
    test(
        'checkPublishingReadiness rejects unsupported platform settings version $unsupportedVersion',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverTask = () async {
        final request = await server.first;

        expect(request.method, 'GET');
        expect(request.uri.path, '/publishing/readiness');
        await request.drain<void>();
        _writeJsonResponse(request.response, {
          'status': 'ok',
          'acceptingPosts': true,
          if (unsupportedVersion != null)
            'platformSettingsVersion': unsupportedVersion,
        });
        await request.response.close();
      }();

      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
        );

        await expectLater(
          client.checkPublishingReadiness(),
          throwsA(
            isA<ApiException>()
                .having(
                  (error) => error.code,
                  'code',
                  platformSettingsUnsupportedCode,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('อัปเดต PostDee API'),
                ),
          ),
        );
        await serverTask;
      } finally {
        await server.close(force: true);
      }
    });
  }

  test('CreatePostRequest serializes selected platform settings', () {
    const request = CreatePostRequest(
      clientRequestId: 'draft-platform-settings',
      caption: 'สินค้าใหม่',
      videoS3Key: 'uploads/seller/video.mp4',
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
      platformSettings: {
        'TIKTOK': {'publishMode': 'INBOX_DRAFT'},
        'YOUTUBE_SHORTS': {
          'title': 'คลิปสินค้า',
          'visibility': 'unlisted',
          'madeForKids': false,
          'containsSyntheticMedia': true,
          'communityGuidelinesCertified': true,
        },
      },
    );

    expect(
        request.toJson(),
        containsPair('platformSettings', {
          'TIKTOK': {'publishMode': 'INBOX_DRAFT'},
          'YOUTUBE_SHORTS': {
            'title': 'คลิปสินค้า',
            'visibility': 'unlisted',
            'madeForKids': false,
            'containsSyntheticMedia': true,
            'communityGuidelinesCertified': true,
          },
        }));
  });

  test(
      'createPost exposes an idempotent replay without changing the post shape',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverTask = () async {
      final request = await server.first;

      expect(request.method, 'POST');
      expect(request.uri.path, '/posts');
      expect(await _readJsonRequest(request),
          containsPair('clientRequestId', 'draft-123'));
      _writeJsonResponse(request.response, {
        'status': 'ok',
        'idempotentReplay': true,
        'post': {
          'id': 'post-1',
          'videoS3Key': 'uploads/seller/video.mp4',
          'platforms': ['TIKTOK'],
          'status': 'PUBLISHED',
          'deliveryOutcome': 'DRAFT',
        },
      });
      await request.response.close();
    }();

    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final result = await client.createPost(
        const CreatePostRequest(
          clientRequestId: 'draft-123',
          caption: 'Already published',
          videoS3Key: 'uploads/seller/video.mp4',
          platforms: ['TIKTOK'],
        ),
      );

      expect(result.id, 'post-1');
      expect(result.status, 'PUBLISHED');
      expect(result.idempotentReplay, isTrue);
      await serverTask;
    } finally {
      await server.close(force: true);
    }
  });

  test('createPost exposes a failed idempotent attempt for explicit recovery',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final resultFuture = client.createPost(
        const CreatePostRequest(
          clientRequestId: 'draft-failed-123',
          caption: 'Failed original attempt',
          videoS3Key: 'uploads/seller/video.mp4',
          platforms: ['TIKTOK'],
        ),
      );
      final expectation = expectLater(
        resultFuture,
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.conflict,
              )
              .having(
                (error) => error.code,
                'code',
                idempotentPostFailedCode,
              )
              .having((error) => error.postId, 'postId', 'post-failed-1'),
        ),
      );
      final request = await server.first;
      await request.drain<void>();
      _writeJsonResponse(
        request.response,
        {
          'status': 'error',
          'code': idempotentPostFailedCode,
          'message': 'The original post request failed.',
          'postId': 'post-failed-1',
        },
        statusCode: HttpStatus.conflict,
      );
      await request.response.close();

      await expectation;
    } finally {
      await server.close(force: true);
    }
  });

  test('checkPublishingReadiness preserves the unavailable error contract',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverTask = () async {
      final request = await server.first;

      expect(request.method, 'GET');
      expect(request.uri.path, '/publishing/readiness');
      await request.drain<void>();
      _writeJsonResponse(
        request.response,
        {
          'status': 'error',
          'code': 'SOCIAL_PUBLISHING_UNAVAILABLE',
          'message':
              'Social publishing is temporarily unavailable. Please try again later.',
        },
        statusCode: HttpStatus.serviceUnavailable,
      );
      await request.response.close();
    }();

    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );

      await expectLater(
        client.checkPublishingReadiness(),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.serviceUnavailable,
              )
              .having(
                (error) => error.code,
                'code',
                socialPublishingUnavailableCode,
              ),
        ),
      );
      await serverTask;
    } finally {
      await server.close(force: true);
    }
  });

  test('publishPostNow sends an authenticated command to its endpoint',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        authHeaders: PostDeeApiAuthHeaders(
          authTokenProvider: () async => 'firebase-id-token',
        ),
      );
      final resultFuture = client.publishPostNow('post-1');
      final request = await server.first;

      expect(request.method, 'POST');
      expect(request.uri.path, '/posts/post-1/publish-now');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer firebase-id-token',
      );
      expect(await _readJsonRequest(request), isEmpty);
      _writeJsonResponse(request.response, {'status': 'ok'});
      await request.response.close();

      await resultFuture;
    } finally {
      await server.close(force: true);
    }
  });

  for (final errorCode in [
    scheduledPostNotFoundCode,
    socialPublishingUnavailableCode,
    publishQueueUnavailableCode,
  ]) {
    test('publishPostNow preserves the backend $errorCode error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
        );
        final resultFuture = client.publishPostNow('post-1');
        final expectation = expectLater(
          resultFuture,
          throwsA(
            isA<ApiException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.serviceUnavailable,
                )
                .having(
                  (error) => error.code,
                  'code',
                  errorCode,
                ),
          ),
        );
        final request = await server.first;
        await request.drain<void>();
        _writeJsonResponse(
          request.response,
          {
            'status': 'error',
            'code': errorCode,
            'message': 'Publish-now request failed.',
          },
          statusCode: HttpStatus.serviceUnavailable,
        );
        await request.response.close();

        await expectation;
      } finally {
        await server.close(force: true);
      }
    });
  }

  test('subtitle segment parser preserves validated word contract presence',
      () {
    final legacy = ClipTranscriptSegment.fromJson({
      'text': 'legacy',
      'start': 0,
      'end': 1,
    });
    final rejected = ClipTranscriptSegment.fromJson({
      'text': 'rejected',
      'start': 1,
      'end': 2,
      'words': <Object?>[],
    });
    final validated = ClipTranscriptSegment.fromJson({
      'text': 'hello world',
      'start': 2,
      'end': 3,
      'words': [
        {'word': 'hello', 'start': 2, 'end': 2.4},
        {'word': 'world', 'start': 2.5, 'end': 3},
      ],
    });
    final malformed = ClipTranscriptSegment.fromJson({
      'text': 'malformed',
      'start': 3,
      'end': 4,
      'words': 'not-a-list',
    });

    expect(legacy.words, isNull);
    expect(rejected.words, isEmpty);
    expect(validated.words?.map((word) => word.word), ['hello', 'world']);
    expect(validated.words?.last.start, 2.5);
    expect(malformed.words, isEmpty);
  });

  test('subtitle segment parser rejects malformed validated word fields', () {
    for (final malformedWord in [
      {'word': 7, 'start': 0, 'end': 1},
      {'word': 'hello', 'start': '0', 'end': 1},
      {'word': 'hello', 'start': 0, 'end': '1'},
      {'word': 'hello', 'start': double.nan, 'end': 1},
      {'word': 'hello', 'start': 0, 'end': double.infinity},
      {'word': 'hello', 'start': 0},
      {'word': 'hello', 'end': 1},
    ]) {
      final segment = ClipTranscriptSegment.fromJson({
        'text': 'hello',
        'start': 0,
        'end': 1,
        'words': [malformedWord],
      });

      expect(segment.words, isEmpty);
    }
  });

  test('AI edit transcript parses repaired boundary segments independently',
      () {
    final transcript = AiEditTranscriptResult.fromJson(const {
      'text': 'ดุ๊กดิ๊กมาก',
      'language': 'th',
      'durationSeconds': 2,
      'segments': [
        {'text': 'ดุ๊ก', 'start': 0, 'end': 1},
        {'text': 'ดิ๊กมาก', 'start': 1, 'end': 2},
      ],
      'boundarySegments': [
        {'text': 'ดุ๊กดิ๊กมาก', 'start': 0, 'end': 2},
      ],
      'words': <Object?>[],
      'model': 'test-elevenlabs',
    });

    expect(transcript.segments.map((segment) => segment.text), [
      'ดุ๊ก',
      'ดิ๊กมาก',
    ]);
    expect(transcript.boundarySegments, hasLength(1));
    expect(transcript.boundarySegments.single.text, 'ดุ๊กดิ๊กมาก');
    expect(transcript.boundarySegments.single.start, 0);
    expect(transcript.boundarySegments.single.end, 2);
  });

  test('legacy AI edit transcript does not reuse raw segments as boundaries',
      () {
    final transcript = AiEditTranscriptResult.fromJson(const {
      'text': 'ขอบจากผู้ให้บริการ',
      'language': 'th',
      'durationSeconds': 2,
      'segments': [
        {'text': 'ขอบจากผู้ให้บริการ', 'start': 0, 'end': 2},
      ],
      'words': <Object?>[],
      'model': 'legacy',
    });
    final malformed = AiEditTranscriptResult.fromJson(const {
      'text': 'ขอบเสีย',
      'language': 'th',
      'durationSeconds': 2,
      'segments': <Object?>[],
      'boundarySegments': 'not-a-list',
      'words': <Object?>[],
      'model': 'malformed',
    });

    expect(transcript.segments, hasLength(1));
    expect(transcript.boundarySegments, isEmpty);
    expect(malformed.boundarySegments, isEmpty);
  });

  test('malformed boundary item invalidates the whole boundary timeline', () {
    final malformedItems = <Object?>[
      'not-a-map',
      {'text': 7, 'start': 1, 'end': 2},
      {'text': 'ไม่มีเวลาเริ่ม', 'end': 2},
      {'text': 'เวลาไม่สิ้นสุด', 'start': double.nan, 'end': 2},
      {'text': 'เกินความยาวคลิป', 'start': 1, 'end': 99},
    ];

    for (final malformedItem in malformedItems) {
      final transcript = AiEditTranscriptResult.fromJson({
        'text': 'ช่วงแรก ช่วงสอง',
        'language': 'th',
        'durationSeconds': 3,
        'segments': const <Object?>[],
        'boundarySegments': [
          const {'text': 'ช่วงแรก', 'start': 0, 'end': 1},
          malformedItem,
          const {'text': 'ช่วงสอง', 'start': 2, 'end': 3},
        ],
        'words': const <Object?>[],
        'model': 'malformed-boundary',
      });

      expect(
        transcript.boundarySegments,
        isEmpty,
        reason: 'partial boundary evidence must never survive $malformedItem',
      );
    }
  });

  test('VerifyStorePurchaseRequest serializes Android purchase tokens', () {
    expect(
      const VerifyStorePurchaseRequest.android(
        purchaseToken: 'android-token',
      ).toJson(),
      {
        'platform': 'ANDROID',
        'productId': 'postdee_pro_monthly',
        'purchaseToken': 'android-token',
      },
    );
  });

  test('VerifyStorePurchaseRequest serializes iOS transaction ids', () {
    expect(
      const VerifyStorePurchaseRequest.ios(
        transactionId: 'ios-transaction',
      ).toJson(),
      {
        'platform': 'IOS',
        'productId': 'postdee_pro_monthly',
        'transactionId': 'ios-transaction',
      },
    );
  });

  test('StoreSubscriptionVerificationResult parses purchase and subscription',
      () {
    final result = StoreSubscriptionVerificationResult.fromJson({
      'purchase': {
        'provider': 'mock-store',
        'platform': 'ANDROID',
        'productId': 'postdee_pro_monthly',
        'verifiedAt': '2026-06-04T00:00:00.000Z',
      },
      'subscription': {
        'userId': 'seller-store',
        'plan': 'PRO',
        'status': 'ACTIVE',
        'monthlyPostLimit': null,
        'usedPostsThisMonth': null,
        'remainingPostsThisMonth': null,
        'canSchedule': true,
        'canUseAiCaptions': true,
        'canUseAnalytics': true,
      },
    });

    expect(result.purchase.platform, 'ANDROID');
    expect(result.purchase.productId, 'postdee_pro_monthly');
    expect(result.subscription.isPro, isTrue);
  });

  test('SubscriptionStatusResult parses monthly post usage', () {
    final subscription = SubscriptionStatusResult.fromJson({
      'userId': 'seller-usage',
      'plan': 'BASIC',
      'status': 'INACTIVE',
      'monthlyPostLimit': 3,
      'usedPostsThisMonth': 2,
      'remainingPostsThisMonth': 1,
      'phoneVerified': true,
      'requiresPhoneVerification': false,
      'canUseFreePostQuota': true,
      'canSchedule': false,
      'canUseAiCaptions': false,
      'canUseAnalytics': false,
    });

    expect(subscription.phoneVerified, isTrue);
    expect(subscription.requiresPhoneVerification, isFalse);
    expect(subscription.canUseFreePostQuota, isTrue);
    expect(subscription.usedPostsThisMonth, 2);
    expect(subscription.remainingPostsThisMonth, 1);
  });

  test('SubscriptionStatusResult parses phone verification gates', () {
    final subscription = SubscriptionStatusResult.fromJson({
      'userId': 'seller-basic',
      'plan': 'BASIC',
      'status': 'INACTIVE',
      'monthlyPostLimit': 3,
      'usedPostsThisMonth': 0,
      'remainingPostsThisMonth': 0,
      'phoneVerified': false,
      'requiresPhoneVerification': true,
      'canUseFreePostQuota': false,
      'canSchedule': false,
      'canUseAiCaptions': false,
      'canUseAnalytics': false,
    });

    expect(subscription.phoneVerified, isFalse);
    expect(subscription.requiresPhoneVerification, isTrue);
    expect(subscription.canUseFreePostQuota, isFalse);
  });

  test('SubscriptionStatusResult keeps legacy AI review gates disabled', () {
    final subscription = SubscriptionStatusResult.fromJson({
      'userId': 'seller-starter',
      'plan': 'STARTER',
      'status': 'ACTIVE',
      'monthlyPostLimit': 120,
      'usedPostsThisMonth': 5,
      'remainingPostsThisMonth': 115,
      'canSchedule': true,
      'canUseAiCaptions': true,
      'canUseAnalytics': false,
      'canUseAiAudioReview': false,
      'canUseAiVideoReview': false,
    });

    expect(subscription.isStarter, isTrue);
    expect(subscription.isPro, isFalse);
    expect(subscription.canSchedule, isTrue);
    expect(subscription.monthlyPostLimit, 120);
    expect(subscription.canUseAiAudioReview, isFalse);
    expect(subscription.canUseAiVideoReview, isFalse);
  });

  test('UploadResult tolerates hidden storage provider details', () {
    final result = UploadResult.fromJson({
      'id': 'upload-1',
      'videoS3Key': 'uploads/seller/upload-1/demo.mp4',
      'uploadUrl': 'https://uploads.postdee.test/upload',
      'uploadMethod': 'PUT',
      'uploadHeaders': {'Content-Type': 'video/mp4'},
      'uploadExpiresAt': '2026-06-27T12:00:00.000Z',
    });

    expect(result.id, 'upload-1');
    expect(result.videoS3Key, 'uploads/seller/upload-1/demo.mp4');
    expect(result.storageProvider, 'private');
    expect(result.uploadMethod, 'PUT');
    expect(result.uploadHeaders, {'Content-Type': 'video/mp4'});
    expect(result.uploadExpiresAt?.toUtc().toIso8601String(),
        '2026-06-27T12:00:00.000Z');
  });

  test('upload models advertise and parse multipart-v1 session metadata', () {
    expect(
      const CreateUploadRequest(
        fileName: 'clip.mp4',
        contentType: 'video/mp4',
        sizeBytes: 10,
      ).toJson(),
      {
        'fileName': 'clip.mp4',
        'contentType': 'video/mp4',
        'sizeBytes': 10,
        'uploadProtocol': 'multipart-v1',
      },
    );

    final result = UploadResult.fromJson({
      'id': 'upload-multipart',
      'videoS3Key': 'uploads/seller/upload-multipart/clip.mp4',
      'storageProvider': 'private',
      'uploadProtocol': 'multipart-v1',
      'partSizeBytes': 5,
      'partCount': 2,
      'sessionExpiresAt': '2026-07-13T12:00:00.000Z',
    });

    expect(result.uploadProtocol, 'multipart-v1');
    expect(result.partSizeBytes, 5);
    expect(result.partCount, 2);
    expect(result.sessionExpiresAt?.toUtc().toIso8601String(),
        '2026-07-13T12:00:00.000Z');
  });

  final multipartCases = <({
    String name,
    List<int> bytes,
    int partSizeBytes,
    List<List<int>> expectedParts,
  })>[
    (
      name: 'one part',
      bytes: <int>[0, 1, 2, 3],
      partSizeBytes: 8,
      expectedParts: <List<int>>[
        <int>[0, 1, 2, 3],
      ],
    ),
    (
      name: 'two parts with an exact final byte boundary',
      bytes: <int>[0, 1, 2, 3, 4, 5, 6],
      partSizeBytes: 4,
      expectedParts: <List<int>>[
        <int>[0, 1, 2, 3],
        <int>[4, 5, 6],
      ],
    ),
  ];

  for (final uploadCase in multipartCases) {
    test('uploadVideoFile uploads ${uploadCase.name} and completes with ETags',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('postdee-multipart-upload-');
      final file = File('${directory.path}/clip.mp4');
      await file.writeAsBytes(uploadCase.bytes);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final baseUrl = 'http://${server.address.address}:${server.port}';
      final uploadId = 'upload-${uploadCase.expectedParts.length}';
      final uploadedParts = <int, List<int>>{};
      Map<String, Object?>? completeBody;
      var aborted = false;

      final serverTask = () async {
        await for (final request in server) {
          final partMatch = RegExp(
            '^/uploads/$uploadId/parts/([0-9]+)\$',
          ).firstMatch(request.uri.path);
          final objectMatch = RegExp(
            '^/objects/$uploadId/([0-9]+)\$',
          ).firstMatch(request.uri.path);

          if (partMatch != null) {
            final partNumber = int.parse(partMatch.group(1)!);
            await _readJsonRequest(request);
            _writeJsonResponse(request.response, {
              'status': 'ok',
              'part': {
                'partNumber': partNumber,
                'sizeBytes': uploadCase.expectedParts[partNumber - 1].length,
                'uploadUrl': '$baseUrl/objects/$uploadId/$partNumber',
                'uploadMethod': 'PUT',
                'uploadHeaders': {
                  'Content-Length':
                      '${uploadCase.expectedParts[partNumber - 1].length}',
                  'x-postdee-part': '$partNumber',
                },
                'uploadExpiresAt': '2099-01-01T00:00:00.000Z',
              },
            });
          } else if (objectMatch != null) {
            final partNumber = int.parse(objectMatch.group(1)!);
            uploadedParts[partNumber] = await _readRequestBytes(request);
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.set(HttpHeaders.etagHeader, '"etag-$partNumber"');
          } else if (request.uri.path == '/uploads/$uploadId/complete') {
            completeBody = await _readJsonRequest(request);
            _writeJsonResponse(request.response, {
              'status': 'ok',
              'upload': {
                'id': uploadId,
                'videoS3Key': 'uploads/seller/$uploadId/clip.mp4',
                'storageProvider': 'private',
                'uploadProtocol': 'multipart-v1',
                'partSizeBytes': uploadCase.partSizeBytes,
                'partCount': uploadCase.expectedParts.length,
                'sessionExpiresAt': '2099-01-01T00:00:00.000Z',
              },
            });
          } else if (request.uri.path == '/uploads/$uploadId') {
            aborted = true;
            await request.drain<void>();
            request.response.statusCode = HttpStatus.noContent;
          } else {
            await request.drain<void>();
            request.response.statusCode = HttpStatus.notFound;
          }

          await request.response.close();
        }
      }();

      try {
        final client = PostDeeApiClient(baseUrl: baseUrl);
        await client.uploadVideoFile(
          UploadResult(
            id: uploadId,
            videoS3Key: 'uploads/seller/$uploadId/clip.mp4',
            storageProvider: 'private',
            uploadProtocol: 'multipart-v1',
            partSizeBytes: uploadCase.partSizeBytes,
            partCount: uploadCase.expectedParts.length,
            sessionExpiresAt: DateTime.utc(2099),
          ),
          file,
        );

        expect(
          <List<int>>[
            for (var partNumber = 1;
                partNumber <= uploadCase.expectedParts.length;
                partNumber += 1)
              uploadedParts[partNumber]!,
          ],
          uploadCase.expectedParts,
        );
        expect(completeBody, {
          'parts': [
            for (var partNumber = 1;
                partNumber <= uploadCase.expectedParts.length;
                partNumber += 1)
              {
                'partNumber': partNumber,
                'etag': '"etag-$partNumber"',
              },
          ],
        });
        expect(aborted, isFalse);
      } finally {
        await server.close(force: true);
        await serverTask;
        await directory.delete(recursive: true);
      }
    });
  }

  test('uploadVideoFile retries a failed part with a fresh signed URL',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-multipart-retry-');
    final file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes(const <int>[1, 2, 3]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${server.address.address}:${server.port}';
    var partRequestCount = 0;
    final objectPaths = <String>[];
    var completed = false;

    final serverTask = () async {
      await for (final request in server) {
        if (request.uri.path == '/uploads/retry-upload/parts/1') {
          partRequestCount += 1;
          await _readJsonRequest(request);
          if (partRequestCount == 1) {
            request.response
              ..statusCode = HttpStatus.serviceUnavailable
              ..write('temporary signing outage');
          } else {
            _writeJsonResponse(request.response, {
              'status': 'ok',
              'part': {
                'partNumber': 1,
                'sizeBytes': 3,
                'uploadUrl': '$baseUrl/objects/attempt-$partRequestCount',
                'uploadMethod': 'PUT',
                'uploadHeaders': <String, String>{},
                'uploadExpiresAt': '2099-01-01T00:00:00.000Z',
              },
            });
          }
        } else if (request.uri.path.startsWith('/objects/attempt-')) {
          objectPaths.add(request.uri.path);
          await request.drain<void>();
          if (objectPaths.length == 1) {
            request.response
              ..statusCode = HttpStatus.serviceUnavailable
              ..write('temporary outage');
          } else {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.set(HttpHeaders.etagHeader, '"retry-etag"');
          }
        } else if (request.uri.path == '/uploads/retry-upload/complete') {
          completed = true;
          await _readJsonRequest(request);
          _writeJsonResponse(request.response, {
            'status': 'ok',
            'upload': {
              'id': 'retry-upload',
              'videoS3Key': 'uploads/retry-upload/clip.mp4',
              'storageProvider': 'private',
            },
          });
        } else {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.notFound;
        }

        await request.response.close();
      }
    }();

    try {
      final client = PostDeeApiClient(baseUrl: baseUrl);
      await client.uploadVideoFile(
        UploadResult(
          id: 'retry-upload',
          videoS3Key: 'uploads/retry-upload/clip.mp4',
          storageProvider: 'private',
          uploadProtocol: 'multipart-v1',
          partSizeBytes: 3,
          partCount: 1,
          sessionExpiresAt: DateTime.utc(2099),
        ),
        file,
      );

      expect(partRequestCount, 3);
      expect(objectPaths, ['/objects/attempt-2', '/objects/attempt-3']);
      expect(completed, isTrue);
    } finally {
      await server.close(force: true);
      await serverTask;
      await directory.delete(recursive: true);
    }
  });

  test('uploadVideoFile aborts after three retryable failures', () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-multipart-abort-');
    final file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes(const <int>[1, 2, 3]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${server.address.address}:${server.port}';
    var partRequestCount = 0;
    var objectRequestCount = 0;
    var abortRequestCount = 0;

    final serverTask = () async {
      await for (final request in server) {
        if (request.uri.path == '/uploads/failed-upload/parts/1') {
          partRequestCount += 1;
          await _readJsonRequest(request);
          _writeJsonResponse(request.response, {
            'status': 'ok',
            'part': {
              'partNumber': 1,
              'sizeBytes': 3,
              'uploadUrl': '$baseUrl/objects/failure-$partRequestCount',
              'uploadMethod': 'PUT',
              'uploadHeaders': <String, String>{},
              'uploadExpiresAt': '2099-01-01T00:00:00.000Z',
            },
          });
        } else if (request.uri.path.startsWith('/objects/failure-')) {
          objectRequestCount += 1;
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.serviceUnavailable
            ..write('still unavailable');
        } else if (request.uri.path == '/uploads/failed-upload' &&
            request.method == 'DELETE') {
          abortRequestCount += 1;
          await request.drain<void>();
          request.response.statusCode = HttpStatus.noContent;
        } else {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.notFound;
        }

        await request.response.close();
      }
    }();

    try {
      final client = PostDeeApiClient(baseUrl: baseUrl);
      await expectLater(
        client.uploadVideoFile(
          UploadResult(
            id: 'failed-upload',
            videoS3Key: 'uploads/failed-upload/clip.mp4',
            storageProvider: 'private',
            uploadProtocol: 'multipart-v1',
            partSizeBytes: 3,
            partCount: 1,
            sessionExpiresAt: DateTime.utc(2099),
          ),
          file,
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.serviceUnavailable,
          ),
        ),
      );

      expect(partRequestCount, 3);
      expect(objectRequestCount, 3);
      expect(abortRequestCount, 1);
    } finally {
      await server.close(force: true);
      await serverTask;
      await directory.delete(recursive: true);
    }
  });

  test('uploadVideoFile requires an ETag and aborts when it is missing',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-multipart-etag-');
    final file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes(const <int>[1, 2, 3]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${server.address.address}:${server.port}';
    var aborted = false;

    final serverTask = () async {
      await for (final request in server) {
        if (request.uri.path == '/uploads/missing-etag/parts/1') {
          await _readJsonRequest(request);
          _writeJsonResponse(request.response, {
            'status': 'ok',
            'part': {
              'partNumber': 1,
              'sizeBytes': 3,
              'uploadUrl': '$baseUrl/objects/missing-etag',
              'uploadMethod': 'PUT',
              'uploadHeaders': <String, String>{},
              'uploadExpiresAt': '2099-01-01T00:00:00.000Z',
            },
          });
        } else if (request.uri.path == '/objects/missing-etag') {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.ok;
        } else if (request.uri.path == '/uploads/missing-etag' &&
            request.method == 'DELETE') {
          aborted = true;
          await request.drain<void>();
          request.response.statusCode = HttpStatus.noContent;
        } else {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.notFound;
        }

        await request.response.close();
      }
    }();

    try {
      final client = PostDeeApiClient(baseUrl: baseUrl);
      await expectLater(
        client.uploadVideoFile(
          UploadResult(
            id: 'missing-etag',
            videoS3Key: 'uploads/missing-etag/clip.mp4',
            storageProvider: 'private',
            uploadProtocol: 'multipart-v1',
            partSizeBytes: 3,
            partCount: 1,
          ),
          file,
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('ETag'),
          ),
        ),
      );
      expect(aborted, isTrue);
    } finally {
      await server.close(force: true);
      await serverTask;
      await directory.delete(recursive: true);
    }
  });

  final ambiguousCompletionCases = <({
    String name,
    List<String> sessionStatuses,
    bool shouldSucceed,
  })>[
    (
      name: 'resolves 409 completion in progress after status completes',
      sessionStatuses: const ['COMPLETING', 'COMPLETED'],
      shouldSucceed: true,
    ),
    (
      name: 'uses bounded backoff without aborting an in-progress completion',
      sessionStatuses: const [
        'COMPLETING',
        'COMPLETING',
        'COMPLETING',
        'COMPLETING',
      ],
      shouldSucceed: false,
    ),
  ];

  for (final completionCase in ambiguousCompletionCases) {
    test('uploadVideoFile ${completionCase.name}', () async {
      final directory =
          await Directory.systemTemp.createTemp('postdee-multipart-complete-');
      final file = File('${directory.path}/clip.mp4');
      await file.writeAsBytes(const <int>[1, 2, 3]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final baseUrl = 'http://${server.address.address}:${server.port}';
      final uploadId = completionCase.shouldSucceed
          ? 'eventual-complete'
          : 'pending-complete';
      final pollDelays = <Duration>[];
      var statusRequestCount = 0;
      var aborted = false;

      final serverTask = () async {
        await for (final request in server) {
          if (request.uri.path == '/uploads/$uploadId/parts/1') {
            await _readJsonRequest(request);
            _writeJsonResponse(request.response, {
              'status': 'ok',
              'part': {
                'partNumber': 1,
                'sizeBytes': 3,
                'uploadUrl': '$baseUrl/objects/$uploadId',
                'uploadMethod': 'PUT',
                'uploadHeaders': <String, String>{},
                'uploadExpiresAt': '2099-01-01T00:00:00.000Z',
              },
            });
          } else if (request.uri.path == '/objects/$uploadId') {
            await request.drain<void>();
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.set(HttpHeaders.etagHeader, '"complete-etag"');
          } else if (request.uri.path == '/uploads/$uploadId/complete') {
            await _readJsonRequest(request);
            _writeJsonResponse(
              request.response,
              {
                'status': 'error',
                if (completionCase.shouldSucceed)
                  'code': 'UPLOAD_COMPLETION_IN_PROGRESS',
                'message': completionCase.shouldSucceed
                    ? 'Upload completion is still in progress.'
                    : 'Completion response was lost',
              },
              statusCode: completionCase.shouldSucceed
                  ? HttpStatus.conflict
                  : HttpStatus.serviceUnavailable,
            );
          } else if (request.uri.path == '/uploads/$uploadId' &&
              request.method == 'GET') {
            final statusIndex =
                statusRequestCount < completionCase.sessionStatuses.length
                    ? statusRequestCount
                    : completionCase.sessionStatuses.length - 1;
            final sessionStatus = completionCase.sessionStatuses[statusIndex];
            statusRequestCount += 1;
            _writeJsonResponse(request.response, {
              'status': 'ok',
              'sessionStatus': sessionStatus,
              'upload': {
                'id': uploadId,
                'videoS3Key': 'uploads/$uploadId/clip.mp4',
                'storageProvider': 'private',
              },
            });
          } else if (request.uri.path == '/uploads/$uploadId' &&
              request.method == 'DELETE') {
            aborted = true;
            await request.drain<void>();
            request.response.statusCode = HttpStatus.noContent;
          } else {
            await request.drain<void>();
            request.response.statusCode = HttpStatus.notFound;
          }

          await request.response.close();
        }
      }();

      try {
        final client = PostDeeApiClient(
          baseUrl: baseUrl,
          multipartCompletionPollDelay: (duration) async {
            pollDelays.add(duration);
          },
        );
        final uploadFuture = client.uploadVideoFile(
          UploadResult(
            id: uploadId,
            videoS3Key: 'uploads/$uploadId/clip.mp4',
            storageProvider: 'private',
            uploadProtocol: 'multipart-v1',
            partSizeBytes: 3,
            partCount: 1,
          ),
          file,
        );

        if (completionCase.shouldSucceed) {
          await uploadFuture;
        } else {
          await expectLater(
            uploadFuture,
            throwsA(
              isA<ApiException>().having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.serviceUnavailable,
              ),
            ),
          );
        }

        final expectedStatusRequestCount = completionCase.shouldSucceed ? 2 : 4;
        expect(statusRequestCount, expectedStatusRequestCount);
        expect(
          pollDelays,
          completionCase.shouldSucceed
              ? const [Duration(seconds: 1)]
              : const [
                  Duration(seconds: 1),
                  Duration(seconds: 2),
                  Duration(seconds: 4),
                ],
        );
        expect(aborted, isFalse);
      } finally {
        await server.close(force: true);
        await serverTask;
        await directory.delete(recursive: true);
      }
    });
  }

  test('uploadVideoFile keeps legacy direct PUT uploads working', () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-legacy-upload-');
    final file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes(const <int>[4, 5, 6]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    List<int>? uploadedBytes;
    String? contentType;

    try {
      final client = PostDeeApiClient();
      final uploadFuture = client.uploadVideoFile(
        UploadResult(
          id: 'legacy-upload',
          videoS3Key: 'uploads/legacy-upload/clip.mp4',
          storageProvider: 'private',
          uploadUrl:
              'http://${server.address.address}:${server.port}/legacy-upload',
          uploadMethod: 'PUT',
          uploadHeaders: const {'Content-Type': 'video/mp4'},
        ),
        file,
      );
      final request = await server.first;
      contentType = request.headers.value(HttpHeaders.contentTypeHeader);
      uploadedBytes = await _readRequestBytes(request);
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      await uploadFuture;

      expect(request.method, 'PUT');
      expect(uploadedBytes, <int>[4, 5, 6]);
      expect(contentType, 'video/mp4');
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('uploadVideoFile rejects a signed URL that is about to expire',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-expired-upload-');
    final file = File('${directory.path}/probe.mp4');
    await file.writeAsBytes(const [1, 2, 3]);

    try {
      final client = PostDeeApiClient();

      await expectLater(
        client.uploadVideoFile(
          UploadResult(
            id: 'expired-upload',
            videoS3Key: 'uploads/seller/expired/probe.mp4',
            storageProvider: 'private',
            uploadUrl: 'https://uploads.postdee.test/expired',
            uploadMethod: 'PUT',
            uploadExpiresAt:
                DateTime.now().toUtc().add(const Duration(seconds: 10)),
          ),
          file,
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'UPLOAD_URL_EXPIRED',
          ),
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('uploadVideoFile maps an expired R2 response to a retryable error',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-r2-expired-response-');
    final file = File('${directory.path}/probe.mp4');
    await file.writeAsBytes(const [1, 2, 3]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final client = PostDeeApiClient();
      final uploadFuture = client.uploadVideoFile(
        UploadResult(
          id: 'expired-response-upload',
          videoS3Key: 'uploads/seller/expired-response/probe.mp4',
          storageProvider: 'private',
          uploadUrl: 'http://${server.address.address}:${server.port}/upload',
          uploadMethod: 'PUT',
        ),
        file,
      );
      final uploadExpectation = expectLater(
        uploadFuture,
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'UPLOAD_URL_EXPIRED',
          ),
        ),
      );
      final request = await server.first;

      expect(request.method, 'PUT');
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.forbidden
        ..headers.contentType = ContentType('application', 'xml')
        ..write('<Error><Code>ExpiredRequest</Code></Error>');
      await request.response.close();

      await uploadExpectation;
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('createAndUploadFileWithRetry requests one fresh URL after expiry',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-upload-retry-');
    final file = File('${directory.path}/probe.mp4');
    await file.writeAsBytes(const [1, 2, 3]);
    var createCalls = 0;
    var uploadCalls = 0;

    try {
      final result = await createAndUploadFileWithRetry(
        request: const CreateUploadRequest(
          fileName: 'probe.mp4',
          contentType: 'video/mp4',
          sizeBytes: 3,
        ),
        file: file,
        createUpload: (_) async {
          createCalls += 1;
          return UploadResult(
            id: 'upload-$createCalls',
            videoS3Key: 'uploads/seller/upload-$createCalls/probe.mp4',
            storageProvider: 'private',
          );
        },
        uploadFile: (upload, _) async {
          uploadCalls += 1;
          if (uploadCalls == 1) {
            throw const ApiException(
              'Upload URL expired',
              statusCode: HttpStatus.forbidden,
              code: 'UPLOAD_URL_EXPIRED',
            );
          }
        },
      );

      expect(createCalls, 2);
      expect(uploadCalls, 2);
      expect(result.id, 'upload-2');
      expect(result.videoS3Key, 'uploads/seller/upload-2/probe.mp4');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('createAndUploadFileWithRetry leaves multipart retries to the session',
      () async {
    final file = File('unused-multipart-upload.mp4');
    var createCalls = 0;

    await expectLater(
      createAndUploadFileWithRetry(
        request: const CreateUploadRequest(
          fileName: 'clip.mp4',
          contentType: 'video/mp4',
          sizeBytes: 3,
        ),
        file: file,
        createUpload: (_) async {
          createCalls += 1;
          return const UploadResult(
            id: 'managed-upload',
            videoS3Key: 'uploads/managed-upload/clip.mp4',
            storageProvider: 'private',
            uploadProtocol: 'multipart-v1',
            partSizeBytes: 3,
            partCount: 1,
          );
        },
        uploadFile: (_, __) async {
          throw const ApiException(
            'Part URL expired after retry limit',
            statusCode: HttpStatus.forbidden,
            code: 'UPLOAD_URL_EXPIRED',
          );
        },
      ),
      throwsA(isA<ApiException>()),
    );

    expect(createCalls, 1);
  });

  test('createAndUploadFileWithRetry does not retry unrelated failures',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-upload-no-retry-');
    final file = File('${directory.path}/probe.mp4');
    await file.writeAsBytes(const [1, 2, 3]);
    var createCalls = 0;

    try {
      await expectLater(
        createAndUploadFileWithRetry(
          request: const CreateUploadRequest(
            fileName: 'probe.mp4',
            contentType: 'video/mp4',
            sizeBytes: 3,
          ),
          file: file,
          createUpload: (_) async {
            createCalls += 1;
            return const UploadResult(
              id: 'upload-1',
              videoS3Key: 'uploads/seller/upload-1/probe.mp4',
              storageProvider: 'private',
            );
          },
          uploadFile: (_, __) async {
            throw const ApiException(
              'R2 unavailable',
              statusCode: HttpStatus.serviceUnavailable,
            );
          },
        ),
        throwsA(isA<ApiException>()),
      );

      expect(createCalls, 1);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('GenerateRealClipCaptionRequest serializes selected clip context only',
      () {
    expect(
      const GenerateRealClipCaptionRequest(
        videoS3Key: 'uploads/demo.mp4',
        guidance: 'make it friendly',
        selectedFrameKeys: ['frames/one.jpg'],
        deleteAfterUse: true,
      ).toJson(),
      {
        'videoS3Key': 'uploads/demo.mp4',
        'guidance': 'make it friendly',
        'selectedFrameKeys': ['frames/one.jpg'],
        'deleteAfterUse': true,
      },
    );
  });

  test('RealClipCaptionResult parses SEO, hook, source, and quota payloads',
      () {
    final result = RealClipCaptionResult.fromJson({
      'caption': 'Caption option',
      'captionOptions': ['Caption option', 'Second option'],
      'hooks': ['Hook one', 'Hook two'],
      'hashtags': ['#PostDee', '#ShortVideo'],
      'seoKeywords': ['short video', 'affiliate seller'],
      'searchTitle': 'Best moments from demo.mp4',
      'context': {
        'selectedCaptionLanguage': 'English',
        'selectedTargetMarket': 'United States',
        'selectedTone': 'affiliate',
        'detectedSpokenLanguage': 'Thai',
        'suggestedCaptionLanguage': 'English',
        'suggestedTargetMarket': 'United States',
      },
      'source': {
        'videoS3Key': 'uploads/demo.mp4',
        'mode': 'AUDIO_WITH_FRAMES',
        'selectedFrameCount': 2,
      },
      'quota': {
        'limit': 120,
        'usedThisMonth': 1,
        'remainingThisMonth': 119,
      },
    });

    expect(result.caption, 'Caption option');
    expect(result.captionOptions, ['Caption option', 'Second option']);
    expect(result.hooks, ['Hook one', 'Hook two']);
    expect(result.hashtags, ['#PostDee', '#ShortVideo']);
    expect(result.seoKeywords, ['short video', 'affiliate seller']);
    expect(result.searchTitle, 'Best moments from demo.mp4');
    expect(result.context.selectedCaptionLanguage, 'English');
    expect(result.context.selectedTargetMarket, 'United States');
    expect(result.context.selectedTone, 'affiliate');
    expect(result.context.detectedSpokenLanguage, 'Thai');
    expect(result.source.videoS3Key, 'uploads/demo.mp4');
    expect(result.source.mode, 'AUDIO_WITH_FRAMES');
    expect(result.source.selectedFrameCount, 2);
    expect(result.quota.limit, 120);
    expect(result.quota.usedThisMonth, 1);
    expect(result.quota.remainingThisMonth, 119);
  });

  test('ScheduledPostResult parses calendar post payloads', () {
    final post = ScheduledPostResult.fromJson({
      'id': 'post-1',
      'userId': 'seller-1',
      'caption': 'Launch clip',
      'videoS3Key': 'uploads/launch.mp4',
      'platforms': ['TIKTOK', 'YOUTUBE_SHORTS'],
      'scheduledAt': '2026-06-07T11:30:00.000Z',
      'status': 'PARTIAL_PUBLISHED',
      'publishedAt': '2026-06-07T11:31:00.000Z',
      'createdAt': '2026-06-01T00:00:00.000Z',
      'platformResults': [
        {
          'postId': 'post-1',
          'platform': 'TIKTOK',
          'status': 'PUBLISHED',
          'deliveryOutcome': 'DRAFT',
          'publishedAt': '2026-06-07T11:31:00.000Z',
        },
      ],
    });

    expect(post.id, 'post-1');
    expect(post.userId, 'seller-1');
    expect(post.caption, 'Launch clip');
    expect(post.platforms, ['TIKTOK', 'YOUTUBE_SHORTS']);
    expect(
        post.scheduledAt.toUtc().toIso8601String(), '2026-06-07T11:30:00.000Z');
    expect(post.status, 'PARTIAL_PUBLISHED');
    expect(post.publishedAt?.toUtc().toIso8601String(),
        '2026-06-07T11:31:00.000Z');
    expect(post.platformResults, hasLength(1));
    expect(post.platformResults.single.platform, 'TIKTOK');
    expect(post.platformResults.single.deliveryOutcome, 'DRAFT');
  });

  test('ScheduledPostResult keeps optional calendar fields backward compatible',
      () {
    final post = ScheduledPostResult.fromJson({
      'id': 'post-legacy',
      'caption': 'Legacy clip',
      'videoS3Key': 'uploads/legacy.mp4',
      'platforms': ['YOUTUBE_SHORTS'],
      'scheduledAt': '2026-06-07T11:30:00.000Z',
      'status': 'QUEUED',
      'createdAt': '2026-06-01T00:00:00.000Z',
    });

    expect(post.userId, isNull);
    expect(post.publishedAt, isNull);
    expect(post.platformResults, isEmpty);
  });

  test('PostSummaryResult parses honest per-platform publish results', () {
    final post = PostSummaryResult.fromJson({
      'id': 'post-1',
      'caption': 'Launch clip',
      'videoS3Key': 'uploads/launch.mp4',
      'platforms': ['TIKTOK', 'YOUTUBE_SHORTS'],
      'status': 'PARTIAL_PUBLISHED',
      'createdAt': '2026-06-01T00:00:00.000Z',
      'platformResults': [
        {
          'postId': 'post-1',
          'platform': 'TIKTOK',
          'status': 'PUBLISHED',
          'externalPostId': 'https://tiktok.test/post-1',
          'publishedAt': '2026-06-02T10:00:00.000Z',
        },
        {
          'postId': 'post-1',
          'platform': 'YOUTUBE_SHORTS',
          'status': 'FAILED',
          'errorMessage': 'YouTube rejected the upload',
        },
      ],
    });

    expect(post.platformResults, hasLength(2));
    expect(post.platformResults.first.platform, 'TIKTOK');
    expect(post.platformResults.first.externalPostId,
        'https://tiktok.test/post-1');
    expect(post.platformResults.first.publishedAt?.toUtc().toIso8601String(),
        '2026-06-02T10:00:00.000Z');
    expect(post.platformResults.last.status, 'FAILED');
    expect(
        post.platformResults.last.errorMessage, 'YouTube rejected the upload');
  });

  test('SocialConnectionResult parses connected platform status', () {
    final result = SocialConnectionResult.fromJson({
      'platform': 'TIKTOK',
      'connected': true,
      'displayName': '@seller_one',
      'externalAccountId': 'external-tiktok',
      'connectedAt': '2026-06-26T09:00:00.000Z',
    });

    expect(result.platform, 'TIKTOK');
    expect(result.connected, isTrue);
    expect(result.displayName, '@seller_one');
    expect(result.externalAccountId, 'external-tiktok');
    expect(result.connectedAt?.toUtc().toIso8601String(),
        '2026-06-26T09:00:00.000Z');
  });

  test('SocialConnectLinkResult parses connect URLs', () {
    final result = SocialConnectLinkResult.fromJson({
      'connectUrl': 'https://postpeer.test/connect/youtube',
      'expiresAt': '2026-06-26T09:10:00.000Z',
    });

    expect(
        result.connectUrl.toString(), 'https://postpeer.test/connect/youtube');
    expect(result.expiresAt?.toUtc().toIso8601String(),
        '2026-06-26T09:10:00.000Z');
  });

  test(
      'PostDeeApiAuthHeaders sends a Firebase bearer token when one is available',
      () async {
    final headers = await PostDeeApiAuthHeaders(
      authTokenProvider: () async => 'firebase-id-token',
      mockUserId: 'local-dev-user',
      mockSubscriptionPlan: 'PRO',
    ).load();

    expect(headers, {
      'Accept': 'application/json',
      'x-postdee-subscription-plan': 'PRO',
      'Authorization': 'Bearer firebase-id-token',
    });
  });

  test(
      'PostDeeApiAuthHeaders falls back to mock development headers without a token',
      () async {
    final headers = await PostDeeApiAuthHeaders(
      authTokenProvider: () async => '',
      mockUserId: 'seller-dev',
      mockSubscriptionPlan: 'PRO',
    ).load();

    expect(headers, {
      'Accept': 'application/json',
      'x-postdee-user-id': 'seller-dev',
      'x-postdee-subscription-plan': 'PRO',
    });
  });

  test('AppConfig leaves development auth overrides empty by default', () {
    expect(AppConfig.mockUserId, isEmpty);
    expect(AppConfig.mockSubscriptionPlan, isEmpty);
  });

  test('AiEditPrepareRequest serializes UI capabilities and recipe settings',
      () {
    expect(
      const AiEditPrepareRequest(
        videoS3Key: 'uploads/seller/video.mp4',
        durationSeconds: 65,
        styleId: 'flash_sale',
        prompt: 'เน้นสินค้าให้เด่น',
        capabilities: {
          'subtitle': true,
          'silence': false,
        },
        settings: AiEditPrepareSettings(
          subtitleStyle: 'bold',
          subtitleColor: '#FFFFFF',
          subtitleOutlineColor: '#112233',
          subtitleWordsPerLine: 2,
          subtitlePosition: 'bottom',
          subtitleNormalizedX: 0.27,
          subtitleNormalizedY: 0.63,
          ctaText: 'กดตะกร้าเลย',
          silencePreset: 'natural',
          speechReductionMode: 'auto',
          fillerWords: ['เอ่อ', 'แบบว่า'],
          music: AiEditMusicSettings(
            source: 'library',
            genre: 'fun',
            trackId: 'postdee-sale-01',
            beatIntensity: 'energetic',
            volume: 0.25,
            ducking: AiEditMusicDuckingSettings(
              enabled: true,
              musicVolumeDuringSpeech: 0.12,
            ),
          ),
        ),
      ).toJson(),
      {
        'videoS3Key': 'uploads/seller/video.mp4',
        'durationSeconds': 65.0,
        'styleId': 'flash_sale',
        'prompt': 'เน้นสินค้าให้เด่น',
        'capabilities': {
          'subtitle': true,
          'silence': false,
        },
        'settings': {
          'subtitleStyle': 'bold',
          'subtitleColor': '#FFFFFF',
          'subtitleOutlineColor': '#112233',
          'subtitleWordsPerLine': 2,
          'subtitlePosition': 'bottom',
          'subtitleNormalizedX': 0.27,
          'subtitleNormalizedY': 0.63,
          'ctaText': 'กดตะกร้าเลย',
          'silencePreset': 'natural',
          'speechReductionMode': 'auto',
          'fillerWords': ['เอ่อ', 'แบบว่า'],
          'music': {
            'source': 'library',
            'genre': 'fun',
            'trackId': 'postdee-sale-01',
            'beatIntensity': 'energetic',
            'volume': 0.25,
            'ducking': {
              'enabled': true,
              'musicVolumeDuringSpeech': 0.12,
            },
          },
        },
      },
    );
  });

  test('AiEditSubtitleStyleResult parses outline color and normalized position',
      () {
    final style = AiEditSubtitleStyleResult.fromJson(const {
      'mode': 'bold',
      'color': '#FFFFFF',
      'wordsPerLine': 3,
      'position': 'middle',
      'outlineColor': '#112233',
      'normalizedX': 0.27,
      'normalizedY': 0.63,
    });

    expect(style.outlineColor, '#112233');
    expect(style.normalizedX, 0.27);
    expect(style.normalizedY, 0.63);
  });

  test('AiEditSubtitleStyleResult keeps legacy subtitle style defaults', () {
    final style = AiEditSubtitleStyleResult.fromJson(const {
      'mode': 'bold',
      'color': '#FFFFFF',
      'wordsPerLine': 2,
      'position': 'top',
    });

    expect(style.outlineColor, '#000000');
    expect(style.normalizedX, isNull);
    expect(style.normalizedY, isNull);
    expect(style.position, 'top');
  });

  test('AiEditSubtitleStyleResult fails safe for invalid custom style values',
      () {
    final style = AiEditSubtitleStyleResult.fromJson({
      'outlineColor': 42,
      'normalizedX': 'not-a-number',
      'normalizedY': 1.01,
    });
    final malformedColor = AiEditSubtitleStyleResult.fromJson(const {
      'outlineColor': '#GGGGGG',
      'normalizedX': double.nan,
      'normalizedY': -0.01,
    });

    expect(style.outlineColor, '#000000');
    expect(style.normalizedX, isNull);
    expect(style.normalizedY, isNull);
    expect(malformedColor.outlineColor, '#000000');
    expect(malformedColor.normalizedX, isNull);
    expect(malformedColor.normalizedY, isNull);
  });

  test('AiEditRecipeResult parses speech reduction review contract', () {
    final recipe = AiEditRecipeResult.fromJson({
      'version': 1,
      'status': 'ready',
      'renderMode': 'mobile-ffmpeg',
      'speechReduction': {
        'version': 1,
        'status': 'ready',
        'groups': [
          {
            'id': 'group-1',
            'text': 'really really',
            'normalizedText': 'really',
            'totalOccurrences': 2,
            'occurrenceIds': ['occurrence-1', 'occurrence-2'],
          },
        ],
        'occurrences': [
          {
            'id': 'occurrence-1',
            'groupId': 'group-1',
            'text': 'really',
            'normalizedText': 'really',
            'start': 1.2,
            'end': 1.45,
            'occurrenceIndex': 1,
            'occurrenceCount': 2,
            'kind': 'adjacent-word',
            'recommendation': 'cut',
            'selectedByDefault': true,
            'confidence': 0.92,
            'contextBefore': 'This is',
            'contextAfter': 'good',
            'canAutoRemove': true,
          },
        ],
        'defaultCutRanges': [
          {
            'occurrenceId': 'occurrence-1',
            'start': 1.18,
            'end': 1.47,
          },
        ],
      },
    });

    expect(recipe.speechReduction.isReady, isTrue);
    expect(recipe.speechReduction.version, 1);
    expect(recipe.speechReduction.groups.single.id, 'group-1');
    expect(recipe.speechReduction.groups.single.normalizedText, 'really');
    expect(recipe.speechReduction.groups.single.totalOccurrences, 2);
    expect(
      recipe.speechReduction.groups.single.occurrenceIds,
      ['occurrence-1', 'occurrence-2'],
    );
    final occurrence = recipe.speechReduction.occurrences.single;
    expect(occurrence.kind, 'adjacent-word');
    expect(occurrence.recommendation, 'cut');
    expect(occurrence.occurrenceIndex, 1);
    expect(occurrence.occurrenceCount, 2);
    expect(occurrence.confidence, 0.92);
    expect(occurrence.canAutoRemove, isTrue);
    expect(recipe.speechReduction.defaultCutRanges.single.start, 1.18);
  });

  test('AiEditRecipeResult keeps legacy speech reduction safely unavailable',
      () {
    final legacy = AiEditRecipeResult.fromJson({
      'version': 1,
      'status': 'ready',
      'renderMode': 'mobile-ffmpeg',
    });

    expect(legacy.speechReduction.isReady, isFalse);
    expect(legacy.speechReduction.status, 'unavailable');
    expect(legacy.speechReduction.groups, isEmpty);
    expect(legacy.speechReduction.occurrences, isEmpty);
    expect(legacy.speechReduction.defaultCutRanges, isEmpty);
  });

  test('AiEditRecipeResult selects a cached subtitle density variant', () {
    final recipe = AiEditRecipeResult.fromJson(const {
      'version': 1,
      'status': 'ready',
      'renderMode': 'mobile-ffmpeg',
      'subtitles': {
        'enabled': true,
        'segments': [
          {'text': 'อ่าน ง่าย วันนี้', 'start': 0, 'end': 1},
        ],
        'variants': {
          '1': [
            {'text': 'อ่าน', 'start': 0, 'end': 0.3},
            {'text': 'ง่าย', 'start': 0.3, 'end': 0.6},
            {'text': 'วันนี้', 'start': 0.6, 'end': 1},
          ],
          '3': [
            {'text': 'อ่าน ง่าย วันนี้', 'start': 0, 'end': 1},
          ],
          '5': [
            {'text': 'อ่าน ง่าย วันนี้ ได้เลย', 'start': 0, 'end': 1.2},
          ],
        },
        'style': {
          'mode': 'outline',
          'color': '#FFFFFF',
          'outlineColor': '#000000',
          'wordsPerLine': 3,
          'position': 'bottom',
        },
      },
    });

    final oneWordRecipe = recipe.withSubtitleWordsPerLine(1);

    expect(oneWordRecipe, isNotNull);
    expect(oneWordRecipe!.subtitles.style.wordsPerLine, 1);
    expect(
      oneWordRecipe.subtitles.segments.map((segment) => segment.text),
      ['อ่าน', 'ง่าย', 'วันนี้'],
    );
    expect(recipe.withSubtitleWordsPerLine(4), isNull);
  });

  test('legacy recipe can reuse only its current subtitle density', () {
    final recipe = AiEditRecipeResult.fromJson(const {
      'version': 1,
      'status': 'ready',
      'renderMode': 'mobile-ffmpeg',
      'subtitles': {
        'enabled': true,
        'segments': [
          {'text': 'ซับเดิม', 'start': 0, 'end': 1},
        ],
        'style': {
          'wordsPerLine': 2,
        },
      },
    });

    expect(recipe.withSubtitleWordsPerLine(2), same(recipe));
    expect(recipe.withSubtitleWordsPerLine(1), isNull);
  });

  test('withPlan keeps silence candidates out of executable cut ranges', () {
    final recipeWithSilenceCandidate = AiEditRecipeResult.fromJson(const {
      'version': 1,
      'status': 'ready',
      'renderMode': 'mobile-ffmpeg',
      'transcript': {
        'text': '',
        'language': 'th',
        'durationSeconds': 40,
        'segments': <Object?>[],
        'words': <Object?>[],
        'model': 'test',
      },
      'subtitles': {
        'enabled': false,
        'segments': <Object?>[],
        'style': <String, Object?>{},
      },
      'cutRanges': [
        {'start': 5, 'end': 6},
      ],
      'silenceRanges': [
        {'start': 5, 'end': 6},
      ],
      'fillerRanges': <Object?>[],
      'capabilities': <String, Object?>{},
    });

    final updated = recipeWithSilenceCandidate.withPlan(
      const AiEditPlanResult(
        cuts: [AiEditCut(start: 20, end: 30)],
        summary: 'test',
        model: 'test',
      ),
    );

    expect(updated.cutRanges, hasLength(1));
    expect(updated.cutRanges.single.start, 20);
    expect(updated.cutRanges.single.end, 30);
    expect(updated.silenceRanges, hasLength(1));
    expect(updated.silenceRanges.single.start, 5);
    expect(updated.silenceRanges.single.end, 6);
  });

  test('AI edit recipe parses safe sound-effect source anchors', () {
    final recipe = AiEditRecipeResult.fromJson(const {
      'transcript': {
        'durationSeconds': 12,
      },
      'soundEffects': [
        {'soundId': 'soft_pop', 'sourceSeconds': 1.25},
        {'soundId': 'success_ding', 'sourceSeconds': 9.5},
      ],
    });

    expect(recipe.soundEffects, hasLength(2));
    expect(recipe.soundEffects.first.soundId, 'soft_pop');
    expect(recipe.soundEffects.first.sourceSeconds, 1.25);
    expect(recipe.soundEffects.last.soundId, 'success_ding');
    expect(recipe.soundEffects.last.sourceSeconds, 9.5);
    expect(
      () => recipe.soundEffects.add(
        const AiEditSoundEffectSuggestionResult(
          soundId: 'clean_tap',
          sourceSeconds: 2,
        ),
      ),
      throwsUnsupportedError,
    );

    final replanned = recipe.withPlan(
      const AiEditPlanResult(
        cuts: [AiEditCut(start: 3, end: 4)],
        summary: 'replanned',
        model: 'test',
      ),
    );
    expect(replanned.soundEffects, same(recipe.soundEffects));
  });

  test('AI edit recipe rejects the complete sound-effect list if one is unsafe',
      () {
    final invalidItems = <Object?>[
      {'soundId': 'unknown', 'sourceSeconds': 2},
      {'soundId': 'soft_pop', 'sourceSeconds': -0.1},
      {'soundId': 'soft_pop', 'sourceSeconds': 12},
      {'soundId': 'soft_pop', 'sourceSeconds': double.nan},
      {'soundId': 'soft_pop', 'sourceSeconds': '2'},
      {
        'soundId': 'soft_pop',
        'sourceSeconds': 2,
        'url': 'https://untrusted.example/sfx.wav',
      },
      {
        'soundId': 'soft_pop',
        'sourceSeconds': 2,
        'assetPath': 'assets/sfx/soft_pop.wav',
      },
      {'soundId': 'soft_pop', 'sourceSeconds': 2, 'volume': 1},
      'not-an-object',
    ];

    for (final invalidItem in invalidItems) {
      final recipe = AiEditRecipeResult.fromJson({
        'transcript': const {
          'durationSeconds': 12,
        },
        'soundEffects': [
          const {'soundId': 'clean_tap', 'sourceSeconds': 1},
          invalidItem,
        ],
      });

      expect(recipe.soundEffects, isEmpty, reason: '$invalidItem');
    }
  });

  test('AI edit recipe rejects stacked sound effects at one source anchor', () {
    final recipe = AiEditRecipeResult.fromJson(const {
      'transcript': {'durationSeconds': 12},
      'soundEffects': [
        {'soundId': 'clean_tap', 'sourceSeconds': 1},
        {'soundId': 'soft_pop', 'sourceSeconds': 4},
        {'soundId': 'success_ding', 'sourceSeconds': 4.0},
      ],
    });

    expect(recipe.soundEffects, isEmpty);
  });

  test('AI edit recipe rejects excessive or malformed sound-effect lists', () {
    final excessive = AiEditRecipeResult.fromJson({
      'transcript': const {'durationSeconds': 20},
      'soundEffects': List.generate(
        9,
        (index) => {'soundId': 'soft_pop', 'sourceSeconds': index},
      ),
    });
    final malformed = AiEditRecipeResult.fromJson(const {
      'transcript': {'durationSeconds': 20},
      'soundEffects': {'soundId': 'soft_pop', 'sourceSeconds': 1},
    });

    expect(excessive.soundEffects, isEmpty);
    expect(malformed.soundEffects, isEmpty);
  });

  test('speech reduction parser fails closed for an unknown contract', () {
    final reduction = AiEditSpeechReductionResult.fromJson({
      'version': 99,
      'status': 'future-status',
      'groups': [
        {
          'id': 'unsafe-group',
          'text': 'future',
          'totalOccurrences': 1,
          'occurrenceIds': ['unsafe-occurrence'],
        },
      ],
      'occurrences': [
        {
          'id': 'unsafe-occurrence',
          'groupId': 'unsafe-group',
          'text': 'future',
          'start': 1,
          'end': 2,
          'kind': 'future-kind',
          'recommendation': 'cut',
          'selectedByDefault': true,
          'canAutoRemove': true,
        },
      ],
    });

    expect(reduction.status, 'unavailable');
    expect(reduction.groups, isEmpty);
    expect(reduction.occurrences, isEmpty);
    expect(reduction.defaultCutRanges, isEmpty);
  });

  test('speech reduction parser keeps an unknown occurrence kind unselected',
      () {
    final reduction = AiEditSpeechReductionResult.fromJson({
      'version': 1,
      'status': 'ready',
      'occurrences': [
        {
          'id': 'future-occurrence',
          'groupId': 'future-group',
          'text': 'future',
          'start': 1,
          'end': 2,
          'kind': 'future-kind',
          'recommendation': 'cut',
          'selectedByDefault': true,
          'canAutoRemove': true,
        },
      ],
    });

    final occurrence = reduction.occurrences.single;
    expect(occurrence.kind, 'frequent-only');
    expect(occurrence.recommendation, 'keep');
    expect(occurrence.selectedByDefault, isFalse);
    expect(occurrence.canAutoRemove, isFalse);
  });

  test('prepareAiEdit posts the request and parses the mobile recipe',
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
      final resultFuture = apiClient.prepareAiEdit(
        const AiEditPrepareRequest(
          videoS3Key: 'uploads/seller-test/video.mp4',
          durationSeconds: 12,
          capabilities: {
            'subtitle': true,
            'silence': true,
          },
        ),
      );
      final request = await server.first;
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;

      expect(request.method, 'POST');
      expect(request.uri.path, '/ai-edits/prepare');
      expect(request.headers.value('x-postdee-user-id'), 'seller-test');
      expect(body['videoS3Key'], 'uploads/seller-test/video.mp4');
      expect(body['capabilities'], {
        'subtitle': true,
        'silence': true,
      });

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'recipe': {
            'version': 1,
            'status': 'ready',
            'renderMode': 'mobile-ffmpeg',
            'transcript': {
              'text': 'สวัสดี เว้นช่วง แล้วไปต่อ',
              'language': 'th',
              'durationSeconds': 12,
              'segments': [
                {'text': 'สวัสดี', 'start': 0, 'end': 2},
                {'text': 'แล้วไปต่อ', 'start': 3, 'end': 5},
              ],
              'words': [
                {'word': 'สวัสดี', 'start': 0, 'end': 1},
              ],
              'model': 'test-whisper',
            },
            'subtitles': {
              'enabled': true,
              'segments': [
                {'text': 'สวัสดี', 'start': 0, 'end': 2},
              ],
              'style': {
                'mode': 'bold',
                'color': '#FFFFFF',
                'wordsPerLine': 2,
                'position': 'bottom',
              },
            },
            'cutRanges': [
              {'start': 6, 'end': 7},
            ],
            'silenceRanges': [
              {'start': 2, 'end': 3},
            ],
            'fillerRanges': <Object?>[],
            'plan': {
              'cuts': [
                {'start': 6, 'end': 7},
              ],
              'summary': 'ตัดช่วงท้ายตามคำสั่ง',
              'model': 'test-editor',
            },
            'music': {
              'source': 'original',
              'beatIntensity': 'balanced',
              'volume': 0.25,
              'ducking': {
                'enabled': true,
                'musicVolumeDuringSpeech': 0.12,
              },
            },
            'capabilities': {
              'subtitle': {
                'enabled': true,
                'state': 'applied',
                'message': 'สร้างซับแล้ว',
              },
              'silence': {
                'enabled': true,
                'state': 'applied',
                'message': 'พบช่วงเงียบแล้ว',
              },
            },
          },
          'quota': {
            'limitMinutes': 200,
            'usedMinutes': 12,
            'remainingMinutes': 188,
          },
        }));
      await request.response.close();

      final result = await resultFuture;

      expect(result.quota.remainingMinutes, 188);
      expect(result.recipe.transcript.language, 'th');
      expect(result.recipe.transcript.segments, hasLength(2));
      expect(result.recipe.transcript.words.single.word, 'สวัสดี');
      expect(result.recipe.cutRanges, hasLength(1));
      expect(result.recipe.cutRanges.single.start, 6);
      expect(result.recipe.silenceRanges.single.end, 3);
      expect(result.recipe.fillerRanges, isEmpty);
      expect(result.recipe.plan.cuts.single.start, 6);
      expect(result.recipe.plan.summary, 'ตัดช่วงท้ายตามคำสั่ง');
      expect(result.recipe.plan.model, 'test-editor');
      expect(result.recipe.subtitles.style.mode, 'bold');
      expect(result.recipe.subtitles.style.wordsPerLine, 2);
      expect(result.recipe.music.source, 'original');
      expect(result.recipe.music.beatIntensity, 'balanced');
      expect(result.recipe.music.volume, 0.25);
      expect(result.recipe.music.ducking.enabled, isTrue);
      expect(
        result.recipe.music.ducking.musicVolumeDuringSpeech,
        0.12,
      );
      expect(result.recipe.capabilities['subtitle']?.state, 'applied');
      expect(result.recipe.capabilities['silence']?.message, 'พบช่วงเงียบแล้ว');
    } finally {
      await server.close(force: true);
    }
  });

  test('prepareAiEdit preserves timing evidence unavailable error contract',
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
      final resultFuture = apiClient.prepareAiEdit(
        const AiEditPrepareRequest(
          videoS3Key: 'uploads/seller-test/video.mp4',
          durationSeconds: 12,
          targetDurationSeconds: 6,
        ),
      );
      final expectation = expectLater(
        resultFuture,
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.unprocessableEntity,
              )
              .having(
                (error) => error.code,
                'code',
                'AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE',
              )
              .having(
                (error) => error.message,
                'message',
                'Transcript timing evidence is unavailable',
              ),
        ),
      );
      final request = await server.first;

      _writeJsonResponse(
        request.response,
        const {
          'status': 'error',
          'code': 'AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE',
          'message': 'Transcript timing evidence is unavailable',
        },
        statusCode: HttpStatus.unprocessableEntity,
      );
      await request.response.close();

      await expectation;
    } finally {
      await server.close(force: true);
    }
  });

  test('checkAccountDeletionReady returns identity deletion retry state',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final apiClient = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        authHeaders: PostDeeApiAuthHeaders(
          authTokenProvider: () async => null,
          mockUserId: 'seller-test',
        ),
      );
      final resultFuture = apiClient.checkAccountDeletionReady();
      final request = await server.first;

      expect(request.method, 'GET');
      expect(request.uri.path, '/account/deletion-readiness');

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'identityAlreadyDeleted': true,
        }));
      await request.response.close();

      expect(await resultFuture, isTrue);
    } finally {
      await server.close(force: true);
    }
  });

  test('checkAccountDeletionReady defaults missing retry state to false',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final apiClient = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final resultFuture = apiClient.checkAccountDeletionReady();
      final request = await server.first;

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok'}));
      await request.response.close();

      expect(await resultFuture, isFalse);
    } finally {
      await server.close(force: true);
    }
  });

  test('resyncRevenueCatSubscription posts to the authenticated backend route',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final apiClient = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        authHeaders: PostDeeApiAuthHeaders(
          authTokenProvider: () async => null,
          mockUserId: 'seller-resync',
        ),
      );
      final resultFuture = apiClient.resyncRevenueCatSubscription();
      final request = await server.first;

      expect(request.method, 'POST');
      expect(request.uri.path, '/billing/revenuecat/resync');
      expect(request.headers.value('x-postdee-user-id'), 'seller-resync');
      expect(await _readJsonRequest(request), isEmpty);

      _writeJsonResponse(request.response, {
        'status': 'ok',
        'plan': 'PRO',
      });
      await request.response.close();

      await expectLater(resultFuture, completion('PRO'));
    } finally {
      await server.close(force: true);
    }
  });
}
