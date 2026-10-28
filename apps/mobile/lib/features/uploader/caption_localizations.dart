import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';

bool captionUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String captionText(BuildContext context, String thai, String english) =>
    captionUsesThai(context) ? thai : english;

/// Only app-owned labels and messages belong here. Captions, templates, SEO,
/// instructions, examples and unknown provider messages must stay raw.
String localizeCaptionMessage(BuildContext context, String message) {
  if (captionUsesThai(context)) return message;
  final known = _englishMessages[message];
  if (known != null) return known;

  final characters = _whole(RegExp(r'^(\d+) ตัวอักษร$'), message);
  if (characters != null) {
    return '${characters[1]} ${characters[1] == '1' ? 'character' : 'characters'}';
  }
  final youtubeCount =
      _whole(RegExp(r'^(\d+) / 5,000 ไบต์ · ชื่อคลิปตั้งในช่องทาง$'), message);
  if (youtubeCount != null) {
    return '${youtubeCount[1]} / 5,000 bytes · Set the video title in Channels';
  }
  final field =
      _whole(RegExp(r'^แคปชั่น (TikTok|YouTube|Instagram|Facebook)$'), message);
  if (field != null) return '${field[1]} caption';
  final required = _whole(
      RegExp(
          r'^เพิ่มแคปชั่น (TikTok|YouTube Shorts|Instagram Reels|Facebook Reels) ก่อนโพสต์$'),
      message);
  if (required != null) return 'Add a ${required[1]} caption before posting.';
  final examples = _whole(RegExp(r'^ตัวอย่างที่จำไว้ (\d+)/3$'), message);
  if (examples != null) return 'Remembered examples ${examples[1]}/3';
  final cost = _whole(RegExp(r'^สร้างแคปชั่น · ([1-4]) เครดิต$'), message);
  if (cost != null) {
    return 'Generate captions · ${cost[1]} ${cost[1] == '1' ? 'credit' : 'credits'}';
  }
  final insufficient = _whole(
      RegExp(
          r'^เครดิตไม่พอ ต้องใช้ ([1-4]) เครดิต ลดช่องทางหรือเติมเครดิตแล้วลองใหม่$'),
      message);
  if (insufficient != null) {
    return 'Not enough credits. ${insufficient[1]} ${insufficient[1] == '1' ? 'credit' : 'credits'} required. Choose fewer channels or add credits and try again.';
  }

  for (final entry in _captionLimits.entries) {
    final count = _whole(
        RegExp(
            '^${entry.key}: ((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)) / ${entry.value.$1} ${entry.value.$2}\$'),
        message);
    if (count != null) {
      return '${entry.key}: ${count[1]} / ${entry.value.$1} ${entry.value.$3}';
    }
  }
  final preview = _whole(
      RegExp(r'^(ตรวจข้อความสำรอง|แคปชั่นจาก AI) ([0-4]) ช่องทาง$'), message);
  if (preview != null) {
    final count = preview[2];
    final channels = '$count ${count == '1' ? 'channel' : 'channels'}';
    return '${preview[1] == 'ตรวจข้อความสำรอง' ? 'Review fallback captions for' : 'AI captions for'} $channels';
  }
  final apply = _whole(RegExp(r'^ใช้(ทั้ง 4| ([0-4])) แคปชั่น$'), message);
  if (apply != null) {
    final count = apply[2];
    return count == null
        ? 'Use all 4 captions'
        : 'Use $count ${count == '1' ? 'caption' : 'captions'}';
  }

  const noCharge = ' · ไม่หักโควตา AI';
  final uncharged = message.endsWith(noCharge);
  final fallbackBase = uncharged
      ? message.substring(0, message.length - noCharge.length)
      : message;
  final fallback = _fallbackMessages[fallbackBase];
  final review = _whole(
      RegExp(
          r'^AI วิเคราะห์คลิปไม่สำเร็จ กรุณาตรวจข้อความ ([0-4]) ช่องทางก่อนใช้$'),
      fallbackBase);
  if (fallback != null || review != null) {
    final text = fallback ??
        'AI could not analyze the video. Review the text for ${review![1]} ${review[1] == '1' ? 'channel' : 'channels'} before use.';
    return '$text${uncharged ? ' · No AI quota charged' : ''}';
  }
  return message;
}

