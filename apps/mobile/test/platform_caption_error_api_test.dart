import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  for (final entry in {
    'YOUTUBE_DESCRIPTION_TOO_LONG': '5,000',
    'YOUTUBE_DESCRIPTION_INVALID_CHARACTERS': 'ห้ามมี',
    'INSTAGRAM_CAPTION_TOO_LONG': '2,200',
    'FACEBOOK_CAPTION_TOO_LONG': '63,206',
    'provider-private-reason': 'ตรวจสอบแคปชั่น',
  }.entries) {
    test('server caption error ${entry.key} displays safe Thai guidance',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final task = () async {
        final request = await server.first;
        await request.drain<void>();
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'code': 'PLATFORM_CAPTION_INVALID',
          'reason': entry.key,
          'message': 'provider-private-value',
        }));
        await request.response.close();
      }();
      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
        );
        await expectLater(
            client.createPost(const CreatePostRequest(
              clientRequestId: 'fixture-id',
              caption: 'caption',
              videoS3Key: 'uploads/fixture.mp4',
              platforms: ['YOUTUBE_SHORTS'],
            )),
            throwsA(isA<ApiException>()
                .having(
                    (error) => error.code, 'code', 'PLATFORM_CAPTION_INVALID')
                .having((error) => error.statusCode, 'status',
                    HttpStatus.badRequest)
                .having((error) => error.message, 'Thai guidance',
                    contains(entry.value))
                .having((error) => error.message, 'sanitized',
                    isNot(contains('provider-private-value')))));
        await task;
      } finally {
        await server.close(force: true);
      }
    });
  }
}
