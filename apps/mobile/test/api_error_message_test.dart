import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/api_error_message.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('gateway errors use Thai service recovery copy without exposing HTML',
      () {
    expect(
        apiErrorMessage(const ApiException('<html>Service Suspended</html>',
            statusCode: 503)),
        apiUnavailableMessage);
  });
  test('typed and transport deadlines share the Thai timeout message', () {
    expect(
        apiErrorMessage(const ApiException('internal timeout',
            code: apiRequestTimeoutCode, statusCode: 408)),
        apiTimeoutMessage);
    expect(
        apiErrorMessage(TimeoutException('internal host')), apiTimeoutMessage);
  });
  test('network errors do not expose hosts or technical exception types', () {
    expect(apiErrorMessage(const SocketException('secret-host')),
        'เชื่อมต่อ PostDee ไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่');
  });
  test(
      'Thai validation remains actionable and unknown technical errors use the screen fallback',
      () {
    expect(
        apiErrorMessage(
            const ApiException('เลือกเวลาในอนาคต', statusCode: 400)),
        'เลือกเวลาในอนาคต');
    expect(
        apiErrorMessage(const ApiException('Request failed'),
            fallbackMessage: 'โหลดข้อมูลไม่สำเร็จ'),
        'โหลดข้อมูลไม่สำเร็จ');
  });

  test('English gateway and deadline copy hides provider details', () {
    expect(
      apiErrorMessage(
        const ApiException('<html>private provider failure</html>',
            statusCode: 503),
        languageCode: 'en',
      ),
      'PostDee is temporarily unavailable. Please try again later.',
    );
    for (final error in [
      TimeoutException('private host'),
      const ApiException('internal timeout', code: apiRequestTimeoutCode),
      const ApiException('upstream response', statusCode: 408),
    ]) {
      expect(
        apiErrorMessage(error, languageCode: 'en'),
        'The request took too long. Please try again.',
      );
    }
  });

  test('English transport errors do not expose host or certificate details',
      () {
    for (final error in [
      const SocketException('private host'),
      const HttpException('private upstream URL'),
      const HandshakeException('private certificate'),
    ]) {
      expect(
        apiErrorMessage(error, languageCode: 'en'),
        'Cannot connect to PostDee. Check your internet connection and try again.',
      );
    }
  });

  test('English authentication and rate limits provide recovery actions', () {
    expect(
      apiErrorMessage(const ApiException('private', statusCode: 401),
          languageCode: 'en'),
      'Please sign in again and retry.',
    );
    expect(
      apiErrorMessage(const ApiException('private', statusCode: 429),
          languageCode: 'en'),
      'Too many requests. Wait a moment and try again.',
    );
  });

  test('English uses the screen fallback for validation and technical errors',
      () {
    for (final error in [
      const ApiException('เลือกเวลาในอนาคต', statusCode: 400),
      const ApiException('<html>upstream failure</html>'),
      const ApiException('Exception: private provider details'),
      const ApiException('Request failed'),
      StateError('private state'),
    ]) {
      expect(
        apiErrorMessage(error,
            languageCode: 'en',
            fallbackMessage: 'Could not load your plan. Please try again.'),
        'Could not load your plan. Please try again.',
      );
    }
  });

  test('English has a safe default fallback when no screen copy is supplied',
      () {
    expect(
      apiErrorMessage(const ApiException('เลือกเวลาในอนาคต', statusCode: 400),
          languageCode: 'en'),
      'Could not complete the action. Please try again.',
    );
    expect(
      apiErrorMessage(StateError('private state'), languageCode: 'en'),
      'Could not complete the action. Please try again.',
    );
  });
}
