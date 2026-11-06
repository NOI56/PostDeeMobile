import 'package:flutter/material.dart';

import 'clip_split_plan.dart';
import 'uploader_localizations.dart';

String clipSplitText(BuildContext context, String thai, String english) =>
    uploaderText(context, thai, english);

String clipSplitPartsText(BuildContext context, int count) => clipSplitText(
    context, '$count ตอน', '$count ${count == 1 ? 'part' : 'parts'}');

String clipSplitUnitsText(BuildContext context, int count) => clipSplitText(
    context,
    '$count หน่วยโพสต์',
    '$count post ${count == 1 ? 'unit' : 'units'}');

String clipSplitProblemText(
        BuildContext context, ClipSplitPlanProblem problem) =>
    switch (problem) {
      ClipSplitPlanProblem.invalidDuration => clipSplitText(
          context,
          'ยังอ่านความยาวคลิปไม่ได้ กรุณาเลือกคลิปใหม่',
          'Could not read the video length. Choose the video again.'),
      ClipSplitPlanProblem.noPlatforms => clipSplitText(
          context, 'เลือกอย่างน้อย 1 ช่องทาง', 'Select at least one channel.'),
      ClipSplitPlanProblem.unsupportedPlatform => clipSplitText(
          context,
          'ช่องทางนี้ยังไม่รองรับการแบ่งคลิป',
          'Splitting is not supported for this channel yet.'),
      ClipSplitPlanProblem.tikTokAccountRequired => clipSplitText(
          context, 'รอตรวจสิทธิ์บัญชี TikTok', 'TikTok account check pending'),
      ClipSplitPlanProblem.tooShort => clipSplitText(
          context,
          'คลิปสั้นกว่าความยาวขั้นต่ำของช่องทางที่เลือก',
          'The video is shorter than a selected channel allows.'),
      ClipSplitPlanProblem.tooManyParts => clipSplitText(
          context,
          'แบ่งได้สูงสุด $maxClipSplitParts คลิปต่อชุด กรุณาเลือกคลิปที่สั้นลงหรือลดช่องทาง',
          'Up to $maxClipSplitParts clips per set. Choose a shorter video or fewer channels.'),
      ClipSplitPlanProblem.invalidBoundary => clipSplitText(
          context,
          'จุดแบ่งนี้ทำให้บางตอนสั้นหรือยาวเกินไป กรุณาปรับใหม่',
          'This cut makes a part too short or too long. Adjust it again.'),
      ClipSplitPlanProblem.invalidSegmentRange => clipSplitText(
          context,
          'ช่วงเวลาต้องอยู่ในต้นฉบับ ไม่ทับตอนอื่น และยาวตามข้อกำหนดของช่องทาง',
          'Keep ranges within the original, without overlaps, and within the channel’s allowed length.'),
      ClipSplitPlanProblem.noSharedRange => clipSplitText(
          context,
          'ยังใช้จุดแบ่งร่วมกันไม่ได้ ลองแบ่งเฉพาะช่องทางที่ยาวเกิน',
          'These channels cannot share the same cuts. Split only the channels that need it.'),
    };

/// Keep displayed clocks compact; measured ranges retain their own precision.
String formatClipSplitTime(double seconds) {
  final microseconds = (seconds * 1000000).round();
  final minutes = microseconds ~/ 60000000;
  final wholeSeconds = (microseconds ~/ 1000000) % 60;
  return '$minutes:${wholeSeconds.toString().padLeft(2, '0')}';
}
