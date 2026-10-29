import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import 'caption_localizations.dart';
import 'channel_localizations.dart';
import 'review_localizations.dart';
import 'publish_submission_localizations.dart';

bool uploaderUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String uploaderText(BuildContext context, String thai, String english) =>
    uploaderUsesThai(context) ? thai : english;

/// Only app-owned copy belongs here. Render filenames, captions, draft names,
/// and unrecognized provider text directly instead of passing them here.
String localizeUploaderMessage(BuildContext context, String message) {
  if (uploaderUsesThai(context)) return message;
  final known = _englishMessages[message];
  if (known != null) return known;

  final step = _wholeMatch(
      RegExp(
          r'^ขั้นตอนที่ ([1-4]) จาก 4 · (เลือกคลิป|เขียนแคปชัน|เลือกช่องทาง|ตรวจทาน)( เสร็จแล้ว)?$'),
      message);
  if (step != null) {
    final index = int.parse(step[1]!) - 1;
    const titles = ['เลือกคลิป', 'เขียนแคปชัน', 'เลือกช่องทาง', 'ตรวจทาน'];
    if (titles[index] == step[2]) {
      return 'Step ${step[1]} of 4 · ${_englishMessages[step[2]]}${step[3] == null ? '' : ' · Completed'}';
    }
  }
  final drafts = _wholeMatch(RegExp(r'^ฉบับร่าง \((\d+)\)$'), message);
  if (drafts != null) return 'Drafts (${drafts[1]})';
  final channels =
      _wholeMatch(RegExp(r'^(\d+) ช่องทาง · เก็บในเครื่อง$'), message);
  if (channels != null) {
    return '${channels[1]} ${channels[1] == '1' ? 'channel' : 'channels'} · Stored on this device';
  }
  final footer = _wholeMatch(
      RegExp(r'^(เลือกแล้ว|ส่ง|ตั้งเวลา|ยืนยันส่ง) (\d+) ช่องทาง$'), message);
  if (footer != null) {
    final channels =
        '${footer[2]} ${footer[2] == '1' ? 'channel' : 'channels'}';
    return switch (footer[1]) {
      'เลือกแล้ว' => '$channels selected',
      'ส่ง' => 'Send to $channels',
      'ตั้งเวลา' => 'Schedule for $channels',
      _ => 'Confirm send to $channels',
    };
  }
  final frame = _wholeMatch(
      RegExp(r'^เลือกเฟรมที่ ((?:\d{2,}:)?[0-5]\d:[0-5]\d)$'), message);
  if (frame != null) return 'Selected frame at ${frame[1]}';
  final picker =
      _wholeMatch(RegExp(r'^เลือกวิดีโอไม่ได้: ([\s\S]*)$'), message);
  if (picker != null) return 'Could not select the video: ${picker[1]}';

  final duration = _durationMessage(message);
  if (duration != null) return duration;
  final recovered = _wholeMatch(
      RegExp(
          r'^พบรายการเดิม: ([\s\S]+) · (รับรายการแล้ว กำลังรอส่ง|กำลังส่ง|ส่งสำเร็จ|ส่งสำเร็จเพียงบางช่องทาง|ส่งไม่สำเร็จ กรุณาตรวจรายละเอียดในรายการโพสต์|กรุณาตรวจสถานะในรายการโพสต์) · ไม่ได้ส่งซ้ำ ร่างยังอยู่ในเครื่อง$'),
      message);
  if (recovered != null) {
    return 'Original submission found: ${recovered[1]} · ${_recoveryStatuses[recovered[2]]} · Not submitted again. The draft is still on this device.';
  }
  return localizePublishSubmissionMessage(context, localizeReviewMessage(context,
      localizeChannelMessage(context, localizeCaptionMessage(context, message))));
}

RegExpMatch? _wholeMatch(RegExp pattern, String message) {
  final match = pattern.firstMatch(message);
  return match != null && match.start == 0 && match.end == message.length
      ? match
      : null;
}

