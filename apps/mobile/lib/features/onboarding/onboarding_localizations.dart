import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';

bool onboardingUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String onboardingText(BuildContext context, String thai, String english) =>
    onboardingUsesThai(context) ? thai : english;

/// Only app-owned intro copy. Native language names and unknown data stay raw.
String localizeOnboardingMessage(BuildContext context, String message) =>
    onboardingUsesThai(context) ? message : _messages[message] ?? message;

String onboardingStepLabel(BuildContext context, int current, int total) =>
    onboardingText(
        context, 'ขั้นตอนที่ $current จาก $total', 'Step $current of $total');

const _messages = <String, String>{
  'เชื่อมช่องทางครั้งเดียว': 'Connect your channels once',
  'เชื่อม TikTok, YouTube Shorts, Instagram Reels และ Facebook Reels บนเพจ ไม่ต้องสลับหลายแอป':
      'Connect TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Reels without switching between apps.',
  'คลิปเดียว โพสต์ได้ทุกที่': 'One video. Every channel.',
  'เลือกวิดีโอ 9:16 หนึ่งคลิป แล้วส่งขึ้นทุกช่องทางพร้อมกัน พร้อม AI ช่วยใส่แคปชั่นภาษาไทย':
      'Choose one 9:16 video and send it to all your channels, with AI to help write Thai captions.',
  'ตั้งเวลา + ดูยอดที่เดียว': 'Schedule and track in one place',
  'วางแผนโพสต์ในปฏิทิน แล้วดูยอดวิว ไลก์ และเอนเกจเมนต์รวมทุกแพลตฟอร์มในหน้าเดียว':
      'Plan posts in your calendar, then see views, likes, and engagement across platforms in one place.',
  'ข้าม': 'Skip',
  'ย้อนกลับ': 'Back',
  'ถัดไป': 'Next',
  'เริ่มใช้งาน': 'Get started',
  'ภาษา': 'Language',
  'เปลี่ยนภาษา': 'Change language',
};

class OnboardingText extends StatelessWidget {
  const OnboardingText(this.message,
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
  Widget build(BuildContext context) => Text(
        localizeOnboardingMessage(context, message),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      );
}
