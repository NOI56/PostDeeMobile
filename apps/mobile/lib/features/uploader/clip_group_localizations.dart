import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/api_error_message.dart';
import '../../core/network/postdee_api_client.dart';
import '../platforms/social_platform.dart';
import 'clip_group_draft.dart';
import 'clip_group_draft_store.dart';
import 'clip_group_submission.dart';
import 'clip_split_localizations.dart';
import 'publish_draft.dart';
import 'uploader_localizations.dart';

String clipGroupText(BuildContext context, String thai, String english) =>
    uploaderText(context, thai, english);

String clipGroupPartLabel(
    BuildContext context, ClipGroupDraft group, ClipGroupItem item,
    {String? platformApiValue}) {
  final labels = <String, String>{};
  for (final platform in platformApiValue == null
      ? item.platformApiValues
      : [platformApiValue]) {
    final parts = group.items
        .where((part) => part.platformApiValues.contains(platform))
        .toList()
      ..sort((a, b) {
        final start = a.sourceStartSeconds.compareTo(b.sourceStartSeconds);
        return start != 0
            ? start
            : a.sourceEndSeconds.compareTo(b.sourceEndSeconds);
      });
    final index = parts.indexWhere((part) => part.draftId == item.draftId);
    labels[platform] = parts.length <= 1
        ? clipGroupText(context, 'คลิปเต็ม', 'Full clip')
        : clipGroupText(context, 'ตอน ${index + 1}/${parts.length}',
            'Part ${index + 1}/${parts.length}');
  }
  if (labels.values.toSet().length == 1) return labels.values.first;
  return labels.entries.map((entry) {
    final platform = SocialPlatform.values
        .where((platform) => platform.apiValue == entry.key)
        .firstOrNull;
    return '${platform?.label ?? entry.key} · ${entry.value}';
  }).join(' · ');
}

String clipGroupConsentLabel(BuildContext context, ClipGroupDraft group,
        ClipGroupItem item, String platformApiValue) =>
    '${clipGroupPartLabel(context, group, item, platformApiValue: platformApiValue)} · '
    '${formatClipSplitTime(item.sourceStartSeconds)}–${formatClipSplitTime(item.sourceEndSeconds)}';

String clipGroupReceiptStatusText(BuildContext context, ClipGroupItem item) =>
    switch (item.acceptedPostStatus?.toUpperCase()) {
      'QUEUED' => clipGroupText(context, 'เข้าคิวแล้ว', 'Queued'),
      'PUBLISHING' =>
        clipGroupText(context, 'กำลังส่ง', 'Delivery in progress'),
      'PUBLISHED' =>
        clipGroupText(context, 'ส่งงานสำเร็จแล้ว', 'Delivery completed'),
      'PARTIAL_PUBLISHED' =>
        clipGroupText(context, 'ส่งสำเร็จบางช่องทาง', 'Partially delivered'),
      'FAILED' => clipGroupText(context, 'ส่งไม่สำเร็จ', 'Delivery failed'),
      _ => clipGroupText(
          context, 'รับรายการแล้ว · รอตรวจผล', 'Accepted · Check delivery'),
    };

String clipGroupActivityText(
        BuildContext context, ClipGroupSubmissionProgress progress) =>
    switch (progress.activity) {
      ClipGroupSubmissionActivity.confirmingSettings =>
        clipGroupText(context, 'กำลังยืนยันการตั้งค่า', 'Confirming settings'),
      ClipGroupSubmissionActivity.recovering => clipGroupText(
          context, 'กำลังตรวจรายการเดิม', 'Checking the existing request'),
      ClipGroupSubmissionActivity.preparingMedia =>
        clipGroupText(context, 'กำลังเตรียมคลิป', 'Preparing video'),
      ClipGroupSubmissionActivity.uploadingVideo =>
        clipGroupText(context, 'กำลังอัปโหลดคลิป', 'Uploading video'),
      ClipGroupSubmissionActivity.uploadingCover =>
        clipGroupText(context, 'กำลังอัปโหลดหน้าปก', 'Uploading cover'),
      ClipGroupSubmissionActivity.creatingPost => clipGroupText(
          context, 'กำลังสร้างคิวโพสต์', 'Creating the post request'),
      ClipGroupSubmissionActivity.finalizing => clipGroupText(
          context, 'กำลังยืนยันผลรับรายการ', 'Saving the accepted result'),
      _ => progress.stage == ClipGroupSubmissionStage.accepted
          ? clipGroupText(context, 'รับรายการแล้ว', 'Request accepted')
          : clipGroupText(context, 'กำลังตรวจความพร้อม', 'Checking readiness'),
    };

