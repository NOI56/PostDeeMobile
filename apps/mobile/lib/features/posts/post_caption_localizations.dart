import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/network/api_error_message.dart';
import '../../core/network/postdee_api_client.dart';
import '../uploader/caption_localizations.dart';

String postCaptionLanguage(BuildContext context) =>
    Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
        ?.locale
        .languageCode ??
    'th';

String postCaptionText(BuildContext context, String thai) =>
    postCaptionLanguage(context) == 'th' ? thai : _english[thai] ?? thai;

String postCaptionValidationText(BuildContext context, String thai) =>
    _english.containsKey(thai)
        ? postCaptionText(context, thai)
        : localizeCaptionMessage(context, thai);

String postCaptionErrorText(BuildContext context, Object error) {
  final code = error is ApiException ? error.code : null;
  if (error is ApiException &&
      code == 'PLATFORM_CAPTION_INVALID' &&
      const {
        'คำอธิบาย YouTube ต้องไม่เกิน 5,000 ไบต์ กรุณาย่อแคปชั่นก่อนโพสต์',
        'คำอธิบาย YouTube ห้ามมี < หรือ > กรุณาแก้แคปชั่นก่อนโพสต์',
        'แคปชั่น Instagram ต้องไม่เกิน 2,200 ตัวอักษร',
        'แคปชั่น Facebook ต้องไม่เกิน 63,206 ตัวอักษร',
      }.contains(error.message)) {
    return postCaptionValidationText(context, error.message);
  }
  final message = switch (code) {
    'POST_NOT_EDITABLE' => 'โพสต์นี้เริ่มส่งหรือถูกยกเลิกแล้ว แก้แคปชั่นไม่ได้',
    'POST_CAPTION_EDIT_WINDOW_CLOSED' => 'ใกล้เวลาโพสต์แล้ว แก้แคปชั่นไม่ได้',
    'POST_CAPTION_CONFLICT' =>
      'โพสต์เปลี่ยนไปแล้ว กรุณาโหลดข้อมูลล่าสุดก่อนแก้ใหม่',
    'POST_NOT_FOUND' => 'ไม่พบโพสต์นี้ในบัญชี อาจถูกยกเลิกหรือถูกนำออกแล้ว',
    'POST_CAPTION_EDIT_UNAVAILABLE' =>
      'ระบบยังไม่รองรับการแก้แคปชั่น กรุณาลองใหม่ภายหลัง',
    'TIKTOK_CAPTION_TOO_LONG' => 'แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร',
    'INVALID_YOUTUBE_TITLE' =>
      'ชื่อ YouTube ต้องไม่เกิน 100 ตัวอักษร และห้ามมี < หรือ >',
    'PLATFORM_CAPTION_INVALID' ||
    'INVALID_CAPTION' ||
    'INVALID_PLATFORM_CAPTIONS' =>
      'แคปชั่นไม่ตรงตามกฎช่องทาง กรุณาตรวจข้อความและลองใหม่',
    _ => null,
  };
  return message != null
      ? postCaptionValidationText(context, message)
      : apiErrorMessage(error,
          languageCode: postCaptionLanguage(context),
          fallbackMessage:
              postCaptionText(context, 'บันทึกแคปชั่นไม่สำเร็จ กรุณาลองใหม่'));
}

const _english = {
  'แก้ไขแคปชั่น': 'Edit caption',
  'แคปชั่น': 'Caption',
  'บันทึกแคปชั่น': 'Save caption',
  'กำลังบันทึก...': 'Saving...',
  'บันทึกแคปชั่นแล้ว': 'Caption saved',
  'แก้แคปชั่นได้ก่อนเวลาโพสต์มากกว่า 1 นาที โดยไม่ใช้เครดิต AI หรือโควต้าโพสต์เพิ่ม':
      'Edit captions more than a minute before posting, without using AI credits or extra post quota.',
  'ใกล้เวลาโพสต์แล้ว แก้แคปชั่นไม่ได้':
      'It is too close to the scheduled time to edit the caption.',
  'โพสต์นี้เริ่มส่งหรือถูกยกเลิกแล้ว แก้แคปชั่นไม่ได้':
      'This post has started sending or was canceled. Its caption cannot be edited.',
  'โพสต์เปลี่ยนไปแล้ว กรุณาโหลดข้อมูลล่าสุดก่อนแก้ใหม่':
      'The post changed. Load its latest information before editing again.',
  'ไม่พบโพสต์นี้ในบัญชี อาจถูกยกเลิกหรือถูกนำออกแล้ว':
      'This post is not available in your account. It may have been canceled or removed.',
  'ระบบยังไม่รองรับการแก้แคปชั่น กรุณาลองใหม่ภายหลัง':
      'Caption editing is not available yet. Please try again later.',
  'แคปชั่นไม่ตรงตามกฎช่องทาง กรุณาตรวจข้อความและลองใหม่':
      'The caption does not meet the channel rules. Check the text and try again.',
  'บันทึกแคปชั่นไม่สำเร็จ กรุณาลองใหม่':
      'Could not save the caption. Please try again.',
  'โหลดโพสต์ไม่สำเร็จ กรุณาลองใหม่':
      'Could not load the post. Please try again.',
  'บัญชีเปลี่ยนแล้ว กรุณากลับไปเปิดโพสต์จากบัญชีปัจจุบัน':
      'Your account changed. Open the post again from your current account.',
  'ลองใหม่': 'Try again',
  'โหลดข้อมูลล่าสุด': 'Load latest',
  'ทิ้งการแก้ไข?': 'Discard changes?',
  'แคปชั่นที่แก้ไขยังไม่ได้บันทึก': 'Your caption changes have not been saved.',
  'แก้ไขต่อ': 'Keep editing',
  'ทิ้งการแก้ไข': 'Discard changes',
  'ชื่อคลิป YouTube': 'YouTube video title',
  'ปรับชื่อเฉพาะ YouTube': 'Customize YouTube title',
  'ใช้ชื่อจากแคปชัน': 'Use title from caption',
  'ชื่อจากแคปชัน': 'Title from caption',
  'เพิ่มแคปชั่นก่อนโพสต์': 'Add a caption before posting.',
  'เพิ่มแคปชันหรือชื่อคลิป YouTube ก่อนโพสต์':
      'Add a caption or YouTube video title before posting.',
  'เพิ่มแคปชั่นสำหรับช่องทางนี้': 'Add a caption for this channel.',
  'แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร':
      'The TikTok caption must be no longer than 2,200 characters.',
  'ชื่อ YouTube ต้องไม่เกิน 100 ตัวอักษร และห้ามมี < หรือ >':
      'YouTube titles must be 100 characters or fewer and cannot contain < or >.',
  'คำอธิบาย YouTube ห้ามมี < หรือ > กรุณาแก้แคปชั่นก่อนโพสต์':
      'YouTube descriptions cannot contain < or >. Edit the caption before posting.',
};
