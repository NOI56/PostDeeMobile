import 'dart:async';
import 'dart:io';

import 'postdee_api_client.dart';

const apiUnavailableMessage =
    'ระบบ PostDee ไม่พร้อมใช้งานชั่วคราว กรุณาลองใหม่ภายหลัง';
const apiTimeoutMessage = 'ระบบตอบกลับช้าเกินไป กรุณาลองใหม่อีกครั้ง';

String apiErrorMessage(
  Object error, {
  String? fallbackMessage,
  String languageCode = 'th',
}) {
  final isThai = languageCode == 'th';
  final fallback = fallbackMessage ??
      (isThai
          ? 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'
          : 'Could not complete the action. Please try again.');
  if (error is TimeoutException ||
      (error is ApiException &&
          (error.code == apiRequestTimeoutCode || error.statusCode == 408))) {
    return isThai
        ? apiTimeoutMessage
        : 'The request took too long. Please try again.';
  }
  if (error is SocketException ||
      error is HttpException ||
      error is HandshakeException) {
    return isThai
        ? 'เชื่อมต่อ PostDee ไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่'
        : 'Cannot connect to PostDee. Check your internet connection and try again.';
  }
  if (error is! ApiException) return fallback;
  if (error.statusCode != null && error.statusCode! >= 500) {
    return isThai
        ? apiUnavailableMessage
        : 'PostDee is temporarily unavailable. Please try again later.';
  }
  if (error.statusCode == 401) {
    return isThai
        ? 'กรุณาเข้าสู่ระบบใหม่ แล้วลองอีกครั้ง'
        : 'Please sign in again and retry.';
  }
  if (error.statusCode == 429) {
    return isThai
        ? 'มีคำขอมากเกินไป กรุณารอสักครู่แล้วลองใหม่'
        : 'Too many requests. Wait a moment and try again.';
  }
  // Keep useful Thai validation copy, without exposing raw provider/HTML errors.
  if (isThai &&
      RegExp(r'[\u0E00-\u0E7F]').hasMatch(error.message) &&
      !error.message.contains('<') &&
      !error.message.contains('Exception')) {
    return error.message;
  }
  return fallback;
}
