import 'dart:io';

import 'cover_image_processor.dart';
import 'platform_publish_settings.dart';

const publishDraftManifestVersion = 3;
const legacyPublishDraftManifestVersion = 2;

class PublishDraftValidationException implements Exception {
  const PublishDraftValidationException(this.message);

  final String message;

  @override
  String toString() => 'PublishDraftValidationException: $message';
}

class PublishDraftCover {
  const PublishDraftCover({
    required this.imagePath,
    required this.sizeBytes,
    required this.design,
    required this.sourceKind,
    this.durationMs,
    this.sourceImagePath,
    this.sourceImageName,
  });

  final String imagePath;
  final int sizeBytes;
  final CoverDesign design;
  final int? durationMs;
  final CoverSourceKind sourceKind;
  final String? sourceImagePath;
  final String? sourceImageName;

  CoverEditorResult toEditorResult() => CoverEditorResult(
        localImagePath: imagePath,
        sizeBytes: sizeBytes,
        design: design,
        durationMs: durationMs,
        sourceKind: sourceKind,
        sourceImagePath: sourceImagePath,
        sourceImageName: sourceImageName,
      );
}

class PublishDraft {
  const PublishDraft({
    required this.version,
    required this.id,
    required this.ownerUserId,
    required this.submissionRequestId,
    required this.createdAt,
    required this.updatedAt,
    required this.videoPath,
    required this.videoName,
    required this.videoSizeBytes,
    required this.caption,
    required this.aiGuidance,
    required this.watermarkEnabled,
    required this.platformApiValues,
    this.platformSettings = const PlatformPublishSettings(),
    this.videoWidth,
    this.videoHeight,
    this.scheduledAt,
    this.cover,
  });

  final int version;
  final String id;
  final String ownerUserId;
  final String submissionRequestId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String videoPath;
  final String videoName;
  final int videoSizeBytes;
  final int? videoWidth;
  final int? videoHeight;
  final String caption;
  final String aiGuidance;
  final bool watermarkEnabled;
  final Set<String> platformApiValues;
  final PlatformPublishSettings platformSettings;
  final DateTime? scheduledAt;
  final PublishDraftCover? cover;
}

class PublishDraftSaveRequest {
  const PublishDraftSaveRequest({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.videoFile,
    required this.videoName,
    required this.videoSizeBytes,
    required this.caption,
    required this.aiGuidance,
    required this.watermarkEnabled,
    required this.platformApiValues,
    this.platformSettings = const PlatformPublishSettings(),
    this.videoWidth,
    this.videoHeight,
    this.scheduledAt,
    this.coverImageFile,
    this.coverDesign,
    this.coverDurationMs,
    this.coverSourceKind = CoverSourceKind.videoFrame,
    this.coverSourceImageFile,
    this.coverSourceImageName,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final File videoFile;
  final String videoName;
  final int videoSizeBytes;
  final int? videoWidth;
  final int? videoHeight;
  final String caption;
  final String aiGuidance;
  final bool watermarkEnabled;
  final Set<String> platformApiValues;
  final PlatformPublishSettings platformSettings;
  final DateTime? scheduledAt;
  final File? coverImageFile;
  final CoverDesign? coverDesign;
  final int? coverDurationMs;
  final CoverSourceKind coverSourceKind;
  final File? coverSourceImageFile;
  final String? coverSourceImageName;
}