RegExpMatch? _whole(RegExp pattern, String message) {
  final match = pattern.firstMatch(message);
  return match != null && match.start == 0 && match.end == message.length
      ? match
      : null;
}

const _captionLimits = <String, (String, String, String)>{
  'TikTok': ('2,200', 'ตัวอักษร', 'characters'),
  'Instagram': ('2,200', 'ตัวอักษร', 'characters'),
  'Facebook': ('63,206', 'ตัวอักษร', 'characters'),
  'YouTube': ('5,000', 'ไบต์', 'bytes'),
};

const _fallbackMessages = <String, String>{
  'AI วิเคราะห์คลิปไม่สำเร็จ กรุณาตรวจข้อความสำรองก่อนใช้':
      'AI could not analyze the video. Review the fallback text before using it.',
  'AI วิเคราะห์คลิปไม่สำเร็จ แคปชันนี้เป็นข้อความสำรอง กรุณาตรวจและแก้ไขก่อนใช้':
      'AI could not analyze the video. This is fallback text. Review and edit it before use.',
};

const _englishMessages = <String, String>{
  'เขียนเอง หรือกดให้ AI ช่วยเมื่อพร้อม':
      'Write your own caption, or let AI help when you are ready.',
  'ตั้งค่าขั้นสูง': 'Advanced settings',
  'เขียนเอง หรือเลือกช่องทางที่ต้องการให้ AI เขียน':
      'Write your own captions, or choose channels for AI to write for',
  'เขียนแคปชั่นแยกแต่ละช่องทาง': 'Write separate captions for each channel',
  'คืนข้อความก่อนใช้ AI': 'Restore text from before AI',
  'แคปชั่น': 'Caption',
  'ดูคลิป': 'Watch video',
  'เล่าเรื่องคลิปหรือสิ่งที่อยากบอกลูกค้า...':
      'Tell the story of your video or what you want customers to know...',
  'เพิ่มแคปชันก่อนไปต่อ': 'Add a caption before continuing.',
  'เพิ่มแคปชั่นก่อนโพสต์': 'Add a caption before posting.',
  'เพิ่มแคปชันหรือชื่อคลิป YouTube ก่อนโพสต์':
      'Add a caption or YouTube video title before posting.',
  'แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร':
      'The TikTok caption must be no longer than 2,200 characters.',
  'แคปชั่น Instagram ต้องไม่เกิน 2,200 ตัวอักษร':
      'The Instagram caption must be no longer than 2,200 characters.',
  'แคปชั่น Facebook ต้องไม่เกิน 63,206 ตัวอักษร':
      'The Facebook caption must be no longer than 63,206 characters.',
  'คำอธิบาย YouTube ต้องไม่เกิน 5,000 ไบต์ กรุณาย่อแคปชั่นก่อนโพสต์':
      'The YouTube description must be no longer than 5,000 bytes. Shorten the caption before posting.',
  'YouTube นับความยาวเป็นไบต์ ภาษาไทยอาจใช้หลายไบต์ต่ออักษร':
      'YouTube counts length in bytes. Thai text can use multiple bytes per character.',
  'กรุณาตรวจว่าแคปชั่นตรงกับคลิปที่เลือกก่อนใช้':
      'Check that the caption matches your selected video before using it.',
  'ตรวจแล้ว': 'Reviewed',
  'คำค้นที่ AI แนะนำ': 'AI-suggested keywords',
  'เทมเพลตแคปชัน': 'Caption templates',
  'เทมเพลต': 'Templates',
  'กำลังโหลดเทมเพลต...': 'Loading templates...',
  'โหลดเทมเพลต': 'Load templates',
  'ใส่แคปชั่น': 'Insert caption',
  'คำอธิบาย YouTube': 'YouTube description',
  'แคปชั่น Reels': 'Instagram caption',
  'เขียนแคปชั่นสำหรับช่องทางนี้...': 'Write a caption for this channel...',
  'กลับไปเขียนเอง': 'Back to writing',
  'ตรวจข้อความสำรองทั้ง 4 ช่องทาง':
      'Review fallback captions for all 4 channels',
  'แคปชั่นจาก AI ทั้ง 4 ช่องทาง': 'AI captions for all 4 channels',
  'เลือกใช้แล้วแก้ต่อได้ ข้อความเดิมจะยังอยู่จนกดใช้':
      'You can edit after using these captions. Your original text stays until you tap Use.',
  'แคปชั่น AI คงเหลือ': 'AI caption credits remaining',
  'AI แคปชั่นใช้ได้ใน Starter หรือ Pro':
      'AI captions are available on Starter or Pro',
  'สไตล์การเขียน': 'Writing style',
  'สไตล์': 'Style',
  'น้ำเสียง': 'Tone',
  'ความยาว': 'Length',
  'อัตโนมัติ': 'Auto',
  'เป็นกันเอง': 'Friendly',
  'สนุก/ตลก': 'Fun / playful',
  'รีวิวตรง ๆ': 'Direct review',
  'ขายแบบนุ่มนวล': 'Soft sell',
  'สั้น กระชับ': 'Short and concise',
  'เล่าเพิ่มอีกนิด': 'A little more detail',
  'ไม่ใช้อีโมจิ': 'No emoji',
  'ใช้เล็กน้อย': 'Light emoji',
  'คำแนะนำเพิ่มเติม (ถ้ามี)': 'Additional instructions (optional)',
  'เช่น ขอข้อความสั้น / เน้นลูกค้าใหม่':
      'e.g. Keep it short / Focus on new customers',
  'เช่น ขอขายจริงใจ / อยากได้แนวตลก / เน้นลูกค้าแม่และเด็ก':
      'e.g. Use an honest sales tone / Make it playful / Focus on parents and children',
  'เช่น ชื่อสินค้า ราคา จุดเด่น หรือเรื่องที่อยากให้พูดถึง':
      'e.g. Product name, price, highlights, or topics to mention',
  'จำสไตล์จากข้อความที่ฉันแก้': 'Remember my writing edits',
  'จำเมื่อแก้แคปชัน AI แล้วกดถัดไป เก็บในเครื่องนี้เฉพาะบัญชีของคุณ':
      'Remembered when you edit an AI caption and tap Next. Saved on this device for your account only.',
  'ลบข้อความตัวอย่างที่จำไว้': 'Clear remembered examples',
  'กำลังบันทึก...': 'Saving...',
  'บันทึกสไตล์': 'Save style',
  'กำลังบันทึกสไตล์...': 'Saving style...',
  'ยกเลิก': 'Cancel',
  'จำรูปแบบข้อความไม่สำเร็จ กรุณาลองใหม่ภายหลัง':
      'Could not remember your writing style. Please try again later.',
  'บันทึกสไตล์ไม่สำเร็จ กรุณาลองใหม่':
      'Could not save your style. Please try again.',
  'ให้ AI ช่วยเขียน': 'Let AI write',
  'เลือกช่องทางที่ต้องการ': 'Choose channels',
  'AI แคปชั่นจากคลิปจริง': 'AI captions from your video',
  'เลือกคลิปก่อน แล้วให้ AI ฟังเสียงจริงในคลิปเพื่อทำ Hook, SEO และแฮชแท็ก':
      'Choose a video first. AI will use its audio to create a hook, SEO keywords and hashtags.',
  'กำลังโหลดโควตา...': 'Loading AI caption quota...',
  'โหลดโควตาไม่สำเร็จ': 'Could not load AI caption quota.',
  'โหลดโควตาอีกครั้ง': 'Reload AI caption quota',
  'เครดิตไม่พอ ลดช่องทางหรือเติมเครดิต':
      'Not enough credits. Choose fewer channels or add credits.',
  'เครดิตไม่พอ เติมเครดิตเพื่อให้ AI ช่วยเขียน':
      'Not enough credits. Add credits to let AI write.',
  'กำลังเตรียมแคปชัน...': 'Preparing captions...',
  'เลือกช่องทางให้ AI เขียน': 'Choose channels for AI',
  'เครดิต AI หมดแล้ว': 'No AI credits remaining',
  'กำลังเตรียมแคปชันจากคลิปที่เลือก':
      'Preparing captions from the selected video',
  'แคปชันพร้อมแล้ว ตรวจข้อความก่อนใช้':
      'Caption ready. Review the text before using it.',
  'ปรับสไตล์และคำแนะนำ': 'Customize style and instructions',
  'เลือกช่องทางให้ AI เขียนก่อน': 'Choose channels for AI to write for first.',
  'เลือกคลิปก่อน แล้ว AI จะคิดแคปชั่นจากเสียงในคลิปนั้น':
      'Choose a video first. AI will write a caption from its audio.',
  'ตรวจสอบสิทธิ์แพ็กเกจไม่สำเร็จ กรุณาลองใหม่':
      'Could not check your plan access. Please try again.',
  'AI แคปชั่นใช้ได้ในแพ็กเกจ Starter หรือ Pro กรุณาตรวจสอบแพ็กเกจของคุณ':
      'AI captions are available on Starter or Pro. Please check your plan.',
  'คุณแก้ข้อความระหว่างที่ AI ทำงาน จึงเก็บข้อความที่คุณเขียนไว้':
      'You edited the text while AI was working. Your writing has been kept.',
  'ระบบ AI ยังส่งแคปชั่นไม่ครบช่องทางที่เลือก กรุณาลองใหม่ภายหลัง':
      'AI did not return captions for all selected channels. Please try again later.',
  'ใช้โควตา AI แคปชั่นของเดือนนี้ครบแล้ว สมาชิก Starter หรือ Pro ดูแพ็กเติมได้ในหน้าเลือกแพ็กเกจ หรือรอรอบเดือนถัดไป':
      'Your AI caption quota for this month has been used. Starter or Pro members can view add-ons on the Plans page or wait for the next monthly period.',
  'กรุณาอัปเดตแอปหรือตรวจสอบช่องทางที่เลือก แล้วลองสร้างแคปชั่นใหม่':
      'Update the app or check your selected channels, then try generating captions again.',
  'อัปโหลดคลิปให้ AI ไม่สำเร็จ กรุณาเลือกไฟล์ MP4 ที่มีขนาดไม่เกินกำหนด':
      'Could not upload the video for AI. Choose an MP4 file within the size limit.',
  'ให้ AI คิดแคปชั่นไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
      'AI could not write a caption. Please try again.',
  'เกิดข้อผิดพลาดระหว่างให้ AI คิดแคปชั่น':
      'An error occurred while AI was writing a caption.',
  'เลือกคลิปจริงจากเครื่องก่อนให้ AI คิดแคปชั่น':
      'Choose a local video before asking AI to write a caption.',
  'ไม่พบไฟล์วิดีโอในเครื่อง': 'The video file was not found on this device.',
  'ไฟล์วิดีโอที่เลือกมีข้อมูลไม่ครบ':
      'The selected video file is missing required information.',
  'คลิปยาวเกินไปสำหรับ AI แคปชั่น ลองตัดให้สั้นลงแล้วลองใหม่':
      'This video is too long for AI captions. Try a shorter video.',
  'ลิงก์อัปโหลดหมดอายุ กำลังลองใหม่...': 'The upload link expired. Retrying...',
  'เชื่อมต่อ PostDee API ไม่ได้': 'Could not connect to PostDee.',
  'เกิดข้อผิดพลาดระหว่างโหลดเทมเพลต':
      'An error occurred while loading templates.',
};

class CaptionText extends StatelessWidget {
  const CaptionText(this.message,
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
      Text(localizeCaptionMessage(context, message),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap);
}
