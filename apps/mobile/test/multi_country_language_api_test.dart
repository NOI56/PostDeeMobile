import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  for (final language in ['th', 'en']) {
    test('device registration sends $language and unregister stays scoped',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <({String method, Map<String, dynamic> body})>[];
      final serving = () async {
        await for (final request in server) {
          requests.add((
            method: request.method,
            body: jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>
          ));
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
          await request.response.close();
        }
      }();
      try {
        final client =
            PostDeeApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        await client.registerDeviceToken('device-token',
            platform: 'android', language: language);
        await client.unregisterDeviceToken('device-token');
        expect(requests.map((request) => request.method), ['POST', 'DELETE']);
        expect(requests.first.body, {
          'token': 'device-token',
          'platform': 'android',
          'language': language,
        });
        expect(requests.last.body, {'token': 'device-token'});
      } finally {
        await server.close(force: true);
        await serving;
      }
    });

    test('clip caption requests always send current $language app language',
        () async {
      final controller = PostDeeLanguageController.instance;
      final previous = controller.locale!;
      await controller.setLocale(Locale(language));
      addTearDown(() => controller.setLocale(previous));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      final serving = () async {
        await for (final request in server) {
          expect(request.uri.path, '/captions/generate-from-clip');
          requests.add(jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>);
          request.response
            ..statusCode = 503
            ..headers.contentType = ContentType.json
            ..write('{"message":"fixture response"}');
          await request.response.close();
        }
      }();
      try {
        final client =
            PostDeeApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        for (final outputLanguage in ['auto', 'ja']) {
          await expectLater(
              client.generateCaptionFromClip(GenerateRealClipCaptionRequest(
                audioS3Key: 'uploads/owner/clip.m4a',
                captionLanguage: outputLanguage,
              )),
              throwsA(isA<ApiException>()));
        }
        expect(
            requests.map((body) => body['appLanguage']), [language, language]);
        expect(requests.first.containsKey('captionLanguage'), isFalse);
        expect(requests.last['captionLanguage'], 'ja');
      } finally {
        await server.close(force: true);
        await serving;
      }
    });
  }
}
