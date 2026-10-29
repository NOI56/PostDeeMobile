import 'package:flutter/widgets.dart';

import 'cover_editor_localizations.dart';
import 'publish_flow_localizations.dart';

/// Presentation-only submission messages; raw IDs and provider data stay intact.
String localizePublishSubmissionMessage(BuildContext context, String message) {
  if (publishFlowUsesThai(context)) return message;
  final fixed = _messages[message];
  if (fixed != null) return fixed;
  const watermarkFailure = 'ใส่ลายน้ำวิดีโอไม่สำเร็จ: ';
  if (message.startsWith(watermarkFailure) &&
      message.length > watermarkFailure.length) {
    return 'Could not apply the watermark. Try again.';
  }
  final receipt = _receipt(context, message);
  if (receipt != null) return receipt;
  final cover = localizeCoverEditorMessage(context, message);
  return cover != message
      ? cover
      : localizePublishFlowMessage(context, message);
}

String? _receipt(BuildContext context, String message) {
  var body = message;
  var prefix = '';
  const watermark = 'ใส่ลายน้ำแล้ว · ';
  const replay = 'พบรายการเดิม · ';
  if (body.startsWith(watermark)) {
    body = body.substring(watermark.length);
    prefix = 'Watermark applied · ';
  }
  if (body.startsWith(replay)) {
    body = body.substring(replay.length);
    prefix += 'Existing post found · ';
  }
  final match = _receiptPattern.firstMatch(body);
  if (match == null || match.start != 0 || match.end != body.length) {
    return null;
  }
  var postId = match[3]!;
  var warning = '';
  // The producer appends at most one of these exact terminal warnings. Do not
  // replace strings within the ID, which can itself contain Thai and colons.
  for (final entry in _cleanupWarnings.entries) {
    if (postId.endsWith(entry.key)) {
      postId = postId.substring(0, postId.length - entry.key.length);
      warning = entry.value;
      break;
    }
  }
  if (postId.isEmpty || _cleanupWarnings.keys.any(postId.endsWith)) return null;
  final count = match[2];
  final status = count != null
      ? 'Post received for $count ${count == '1' ? 'channel' : 'channels'}, delivery in progress'
      : localizePublishFlowMessage(
          context,
          match[1] == 'ส่งสำเร็จเพียงบางช่องทาง'
              ? 'ส่งสำเร็จบางช่องทาง'
              : match[1]!);
  return '$prefix$status: $postId$warning';
}

final _receiptPattern = RegExp(
    r'^(กำลังส่ง|ส่งสำเร็จ|ส่งสำเร็จเพียงบางช่องทาง|รับรายการ ([0-6]) ช่องทางแล้ว กำลังส่ง): ([\s\S]+)$');
const _cleanupWarnings = <String, String>{
  ' · ลบร่างแล้ว แต่รีเฟรชรายการร่างไม่สำเร็จ':
      ' · Draft deleted, but the draft list could not be refreshed.',
  ' · โพสต์เข้าคิวแล้ว แต่ลบร่างในเครื่องไม่สำเร็จ':
      ' · The post was queued, but the draft on this device could not be deleted.',
};
const _unavailableTitle = 'ระบบรับงานโพสต์ยังไม่เปิดใช้งานในขณะนี้';
const _unavailableBefore = 'วิดีโอยังไม่ได้อัปโหลด กรุณาลองใหม่ภายหลัง';
const _unavailableAfter =
    'ยังไม่ได้สร้างโพสต์ และไฟล์วิดีโออาจถูกอัปโหลดไว้ชั่วคราว กรุณาลองใหม่ภายหลัง';
const _unavailableTitleEnglish = 'Publishing is currently unavailable';
const _unavailableBeforeEnglish =
    'The video has not been uploaded. Try again later.';
const _unavailableAfterEnglish =
    'No post was created. The video may have been uploaded temporarily. Try again later.';
