import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';

bool channelUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String channelText(BuildContext context, String thai, String english) =>
    channelUsesThai(context) ? thai : english;

/// Call only for app-owned labels. Account names, captions, titles, and unknown
/// provider messages must remain raw at their presentation boundaries.
String localizeChannelMessage(BuildContext context, String message) {
  if (channelUsesThai(context)) return message;
  final known = _messages[message];
  if (known != null) return known;
  final connected = _whole(RegExp(r'^เชื่อมต่อแล้ว ([0-6]) ช่องทาง$'), message);
  if (connected != null) {
    return '${connected[1]} ${connected[1] == '1' ? 'channel' : 'channels'} connected';
  }
  for (final entry in _privacy.entries) {
    if (message == 'โพสต์ตรง · ${entry.key}') {
      return 'Direct post · ${entry.value}';
    }
  }
  for (final platform in _platforms) {
    final prefix = '$platform: ';
    if (message.startsWith(prefix)) {
      final status = message.substring(prefix.length);
      if (_readiness.containsKey(status)) return '$prefix${_readiness[status]}';
    }
    if (message ==
        'บัญชี $platform เปลี่ยนแล้ว กรุณารีเฟรชช่องทางและตรวจทานใหม่') {
      return 'The $platform account has changed. Refresh channels and review your settings again.';
    }
  }
  const policyPrefix =
      'เปิดเงื่อนไข TikTok ไม่สำเร็จ ลองใหม่หรือเปิดลิงก์นี้ในเบราว์เซอร์: ';
  for (final url in [
    'https://www.tiktok.com/legal/page/global/music-usage-confirmation/en',
    'https://www.tiktok.com/legal/page/global/bc-policy/en',
  ]) {
    if (message == '$policyPrefix$url') {
      return 'Could not open TikTok terms. Try again or open this link in your browser: $url';
    }
  }
  return message;
}

RegExpMatch? _whole(RegExp pattern, String value) {
  final match = pattern.firstMatch(value);
  return match != null && match.start == 0 && match.end == value.length
      ? match
      : null;
}