/// Only recognized app-owned reasons are displayed. Unknown errors never expose
/// exception names, provider responses, or untranslated technical details.
String clipGroupErrorText(BuildContext context, Object? error) {
  final fallback = clipGroupText(
      context,
      'ดำเนินการกับชุดคลิปไม่สำเร็จ กรุณาตรวจรายการเดิมแล้วลองอีกครั้ง',
      'Could not complete this set. Check existing submissions before retrying.');
  if (error == null) return fallback;
  if (error is AuthSessionChangedException) {
    return clipGroupText(
        context,
        'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดชุดคลิปใหม่',
        'Your account changed. Reopen this set.');
  }
  if (error is ClipGroupSubmissionException) {
    final (thai, english) = switch (error.problem) {
      ClipGroupSubmissionProblem.cancelled => (
          'หยุดส่งแล้ว รายการที่รับแล้วจะไม่ถูกส่งซ้ำ',
          'Submission stopped. Accepted items will not be sent again.'
        ),
      ClipGroupSubmissionProblem.alreadyRunning => (
          'ชุดนี้กำลังส่งอยู่ กรุณารอสักครู่ก่อนลองใหม่',
          'This set is already submitting. Wait before retrying.'
        ),
      ClipGroupSubmissionProblem.groupChanged => (
          'ชุดคลิปเปลี่ยนแล้ว กรุณาเปิดชุดคลิปอีกครั้ง',
          'This set changed. Reopen it before submitting.'
        ),
      ClipGroupSubmissionProblem.missingDraft => (
          'ไม่พบคลิปร่างบางรายการ กรุณาตรวจฉบับร่างก่อนส่ง',
          'Some member drafts are missing. Check Drafts before submitting.'
        ),
      ClipGroupSubmissionProblem.draftChanged => (
          'คลิปบางรายการเปลี่ยนแล้ว กรุณาตรวจชุดคลิปอีกครั้ง',
          'Some clips changed. Review the set again.'
        ),
      ClipGroupSubmissionProblem.invalidMember => (
          'ข้อมูลคลิปบางรายการไม่ตรงกับชุด กรุณาเปิดชุดคลิปใหม่',
          'Some clip details do not match the set. Reopen it.'
        ),
      ClipGroupSubmissionProblem.unconfirmed => (
          'กรุณาตรวจแคปชั่น การตั้งค่า และเวลาส่งแต่ละคลิปก่อนยืนยันอีกครั้ง',
          'Review each clip’s caption, settings, and posting time before confirming again.'
        ),
      ClipGroupSubmissionProblem.checkpointFailed => (
          'ยังบันทึกผลรับรายการไม่ได้ กรุณาตรวจรายการเดิมก่อนลองใหม่',
          'The accepted result could not be saved. Check existing submissions before retrying.'
        ),
    };
    return clipGroupText(context, thai, english);
  }
  final message = switch (error) {
    ClipGroupDraftException() => error.message,
    PublishDraftValidationException() => error.message,
    ApiException() => error.message,
    _ => null,
  };
  String? recognized;
  if (message != null) {
    final english = _clipGroupErrors[message];
    if (english != null) {
      recognized = clipGroupText(context, message, english);
    } else {
      final localized = localizeUploaderMessage(context, message);
      if (!uploaderUsesThai(context) &&
          localized != message &&
          !RegExp(r'[\u0E00-\u0E7F]').hasMatch(localized) &&
          !localized.contains('Exception') &&
          !localized.contains('<')) {
        recognized = localized;
      } else if (uploaderUsesThai(context) &&
          (_existingValidationMessages.contains(message) ||
              _knownValidationPattern.hasMatch(message))) {
        recognized = message;
      }
    }
  }
  return apiErrorMessage(error,
      languageCode: uploaderUsesThai(context) ? 'th' : 'en',
      fallbackMessage: recognized ?? fallback);
}

