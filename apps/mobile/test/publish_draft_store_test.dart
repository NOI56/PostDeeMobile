import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('postdee-publish-drafts-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<File> fixture(String name, List<int> bytes) async {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  PublishDraftSaveRequest request({
    String id = 'draft-1',
    required File video,
    File? cover,
    File? coverSource,
    DateTime? updatedAt,
    String caption = 'แคปชันร่าง',
    bool watermarkEnabled = true,
    Set<String> platformApiValues = const {
      'TIKTOK',
      'YOUTUBE_SHORTS',
    },
    DateTime? scheduledAt,
    PlatformPublishSettings platformSettings = const PlatformPublishSettings(),
  }) {
    return PublishDraftSaveRequest(
      id: id,
      createdAt: DateTime.utc(2026, 8, 11, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 11, 2),
      videoFile: video,
      videoName: 'seller-clip.mp4',
      videoSizeBytes: 4,
      videoWidth: 1080,
      videoHeight: 1920,
      caption: caption,
      aiGuidance: 'โทนสนุก เน้นโปรวันนี้',
      watermarkEnabled: watermarkEnabled,
      platformApiValues: platformApiValues,
      platformSettings: platformSettings,
      scheduledAt: scheduledAt ?? DateTime.utc(2026, 8, 12, 11, 30),
      coverImageFile: cover,
      coverDesign: cover == null
          ? null
          : const CoverDesign(
              coverFrameTimeMs: 1400,
              text: 'โปรวันนี้',
              fontFamily: CoverFontFamily.anuphan,
              fontWeight: 700,
              fontSize: 48,
              textColor: Color(0xFFFAFAFA),
              backgroundColor: Color(0xCC111111),
              dx: .45,
              dy: .3,
            ),
      coverDurationMs: cover == null ? null : 8000,
      coverSourceKind: coverSource == null
          ? CoverSourceKind.videoFrame
          : CoverSourceKind.galleryImage,
      coverSourceImageFile: coverSource,
      coverSourceImageName: coverSource == null ? null : 'custom-cover.png',
    );
  }

  FilePublishDraftStore storeFor(
    String ownerUserId, {
    Future<void> Function()? beforePromotion,
  }) =>
      FilePublishDraftStore(
        rootDirectory: Directory('${root.path}/store/$ownerUserId'),
        ownerRootBoundary: Directory('${root.path}/store'),
        ownerUserId: ownerUserId,
        beforePromotion: beforePromotion,
      );

  test('copies video and cover into app-owned storage and restores every field',
      () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final cover = await fixture('source-cover.jpg', [5, 6, 7]);
    final coverSource = await fixture('source-art.png', [8, 9]);
    final store = storeFor('firebase-user-a');

    final saved = await store.saveDraft(
      request(
        video: video,
        cover: cover,
        coverSource: coverSource,
        platformSettings: const PlatformPublishSettings(
          youtubeTitle: 'Summer collection',
          youtubeVisibility: YouTubeVisibility.public,
          youtubeMadeForKids: false,
          youtubeContainsSyntheticMedia: true,
          youtubeCommunityGuidelinesCertified: true,
          instagramShareToFeed: false,
          facebookPublishMode: FacebookPublishMode.publish,
        ),
      ),
    );
    await video.delete();
    await cover.delete();
    await coverSource.delete();

    final restored = await store.loadDraft('draft-1');

    expect(restored, isNotNull);
    expect(restored!.id, 'draft-1');
    expect(restored.ownerUserId, 'firebase-user-a');
    expect(restored.caption, 'แคปชันร่าง');
    expect(restored.aiGuidance, 'โทนสนุก เน้นโปรวันนี้');
    expect(restored.watermarkEnabled, isTrue);
    expect(restored.videoName, 'seller-clip.mp4');
    expect(restored.videoSizeBytes, 4);
    expect(restored.videoWidth, 1080);
    expect(restored.videoHeight, 1920);
    expect(restored.platformApiValues, {'TIKTOK', 'YOUTUBE_SHORTS'});
    expect(
        restored.platformSettings.youtubeVisibility, YouTubeVisibility.public);
    expect(restored.platformSettings.youtubeTitle, 'Summer collection');
    expect(restored.platformSettings.youtubeMadeForKids, isFalse);
    expect(restored.platformSettings.youtubeContainsSyntheticMedia, isTrue);
    expect(
      restored.platformSettings.youtubeCommunityGuidelinesCertified,
      isTrue,
    );
    expect(restored.platformSettings.instagramShareToFeed, isFalse);
    expect(
      restored.platformSettings.facebookPublishMode,
      FacebookPublishMode.publish,
    );
    expect(restored.scheduledAt, DateTime.utc(2026, 8, 12, 11, 30));
    expect(await File(restored.videoPath).readAsBytes(), [1, 2, 3, 4]);
    expect(await File(restored.cover!.imagePath).readAsBytes(), [5, 6, 7]);
    expect(await File(restored.cover!.sourceImagePath!).readAsBytes(), [8, 9]);
    expect(restored.cover!.design.text, 'โปรวันนี้');
    expect(restored.cover!.design.fontFamily, CoverFontFamily.anuphan);
    expect(restored.cover!.sourceKind, CoverSourceKind.galleryImage);
    expect(restored.cover!.sourceImageName, 'custom-cover.png');
    expect(saved.videoPath, restored.videoPath);
    expect(
      saved.submissionRequestId,
      matches(RegExp(r'^submit_[0-9a-f]{64}$')),
    );
    expect(
      saved.videoPath.replaceAll('\\', '/'),
      startsWith('${root.path.replaceAll('\\', '/')}/store'),
    );
  });

  test('keeps one submission id for the full lifetime of a draft', () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final changedVideo = await fixture('changed.mp4', [4, 3, 2, 1]);
    final store = storeFor('firebase-user-a');

    final first = await store.saveDraft(request(video: video));
    final sameIntent = await store.saveDraft(
      request(
        video: video,
        updatedAt: DateTime.utc(2026, 8, 11, 3),
      ),
    );
    final changedCaption = await store.saveDraft(
      request(
        video: video,
        caption: 'แคปชันใหม่',
        updatedAt: DateTime.utc(2026, 8, 11, 4),
      ),
    );
    final changedMedia = await store.saveDraft(
      request(
        video: changedVideo,
        caption: 'แคปชันใหม่',
        updatedAt: DateTime.utc(2026, 8, 11, 5),
      ),
    );

    expect(sameIntent.submissionRequestId, first.submissionRequestId);
    expect(changedCaption.submissionRequestId, first.submissionRequestId);
    expect(changedMedia.submissionRequestId, first.submissionRequestId);
  });

  test('reads v2 drafts without settings but rejects incomplete v3 drafts',
      () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final store = storeFor('firebase-user-a');
    await store.saveDraft(request(video: video));
    final manifestFile = File(
      '${root.path}/store/firebase-user-a/draft-1/manifest.json',
    );
    final manifest = Map<String, Object?>.from(
      jsonDecode(await manifestFile.readAsString()) as Map,
    )
      ..['version'] = 2
      ..remove('platformSettings');
    await manifestFile.writeAsString(jsonEncode(manifest), flush: true);

    final legacy = await store.loadDraft('draft-1');
    expect(legacy, isNotNull);
    expect(legacy!.version, 2);
    expect(
      legacy.platformSettings,
      const PlatformPublishSettings(),
    );

    manifest['version'] = publishDraftManifestVersion;
    await manifestFile.writeAsString(jsonEncode(manifest), flush: true);
    expect(await store.loadDraft('draft-1'), isNull);
  });

  test('lists valid drafts newest first and skips corrupt manifests', () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final store = storeFor('firebase-user-a');

    await store.saveDraft(
      request(
        id: 'older',
        video: video,
        updatedAt: DateTime.utc(2026, 8, 11, 2),
      ),
    );
    await store.saveDraft(
      request(
        id: 'newer',
        video: video,
        updatedAt: DateTime.utc(2026, 8, 11, 3),
      ),
    );
    final corrupt = Directory('${root.path}/store/firebase-user-a/corrupt');
    await corrupt.create(recursive: true);
    await File('${corrupt.path}/manifest.json').writeAsString('{bad json');

    final drafts = await store.listDrafts();

    expect(drafts.map((draft) => draft.id), ['newer', 'older']);
  });

  test('failed update keeps the last complete draft readable', () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final firstStore = storeFor('firebase-user-a');
    await firstStore.saveDraft(request(video: video));

    final failingStore = FilePublishDraftStore(
      rootDirectory: Directory('${root.path}/store/firebase-user-a'),
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
      beforePromotion: () async => throw StateError('disk interrupted'),
    );

    await expectLater(
      failingStore.saveDraft(
        PublishDraftSaveRequest(
          id: 'draft-1',
          createdAt: DateTime.utc(2026, 8, 11, 1),
          updatedAt: DateTime.utc(2026, 8, 11, 4),
          videoFile: video,
          videoName: 'seller-clip.mp4',
          videoSizeBytes: 4,
          caption: 'ค่าที่ยังบันทึกไม่สำเร็จ',
          aiGuidance: '',
          watermarkEnabled: false,
          platformApiValues: const {},
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final restored = await firstStore.loadDraft('draft-1');
    expect(restored, isNotNull);
    expect(restored!.caption, 'แคปชันร่าง');
  });

  test('recovers a fully written next directory after an interrupted promotion',
      () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final storeRoot = Directory('${root.path}/store/firebase-user-a');
    final failingStore = FilePublishDraftStore(
      rootDirectory: storeRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
      beforePromotion: () async => throw StateError('before rotate'),
    );

    await expectLater(
      failingStore.saveDraft(request(video: video)),
      throwsA(isA<StateError>()),
    );

    final recovered = await FilePublishDraftStore(
      rootDirectory: storeRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
    ).loadDraft('draft-1');
    expect(recovered, isNotNull);
    expect(recovered!.caption, 'แคปชันร่าง');
  });

  test('rejects unsafe ids and missing or empty video files', () async {
    final video = await fixture('source.mp4', [1]);
    final empty = await fixture('empty.mp4', []);
    final store = storeFor('firebase-user-a');

    await expectLater(
      store.saveDraft(request(id: '../outside', video: video)),
      throwsA(isA<PublishDraftValidationException>()),
    );
    await expectLater(
      store.saveDraft(request(id: 'empty', video: empty)),
      throwsA(isA<PublishDraftValidationException>()),
    );
    await video.delete();
    await expectLater(
      store.saveDraft(request(id: 'missing', video: video)),
      throwsA(isA<PublishDraftValidationException>()),
    );
  });

  test('delete removes only the requested draft directory', () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final store = storeFor('firebase-user-a');
    await store.saveDraft(request(id: 'keep', video: video));
    await store.saveDraft(request(id: 'remove', video: video));

    await store.deleteDraft('remove');

    expect(await store.loadDraft('remove'), isNull);
    expect(await store.loadDraft('keep'), isNotNull);
  });

  test('partial raw-media deletion is reported as a failure', () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final ownerRoot = Directory('${root.path}/store/firebase-user-a');
    final store = storeFor('firebase-user-a');
    final saved = await store.saveDraft(request(video: video));
    final partiallyFailingStore = FilePublishDraftStore(
      rootDirectory: ownerRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
      deleteDraftDirectory: (directory) async {
        if (directory.path.endsWith('draft-1')) {
          final manifest = File('${directory.path}/manifest.json');
          if (await manifest.exists()) await manifest.delete();
          throw const FileSystemException('media file is locked');
        }
        if (await directory.exists()) await directory.delete(recursive: true);
      },
    );

    await expectLater(
      partiallyFailingStore.deleteDraft(saved.id),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(saved.videoPath).exists(), isTrue);
    expect(await ownerRoot.exists(), isTrue);

    await store.deleteDraft(saved.id);
    expect(await ownerRoot.exists(), isTrue);
    expect(await Directory('${ownerRoot.path}/draft-1').exists(), isFalse);
  });

  test('rejects malformed manifest values instead of escaping the draft folder',
      () async {
    final storeRoot = Directory('${root.path}/store/firebase-user-a');
    final draftDirectory = Directory('${storeRoot.path}/bad');
    await draftDirectory.create(recursive: true);
    await File('${draftDirectory.path}/manifest.json').writeAsString('''
      {
        "version": 1,
        "id": "bad",
        "ownerUserId": "firebase-user-a",
        "createdAt": "2026-08-11T01:00:00.000Z",
        "updatedAt": "2026-08-11T02:00:00.000Z",
        "videoName": "clip.mp4",
        "videoRelativePath": "../outside.mp4",
        "videoSizeBytes": 4,
        "caption": "bad",
        "aiGuidance": "",
        "watermarkEnabled": false,
        "platformApiValues": []
      }
    ''');

    final draft = await FilePublishDraftStore(
      rootDirectory: storeRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
    ).loadDraft('bad');
    expect(draft, isNull);
    expect(await draftDirectory.exists(), isTrue);
    expect(await File('${draftDirectory.path}/manifest.json').exists(), isTrue);
  });

  test('rejects a manifest owned by a different signed-in account', () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final ownerA = storeFor('firebase-user-a');
    await ownerA.saveDraft(request(video: video));

    final manifest = File(
      '${root.path}/store/firebase-user-a/draft-1/manifest.json',
    );
    final text = await manifest.readAsString();
    await manifest.writeAsString(
      text.replaceFirst('firebase-user-a', 'firebase-user-b'),
      flush: true,
    );

    expect(await ownerA.loadDraft('draft-1'), isNull);
  });

  test('serializes saves across separate store instances for the same owner',
      () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final ownerRoot = Directory('${root.path}/store/firebase-user-a');
    final firstAtPromotion = Completer<void>();
    final secondAtPromotion = Completer<void>();
    final releaseFirst = Completer<void>();
    final firstStore = FilePublishDraftStore(
      rootDirectory: ownerRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
      beforePromotion: () async {
        firstAtPromotion.complete();
        await releaseFirst.future;
      },
    );
    final secondStore = FilePublishDraftStore(
      rootDirectory: ownerRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
      beforePromotion: () async => secondAtPromotion.complete(),
    );

    final firstSave = firstStore.saveDraft(request(video: video));
    await firstAtPromotion.future;
    final secondSave = secondStore.saveDraft(
      PublishDraftSaveRequest(
        id: 'draft-1',
        createdAt: DateTime.utc(2026, 8, 11, 1),
        updatedAt: DateTime.utc(2026, 8, 11, 4),
        videoFile: video,
        videoName: 'seller-clip.mp4',
        videoSizeBytes: 4,
        caption: 'ค่าล่าสุด',
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: const {},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(secondAtPromotion.isCompleted, isFalse);
    releaseFirst.complete();
    await Future.wait([firstSave, secondSave]);

    final restored = await firstStore.loadDraft('draft-1');
    expect(restored?.caption, 'ค่าล่าสุด');
  });

  test('deletes all drafts for only this owner directory', () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final ownerRoot = Directory('${root.path}/store/firebase-user-a');
    final otherOwnerFile = File(
      '${root.path}/store/firebase-user-b/keep.txt',
    );
    await otherOwnerFile.create(recursive: true);
    await otherOwnerFile.writeAsString('keep');
    final store = FilePublishDraftStore(
      rootDirectory: ownerRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
    );
    await store.saveDraft(request(id: 'first', video: video));
    await store.saveDraft(request(id: 'second', video: video));
    await File('${ownerRoot.path}/unknown.tmp').writeAsString('stale');
    await Directory('${ownerRoot.path}/not a draft').create();

    await store.deleteAllDrafts();

    expect(await ownerRoot.exists(), isFalse);
    expect(await store.listDrafts(), isEmpty);
    expect(await otherOwnerFile.exists(), isTrue);
  });

  test('delete-all waits for an active save and leaves the owner root empty',
      () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final ownerRoot = Directory('${root.path}/store/firebase-user-a');
    final otherOwnerFile = File(
      '${root.path}/store/firebase-user-b/keep.txt',
    );
    await otherOwnerFile.create(recursive: true);
    await otherOwnerFile.writeAsString('keep');
    final saveReachedPromotion = Completer<void>();
    final releaseSave = Completer<void>();
    final saveStore = FilePublishDraftStore(
      rootDirectory: ownerRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
      beforePromotion: () async {
        saveReachedPromotion.complete();
        await releaseSave.future;
      },
    );
    final deleteStore = FilePublishDraftStore(
      rootDirectory: ownerRoot,
      ownerRootBoundary: Directory('${root.path}/store'),
      ownerUserId: 'firebase-user-a',
    );

    final save = saveStore.saveDraft(request(video: video));
    await saveReachedPromotion.future;
    final deleteAll = deleteStore.deleteAllDrafts();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await ownerRoot.exists(), isTrue);

    releaseSave.complete();
    await save;
    await deleteAll;

    expect(await ownerRoot.exists(), isFalse);
    expect(await deleteStore.listDrafts(), isEmpty);
    expect(await otherOwnerFile.exists(), isTrue);
  });

  test('delete-all rejects a root that is not a direct owner child', () async {
    final boundary = Directory('${root.path}/store');
    final unrelated = File('${boundary.path}/keep.txt');
    await unrelated.create(recursive: true);
    await unrelated.writeAsString('keep');
    final unsafeStore = FilePublishDraftStore(
      rootDirectory: boundary,
      ownerRootBoundary: boundary,
      ownerUserId: 'firebase-user-a',
    );

    await expectLater(
      unsafeStore.deleteAllDrafts(),
      throwsA(isA<PublishDraftValidationException>()),
    );

    expect(await unrelated.readAsString(), 'keep');
  });

  test('rejects draft media that was truncated after a completed save',
      () async {
    final video = await fixture('source.mp4', [1, 2, 3, 4]);
    final cover = await fixture('cover.jpg', [5, 6, 7]);
    final coverSource = await fixture('cover-source.png', [8, 9]);
    final store = storeFor('firebase-user-a');
    final saved = await store.saveDraft(
      request(video: video, cover: cover, coverSource: coverSource),
    );

    await File(saved.videoPath).writeAsBytes([1], flush: true);
    expect(await store.loadDraft(saved.id), isNull);

    await store.saveDraft(
      request(video: video, cover: cover, coverSource: coverSource),
    );
    final restored = await store.loadDraft(saved.id);
    expect(restored, isNotNull);
    await File(restored!.cover!.imagePath).writeAsBytes([5], flush: true);
    expect(await store.loadDraft(saved.id), isNull);

    await store.saveDraft(
      request(video: video, cover: cover, coverSource: coverSource),
    );
    final restoredAgain = await store.loadDraft(saved.id);
    expect(restoredAgain, isNotNull);
    await File(restoredAgain!.cover!.sourceImagePath!)
        .writeAsBytes([8], flush: true);
    expect(await store.loadDraft(saved.id), isNull);
  });
}
