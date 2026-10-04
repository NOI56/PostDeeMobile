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
}