const _platforms = [
  'TikTok',
  'YouTube Shorts',
  'Instagram Reels',
  'Facebook Reels',
  'Facebook Page Reels',
  'Shopee Video',
  'Lazada Video'
];
const _privacy = {
  'ทุกคน': 'Everyone',
  'เพื่อนที่ติดตามกัน': 'Friends who follow each other',
  'ผู้ติดตาม': 'Followers',
  'เฉพาะฉัน': 'Only me',
};
const _readiness = {
  'สิทธิ์เผยแพร่พร้อม · ตรวจแล้ว': 'Publishing permissions verified',
  'เชื่อมต่อแล้ว · ยังยืนยันสิทธิ์เผยแพร่ไม่ได้':
      'Connected · Publishing permissions not verified',
  'ต้องเชื่อมบัญชีใหม่ก่อนโพสต์': 'Reconnect this account before posting',
  'สิทธิ์เผยแพร่ไม่ครบ กรุณาเชื่อมบัญชีใหม่':
      'Publishing permissions are missing. Reconnect this account.',
  'ช่องทางนี้ไม่ได้เชื่อมต่อ กรุณาเชื่อมใหม่':
      'This channel is not connected. Reconnect it.',
  'ยังตรวจสิทธิ์ไม่ได้ กรุณาลองใหม่':
      'Could not check publishing permissions. Try again.',
  'ยังตรวจสิทธิ์ไม่ได้ กรุณารีเฟรชช่องทาง':
      'Could not check publishing permissions. Refresh channels.',
};
const _messages = <String, String>{
  ..._privacy,
  ..._readiness,
  'ตรวจสอบช่องทางที่เชื่อมต่อไม่สำเร็จ ลองใหม่อีกครั้ง':
      'Could not check connected channels. Please try again.',
  'ใช้การตั้งค่ากับคลิปนี้แล้ว แต่จำค่าไว้ครั้งถัดไปไม่สำเร็จ':
      'Settings applied to this video, but they could not be remembered for next time.',
  'โหลดค่าที่จำไว้ไม่สำเร็จ กรุณาเปิดตั้งค่าช่องทางเพื่อตรวจสอบก่อน':
      'Could not load remembered settings. Open channel settings to review them first.',
  'ตรวจสิทธิ์เผยแพร่ไม่สำเร็จ กรุณารีเฟรชช่องทางก่อนโพสต์':
      'Could not check publishing permissions. Refresh channels before posting.',
  'บัญชีหรือคลิปเปลี่ยนแล้ว กรุณาเปิดการตั้งค่าใหม่':
      'The account or video has changed. Reopen settings.',
  'กำลังโหลดค่าที่จำไว้': 'Loading remembered settings',
  'โหลดค่าที่จำไว้ไม่สำเร็จ ตั้งค่าสำหรับคลิปนี้ได้ตามปกติ':
      'Could not load remembered settings. You can still configure this video.',
  'เลือกบัญชีปลายทางและตั้งค่าของแต่ละช่องทาง':
      'Choose destination accounts and configure each channel.',
  'ปิด': 'Close',
  'ยกเลิก': 'Cancel',
  'บันทึกการตั้งค่า': 'Save settings',
  'ยังยืนยันบัญชีไม่ได้': 'Account not confirmed',
  'กำลังตรวจสอบช่องทาง': 'Checking channels...',
  'กำลังตรวจสอบช่องทาง...': 'Checking channels...',
  'ตรวจสอบช่องทางไม่ได้ ลองใหม่': 'Could not check channels. Try again.',
  'ยังไม่ได้เชื่อมต่อช่องทาง': 'No channels connected',
  'กรุณารอผลการตรวจสอบสถานะช่องทาง':
      'Please wait while channel status is checked.',
  'ยังยืนยันสถานะบัญชีไม่ได้ กรุณาลองใหม่ก่อนโพสต์':
      'Account status is not confirmed. Try again before posting.',
  'เชื่อมต่อบัญชีโซเชียลก่อนเริ่มโพสต์':
      'Connect your social accounts before posting.',
  'เลือกเฉพาะช่องทางที่ต้องการโพสต์รอบนี้':
      'Choose only the channels for this post.',
  'โหลดช่องทางที่เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่':
      'Could not check connected channels. Please try again.',
  'ลองใหม่': 'Try again',
  'ตรวจสิทธิ์อีกครั้ง': 'Recheck publishing permissions',
  'เลือกทั้งหมด': 'Select all',
  'เลือกทั้งหมดที่รองรับ': 'Select all supported',
  'ล้างทั้งหมด': 'Clear all',
  'ตั้งค่าช่องทาง': 'Channel settings',
  'แก้การตั้งค่าช่องทางนี้': 'Edit this channel’s settings',
  'กำลังตรวจสอบช่องทางที่เชื่อมต่อ กรุณารอสักครู่':
      'Checking connected channels. Please wait.',
  'เชื่อมและเลือกอย่างน้อย 1 ช่องทางก่อน':
      'Connect and select at least 1 channel first.',
  'ยังยืนยันบัญชีหรือเพจปลายทางไม่ได้ กรุณารีเฟรชช่องทางหรือเชื่อมต่อใหม่':
      'The destination account or Page is not confirmed. Refresh channels or reconnect it.',
  'ร่างใน TikTok': 'TikTok draft',
  'ต้องตั้งค่าโพสต์ตรง': 'Set up Direct post',
  'ต้องตั้งค่า': 'Settings required',
  'ส่วนตัว · พร้อม': 'Private · Ready',
  'ไม่เป็นสาธารณะ · พร้อม': 'Unlisted · Ready',
  'สาธารณะ · พร้อม': 'Public · Ready',
  'แชร์ในฟีด': 'Share to feed',
  'ไม่แชร์ในฟีด': 'Do not share to feed',
  'ร่างบนเพจ': 'Page draft',
  'ยังไม่รองรับ': 'Not supported yet',
  'โพสต์ช่องทางนี้ไม่ได้': 'Cannot post to this channel',
  'ส่งคลิปไปแก้ต่อใน TikTok': 'Send your video to continue editing in TikTok',
  'อัปขึ้น YouTube Shorts จากคลิปเดียว':
      'Upload the same video to YouTube Shorts',
  'เผยแพร่ Reels ตามบัญชีที่เชื่อม': 'Publish Reels to your connected account',
  'เลือกเผยแพร่หรือร่างบนเพจ': 'Choose publishing or a Page draft',
  'โพสต์วิดีโอขึ้น Shopee Video': 'Post a video to Shopee Video',
  'โพสต์วิดีโอขึ้น Lazada Video': 'Post a video to Lazada Video',
  'เปิดการตั้งค่า TikTok เพื่อเลือกการมองเห็นและยืนยันก่อนโพสต์':
      'Open TikTok settings to choose visibility and confirm before posting.',
  'ตั้งค่า YouTube ให้ครบก่อนโพสต์':
      'Complete YouTube settings before posting.',
  'เลือกว่าจะเผยแพร่หรือเก็บเป็นร่างบนเพจก่อน':
      'Choose publishing or a Page draft first.',
  'ตั้งค่า Instagram ให้ครบก่อนโพสต์':
      'Complete Instagram settings before posting.',
  'ช่องทางนี้ยังไม่พร้อมให้โพสต์': 'This channel is not ready for posting yet.',
  'เมื่อบันทึก จะจำวิธีส่งให้ช่องนี้บนเครื่องนี้ ผู้ชมและการโต้ตอบต้องเลือกใหม่ทุกคลิป':
      'Saving remembers the delivery method for this channel on this device. Choose viewers and interactions again for every video.',
  'เมื่อบันทึก จะจำการมองเห็นและกลุ่มผู้ชมให้ช่องนี้บนเครื่องนี้ ตรวจเนื้อหา AI และยืนยันกฎใหม่ทุกคลิป':
      'Saving remembers visibility and audience for this channel on this device. Review AI content and confirm the guidelines again for every video.',
  'เมื่อบันทึก จะจำการแชร์ไปยังฟีดให้บัญชีนี้บนเครื่องนี้':
      'Saving remembers sharing to feed for this account on this device.',
  'เมื่อบันทึก จะจำวิธีเผยแพร่ให้เพจนี้บนเครื่องนี้':
      'Saving remembers the publishing method for this Page on this device.',
  'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดการตั้งค่า TikTok ใหม่':
      'Your account has changed. Reopen TikTok settings.',
  'โหลดตัวเลือก TikTok ล่าสุดไม่สำเร็จ กรุณาลองใหม่':
      'Could not load the latest TikTok options. Please try again.',
  'รอข้อมูลบัญชี TikTok ล่าสุดก่อนตั้งค่าโพสต์ตรง':
      'Wait for the latest TikTok account information before setting up Direct post.',
  'เลือกชนิดเนื้อหาเชิงพาณิชย์ก่อน':
      'Choose the type of commercial content first.',
  'วิธีส่งวิดีโอ': 'Video delivery',
  'ส่งเป็นร่างเข้า TikTok': 'Send as draft to TikTok',
  'โพสต์ตรง': 'Direct post',
  'ตั้งค่าต่อใน TikTok': 'Continue in TikTok',
  'ส่งออกจริงและใช้โควตาโพสต์':
      'This sends the video and uses your post quota.',
  'วิดีโอจะถูกส่งเข้า TikTok Inbox ให้คุณเปิด TikTok เพื่อตรวจ แก้ไข และยืนยันเผยแพร่ต่อ':
      'Your video will be sent to TikTok Inbox. Open TikTok to review, edit, and confirm publishing it.',
  'ผู้ชมและการโต้ตอบ': 'Viewers and interactions',
  'ใครดูวิดีโอนี้ได้': 'Who can view this video',
  'เลือกการมองเห็น': 'Choose visibility',
  'อนุญาตความคิดเห็น': 'Allow comments',
  'อนุญาต Duet': 'Allow Duet',
  'อนุญาต Stitch': 'Allow Stitch',
  'เนื้อหาโปรโมตและผู้สนับสนุน': 'Promotional and sponsored content',
  'เนื้อหาเชิงพาณิชย์': 'Commercial content',
  'โปรโมตแบรนด์ของฉัน': 'Promote my brand',
  'โปรโมตแบรนด์ของบุคคลอื่น': 'Promote another brand',
  'เนื้อหาที่มีผู้สนับสนุนตั้งเป็นเฉพาะฉันไม่ได้ เลือกผู้ชมอื่นก่อน':
      'Sponsored content cannot use Only me. Choose another audience first.',
  'วิดีโอนี้จะแสดงป้าย Paid partnership / มีผู้สนับสนุน':
      'This video will show a Paid partnership label.',
  'วิดีโอนี้จะแสดงป้ายเนื้อหาโปรโมต':
      'This video will show a promotional content label.',
  'เนื้อหา AI และสิทธิ์ใช้งาน': 'AI content and usage rights',
  'เปิดเผย AI เมื่อภาพหรือเสียงในวิดีโอสร้างด้วย AI การช่วยคิดแคปชั่นอย่างเดียวไม่รวมอยู่ในข้อนี้':
      'Disclose AI when images or audio in the video were created with AI. Using AI only to write a caption is not included.',
  'มีเนื้อหาที่สร้างโดย AI': 'Contains AI-generated content',
  'ฉันยืนยันสิทธิ์การใช้เพลงและยอมรับเงื่อนไขการใช้เพลงของ TikTok':
      'I confirm my music usage rights and accept TikTok’s Music Usage Confirmation.',
  'อ่านเงื่อนไขการใช้เพลง': 'Read Music Usage Confirmation',
  'ฉันยอมรับนโยบาย Branded Content ของ TikTok':
      'I accept TikTok’s Branded Content Policy.',
  'อ่านนโยบาย Branded Content': 'Read Branded Content Policy',
  'TikTok อาจใช้เวลาประมวลผลหลายนาที ผลเผยแพร่ขึ้นอยู่กับการมองเห็นที่เลือก':
      'TikTok may take several minutes to process the video. Publishing visibility depends on your selected audience.',
  'บัญชี TikTok นี้ไม่อนุญาต': 'This TikTok account does not allow this.',
  'เลือกผู้ที่สามารถดูวิดีโอ TikTok': 'Choose who can view this TikTok video.',
  'ตรวจสอบบัญชี TikTok และตัวเลือกการโพสต์อีกครั้ง':
      'Recheck the TikTok account and publishing options.',
  'ยืนยันข้อกำหนดการใช้เพลง TikTok':
      'Confirm TikTok’s Music Usage Confirmation.',
  'เนื้อหาที่มีผู้สนับสนุนไม่สามารถตั้งเป็นเฉพาะฉันได้':
      'Sponsored content cannot use Only me.',
  'ยืนยันนโยบายเนื้อหาที่มีผู้สนับสนุน TikTok':
      'Confirm TikTok’s Branded Content Policy.',
  'บัญชี TikTok ไม่รองรับผู้ชมที่เลือก กรุณาเลือกใหม่':
      'This TikTok account does not support your selected audience. Choose again.',
  'บัญชี TikTok ปิดการโต้ตอบที่เลือก กรุณาตรวจสอบใหม่':
      'This TikTok account has disabled a selected interaction. Review your choices.',
  'ตรวจสอบความยาววิดีโอให้ตรงกับข้อจำกัดบัญชี TikTok':
      'Check that the video duration meets this TikTok account’s limit.',
  'บัญชีหรือตัวเลือก TikTok เปลี่ยนแล้ว กรุณาเปิดการตั้งค่า TikTok และยืนยันใหม่':
      'The TikTok account or options have changed. Reopen TikTok settings and confirm again.',
  'เพิ่มชื่อวิดีโอ YouTube': 'Add a YouTube video title.',
  'ชื่อ YouTube ต้องไม่เกิน 100 ตัวอักษร และห้ามมี < หรือ >':
      'YouTube titles must be 100 characters or fewer and cannot contain < or >.',
  'ระบุว่าวิดีโอ YouTube ทำมาเพื่อเด็กหรือไม่':
      'Indicate whether this YouTube video is made for kids.',
  'ระบุว่าวิดีโอมีสื่อสังเคราะห์ที่ดูเหมือนจริงหรือไม่':
      'Indicate whether this video contains realistic synthetic media.',
  'ยืนยันกฎชุมชน YouTube ก่อนโพสต์':
      "Confirm YouTube's Community Guidelines before posting.",
  'ข้อมูลวิดีโอ': 'Video details',
  'ชื่อที่จะปรากฏบน YouTube Shorts': 'Title shown on YouTube Shorts',
  'เพิ่มแคปชันหรือชื่อคลิป YouTube': 'Add a caption or YouTube title',
  'แคปชันฉบับเต็มและแฮชแท็กจะใช้เป็นคำอธิบาย':
      'Your full caption and hashtags will be used as the description.',
  'ปรับชื่อเฉพาะ YouTube': 'Customize YouTube title',
  'ชื่อวิดีโอ YouTube': 'YouTube video title',
  'เว้นว่างเพื่อใช้ชื่อจากแคปชัน':
      'Leave blank to use a title from your caption.',
  'ใช้ชื่อจากแคปชัน': 'Use caption title',
  'การมองเห็น': 'Visibility',
  'ส่วนตัว (Private)': 'Private',
  'ไม่เป็นสาธารณะ (Unlisted)': 'Unlisted',
  'สาธารณะ (Public)': 'Public',
  'การมองเห็นจริงขึ้นอยู่กับสถานะวิดีโอและบัญชี YouTube กรุณาตรวจผลหลังเผยแพร่':
      'Actual visibility depends on your video and YouTube account status. Check the result after publishing.',
  'ผู้ชมและเนื้อหา': 'Audience and content',
  'วิดีโอนี้ทำมาเพื่อเด็กหรือไม่?': 'Is this video made for kids?',
  'พิจารณาว่าเด็กเป็นกลุ่มผู้ชมเป้าหมาย ไม่ใช่เพียงเด็กดูได้':
      'Consider whether children are the intended audience, not just whether they can watch it.',
  'มีสื่อสังเคราะห์ที่ดูเหมือนจริงหรือไม่?':
      'Does this video contain realistic synthetic media?',
  'หมายถึงภาพหรือเสียงที่สร้างหรือดัดแปลงให้ดูเหมือนจริง การช่วยคิดแคปชั่นอย่างเดียวไม่ถือเป็นสื่อสังเคราะห์ในวิดีโอ':
      'This means images or audio created or altered to look real. Using AI only to write a caption does not count as synthetic media in the video.',
  'ฉันยืนยันว่าวิดีโอเป็นไปตามกฎชุมชน YouTube':
      "I confirm that this video follows YouTube's Community Guidelines.",
  'การเผยแพร่ Reels': 'Reels publishing',
  'เผยแพร่ไปยังบัญชีที่แสดงด้านบน Instagram ไม่มี Private รายโพสต์ในช่องทางนี้':
      'Publish to the account shown above. Instagram does not offer per-post Private visibility through this channel.',
  'แชร์ Reels ไปยังฟีด': 'Share Reels to feed',
  'ปิดเพื่อแสดงเฉพาะใน Reels': 'Turn off to show only in Reels.',
  'วิธีเผยแพร่บนเพจ': 'Page publishing',
  'ส่งเป็น Facebook Reels ไปยังเพจที่แสดงด้านบน':
      'Send as Facebook Reels to the Page shown above.',
  'เผยแพร่บนเพจ': 'Publish to Page',
  'เก็บเป็นร่างบนเพจ': 'Save as Page draft',
  'ส่งออกจริงและใช้โควตาโพสต์ · เปิด Facebook เพื่อเผยแพร่ต่อ ต่างจากบันทึกร่างใน PostDee':
      'This sends the post and uses your post quota. Open Facebook to publish it. This is different from saving a draft in PostDee.',
  'ช่องทางนี้ยังไม่รองรับการโพสต์':
      'Posting is not supported for this channel yet.',
  'การเปิดเผยเนื้อหา AI': 'AI content disclosure',
  'หมายถึงภาพหรือเสียงในวิดีโอที่สร้างด้วย AI การใช้ AI ช่วยคิดแคปชั่นอย่างเดียวไม่รวมอยู่ในข้อนี้':
      'This means images or audio in the video created with AI. Using AI only to write a caption is not included.',
  'วิดีโอนี้มีภาพหรือเสียงที่สร้างด้วย AI หรือไม่?':
      'Does this video contain AI-generated images or audio?',
  'ยังไม่ระบุ (ไม่บังคับ)': 'Not specified (optional)',
  'ล้างคำตอบ': 'Clear answer',
  'ภาพปก': 'Cover',
  'เปลี่ยนภาพปกได้ในขั้นตอนคลิป': 'Change the cover in the video step.',
  'ยังไม่ได้เลือกปก · แพลตฟอร์มจะเลือกเฟรมจากวิดีโอ':
      'No cover selected · The platform will choose a video frame.',
  'ใช้ภาพปกที่เลือกไว้': 'Using your selected cover image',
  'ใช่': 'Yes',
  'ไม่ใช่': 'No',
  'เลือกเผยแพร่หรือเก็บเป็นร่างบนเพจก่อนบันทึก':
      'Choose Publish to Page or Save as Page draft before saving.',
};

class ChannelText extends StatelessWidget {
  const ChannelText(this.message,
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
      Text(localizeChannelMessage(context, message),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap);
}
