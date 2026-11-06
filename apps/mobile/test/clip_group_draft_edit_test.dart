import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_edit.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';

PublishDraft _draft({bool uploaded = false}) => PublishDraft(
      version: publishDraftManifestVersion,
      id: 'part',
      ownerUserId: 'owner',
      submissionRequestId: 'same-request',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      videoPath: '/part.mp4',
      videoName: 'part.mp4',
      videoSizeBytes: 12,
      caption: 'original',
      aiGuidance: 'style',
      watermarkEnabled: false,
      platformApiValues: {'YOUTUBE_SHORTS'},
      clipGroupId: 'group',
      uploadedMedia: uploaded
          ? const PublishDraftUploadedMedia(
              mediaContentFingerprint: 'fingerprint',
              videoS3Key: 'uploaded/video',
            )
          : null,
    );

void main() {
  test('member platform captions retain target set and refuse uploaded edits',
      () {
    const settings = PlatformPublishSettings(
        usePlatformCaptions: true,
        platformCaptions: {SocialPlatform.youtubeShorts: ''});
    final request = clipGroupMemberSaveRequest(_draft(),
        platformSettings: settings, now: DateTime.utc(2026, 2));
    expect(request.platformSettings, same(settings));
    expect(request.platformApiValues, {'YOUTUBE_SHORTS'});
    expect(request.caption, 'original');
    expect(
        () => clipGroupMemberSaveRequest(_draft(uploaded: true),
            platformSettings: settings, now: DateTime.utc(2026, 2)),
        throwsA(isA<PublishDraftValidationException>()));
  });
  test('an ambiguous upload cannot be rewritten by a group caption edit', () {
    expect(
      () => clipGroupMemberSaveRequest(_draft(uploaded: true),
          caption: 'changed', now: DateTime.utc(2026, 2)),
      throwsA(isA<PublishDraftValidationException>()),
    );
  });

  test('an ambiguous upload cannot be assigned a different schedule', () {
    expect(
      () => clipGroupMemberSaveRequest(_draft(uploaded: true),
          replaceSchedule: true,
          scheduledAt: DateTime.utc(2026, 2),
          now: DateTime.utc(2026, 2)),
      throwsA(isA<PublishDraftValidationException>()),
    );
  });

  test('saving the unchanged intent retains its identity and upload receipt',
      () {
    final draft = _draft(uploaded: true);
    final request =
        clipGroupMemberSaveRequest(draft, now: DateTime.utc(2026, 2));
    expect(request.id, draft.id);
    expect(request.clipGroupId, 'group');
    expect(request.uploadedMedia, same(draft.uploadedMedia));
    expect(request.videoFile, isA<File>());
  });

  test('setting one member schedule leaves the original immutable', () {
    final draft = _draft();
    final request = clipGroupMemberSaveRequest(draft,
        replaceSchedule: true,
        scheduledAt: DateTime.utc(2026, 2),
        now: DateTime.utc(2026, 2));
    expect(request.scheduledAt, DateTime.utc(2026, 2));
    expect(draft.scheduledAt, isNull);
    expect(request.caption, 'original');
  });
}