String? _durationMessage(String message) {
  var base = message;
  var suffix = '';
  for (final entry in _durationSuffixes.entries) {
    if (message.endsWith(entry.key)) {
      base = message.substring(0, message.length - entry.key.length);
      suffix = entry.value;
      break;
    }
  }
  final known = _durationMessages[base];
  if (known != null) return '$known$suffix';
  final tikTok = _wholeMatch(
      RegExp(
          r'^TikTok ต้องใช้คลิปยาวไม่เกิน (?:(\d+) นาที(?: (\d+) วินาที)?|(\d+) วินาที)$'),
      base);
  if (tikTok == null) return null;
  final minutes = tikTok[1];
  final seconds = tikTok[2] ?? tikTok[3];
  final limit = [
    if (minutes != null) '$minutes ${minutes == '1' ? 'minute' : 'minutes'}',
    if (seconds != null) '$seconds ${seconds == '1' ? 'second' : 'seconds'}',
  ].join(' ');
  return 'TikTok requires a video no longer than $limit$suffix';
}

const _durationMessages = <String, String>{
  'YouTube Shorts ต้องใช้คลิปยาวไม่เกิน 3 นาที':
      'YouTube Shorts requires a video no longer than 3 minutes',
  'Instagram Reels ต้องใช้คลิปยาวตั้งแต่ 3 วินาทีถึง 15 นาที':
      'Instagram Reels requires a video from 3 seconds to 15 minutes long',
  'Facebook Reels ต้องใช้คลิปยาวตั้งแต่ 3 วินาทีถึง 1 นาที 30 วินาที':
      'Facebook Reels requires a video from 3 seconds to 1 minute 30 seconds long',
};

const _durationSuffixes = <String, String>{
  ' จึงโพสต์ช่องทางนี้ไม่ได้': '. This video cannot be posted to this channel.',
  ' กรุณายกเลิกช่องทางนี้หรือเลือกคลิปใหม่':
      '. Deselect this channel or choose another video.',
  ' กรุณาตรวจรายการเดิมก่อนเริ่มรายการโพสต์ใหม่':
      '. Check the original submission before starting a new post request.',
};

const _recoveryStatuses = <String, String>{
  'รับรายการแล้ว กำลังรอส่ง': 'Accepted, waiting to send',
  'กำลังส่ง': 'Sending',
  'ส่งสำเร็จ': 'Delivered',
  'ส่งสำเร็จเพียงบางช่องทาง': 'Partially delivered',
  'ส่งไม่สำเร็จ กรุณาตรวจรายละเอียดในรายการโพสต์':
      'Failed. Check the post details',
  'กรุณาตรวจสถานะในรายการโพสต์': 'Check the status in your posts',
};

