import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_list.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';

PublishDraft _draft(String id,
        {String owner = 'owner',
        String? group,
        bool source = false,
        int updated = 1}) =>
    PublishDraft(
      version: publishDraftManifestVersion,
      id: id,
      ownerUserId: owner,
      submissionRequestId: 'request-$id',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 1, updated),
      videoPath: '/$id.mp4',
      videoName: '$id.mp4',
      videoSizeBytes: 10,
      caption: '',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues:
          source ? {'TIKTOK', 'YOUTUBE_SHORTS'} : {'YOUTUBE_SHORTS'},
      clipGroupId: group,
      isClipGroupSource: source,
    );

ClipGroupDraft _group({
  String id = 'group',
  String owner = 'owner',
  String source = 'original',
  List<String> parts = const ['part'],
}) =>
    ClipGroupDraft(
      id: id,
      ownerUserId: owner,
      sourceDraftId: source,
      title: 'Clip group',
      sharedCaption: '',
      deliveryMode: ClipGroupDeliveryMode.immediate,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 1,
      items: [
        for (var i = 0; i < parts.length; i++)
          ClipGroupItem(
            draftId: parts[i],
            index: i,
            sourceStartSeconds: i * 90.0,
            sourceEndSeconds: (i + 1) * 90.0,
            platformApiValues: const {'YOUTUBE_SHORTS'},
          ),
      ],
    );

