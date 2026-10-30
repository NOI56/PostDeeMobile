import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';

bool publishFlowUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String publishFlowText(BuildContext context, String thai, String english) =>
    publishFlowUsesThai(context) ? thai : english;

/// App-owned progress and result copy only. Never pass raw post IDs, account
/// names, captions or provider details through generic substitutions.
String localizePublishFlowMessage(BuildContext context, String message) {
  if (publishFlowUsesThai(context)) return message;
  final fixed = _messages[message];
  if (fixed != null) return fixed;
  final progress = _whole(_progressPattern, message);
  if (progress != null) return '${progress[1]}% · Step progress';
  final processing = _whole(_processingPattern, message);
  if (processing != null) return 'Processing ${_channels(processing[1]!)}';
  final body = _resultBody(message);
  if (body != null) return body;
  const replayPrefix = 'พบรายการเดิม · ';
  if (message.startsWith(replayPrefix)) {
    final replayBody = _resultBody(message.substring(replayPrefix.length));
    if (replayBody != null) return 'Existing post found · $replayBody';
  }
  final platform = _whole(_platformOutcomePattern, message);
  if (platform != null) return '${platform[1]} · ${_outcomes[platform[2]]}';
  return message;
}

String _channels(String count) =>
    '$count ${count == '1' ? 'channel' : 'channels'}';

String? _resultBody(String message) {
  final fixed = _resultBodies[message];
  if (fixed != null) return fixed;
  for (final (pattern, format) in _bodyPatterns) {
    final count = _whole(pattern, message);
    if (count != null) return format(count[1]!);
  }
  final delivered = _whole(_deliveredPattern, message);
  return delivered == null
      ? null
      : 'Delivered to ${_channels(delivered[1]!)} · ${_outcomes[delivered[2]]}';
}

RegExpMatch? _whole(RegExp pattern, String message) {
  final match = pattern.firstMatch(message);
  return match != null && match.start == 0 && match.end == message.length
      ? match
      : null;
}

final _progressPattern =
    RegExp(r'^(100|[1-9]?[0-9])% · ความคืบหน้าตามขั้นตอน$');
final _processingPattern = RegExp(r'^กำลังดำเนินการสำหรับ ([0-6]) ช่องทาง$');
final _deliveredPattern = RegExp(
    '^ส่ง ([0-6]) ช่องทางสำเร็จ · (${_outcomes.keys.map(RegExp.escape).join('|')})\$');
final _platformOutcomePattern = RegExp(
    '^(${_platforms.map(RegExp.escape).join('|')}) · (${_outcomes.keys.map(RegExp.escape).join('|')})\$');
final _bodyPatterns = <(RegExp, String Function(String))>[
  (
    RegExp(
        r'^ระบบรับผลจาก ([0-6]) ช่องทางแล้ว แต่ยังยืนยันรูปแบบปลายทางไม่ได้$'),
    (n) =>
        'Results received from ${_channels(n)}, but the delivery outcome is not confirmed.'
  ),
  (
    RegExp(r'^ส่ง ([0-6]) ช่องทางเป็นร่างแล้ว · ส่งออกจริงและใช้โควตาโพสต์$'),
    (n) =>
        'Sent as ${n == '1' ? 'a draft' : 'drafts'} to ${_channels(n)} · Data was sent and post quota was used.'
  ),
  (
    RegExp(
        r'^ระบบกำลังส่ง ([0-6]) ช่องทาง กรุณาตรวจผลอีกครั้งในหน้ารายการโพสต์$'),
    (n) =>
        'Sending to ${_channels(n)}. Check the result again in your post list.'
  ),
  (
    RegExp(r'^ส่ง ([0-6]) ช่องทางสำเร็จแล้ว$'),
    (n) => 'Sent to ${_channels(n)}.'
  ),
  (
    RegExp(r'^ระบบรับรายการตั้งเวลาสำหรับ ([0-6]) ช่องทางแล้ว$'),
    (n) => 'Scheduled post received for ${_channels(n)}.'
  ),
  (
    RegExp(r'^ระบบรับรายการ ([0-6]) ช่องทางแล้ว กำลังส่ง$'),
    (n) => 'Post received for ${_channels(n)}. Delivery is in progress.'
  ),
];