const _englishMessages = <String, String>{
  'สร้างโพสต์ใหม่': 'Create post',
  'อัปโหลดครั้งเดียว แล้วเลือกช่องทางที่ต้องการ':
      'Upload once, then choose your channels.',
  'ปิดหน้าสร้างโพสต์': 'Close create post',
  'เลือกคลิป': 'Choose video',
  'เขียนแคปชัน': 'Write caption',
  'เลือกช่องทาง': 'Choose channels',
  'ตรวจทาน': 'Review',
  'คลิป': 'Video',
  'แคปชัน': 'Caption',
  'ช่องทาง': 'Channels',
  'เริ่มจากคลิปแนวตั้งที่อยากโพสต์':
      'Start with the vertical video you want to post.',
  'เลือกวิดีโอ 9:16': 'Choose a 9:16 video',
  'เปลี่ยนคลิป': 'Change video',
  'แต่งหน้าปก': 'Create cover',
  'แก้หน้าปก': 'Edit cover',
  'ดูคลิป': 'Watch',
  'เลือกคลิปก่อน': 'Choose a video first',
  'เลือกคลิปแล้ว': 'Video selected',
  'กำลังดำเนินการ...': 'Please wait...',
  'AI กำลังคิดแคปชัน...': 'AI is writing a caption...',
  'แคปชันแก้ไขได้': 'Caption can be edited',
  'กำลังตรวจบัญชี...': 'Checking accounts...',
  'ยืนยันตั้งเวลา': 'Confirm schedule',
  'แก้แคปชันก่อนส่ง': 'Edit the caption before sending',
  'ตรวจปลายทางก่อนส่ง': 'Check destinations before sending',
  'ถัดไป: เขียนแคปชัน': 'Next: Caption',
  'ถัดไป: เลือกช่องทาง': 'Next: Channels',
  'ถัดไป: ตรวจทาน': 'Next: Review',
  'ย้อนกลับ': 'Back',
  'บันทึกร่าง': 'Save draft',
  'กำลังบันทึก...': 'Saving...',
  'บันทึกแล้ว': 'Saved',
  'กำลังเปิดฉบับร่าง...': 'Opening draft...',
  'เก็บโพสต์นี้ไว้ไหม?': 'Keep this post?',
  'มีข้อมูลที่ยังไม่ได้บันทึก กลับมาแก้ต่อได้จากฉบับร่าง':
      'You have unsaved changes. You can continue editing from drafts.',
  'แก้ไขต่อ': 'Keep editing',
  'ออกโดยไม่บันทึก': 'Leave without saving',
  'บันทึกแล้วออก': 'Save and exit',
  'ฉบับร่างในเครื่อง': 'Drafts on this device',
  'ยังไม่อัปโหลด ไม่ส่งไปแพลตฟอร์ม และไม่ใช้โควตา':
      'Not uploaded, not sent to platforms, and no quota used.',
  'แอปคัดลอกวิดีโอและหน้าปกไว้ในพื้นที่แอปของเครื่องนี้ ร่างไม่ซิงก์ข้ามอุปกรณ์ และอาจรวมอยู่ในข้อมูลสำรองของระบบ':
      'The app copies your video and cover into app storage on this device. Drafts do not sync across devices and may be included in system backups.',
  'ยังไม่มีฉบับร่างในเครื่อง': 'No drafts on this device yet',
  'ลบฉบับร่าง': 'Delete draft',
  'ลบฉบับร่างนี้?': 'Delete this draft?',
  'วิดีโอและหน้าปกที่เก็บไว้กับฉบับร่างนี้จะถูกลบจากพื้นที่ของแอป':
      'The video and cover stored with this draft will be deleted from app storage.',
  'ยกเลิก': 'Cancel',
  'ลบร่าง': 'Delete draft',
  'โพสต์คงเหลือ': 'Post units remaining',
  'กำลังโหลดโควตาโพสต์...': 'Loading post quota...',
  'โหลดโควตาโพสต์ไม่สำเร็จ': 'Could not load post quota.',
  'โหลดโควตาโพสต์ใหม่': 'Reload post quota',
  'ยืนยันเบอร์เพื่อใช้โควตาฟรี':
      'Verify your phone number to use the free quota',
  'เลือกวิดีโอจากเครื่องก่อน': 'Choose a video from your device first.',
  'ไฟล์วิดีโอที่เลือกมีข้อมูลไม่ครบ':
      'The selected video file is missing required information.',
  'อ่านขนาดวิดีโอไม่ได้': 'Could not read the video dimensions.',
  'กำลังอ่านความยาวคลิป...': 'Reading video duration...',
  'ยังอ่านความยาวคลิปไม่ได้ จะตรวจซ้ำก่อนส่ง':
      'Video duration is not available yet. It will be checked again before sending.',
  'เลือกวิดีโอจริงจากเครื่องก่อนแต่งหน้าปก':
      'Choose a local video before editing the cover.',
  'บันทึกหน้าปกแล้ว': 'Cover saved',
  'กำลังสร้างไฟล์หน้าปกใหม่...': 'Rebuilding cover file...',
  'บันทึกร่างไม่สำเร็จ ตรวจสอบพื้นที่ว่างในเครื่อง':
      'Could not save the draft. Check the free space on this device.',
  'บันทึกร่างในเครื่องไม่สำเร็จ': 'Could not save the draft on this device.',
  'ยังเปิดพื้นที่เก็บฉบับร่างในเครื่องไม่ได้':
      'Draft storage on this device is not available yet.',
  'เลือกวิดีโอจากเครื่องก่อนบันทึกร่าง':
      'Choose a video from this device before saving a draft.',
  'เวลาโพสต์ไม่ถูกต้อง กรุณาเลือกใหม่':
      'The posting time is invalid. Please choose it again.',
  'บันทึกร่างในเครื่องแล้ว · ยังไม่อัปโหลด ไม่โพสต์ และไม่ใช้โควตา':
      'Draft saved on this device · Nothing uploaded or posted, and no quota used.',
  'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายการฉบับร่างใหม่':
      'Your account has changed. Please reopen Drafts.',
  'ไม่พบวิดีโอของฉบับร่างนี้ในเครื่อง':
      "This draft's video could not be found on this device.",
  'เปิดฉบับร่างแล้ว': 'Draft opened',
  'เวลาเดิมผ่านไปแล้ว เลือกเวลาใหม่หรือเลือกโพสต์เลยก่อนยืนยัน':
      'The previous time has passed. Choose a new time or Post now before confirming.',
  'บางช่องทางในร่างยังไม่ได้เชื่อมต่อ กรุณาเชื่อมใหม่ก่อนโพสต์':
      'Some channels in this draft are disconnected. Reconnect them before posting.',
  'เปิดฉบับร่างนี้ไม่ได้ อาจถูกลบแล้ว เลือกฉบับร่างอื่นหรือสร้างโพสต์ใหม่':
      'This draft could not be opened. It may have been deleted. Choose another draft or create a new post.',
  'เปิดฉบับร่างไม่สำเร็จ เลือกฉบับร่างอีกครั้ง':
      'Could not open the draft. Please select it again.',
  'โหลดฉบับร่างในเครื่องไม่สำเร็จ': 'Could not load drafts on this device.',
  'ลบฉบับร่างไม่สำเร็จ': 'Could not delete the draft.',
  'ลบฉบับร่างแล้ว': 'Draft deleted',
  'มีข้อมูลอัปโหลดของคำขอเดิม ตรวจผลการส่งได้โดยไม่อัปโหลดหรือส่งโพสต์ซ้ำ':
      'Upload information from the original request is available. Check the result without uploading or submitting the post again.',
  'กำลังตรวจผลการส่งเดิม...': 'Checking the original submission...',
  'ตรวจผลการส่งเดิม': 'Check original submission',
  'ดูโพสต์นี้': 'View this post',
  'เริ่มรายการโพสต์ใหม่': 'Start a new post request',
  'เริ่มรายการโพสต์ใหม่?': 'Start a new post request?',
  'กรุณาตรวจหน้ารายการโพสต์และแพลตฟอร์มปลายทางก่อน เพราะรายการเดิมอาจถูกส่งไปแล้ว การเริ่มรายการใหม่อาจโพสต์ซ้ำได้':
      'Check your post history and destination platforms first. The original request may already have been sent. Starting a new request may create duplicate posts.',
  'ตรวจแล้ว เริ่มรายการใหม่': 'Checked. Start a new request',
  'สร้างร่างสำหรับรายการโพสต์ใหม่แล้ว กรุณาตรวจทานก่อนโพสต์':
      'A draft for a new post request has been created. Review it before posting.',
  'ร่างนี้มีไฟล์อัปโหลดเดิมที่ยังไม่มีข้อมูลระยะเวลาสำหรับ TikTok กรุณาตรวจรายการเดิมก่อนเริ่มรายการโพสต์ใหม่':
      'This draft has an earlier upload without TikTok duration information. Check the original submission before starting a new post request.',
  'ร่างนี้มีไฟล์อัปโหลดเดิมที่ยังไม่ผ่านการเตรียมวิดีโอ TikTok กรุณาตรวจรายการโพสต์และปลายทางก่อนเริ่มรายการโพสต์ใหม่':
      'This draft has an earlier upload that has not passed TikTok video preparation. Check your posts and destinations before starting a new post request.',
  'ไม่พบข้อมูลการส่งเดิม ร่างยังอยู่ในเครื่อง':
      'Original submission information was not found. The draft is still on this device.',
  'ยังไม่พบรายการที่ระบบรับไว้ ร่างและข้อมูลอัปโหลดเดิมยังอยู่ ไม่ได้ส่งโพสต์ใหม่':
      'No accepted submission was found yet. The draft and original upload information are still available. No new post was submitted.',
  'ตรวจผลการส่งเดิมไม่สำเร็จ ร่างยังอยู่ในเครื่อง กรุณาลองใหม่':
      'Could not check the original submission. The draft is still on this device. Please try again.',
  'ระบบ PostDee ไม่พร้อมใช้งานชั่วคราว กรุณาลองใหม่ภายหลัง':
      'PostDee is temporarily unavailable. Please try again later.',
  'ระบบตอบกลับช้าเกินไป กรุณาลองใหม่อีกครั้ง':
      'The request took too long. Please try again.',
  'เชื่อมต่อ PostDee ไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่':
      'Cannot connect to PostDee. Check your internet connection and try again.',
  'กรุณาเข้าสู่ระบบใหม่ แล้วลองอีกครั้ง': 'Please sign in again and retry.',
  'มีคำขอมากเกินไป กรุณารอสักครู่แล้วลองใหม่':
      'Too many requests. Wait a moment and try again.',
  'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
      'Could not complete the action. Please try again.',
};

class UploaderText extends StatelessWidget {
  const UploaderText(this.message,
      {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  final String message;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text(
        localizeUploaderMessage(context, message),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
}
