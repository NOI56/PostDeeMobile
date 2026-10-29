import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../shared/post_schedule_policy.dart';

bool reviewUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String reviewText(BuildContext context, String thai, String english) =>
    reviewUsesThai(context) ? thai : english;

/// App-owned review copy only. Never pass captions, account names or titles here.
String localizeReviewMessage(BuildContext context, String message) {
  if (reviewUsesThai(context)) return message;
  final known = _messages[message];
  if (known != null) return known;
  const draftPrefix = 'เชื่อมช่องทางที่เก็บไว้ในร่างให้ครบก่อนโพสต์: ';
  if (message.startsWith(draftPrefix)) {
    final list = message.substring(draftPrefix.length);
    final platforms = list.split(', ');
    if (platforms.isNotEmpty &&
        platforms.length <= 6 &&
        platforms.toSet().length == platforms.length &&
        platforms.every(_platformLabels.contains)) {
      return 'Reconnect all channels saved in this draft before posting: $list';
    }
  }
  if (message == schedulePaidPlanMessage) {
    return getSchedulePaidPlanMessage(languageCode: 'en');
  }
  if (message == scheduleSubscriptionUnavailableMessage) {
    return getScheduleSubscriptionUnavailableMessage(languageCode: 'en');
  }
  const retryWarning = ' หากเคยกดยืนยันแล้ว ให้ตรวจปฏิทินก่อนเริ่มโพสต์ใหม่';
  final hasRetryWarning = message.endsWith(retryWarning);
  final limit = _whole(
      RegExp(
          r'^ตั้งเวลาโพสต์ล่วงหน้าได้สูงสุด (14|30) วัน กรุณาเลือกเวลาใหม่$'),
      hasRetryWarning
          ? message.substring(0, message.length - retryWarning.length)
          : message);
  if (limit != null) {
    return 'You can schedule posts up to ${limit[1]} days ahead. Choose another time.${hasRetryWarning ? ' If you already confirmed, check Calendar before starting a new post.' : ''}';
  }
  final count = _whole(RegExp(r'^โพสต์ไปยัง ([0-6]) ช่องทาง$'), message);
  if (count != null) {
    return 'Post to ${count[1]} ${count[1] == '1' ? 'channel' : 'channels'}';
  }
  final cover = _whole(RegExp(r'^หน้าปกเลือกจากวินาทีที่ (\d+\.\d)$'), message);
  if (cover != null) return 'Cover selected at ${cover[1]} seconds';
  for (final privacy in _privacy.entries) {
    if (message == 'โพสต์ตรง · ${privacy.key} · TikTok อาจประมวลผลหลายนาที') {
      return 'Direct post · ${privacy.value} · TikTok may take several minutes to process.';
    }
  }
  const quota = ' · ส่งออกจริงและใช้โควตาโพสต์';
  for (final destination in ['TikTok', 'Facebook Page']) {
    final suffix = destination == 'TikTok'
        ? 'Sends the video and uses your post quota.'
        : 'Sends the post and uses your post quota.';
    if (message == 'ส่งเป็นร่างเข้า $destination$quota') {
      return 'Send as draft to $destination · $suffix';
    }
    for (var month = 0; month < _thaiMonths.length; month++) {
      final draft = _whole(
          RegExp(
              '^ส่งเข้าร่างเวลา ([1-9]|[12][0-9]|3[01]) ${RegExp.escape(_thaiMonths[month])} ([01][0-9]|2[0-3]):([0-5][0-9]) น\\. · $destination$quota\$'),
          message);
      if (draft != null) {
        return 'Send to drafts on ${draft[1]} ${_englishMonths[month]} at ${draft[2]}:${draft[3]} · $destination · $suffix';
      }
    }
  }
  for (final label in _detailLabels.entries) {
    for (final answer in _answers.entries) {
      if (message == '${label.key}: ${answer.key}') {
        return '${label.value}: ${answer.value}';
      }
    }
  }
  final interactions = _whole(
      RegExp(
          r'^ความคิดเห็น: (เปิด|ปิด) · Duet: (เปิด|ปิด) · Stitch: (เปิด|ปิด)$'),
      message);
  if (interactions != null) {
    String onOff(String? value) => value == 'เปิด' ? 'On' : 'Off';
    return 'Comments: ${onOff(interactions[1])} · Duet: ${onOff(interactions[2])} · Stitch: ${onOff(interactions[3])}';
  }
  return message;
}

RegExpMatch? _whole(RegExp regex, String value) {
  final match = regex.firstMatch(value);
  return match != null && match.start == 0 && match.end == value.length
      ? match
      : null;
}

const _thaiMonths = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.'
];