final _knownValidationPattern = RegExp(
    r'^(?:ตั้งเวลาโพสต์ล่วงหน้าได้สูงสุด (?:14|30) วัน กรุณาเลือกเวลาใหม่|บัญชี (?:TikTok|YouTube Shorts|Instagram Reels|Facebook Page Reels) เปลี่ยนแล้ว กรุณารีเฟรชช่องทางและตรวจทานใหม่|TikTok ต้องใช้คลิปยาวไม่เกิน (?:(?:\d+) นาที(?: \d+ วินาที)?|\d+ วินาที))(?: จึงโพสต์ช่องทางนี้ไม่ได้| กรุณายกเลิกช่องทางนี้หรือเลือกคลิปใหม่| กรุณาตรวจรายการเดิมก่อนเริ่มรายการโพสต์ใหม่)?$');

const _clipGroupErrors = <String, String>{
  'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดชุดคลิปใหม่':
      'Your account changed. Reopen this set.',
  'เปิดพื้นที่เก็บชุดคลิปไม่ได้':
      'Could not open draft storage. Please try again.',
  'ไม่พบข้อมูลชุดคลิป กรุณาตรวจรายการฉบับร่าง':
      'This set could not be found. Check Drafts.',
  'เปิดชุดคลิปนี้ไม่ได้': 'Could not open this set. Check Drafts and retry.',
  'คลิปนี้เคยเริ่มส่งแล้ว กรุณาตรวจรายการเดิมก่อนแก้ไข':
      'This clip already started submitting. Check its existing request before editing.',
  'ร่างนี้เคยเริ่มส่งแล้ว กรุณาตรวจผลรายการเดิมก่อนแก้ไข':
      'This draft already started submitting. Check its existing request before editing.',
  'รายการคลิปเปลี่ยนแล้ว': 'The clip list changed. Reopen this set.',
  'บันทึกหน้าปกไม่สำเร็จ': 'Could not save the cover. Please try again.',
  'ชุดคลิปเปลี่ยนแล้ว กรุณาเปิดชุดคลิปอีกครั้ง':
      'This set changed. Reopen it before submitting.',
  'ไม่พบคลิปบางรายการ ร่างที่เหลือยังอยู่ กรุณาตรวจชุดคลิป':
      'Some clips are missing. The remaining drafts are safe. Review the set.',
  'บัญชีปลายทางเปลี่ยนแล้ว กรุณาตรวจช่องทางของชุดคลิปใหม่':
      'A destination account changed. Review the channels for this set again.',
  'ไม่พบไฟล์คลิปบางรายการ กรุณาตรวจชุดคลิปก่อนส่ง':
      'Some local clip files are missing. Check the set before submitting.',
  'ไม่พบคลิปบางรายการในชุด':
      'Some clips are missing from this set. Check Drafts.',
  'ยืนยันเบอร์โทรก่อนส่งชุดคลิป':
      'Verify your phone number before submitting this set.',
  'ข้อมูลรายการเดิมไม่ตรงกับคลิป กรุณาตรวจผลก่อนลองใหม่':
      'The existing request does not match this clip. Check its result before retrying.',
  'พบรายการเดิมที่ยังส่งไม่สำเร็จ กรุณาตรวจรายละเอียดโพสต์':
      'An existing request has not completed. Check the post details.',
  'ยังไม่พบรายการเดิม และเวลาส่งผ่านไปแล้ว กรุณาตรวจผลอีกครั้ง':
      'The existing request was not found and the posting time has passed. Check its result again.',
  'ข้อมูลการตรวจคลิปเปลี่ยนแล้ว กรุณาตรวจชุดคลิปอีกครั้ง':
      'The reviewed clip details changed. Review the set again.',
  'คลิปหรือเวลาส่งเปลี่ยนแล้ว กรุณาตรวจชุดคลิปอีกครั้ง':
      'A clip or its posting time changed. Review the set again.',
  'ส่งคลิปนี้ไม่สำเร็จ รายการที่เหลือยังอยู่ในชุด':
      'This clip did not finish submitting. The remaining items are still in the set.',
  'ไม่พบไฟล์วิดีโอของคลิปนี้ในเครื่อง':
      'This clip’s local video file is missing. Check Drafts.',
  'บางช่องทางในชุดคลิปยังไม่พร้อม กรุณาตรวจการเชื่อมต่อ':
      'Some channels are not ready. Check their connections.',
  'ยังไม่ได้ยืนยันการตั้งค่าบางคลิป ชุดคลิปยังอยู่ในฉบับร่าง':
      'Some clip settings have not been confirmed. This set is still in Drafts.',
  'บันทึกการตรวจคลิปไม่สำเร็จ':
      'Could not save the reviewed clip. Please try again.',
  'ตรวจโควตาไม่สำเร็จ กรุณาลองใหม่':
      'Could not verify post units. Please try again.',
  'หน่วยโพสต์ไม่พอสำหรับรายการที่เหลือ':
      'Not enough post units for the remaining items.',
  'ข้อมูลโพสต์ที่ตอบกลับไม่ตรงกับคลิป กรุณาตรวจรายการเดิม':
      'The returned post does not match this clip. Check the existing request.',
  'บันทึกชุดคลิปไม่สำเร็จ กรุณาเปิดฉบับร่างเพื่อตรวจรายการ':
      'Could not finish saving the set. Open Drafts to check its items.',
  'ข้อมูลชุดคลิปไม่ถูกต้อง': 'The set details are invalid. Check Drafts.',
  'ชุดคลิปนี้เป็นของบัญชีอื่น':
      'This set belongs to another account. Sign in to its owner account.',
  'อ่านข้อมูลชุดคลิปเดิมไม่ได้ กรุณาตรวจฉบับร่าง':
      'Could not read this set. Check Drafts before retrying.',
  'ไม่พบฉบับร่างต้นฉบับของชุดคลิป':
      'The original draft for this set is missing. Check Drafts.',
  'ฉบับร่างเป็นส่วนหนึ่งของชุดคลิปอื่น':
      'A draft belongs to another set. Reopen Drafts.',
  'ข้อมูลชุดคลิปมีขนาดใหญ่เกินไป':
      'This set has too much saved information. Check its captions and retry.',
  'บันทึกชุดคลิปไม่สำเร็จ': 'Could not save this set. Please try again.',
  'บัญชีไม่ถูกต้อง': 'The account could not be verified. Sign in again.',
  'พื้นที่ชุดคลิปไม่ปลอดภัย':
      'Could not safely open draft storage. Reopen Drafts before retrying.',
  'สมาชิกชุดคลิปเปลี่ยนแล้ว': 'The clips in this set changed. Reopen the set.',
  'เปลี่ยนรายการโพสต์ที่รับแล้วไม่ได้':
      'An accepted request cannot be changed. Check its existing post.',
  'รหัสชุดคลิปไม่ถูกต้อง': 'This set could not be identified. Reopen Drafts.',
  'ไฟล์ชุดคลิปไม่ปลอดภัย':
      'Could not safely read the set file. Reopen Drafts before retrying.',
};

const _existingValidationMessages = {
  'เพิ่มแคปชั่นก่อนโพสต์',
  'แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร',
  'บัญชีหรือตัวเลือก TikTok เปลี่ยนแล้ว กรุณาเปิดการตั้งค่า TikTok และยืนยันใหม่',
  'บันทึกร่างไม่สำเร็จ ตรวจสอบพื้นที่ว่างในเครื่อง',
  'บันทึกร่างในเครื่องไม่สำเร็จ',
  'ยังเปิดพื้นที่เก็บฉบับร่างในเครื่องไม่ได้',
  'ไม่พบไฟล์วิดีโอในเครื่อง',
  'เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต',
  'ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920',
  'ระบบตอบสถานะโพสต์ที่ยังยืนยันไม่ได้ กรุณาตรวจรายการโพสต์ก่อนลองใหม่',
  'การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299',
  'ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่ก่อนตั้งเวลา',
  'YouTube Shorts ต้องใช้คลิปยาวไม่เกิน 3 นาที',
  'Instagram Reels ต้องใช้คลิปยาวตั้งแต่ 3 วินาทีถึง 15 นาที',
};

String clipGroupDate(BuildContext context, DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String clipGroupTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
