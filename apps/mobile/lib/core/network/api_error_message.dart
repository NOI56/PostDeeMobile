import 'dart:async';
import 'dart:io';

import 'postdee_api_client.dart';

const apiUnavailableMessage =
    'ระบบ PostDee ไม่พร้อมใช้งานชั่วคราว กรุณาลองใหม่ภายหลัง';
const apiTimeoutMessage = 'ระบบตอบกลับช้าเกินไป กรุณาลองใหม่อีกครั้ง';

String apiErrorMessage(
  Object error, {
  String fallbackMessage = 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
}) {
  if (error is TimeoutException ||
      (error is ApiException &&
          (error.code == apiRequestTimeoutCode || error.statusCode == 408))) {
    return apiTimeoutMessage;
  }
  if (error is SocketException ||
      error is HttpException ||
      error is HandshakeException) {
    return 'เชื่อมต่อ PostDee ไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
  }
  if (error is! ApiException) return fallbackMessage;
  if (error.statusCode != null && error.statusCode! >= 500) {
    return apiUnavailableMessage;
  }
  if (error.statusCode == 401) return 'กรุณาเข้าสู่ระบบใหม่ แล้วลองอีกครั้ง';
  if (error.statusCode == 429) {
    return 'มีคำขอมากเกินไป กรุณารอสักครู่แล้วลองใหม่';
  }
  // Keep useful Thai validation copy, without exposing raw provider/HTML errors.
  if (RegExp(r'[\u0E00-\u0E7F]').hasMatch(error.message) &&
      !error.message.contains('<') &&
      !error.message.contains('Exception')) {
    return error.message;
  }
  return fallbackMessage;
}