const _platforms = [
  'TikTok',
  'YouTube Shorts',
  'Instagram Reels',
  'Facebook Reels',
  'Shopee Video',
  'Lazada Video'
];
const _outcomes = {
  'ส่งเป็นร่างแล้ว': 'Sent as draft',
  'ส่วนตัว': 'Private',
  'ไม่แสดงในรายการ': 'Unlisted',
  'เผยแพร่แล้ว': 'Published',
  'ผลยังไม่ยืนยัน': 'Delivery unconfirmed',
  'ส่งสำเร็จหลายรูปแบบ': 'Delivered with different visibility',
};
const _resultBodies = {
  'ส่งสำเร็จเพียงบางช่องทาง กรุณาเปิดรายละเอียดเพื่อตรวจช่องทางที่ไม่สำเร็จ':
      'Only some channels succeeded. Open the post details to check the channels that failed.',
  'รายการนี้ส่งไม่สำเร็จ เปิดรายละเอียดเพื่อดูสิ่งที่ต้องแก้':
      'This post was not sent. Open the details to see what needs fixing.',
};
const _messages = <String, String>{
  ..._outcomes,
  ..._resultBodies,
  'กำลังเตรียมข้อมูล': 'Preparing post',
  'กำลังตรวจสอบระบบโพสต์': 'Checking publishing service',
  'กำลังตรวจสอบแพ็กเกจ': 'Checking plan',
  'กำลังใส่ลายน้ำ': 'Applying watermark',
  'กำลังอัปโหลดวิดีโอ': 'Uploading video',
  'กำลังเชื่อมต่ออัปโหลดใหม่': 'Reconnecting upload',
  'กำลังอัปโหลดหน้าปก': 'Uploading cover',
  'กำลังสร้างคิวโพสต์': 'Creating post',
  'กำลังยืนยันรายการ': 'Finalizing post',
  'ความคืบหน้าตามขั้นตอน': 'Step progress',
  'เตรียมข้อมูล': 'Prepare',
  'อัปโหลด': 'Upload',
  'สร้างคิว': 'Queue',
  'เสร็จแล้ว': 'Done',
  'กำลังทำ': 'In progress',
  'รอขั้นตอน': 'Waiting',
  'เปอร์เซ็นต์นี้แสดงขั้นตอนงาน ไม่ใช่จำนวนไบต์ที่อัปโหลด':
      'This percentage shows progress through the steps, not uploaded bytes.',
  'กรุณาเปิดแอปหน้านี้ไว้ระหว่างเตรียมและส่งข้อมูล ยังยกเลิกไม่ได้จนจบขั้นตอน':
      'Keep this screen open while your post is prepared and sent. You cannot cancel until this step finishes.',
  'ยังยกเลิกไม่ได้ระหว่างส่งข้อมูล กรุณารอจนจบขั้นตอน':
      'You cannot cancel while data is being sent. Wait for this step to finish.',
  'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายการโพสต์ใหม่':
      'Your account has changed. Reopen the post list.',
  'เกิดข้อผิดพลาดระหว่างส่งโพสต์ กรุณาตรวจการเชื่อมต่อแล้วลองใหม่':
      'An error occurred while sending your post. Check your connection and try again.',
  'ส่งโพสต์ไม่สำเร็จ': 'Could not send post',
  'ลองใหม่': 'Try again',
  'กลับไปตรวจสอบ': 'Go back and check',
  'ดูโพสต์นี้': 'View this post',
  'เสร็จสิ้น': 'Done',
  'ดูสถิติโพสต์': 'View post analytics',
  'ส่งสำเร็จบางช่องทาง': 'Delivered to some channels',
  'กำลังส่ง': 'Sending post',
  'ส่งสำเร็จ': 'Post sent',
  'ส่งไม่สำเร็จ': 'Post not sent',
  'จัดคิวส่งตามเวลาแล้ว': 'Post scheduled',
  'รับรายการแล้ว': 'Post received',
};

class PublishFlowText extends StatelessWidget {
  const PublishFlowText(this.message,
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
      Text(localizePublishFlowMessage(context, message),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap);
}