const _platformLabels = [
  'TikTok',
  'YouTube Shorts',
  'Instagram Reels',
  'Facebook Reels',
  'Shopee Video',
  'Lazada Video'
];
const _englishMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];
const _privacy = {
  'ทุกคน': 'Everyone',
  'เพื่อนที่ติดตามกัน': 'Friends who follow each other',
  'ผู้ติดตาม': 'Followers',
  'เฉพาะฉัน': 'Only me'
};
const _answers = {
  'ใช่': 'Yes',
  'ไม่ใช่': 'No',
  'มี': 'Yes',
  'ไม่มี': 'No',
  'ยังไม่ระบุ': 'Not specified',
  'ยังไม่ระบุ (ไม่บังคับ)': 'Not specified (optional)',
  'ยืนยันแล้ว': 'Confirmed',
  'ยังไม่ยืนยัน': 'Not confirmed'
};
const _detailLabels = {
  'โปรโมตแบรนด์ตนเอง': 'Promotes own brand',
  'เนื้อหาที่มีผู้สนับสนุน': 'Sponsored content',
  'สร้างโดย AI': 'AI-generated',
  'สำหรับเด็ก': 'Made for kids',
  'สื่อสังเคราะห์ที่ดูเหมือนจริง': 'Realistic synthetic media',
  'กฎชุมชน YouTube': 'YouTube Community Guidelines',
  'ข้อกำหนดการใช้เพลง TikTok': 'TikTok Music Usage Confirmation',
  'นโยบายเนื้อหาที่มีผู้สนับสนุน': 'Branded Content Policy'
};
const _messages = <String, String>{
  'ตรวจข้อมูลและเลือกเวลาที่ต้องการโพสต์':
      'Review your details and choose when to post.',
  'ระหว่างเตรียมและส่งข้อมูล กรุณาเปิดแอปหน้านี้ไว้ ยังยกเลิกไม่ได้จนจบขั้นตอน':
      'Keep this screen open while your post is being prepared and sent. You cannot cancel until this step finishes.',
  'แก้แคปชัน': 'Edit caption',
  'แก้ช่องทาง': 'Edit channels',
  'ยังไม่ได้เลือกคลิป': 'No video selected',
  'คลิปของคุณ': 'Your video',
  'วันนี้ไม่มีเวลาเหลือสำหรับตั้งโพสต์ เลือกโพสต์เลยหรือวันใหม่':
      'There is no time left to schedule a post today. Choose Post now or another day.',
  'เวลาตั้งโพสต์ไม่ถูกต้อง กรุณาเลือกใหม่':
      'The scheduled time is invalid. Choose another time.',
  'เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต': 'The posting time must be in the future.',
  'เวลาเดิมผ่านไปแล้ว เลือกเวลาใหม่หรือเลือกโพสต์เลยก่อนยืนยัน':
      'The previous time has passed. Choose a new time or Post now before confirming.',
  'เวลาเดิมผ่านไปแล้ว เลือกเวลาใหม่หรือเลือกโพสต์เลย':
      'The previous time has passed. Choose a new time or Post now.',
  'ยืนยันเบอร์โทรก่อนโพสต์ฟรี 3 ครั้งต่อเดือน':
      'Verify your phone number before using the 3 free post units per month.',
  'Starter ตั้งเวลาล่วงหน้าได้ 14 วัน และ Pro 30 วัน กรุณาเลือกเวลาใหม่':
      'Starter allows scheduling up to 14 days ahead and Pro up to 30 days. Choose another time.',
  'ตรวจสอบช่องทางไม่ได้': 'Could not check channels',
  'ยังไม่ได้เลือกช่องทาง': 'No channels selected',
  'ยังไม่ได้เชื่อมช่องทาง': 'No channels connected',
  'เลือกอย่างน้อย 1 ช่องทางก่อนเริ่มโพสต์':
      'Select at least 1 channel before posting.',
  'ต้องเชื่อมอย่างน้อย 1 ช่องทางก่อนจึงจะเริ่มโพสต์ได้':
      'Connect at least 1 channel before posting.',
  'ไปเชื่อมช่องทาง': 'Connect a channel',
  'ไว้ก่อน': 'Not now',
  'พรีวิว': 'Preview',
  'พรีวิววิดีโอ': 'Preview video',
  'แคปชั่น': 'Caption',
  '(ไม่มีแคปชั่น)': '(No caption)',
  'ใช้แคปชั่นแยกตามช่องทางด้านล่าง':
      'Using separate captions for each channel below',
  'แก้ไข': 'Edit',
  'กำหนดเวลา': 'Schedule',
  'โพสต์ทันที': 'Post now',
  'ยังไม่พร้อมโพสต์ตรง': 'Direct post is not ready',
  'ตั้งค่า YouTube ยังไม่ครบ': 'YouTube settings are incomplete',
  'ส่วนตัว (Private)': 'Private',
  'ไม่เป็นสาธารณะ (Unlisted)': 'Unlisted',
  'สาธารณะ (Public)': 'Public',
  'Reels + ฟีด · เผยแพร่ตามบัญชี': 'Reels + feed · Uses account settings',
  'Reels อย่างเดียว · เผยแพร่ตามบัญชี': 'Reels only · Uses account settings',
  'เผยแพร่บนเพจ': 'Publish to Page',
  'เก็บเป็นร่างบนเพจ · ส่งออกจริงและใช้โควตาโพสต์':
      'Save as Page draft · Sends the post and uses your post quota.',
  'ตั้งค่า Facebook ยังไม่ครบ': 'Facebook settings are incomplete',
  'ยังยืนยันบัญชีปลายทางไม่ได้': 'Destination account not confirmed',
  'ยังไม่ทราบรูปแบบเผยแพร่': 'Publishing method not confirmed',
  'Instagram ไม่มี Private รายโพสต์ วิดีโอจะเผยแพร่ตามบัญชีที่เชื่อม':
      'Instagram does not offer per-post Private visibility. The video will use your connected account’s visibility.',
  'ยังไม่ได้เลือกช่องทาง กรุณากลับไปเลือกช่องทางก่อนโพสต์':
      'No channels selected. Go back and choose channels before posting.',
  'ยังยืนยันบัญชีหรือเพจปลายทางของบางช่องทางไม่ได้ กรุณารีเฟรชหรือเชื่อมต่อใหม่':
      'Some destination accounts or Pages are not confirmed. Refresh channels or reconnect them.',
  'ยังยืนยันรูปแบบเผยแพร่ของบางช่องทางไม่ได้ กรุณากลับไปเลือกช่องทางใหม่':
      'The publishing method for some channels is not confirmed. Go back and review your channels.',
  'เมื่อกดยืนยันโพสต์หรือตั้งเวลา คุณรับรองว่าเนื้อหาที่อัปโหลดเป็นไปตามข้อกำหนดการให้บริการ YouTube รวมถึงกฎชุมชน โปรดอย่าละเมิดลิขสิทธิ์หรือความเป็นส่วนตัวของผู้อื่น':
      'By confirming a post or schedule, you certify that your uploaded content complies with YouTube’s Terms of Service and Community Guidelines. Respect other people’s copyright and privacy.',
  'อ่านข้อกำหนด YouTube': 'Read YouTube terms',
  'เปิดข้อกำหนด YouTube ไม่สำเร็จ ลองใหม่หรือเปิด m.youtube.com/terms ในเบราว์เซอร์':
      'Could not open YouTube terms. Try again or open m.youtube.com/terms in your browser.',
  'ดูคลิป': 'Watch video',
  'ดูปก': 'View cover',
  'ปกที่เลือกใน PostDee': 'Cover selected in PostDee',
  'ลายน้ำจริงจะถูกใส่ตอนส่งโพสต์':
      'The watermark will be added when the post is sent.',
  'ภาพตัวอย่างก่อนส่ง · หน้าตาจริงอาจต่างตามแพลตฟอร์ม':
      'Preview before sending · Appearance may vary by platform.',
  'ย่อแคปชั่น': 'Collapse caption',
  'ดูแคปชั่นทั้งหมด': 'Show full caption',
  'เสียงจากคลิป': 'Video audio',
  'ยังแสดงปกไม่ได้': 'Could not display the cover',
  'ข้อมูลพรีวิว': 'Preview information',
  'หัวใจและความคิดเห็นเป็นภาพตัวอย่าง':
      'Hearts and comments are part of the preview.',
  'ปิด': 'Close',
  'TikTok ใช้เฟรมจากคลิปเป็นปก ไม่ใช้ภาพปกแต่งนี้':
      'TikTok uses a video frame as the cover, not this edited cover image.',
  'ภาพปกนี้ไม่ได้ส่งเป็นภาพย่อ YouTube':
      'This cover is not sent as a YouTube thumbnail.',
  'Facebook อาจใช้เฟรมอื่นเป็นภาพปก':
      'Facebook may use a different frame as the cover.',
  'ภาพปกที่เลือกไว้ รูปแบบจริงอาจต่างตามแพลตฟอร์ม':
      'Your selected cover. The final appearance may vary by platform.',
  'การรองรับหน้าปก': 'Cover support',
  'Instagram Reels: ใช้ภาพปกที่แต่งได้':
      'Instagram Reels: Uses your edited cover',
  'Facebook Reels: การแสดงหน้าปกขึ้นอยู่กับ Facebook':
      'Facebook Reels: Cover display depends on Facebook',
  'TikTok: ใช้เฉพาะเฟรมที่เลือก ไม่ส่งข้อความแต่งปก':
      'TikTok: Uses the selected frame only; cover text is not sent',
  'YouTube Shorts: แต่งต่อในแอป YouTube':
      'YouTube Shorts: Continue editing in the YouTube app',
  'ตั้งเวลาโพสต์': 'Post timing',
  'โพสต์เลย': 'Post now',
  'ตั้งเวลา': 'Schedule',
  'วันนี้': 'Today',
  'พรุ่งนี้': 'Tomorrow',
  'เลือกวัน': 'Choose date',
  'เลือกเวลา': 'Choose time',
  'กำหนดเอง': 'Custom',
  'แพ็กเกจ Starter ตั้งเวลาล่วงหน้าได้สูงสุด 14 วัน':
      'Starter: schedule up to 14 days ahead',
  'แพ็กเกจ Pro ตั้งเวลาล่วงหน้าได้สูงสุด 30 วัน':
      'Pro: schedule up to 30 days ahead',
};

class ReviewText extends StatelessWidget {
  const ReviewText(this.message,
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
      Text(localizeReviewMessage(context, message),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap);
}
