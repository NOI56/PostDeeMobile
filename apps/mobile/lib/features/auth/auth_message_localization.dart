import 'package:flutter/widgets.dart';

import '../../core/localization/postdee_localizations.dart';

/// Translate app-owned messages at presentation time so pending auth work and
/// stored errors follow the current locale. Keep unknown provider text intact.
String localizeAuthMessage(BuildContext context, String message) {
  final isThai =
      (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
                  ?.locale
                  .languageCode ??
              'th') ==
          'th';
  final translated = _authMessages[message];
  return translated == null
      ? message
      : (isThai ? translated.$1 : translated.$2);
}

const _authMessages = <String, (String, String)>{
  'กรอกอีเมลให้ถูกต้อง': (
    'กรอกอีเมลให้ถูกต้อง',
    'Enter a valid email address.'
  ),
  'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร': (
    'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร',
    'Your password must have at least 6 characters.',
  ),
  'ดำเนินการใช้เวลานานเกินไป กรุณาลองใหม่': (
    'ดำเนินการใช้เวลานานเกินไป กรุณาลองใหม่',
    'This is taking too long. Please try again.',
  ),
  'ดำเนินการไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่': (
    'ดำเนินการไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
    'Could not complete the request. Check your internet connection and try again.',
  ),
  'Google ตอบกลับช้าเกินไป กรุณาลองใหม่ หรือเข้าสู่ระบบด้วยอีเมล': (
    'Google ตอบกลับช้าเกินไป กรุณาลองใหม่ หรือเข้าสู่ระบบด้วยอีเมล',
    'Google is taking too long to respond. Please try again or sign in with email.',
  ),
  'เข้าสู่ระบบใช้เวลานานเกินไป กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่': (
    'เข้าสู่ระบบใช้เวลานานเกินไป กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
    'Sign-in is taking too long. Check your internet connection and try again.',
  ),
  'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง': (
    'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
    'Could not sign in. Please try again.',
  ),
  'ส่งอีเมลตั้งรหัสผ่านไม่สำเร็จ กรุณาลองใหม่': (
    'ส่งอีเมลตั้งรหัสผ่านไม่สำเร็จ กรุณาลองใหม่',
    'Could not send the password reset email. Please try again.',
  ),
  'หากอีเมลนี้มีบัญชี คุณจะได้รับลิงก์ตั้งรหัสผ่าน กรุณาตรวจสอบกล่องอีเมลและจดหมายขยะ':
      (
    'หากอีเมลนี้มีบัญชี คุณจะได้รับลิงก์ตั้งรหัสผ่าน กรุณาตรวจสอบกล่องอีเมลและจดหมายขยะ',
    'If an account exists for this email, you will receive a password reset link. Check your inbox and spam folder.',
  ),
  'Google could not access a sign-in credential on this device. Please try again, check your Google account in Android Settings, or sign in with email.':
      (
    'Google ยังอ่านข้อมูลเข้าสู่ระบบบนอุปกรณ์นี้ไม่ได้ กรุณาลองใหม่ ตรวจสอบบัญชี Google ในการตั้งค่า Android หรือเข้าสู่ระบบด้วยอีเมล',
    'Google could not access a sign-in credential on this device. Please try again, check your Google account in Android Settings, or sign in with email.',
  ),
  'Google sign-in could not continue because this device needs the Google account signed in again. Open Google Play or Android Settings, confirm the Google account, then try again.':
      (
    'อุปกรณ์นี้ต้องยืนยันบัญชี Google อีกครั้ง กรุณาเปิด Google Play หรือการตั้งค่า Android ตรวจสอบบัญชี Google แล้วลองใหม่',
    'Google sign-in could not continue because this device needs the Google account signed in again. Open Google Play or Android Settings, confirm the Google account, then try again.',
  ),
  'Google sign-in was canceled. Please try again.': (
    'ยกเลิกการเข้าสู่ระบบด้วย Google แล้ว กรุณาลองอีกครั้ง',
    'Google sign-in was canceled. Please try again.',
  ),
  'Google sign-in is not configured correctly. Please contact support.': (
    'การตั้งค่าเข้าสู่ระบบด้วย Google ยังไม่ถูกต้อง กรุณาติดต่อทีมงาน',
    'Google sign-in is not configured correctly. Please contact support.',
  ),
  'Google sign-in is not available right now. Please try again.': (
    'เข้าสู่ระบบด้วย Google ไม่พร้อมใช้งานในขณะนี้ กรุณาลองอีกครั้ง',
    'Google sign-in is not available right now. Please try again.',
  ),
  'Google Sign-In did not return an ID token': (
    'ยังไม่ได้รับข้อมูลยืนยันจาก Google กรุณาลองเข้าสู่ระบบอีกครั้ง',
    'Could not verify your Google sign-in. Please try again.',
  ),
  'Firebase Auth did not return a signed-in user': (
    'ยังยืนยันบัญชีไม่ได้ กรุณาลองเข้าสู่ระบบอีกครั้ง',
    'Could not verify your account. Please try signing in again.',
  ),
  'Firebase Auth did not return an ID token': (
    'ยังไม่ได้รับข้อมูลยืนยันบัญชี กรุณาลองเข้าสู่ระบบอีกครั้ง',
    'Could not verify your sign-in. Please try again.',
  ),
  'Email sign-in is not configured yet': (
    'เข้าสู่ระบบด้วยอีเมลยังไม่พร้อมใช้งาน',
    'Email sign-in is not available yet.',
  ),
  'Firebase Google Sign-In is not configured yet': (
    'เข้าสู่ระบบด้วย Google ยังไม่พร้อมใช้งาน',
    'Google sign-in is not available yet.',
  ),
  'Firebase Auth is disabled. Enable Firebase Auth for sign-in.': (
    'ระบบเข้าสู่ระบบยังไม่เปิดใช้งาน กรุณาติดต่อทีมงาน',
    'Sign-in is not enabled. Please contact support.',
  ),
  'Firebase Auth is not initialized': (
    'ระบบเข้าสู่ระบบยังไม่พร้อมใช้งาน กรุณาลองอีกครั้ง',
    'Sign-in is not ready. Please try again.',
  ),
};
