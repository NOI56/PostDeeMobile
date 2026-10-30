import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';

bool videoPreviewUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String videoPreviewText(BuildContext context, String thai, String english) =>
    videoPreviewUsesThai(context) ? thai : english;

/// Translate app-owned preview copy at render time. Never pass filenames,
/// captions, titles or account names. Unknown provider details stay raw.
String localizeVideoPreviewMessage(BuildContext context, String message) {
  if (videoPreviewUsesThai(context)) return message;
  final known = _messages[message];
  if (known != null) return known;
  final percent = _percentage.firstMatch(message);
  if (percent != null && percent.start == 0 && percent.end == message.length) {
    return '${percent[1]} percent';
  }
  return message;
}

final _percentage = RegExp(r'^(100|[1-9]?[0-9]) เปอร์เซ็นต์$');

const _messages = <String, String>{
  'ดูคลิป': 'Watch video',
  'พรีวิว': 'Preview',
  'เล่นคลิป': 'Play video',
  'หยุดคลิป': 'Pause video',
  'เริ่มคลิปใหม่': 'Restart video',
  'เลื่อนเวลาคลิป': 'Seek video',
  'ปรับเสียงพรีวิว': 'Adjust preview volume',
  'เปิดเสียงพรีวิว': 'Unmute preview',
  'ปิดเสียงพรีวิว': 'Mute preview',
  'ระดับเสียงพรีวิว': 'Preview volume',
  'กำลังเปิดคลิป…': 'Opening video…',
  'ยังเปิดคลิปไม่ได้': 'Could not open this video',
  'ลองเปิดอีกครั้ง หรือกลับไปเลือกคลิปอื่น':
      'Try opening it again, or go back and choose another video.',
  'ลองเปิดคลิปอีกครั้ง': 'Try opening the video again',
  'กลับไปตรวจสถานะเพื่อเปิดตัวอย่างล่าสุด':
      'Go back and check the post status to open the latest preview.',
  'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่':
      'Your account has changed. Reopen the video.',
  'ยังเล่นคลิปไม่ได้ ลองอีกครั้ง': 'Could not play this video. Try again.',
  'ยังปรับเสียงไม่ได้ ลองอีกครั้ง':
      'Could not adjust the preview volume. Try again.',
};

class VideoPreviewText extends StatelessWidget {
  const VideoPreviewText(this.message,
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
      Text(localizeVideoPreviewMessage(context, message),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap);
}