void main() {
  test('a source and its parts form one entry without hiding another draft',
      () {
    final original = _draft('original', group: 'group', source: true);
    final part = _draft('part', group: 'group', updated: 3);
    final other = _draft('other', updated: 2);
    final entries = clipGroupDraftList([part, other, original]);
    expect(entries, hasLength(2));
    expect(entries.first.primaryDraft.id, original.id);
    expect(entries.first.members.map((d) => d.id), ['original', 'part']);
    expect(entries.first.clipCount, 1);
    expect(entries.first.platformApiValues, {'YOUTUBE_SHORTS'});
    expect(entries.last.primaryDraft.id, other.id);
  });

  test('the same group identifier never joins drafts from different owners',
      () {
    final entries = clipGroupDraftList([
      _draft('one', owner: 'owner-a', group: 'same'),
      _draft('two', owner: 'owner-b', group: 'same'),
    ]);
    expect(entries, hasLength(2));
    expect(entries.every((entry) => entry.members.length == 1), isTrue);
  });

  test('a group remains reopenable when accepted children have been removed',
      () {
    final original = _draft('original', group: 'group', source: true);
    final entry = clipGroupDraftList([original]).single;
    expect(entry.isGroup, isTrue);
    expect(entry.primaryDraft.id, 'original');
    expect(entry.clipCount, 0);
  });

  test('a surviving member remains visible when its source is unavailable', () {
    final entry = clipGroupDraftList([_draft('part', group: 'group')]).single;
    expect(entry.isGroup, isTrue);
    expect(entry.primaryDraft.id, 'part');
    expect(entry.clipCount, 1);
  });

  test(
      'committed manifest projects an untagged source and member after a crash',
      () {
    final source = _draft('original');
    final part = _draft('part', updated: 3);
    final other = _draft('other', updated: 2);
    final projected = projectClipGroupDrafts([part, other, source], [_group()]);
    final entries = clipGroupDraftList(projected);
    expect(entries, hasLength(2));
    expect(entries.first.primaryDraft.id, 'original');
    expect(entries.first.primaryDraft.isClipGroupSource, isTrue);
    expect(entries.first.members.map((d) => d.clipGroupId), ['group', 'group']);
    expect(source.clipGroupId, isNull);
    expect(part.clipGroupId, isNull);
    expect(identical(projected[1], other), isTrue);
  });

  test('orphan source and part tags become accessible ordinary drafts', () {
    final source = _draft('original', group: 'not-committed', source: true);
    final part = _draft('part', group: 'not-committed');
    final projected = projectClipGroupDrafts([source, part], []);
    expect(projected.every((draft) => draft.clipGroupId == null), isTrue);
    expect(projected.every((draft) => !draft.isClipGroupSource), isTrue);
    expect(clipGroupDraftList(projected), hasLength(2));
    expect(source.clipGroupId, 'not-committed');
    expect(source.isClipGroupSource, isTrue);
    expect(part.clipGroupId, 'not-committed');
  });

  test('manifest identity corrects stale group and source flags in the view',
      () {
    final projected = projectClipGroupDrafts([
      _draft('original', group: 'old-group'),
      _draft('part', group: 'old-group', source: true),
    ], [
      _group()
    ]);
    expect(projected.map((draft) => draft.clipGroupId), ['group', 'group']);
    expect(projected.map((draft) => draft.isClipGroupSource), [true, false]);
  });

  test('manifest mapping is scoped to both owner and draft identity', () {
    final projected = projectClipGroupDrafts([
      _draft('original', owner: 'owner-a'),
      _draft('part', owner: 'owner-a'),
      _draft('original', owner: 'owner-b', group: 'group', source: true),
      _draft('part', owner: 'owner-b', group: 'group'),
    ], [
      _group(owner: 'owner-a')
    ]);
    expect(projected.take(2).every((draft) => draft.clipGroupId == 'group'),
        isTrue);
    expect(
        projected.skip(2).every((draft) => draft.clipGroupId == null), isTrue);
    expect(clipGroupDraftList(projected), hasLength(3));
  });

  test('the same group identity in separate owners stays separate', () {
    final projected = projectClipGroupDrafts([
      _draft('original', owner: 'owner-a'),
      _draft('part', owner: 'owner-a'),
      _draft('original', owner: 'owner-b'),
      _draft('part', owner: 'owner-b'),
    ], [
      _group(owner: 'owner-a'),
      _group(owner: 'owner-b')
    ]);
    final entries = clipGroupDraftList(projected);
    expect(entries, hasLength(2));
    expect(entries.every((entry) => entry.members.length == 2), isTrue);
    expect(entries.map((entry) => entry.primaryDraft.ownerUserId).toSet(),
        {'owner-a', 'owner-b'});
  });

  test('conflicting source claims expose all affected media as ordinary drafts',
      () {
    final projected = projectClipGroupDrafts([
      _draft('original', group: 'first', source: true),
      _draft('part-a', group: 'first'),
      _draft('part-b', group: 'second'),
    ], [
      _group(id: 'first', parts: ['part-a']),
      _group(id: 'second', parts: ['part-b']),
    ]);
    expect(projected.every((draft) => draft.clipGroupId == null), isTrue);
    expect(clipGroupDraftList(projected), hasLength(3));
  });

  test('a member claimed as another group source fails both groups closed', () {
    final projected = projectClipGroupDrafts([
      _draft('original', group: 'first'),
      _draft('part', group: 'first'),
      _draft('next', group: 'second'),
    ], [
      _group(id: 'first'),
      _group(id: 'second', source: 'part', parts: ['next']),
    ]);
    expect(projected.every((draft) => draft.clipGroupId == null), isTrue);
  });

  test('duplicate manifest identities fail closed without joining member sets',
      () {
    final projected = projectClipGroupDrafts([
      _draft('original', group: 'group'),
      _draft('part-a', group: 'group'),
      _draft('part-b', group: 'group'),
    ], [
      _group(parts: ['part-a']),
      _group(parts: ['part-b']),
    ]);
    expect(projected.every((draft) => draft.clipGroupId == null), isTrue);
  });

  test('invalid manifests never hide media behind a group entry', () {
    final projected = projectClipGroupDrafts([
      _draft('original', group: 'bad'),
      _draft('part', group: 'bad'),
    ], [
      _group(id: '../bad')
    ]);
    expect(projected.every((draft) => draft.clipGroupId == null), isTrue);
  });

  test('projection never materializes missing children or infers acceptance',
      () {
    final manifest = _group(parts: ['part', 'missing']);
    final projected = projectClipGroupDrafts([_draft('original')], [manifest]);
    expect(projected, hasLength(1));
    expect(projected.single.id, 'original');
    expect(projected.single.isClipGroupSource, isTrue);
    expect(manifest.items.every((item) => !item.isAccepted), isTrue);
    expect(clipGroupDraftList(projected).single.clipCount, 0);
  });

  test('view normalization preserves the full draft and unknown upload receipt',
      () {
    const receipt = PublishDraftUploadedMedia(
      mediaContentFingerprint: 'fingerprint',
      videoS3Key: 'uploads/original.mp4',
      coverImageS3Key: 'uploads/cover.jpg',
      videoPreparationPolicy: 'local-policy',
      videoDurationSeconds: 120,
    );
    const cover = PublishDraftCover(
      imagePath: '/owned/cover.jpg',
      sizeBytes: 25,
      design: CoverDesign(text: 'Cover'),
      sourceKind: CoverSourceKind.galleryImage,
      sourceImagePath: '/owned/source.png',
      sourceImageName: 'source.png',
      durationMs: 120000,
    );
    const settings = PlatformPublishSettings(youtubeTitle: 'Title');
    final source = PublishDraft(
      version: 3,
      id: 'original',
      ownerUserId: 'owner',
      submissionRequestId: 'stable-original-request',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 2),
      videoPath: '/owned/original.mp4',
      videoName: 'ต้นฉบับ.mp4',
      videoSizeBytes: 123,
      videoWidth: 1080,
      videoHeight: 1920,
      caption: 'Reviewed caption',
      captionNeedsReview: true,
      captionLanguage: 'th',
      aiGuidance: 'Seller guidance',
      watermarkEnabled: true,
      platformApiValues: const {'YOUTUBE_SHORTS'},
      platformSettings: settings,
      scheduledAt: DateTime.utc(2026, 3),
      cover: cover,
      mediaContentFingerprint: 'fingerprint',
      uploadedMedia: receipt,
    );
    final projected = projectClipGroupDrafts([source], [_group()]).single;
    expect(projected.version, source.version);
    expect(projected.id, source.id);
    expect(projected.ownerUserId, source.ownerUserId);
    expect(projected.submissionRequestId, source.submissionRequestId);
    expect(projected.createdAt, source.createdAt);
    expect(projected.updatedAt, source.updatedAt);
    expect(projected.videoPath, source.videoPath);
    expect(projected.videoName, source.videoName);
    expect(projected.videoSizeBytes, source.videoSizeBytes);
    expect(projected.videoWidth, source.videoWidth);
    expect(projected.videoHeight, source.videoHeight);
    expect(projected.caption, source.caption);
    expect(projected.captionNeedsReview, source.captionNeedsReview);
    expect(projected.captionLanguage, source.captionLanguage);
    expect(projected.aiGuidance, source.aiGuidance);
    expect(projected.watermarkEnabled, source.watermarkEnabled);
    expect(projected.platformApiValues, source.platformApiValues);
    expect(identical(projected.platformSettings, settings), isTrue);
    expect(projected.scheduledAt, source.scheduledAt);
    expect(identical(projected.cover, cover), isTrue);
    expect(projected.mediaContentFingerprint, source.mediaContentFingerprint);
    expect(identical(projected.uploadedMedia, receipt), isTrue);
    expect(source.clipGroupId, isNull);
    expect(source.isClipGroupSource, isFalse);
  });

  test('ordinary drafts are unchanged and the projected list is immutable', () {
    final ordinary = _draft('ordinary');
    final projected = projectClipGroupDrafts([ordinary], [_group()]);
    expect(identical(projected.single, ordinary), isTrue);
    expect(() => projected.clear(), throwsUnsupportedError);
  });
}