const _messages = <String, String>{
  _unavailableTitle: _unavailableTitleEnglish,
  _unavailableBefore: _unavailableBeforeEnglish,
  _unavailableAfter: _unavailableAfterEnglish,
  '$_unavailableTitle $_unavailableBefore':
      '$_unavailableTitleEnglish $_unavailableBeforeEnglish',
  '$_unavailableTitle $_unavailableAfter':
      '$_unavailableTitleEnglish $_unavailableAfterEnglish',
  'ระบบรับงานโพสต์ยังไม่เปิดใช้งาน กรุณาลองใหม่ภายหลัง':
      'Publishing is temporarily unavailable. Please try again later.',
  'อัปโหลด/คิวโพสต์ขัดข้อง': 'Upload or publishing queue issue',
  'รับทราบ': 'OK',
  'สัดส่วนวิดีโอไม่ใช่ 9:16': 'Video is not 9:16',
  'ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920':
      'Use a vertical 9:16 video, such as 1080x1920.',
  'เลือกวิดีโอใหม่': 'Choose another video',
  'ปิด': 'Close',
  'เลือกวิดีโอจริงจากเครื่องก่อนโพสต์': 'Choose a local video before posting.',
  'ไม่พบไฟล์วิดีโอในเครื่อง': 'The video file was not found on this device.',
  'ไฟล์วิดีโอไม่ถูกต้อง เลือกคลิปใหม่อีกครั้ง':
      'The video file is invalid. Choose another video.',
  'เวลาตั้งโพสต์ต้องเป็นรูปแบบ ISO ที่ถูกต้อง':
      'The scheduled time must use a valid ISO format.',
  'เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต': 'The posting time must be in the future.',
  'ร่างนี้มีไฟล์อัปโหลดเดิมที่ยังไม่มีข้อมูลตรวจคลิป เก็บร่างไว้แล้ว กรุณาตรวจรายการโพสต์ก่อนเริ่มรายการใหม่':
      'This draft has an earlier upload without video check information. The draft has been kept. Check your post list before starting a new request.',
  'กำลังใส่ลายน้ำวิดีโอ...': 'Applying watermark...',
  'กำลังเตรียมวิดีโอ TikTok เป็น 30 FPS...':
      'Preparing TikTok video at 30 FPS...',
  'วิดีโอ TikTok ยังไม่ผ่านการตรวจ จึงหยุดก่อนอัปโหลด':
      'The TikTok video has not passed the checks. Upload was stopped.',
  'อ่านรายละเอียดคลิปไม่สำเร็จ ยังไม่ได้อัปโหลด กรุณาลองใหม่หรือเลือกคลิปอีกครั้ง':
      'Could not read the video details. Nothing was uploaded. Try again or choose the video again.',
  'ลิงก์อัปโหลดหมดอายุ กำลังลองใหม่...': 'The upload link expired. Retrying...',
  'กำลังอัปโหลดหน้าปก...': 'Uploading cover...',
  'บันทึกข้อมูลอัปโหลดไม่สำเร็จ กรุณาลองใหม่':
      'Could not save the upload information. Try again.',
  'รายการเดิมส่งไม่สำเร็จ เปิดรายละเอียดเพื่อตรวจสิ่งที่ต้องแก้ ร่างและข้อมูลอัปโหลดยังอยู่':
      'The original post was not sent. Open its details to see what needs fixing. The draft and upload information are still available.',
  'ระบบตอบสถานะโพสต์ที่ยังยืนยันไม่ได้ กรุณาตรวจรายการโพสต์ก่อนลองใหม่':
      'The returned post status is not confirmed. Check your post list before retrying.',
  'รายการโพสต์เดิมจบด้วยสถานะล้มเหลว ร่างยังอยู่ในเครื่อง กรุณาตรวจปลายทางก่อนเริ่มรายการโพสต์ใหม่':
      'The original post ended in failure. The draft is still on this device. Check the destinations before starting a new post request.',
  'ข้อมูลในร่างเปลี่ยนจากคำขอเดิม ร่างยังอยู่ในเครื่อง กรุณาตรวจปลายทางก่อนเริ่มรายการโพสต์ใหม่':
      'The draft has changed from the original request. The draft is still on this device. Check the destinations before starting a new post request.',
  'เชื่อมต่อ PostDee API ไม่ได้': 'Could not connect to PostDee.',
  'เกิดข้อผิดพลาดระหว่างสร้างโพสต์':
      'An error occurred while creating the post.',
  'ล้างไฟล์วิดีโอชั่วคราวไม่สำเร็จ กรุณาตรวจพื้นที่ว่างในเครื่อง':
      'Could not remove temporary video files. Check the free space on this device.',
  'ยังไม่ได้เลือกหน้าปก': 'No cover selected',
  'ยกเลิกการสร้างหน้าปกแล้ว': 'Cover creation was canceled.',
  'หยุดเตรียมวิดีโอ เพราะบัญชีหรือร่างเปลี่ยนแล้ว':
      'Video preparation stopped because the account or draft changed.',
  'หยุดเตรียมวิดีโอแล้ว': 'Video preparation stopped.',
  'อุปกรณ์นี้ยังเตรียมวิดีโอสำหรับ TikTok ไม่ได้ กรุณาใช้ไฟล์ H.264 30 FPS บนอุปกรณ์ที่รองรับ':
      'This device cannot prepare videos for TikTok. Use an H.264 30 FPS file on a supported device.',
  'ตรวจวิดีโอต้นฉบับไม่ได้ กรุณาเลือกไฟล์วิดีโอใหม่':
      'Could not check the original video. Choose another video file.',
  'วิดีโอยาวเกินระยะเวลาที่บัญชี TikTok นี้อนุญาต กรุณาเลือกคลิปที่สั้นลง':
      'This video exceeds the duration allowed by this TikTok account. Choose a shorter video.',
  'วิดีโอมีสัดส่วนกว้างหรือสูงเกินไป จึงปรับขนาดให้ TikTok รับไม่ได้ กรุณาเลือกวิดีโอใหม่':
      'This video is too wide or tall to resize for TikTok. Choose another video.',
  'เตรียมวิดีโอสำหรับ TikTok ไม่สำเร็จ ยังไม่ได้อัปโหลด กรุณาลองใหม่บนอุปกรณ์ที่รองรับ':
      'Could not prepare the video for TikTok. Nothing was uploaded. Try again on a supported device.',
  'วิดีโอที่แปลงยังไม่ผ่านการตรวจภาพ เสียง หรือ 30 FPS จึงหยุดก่อนอัปโหลด กรุณาเลือกวิดีโอใหม่หรือลองบนอุปกรณ์ที่รองรับ':
      'The converted video did not pass video, audio, or 30 FPS checks. Upload was stopped. Choose another video or try a supported device.',
  'เตรียมวิดีโอสำหรับ TikTok ไม่สำเร็จ ยังไม่ได้อัปโหลด กรุณาลองใหม่':
      'Could not prepare the video for TikTok. Nothing was uploaded. Try again.',
  'ไม่พบไฟล์วิดีโอสำหรับใส่ลายน้ำ':
      'The video file for watermarking was not found.',
  'ใส่ลายน้ำแล้วแต่ไม่พบไฟล์ผลลัพธ์':
      'The watermark was applied, but the output file was not found.',
};
