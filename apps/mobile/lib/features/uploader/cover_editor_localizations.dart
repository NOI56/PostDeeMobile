import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';

bool coverEditorUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String coverEditorText(BuildContext context, String thai, String english) =>
    coverEditorUsesThai(context) ? thai : english;

/// App-owned cover controls and known errors only. Never pass cover text,
/// filenames, paths or provider details through a generic substitution.
String localizeCoverEditorMessage(BuildContext context, String message) =>
    coverEditorUsesThai(context) ? message : _messages[message] ?? message;

String coverTimelineSemantics(BuildContext context, String elapsed,
        String duration, int remainingSeconds) =>
    coverEditorText(
        context,
        '$elapsed จาก $duration เหลือ $remainingSeconds วินาที',
        '$elapsed of $duration, $remainingSeconds ${remainingSeconds == 1 ? 'second' : 'seconds'} remaining');

String coverRemainingTime(BuildContext context, int seconds) =>
    coverEditorText(context, 'เหลือ $seconds วิ', '$seconds sec remaining');

const _messages = <String, String>{
  'แต่งหน้าปก': 'Edit cover',
  'เลือกเฟรมหน้าปกจากคลิป': 'Choose a cover frame',
  'เลื่อนเลือกภาพจากคลิป': 'Choose a frame from your video',
  'ภาพตัวอย่างจะเปลี่ยนตามตำแหน่งเวลา แล้วใช้ภาพนั้นเป็นหน้าปก':
      'Move the slider to preview a frame, then use it as your cover.',
  'ข้อความบนหน้าปก (ไม่ใส่ก็ได้)': 'Cover text (optional)',
  'เช่น ลดวันนี้เท่านั้น': 'e.g. Today only',
  'ฟอนต์': 'Font',
  'ความหนาและขนาด': 'Weight and size',
  'สีข้อความ': 'Text color',
  'พื้นหลังข้อความ': 'Text background',
  'ตำแหน่งข้อความ': 'Text position',
  'บน': 'Top',
  'กลาง': 'Center',
  'ล่าง': 'Bottom',
  'ปกติ': 'Regular',
  'กึ่งหนา': 'Semi-bold',
  'หนา': 'Bold',
  'หนาพิเศษ': 'Extra-bold',
  'กำลังสร้างหน้าปก...': 'Creating cover...',
  'ใช้หน้าปกนี้': 'Use this cover',
  'ยังเปิดภาพเคลื่อนไหวไม่ได้ แต่ยังเลือกเวลาและสร้างหน้าปกได้':
      'Video preview is unavailable. You can still choose a time and create a cover.',
  'สร้างหน้าปกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
      'Could not create the cover. Try again.',
  'ไม่พบไฟล์วิดีโอสำหรับสร้างหน้าปก':
      'Video file not found. Choose your video again.',
  'ไม่พบรูปหน้าปก กรุณาเลือกรูปใหม่':
      'Cover image not found. Choose another image.',
  'สร้างภาพหน้าปกไม่สำเร็จ กรุณาลองเลือกเฟรมหรือรูปใหม่':
      'Could not create the cover image. Choose another frame or image.',
  'ตำแหน่งวิดีโอ': 'Video position',
};

class CoverEditorText extends StatelessWidget {
  const CoverEditorText(this.message,
      {super.key,
      this.style,
      this.textAlign,
      this.maxLines,
      this.overflow,
      this.softWrap});
  final String message;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  @override
  Widget build(BuildContext context) =>
      Text(localizeCoverEditorMessage(context, message),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap);
}
