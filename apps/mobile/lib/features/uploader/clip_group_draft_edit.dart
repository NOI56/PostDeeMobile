import 'dart:io';

import 'cover_image_processor.dart';
import 'publish_draft.dart';

/// Retains managed media, covers and the submission identity when editing one
/// member. An unresolved upload always keeps the exact original request intent.
PublishDraftSaveRequest clipGroupMemberSaveRequest(
  PublishDraft draft, {
  required DateTime now,
  String? caption,
  bool? captionNeedsReview,
  DateTime? scheduledAt,
  bool replaceSchedule = false,
}) {
  final nextCaption = caption ?? draft.caption;
  final nextSchedule = replaceSchedule ? scheduledAt : draft.scheduledAt;
  final sameSchedule = draft.scheduledAt == null
      ? nextSchedule == null
      : nextSchedule != null &&
          draft.scheduledAt!.isAtSameMomentAs(nextSchedule);
  if (draft.uploadedMedia != null &&
      (nextCaption != draft.caption || !sameSchedule)) {
    throw const PublishDraftValidationException(
        'ร่างนี้เคยเริ่มส่งแล้ว กรุณาตรวจผลรายการเดิมก่อนแก้ไข');
  }
  final cover = draft.cover;
  final updatedAt = now.toUtc();
  return PublishDraftSaveRequest(
    id: draft.id,
    createdAt: draft.createdAt,
    updatedAt:
        updatedAt.isBefore(draft.createdAt) ? draft.createdAt : updatedAt,
    videoFile: File(draft.videoPath),
    videoName: draft.videoName,
    videoSizeBytes: draft.videoSizeBytes,
    videoWidth: draft.videoWidth,
    videoHeight: draft.videoHeight,
    caption: nextCaption,
    captionNeedsReview: captionNeedsReview ?? draft.captionNeedsReview,
    captionLanguage: draft.captionLanguage,
    aiGuidance: draft.aiGuidance,
    watermarkEnabled: draft.watermarkEnabled,
    platformApiValues: draft.platformApiValues,
    platformSettings: draft.platformSettings,
    scheduledAt: nextSchedule,
    coverImageFile: cover == null ? null : File(cover.imagePath),
    coverDesign: cover?.design,
    coverDurationMs: cover?.durationMs,
    coverSourceKind: cover?.sourceKind ?? CoverSourceKind.videoFrame,
    coverSourceImageFile:
        cover?.sourceImagePath == null ? null : File(cover!.sourceImagePath!),
    coverSourceImageName: cover?.sourceImageName,
    uploadedMedia: draft.uploadedMedia,
    clipGroupId: draft.clipGroupId,
    isClipGroupSource: draft.isClipGroupSource,
  );
}
