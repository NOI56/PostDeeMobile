import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_store.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';

void main() {
  late Directory root;
  late File source;
  late FilePublishDraftStore store;
  final now = DateTime.utc(2026, 11, 5);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('postdee-clip-group-test-');
    source = File('${root.path}/source.mp4')..writeAsBytesSync([1, 2, 3, 4]);
    store = FilePublishDraftStore(
      rootDirectory: Directory('${root.path}/owners/a'),
      ownerRootBoundary: Directory('${root.path}/owners'),
      ownerUserId: 'owner-a',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  PublishDraftSaveRequest request(String id,
          {String? groupId, bool isSource = false}) =>
      PublishDraftSaveRequest(
        id: id,
        createdAt: now,
        updatedAt: now,
        videoFile: source,
        videoName: '$id.mp4',
        videoSizeBytes: 4,
        caption: 'caption',
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: const {'FACEBOOK_REELS'},
        clipGroupId: groupId,
        isClipGroupSource: isSource,
      );

  ClipGroupDraft group({String owner = 'owner-a', String id = 'group-a'}) =>
      ClipGroupDraft(
        id: id,
        ownerUserId: owner,
        sourceDraftId: 'original',
        title: 'Source clip',
        sharedCaption: 'Shared caption',
        deliveryMode: ClipGroupDeliveryMode.immediate,
        createdAt: now,
        updatedAt: now,
        items: [
          for (var i = 0; i < 2; i++)
            ClipGroupItem(
              draftId: 'part-$i',
              index: i,
              sourceStartSeconds: i * 90,
              sourceEndSeconds: (i + 1) * 90,
              platformApiValues: const {'FACEBOOK_REELS'},
              scheduledAt: now.add(Duration(days: i + 1)),
            ),
        ],
      );

  test('optional group metadata preserves v3 and legacy drafts', () async {
    final original = await store.saveDraft(request('original'));
    final grouped =
        await store.saveDraft(request('part-0', groupId: 'group-a'));
    expect(original.clipGroupId, isNull);
    expect(original.isClipGroupSource, isFalse);
    expect(grouped.version, 3);
    expect((await store.loadDraft('part-0'))!.clipGroupId, 'group-a');
    expect((await store.loadDraft('part-0'))!.submissionRequestId,
        grouped.submissionRequestId);
    final tagged = await store
        .saveDraft(request('original', groupId: 'group-a', isSource: true));
    expect(tagged.isClipGroupSource, isTrue);
    expect(tagged.submissionRequestId, original.submissionRequestId);
  });

  test(
      'group store creates once and updates by revision without touching media',
      () async {
    await store.saveDraft(request('original'));
    await store.saveDraft(request('part-0', groupId: 'group-a'));
    await store.saveDraft(request('part-1', groupId: 'group-a'));
    final saved = await store.saveClipGroup(group(), expectedRevision: null);
    expect(saved.revision, 1);
    expect((await store.listDrafts()), hasLength(3));
    final updated = await store.saveClipGroup(
      saved.copyWith(
          sharedCaption: 'New shared caption',
          deliveryMode: ClipGroupDeliveryMode.scheduled),
      expectedRevision: saved.revision,
    );
    expect(updated.revision, 2);
    expect(updated.items[0].scheduledAt, now.add(const Duration(days: 1)));
    expect(updated.items[1].scheduledAt, now.add(const Duration(days: 2)));
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
    await expectLater(store.saveClipGroup(saved, expectedRevision: 1),
        throwsA(isA<ClipGroupDraftConflictException>()));
    await expectLater(store.saveClipGroup(group(), expectedRevision: null),
        throwsA(isA<ClipGroupDraftConflictException>()));
    expect((await store.loadClipGroup('group-a'))!.sharedCaption,
        'New shared caption');
  });

  test('accepted checkpoint survives child deletion and cannot be cleared',
      () async {
    await store.saveDraft(request('original'));
    final saved = await store.saveClipGroup(group(), expectedRevision: null);
    final items = [...saved.items];
    items[0] = items[0].copyWith(
        acceptedPostId: 'post-a',
        acceptedPostStatus: 'QUEUED',
        acceptedScheduledAt: now.add(const Duration(days: 1)));
    final accepted = await store.saveClipGroup(saved.copyWith(items: items),
        expectedRevision: saved.revision);
    await store.deleteDraft('part-0');
    final restored = (await store.loadClipGroup('group-a'))!;
    expect(restored.items.first.isAccepted, isTrue);
    expect(restored.items.first.acceptedPostId, 'post-a');
    expect(restored.items.last.isAccepted, isFalse);
    final cleared = [...restored.items];
    cleared[0] = cleared[0].copyWith(
        acceptedPostId: null,
        acceptedPostStatus: null,
        acceptedScheduledAt: null);
    await expectLater(
        store.saveClipGroup(restored.copyWith(items: cleared),
            expectedRevision: accepted.revision),
        throwsA(isA<ClipGroupDraftException>()));
    expect((await store.loadClipGroup('group-a'))!.items.first.acceptedPostId,
        'post-a');
  });

  test(
      'a missing unaccepted child remains explicit instead of implying success',
      () async {
    await store.saveDraft(request('original'));
    await store.saveClipGroup(group(), expectedRevision: null);
    final restored = (await store.loadClipGroup('group-a'))!;
    expect(restored.items.map((item) => item.draftId), ['part-0', 'part-1']);
    expect(restored.items.every((item) => !item.isAccepted), isTrue);
    expect(await store.loadDraft('part-0'), isNull);
  });

  test('owner mismatch, unsafe ids and changed identity fail closed', () async {
    await store.saveDraft(request('original'));
    await expectLater(
        store.saveClipGroup(group(owner: 'owner-b'), expectedRevision: null),
        throwsA(isA<ClipGroupDraftException>()));
    await expectLater(
        store.saveClipGroup(group(id: '../escape'), expectedRevision: null),
        throwsA(isA<ClipGroupDraftException>()));
    final saved = await store.saveClipGroup(group(), expectedRevision: null);
    final changed = [...saved.items];
    changed[0] = ClipGroupItem(
        draftId: 'other',
        index: 0,
        sourceStartSeconds: 0,
        sourceEndSeconds: 90,
        platformApiValues: const {'FACEBOOK_REELS'});
    await expectLater(
        store.saveClipGroup(saved.copyWith(items: changed),
            expectedRevision: saved.revision),
        throwsA(isA<ClipGroupDraftException>()));
  });

  test(
      'group lists are owner-bound and account deletion clears group artifacts',
      () async {
    await store.saveDraft(request('original'));
    await store.saveClipGroup(group(), expectedRevision: null);
    expect((await store.listClipGroups()).single.id, 'group-a');
    final other = FilePublishDraftStore(
        rootDirectory: Directory('${root.path}/owners/b'),
        ownerRootBoundary: Directory('${root.path}/owners'),
        ownerUserId: 'owner-b');
    expect(await other.loadClipGroup('group-a'), isNull);
    expect(await other.listClipGroups(), isEmpty);
    await store.deleteAllDrafts();
    expect(await store.loadClipGroup('group-a'), isNull);
    expect(await store.listClipGroups(), isEmpty);
  });

  test('a validated next checkpoint is recovered after interrupted promotion',
      () async {
    await store.saveDraft(request('original'));
    final first = await store.saveClipGroup(group(), expectedRevision: null);
    final next = first.copyWith(
        revision: first.revision + 1, sharedCaption: 'Recovered');
    final path = '${root.path}/owners/a/.clip-groups/group-a.json';
    final target = File(path);
    await target.rename('$path.backup');
    await File('$path.next')
        .writeAsString(jsonEncode(next.toJson()), flush: true);
    expect((await store.loadClipGroup('group-a'))!.sharedCaption, 'Recovered');
    expect(await target.exists(), isTrue);
  });

  test('malformed metadata does not make the ordinary draft disappear',
      () async {
    await store.saveDraft(request('original'));
    final path = File('${root.path}/owners/a/original/manifest.json');
    final json = jsonDecode(await path.readAsString()) as Map<String, dynamic>;
    json['clipGroupId'] = '../unsafe';
    json['isClipGroupSource'] = true;
    await path.writeAsString(jsonEncode(json));
    final restored = (await store.loadDraft('original'))!;
    expect(restored.clipGroupId, isNull);
    expect(restored.isClipGroupSource, isFalse);
  });

  test('a late group create never resurrects a deleted owner root', () async {
    await store.saveDraft(request('original'));
    await store.deleteAllDrafts();
    await expectLater(store.saveClipGroup(group(), expectedRevision: null),
        throwsA(isA<ClipGroupDraftException>()));
    expect(await Directory('${root.path}/owners/a').exists(), isFalse);
  });

  test('create never overwrites an unreadable existing group journal',
      () async {
    await store.saveDraft(request('original'));
    final file = File('${root.path}/owners/a/.clip-groups/group-a.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{broken receipt');
    await expectLater(store.saveClipGroup(group(), expectedRevision: null),
        throwsA(isA<ClipGroupDraftException>()));
    expect(await file.readAsString(), '{broken receipt');
  });

  test('source and member bindings cannot capture another group', () async {
    await store
        .saveDraft(request('original', groupId: 'other-group', isSource: true));
    await expectLater(store.saveClipGroup(group(), expectedRevision: null),
        throwsA(isA<ClipGroupDraftException>()));
    expect((await store.loadDraft('original'))!.clipGroupId, 'other-group');
    await store.saveDraft(request('original'));
    await store.saveDraft(request('part-0', groupId: 'other-group'));
    await expectLater(store.saveClipGroup(group(), expectedRevision: null),
        throwsA(isA<ClipGroupDraftException>()));
    expect((await store.loadDraft('part-0'))!.clipGroupId, 'other-group');
    expect(await store.loadClipGroup('group-a'), isNull);
  });

  test('atomic rollback preserves newer or accepted checkpoints', () async {
    await store.saveDraft(request('original'));
    final initial = await store.saveClipGroup(group(), expectedRevision: null);
    final edited = await store.saveClipGroup(
        initial.copyWith(sharedCaption: 'User edit'),
        expectedRevision: initial.revision);
    expect(
        await store.deleteUnacceptedClipGroup('group-a',
            expectedRevision: initial.revision),
        isFalse);
    final accepted = await store.saveClipGroup(
        edited.copyWith(items: [
          edited.items.first.copyWith(acceptedPostId: 'post-1'),
          edited.items.last,
        ]),
        expectedRevision: edited.revision);
    expect(
        await store.deleteUnacceptedClipGroup('group-a',
            expectedRevision: accepted.revision),
        isFalse);
    expect((await store.loadClipGroup('group-a'))!.items.first.acceptedPostId,
        'post-1');
    final untouched = await store.saveClipGroup(group(id: 'untouched'),
        expectedRevision: null);
    expect(
        await store.deleteUnacceptedClipGroup('untouched',
            expectedRevision: untouched.revision),
        isTrue);
    expect(await store.loadClipGroup('untouched'), isNull);
    expect(await store.loadDraft('original'), isNotNull);
  });

  test('separate store instances serialize competing group checkpoints',
      () async {
    await store.saveDraft(request('original'));
    final current = await store.saveClipGroup(group(), expectedRevision: null);
    final other = FilePublishDraftStore(
        rootDirectory: Directory('${root.path}/owners/a'),
        ownerRootBoundary: Directory('${root.path}/owners'),
        ownerUserId: 'owner-a');
    final results = await Future.wait([
      store
          .saveClipGroup(current.copyWith(sharedCaption: 'a'),
              expectedRevision: 1)
          .then<Object>((value) => value, onError: (Object error) => error),
      other
          .saveClipGroup(current.copyWith(sharedCaption: 'b'),
              expectedRevision: 1)
          .then<Object>((value) => value, onError: (Object error) => error),
    ]);
    expect(results.whereType<ClipGroupDraft>(), hasLength(1));
    expect(results.whereType<ClipGroupDraftConflictException>(), hasLength(1));
    expect((await store.loadClipGroup('group-a'))!.revision, 2);
  });
}
