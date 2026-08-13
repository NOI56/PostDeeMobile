import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store_factory.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('publish-draft-owner-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('fails closed when the auth session has no stable user id', () async {
    final store = await createPublishDraftStoreForSession(
      sessionStore: PostDeeAuthSessionStore(),
      loadSupportDirectory: () async => root,
    );

    expect(store, isNull);
  });

  test('uses filename-safe isolated storage for each stable user id', () async {
    final video = File('${root.path}${Platform.pathSeparator}clip.mp4');
    await video.writeAsBytes([1, 2, 3], flush: true);
    final userA = PostDeeAuthSessionStore(
      initialSession: AuthSession.authenticated(
        userId: 'firebase/user:a',
        idToken: 'token-a',
      ),
    );
    final userB = PostDeeAuthSessionStore(
      initialSession: AuthSession.authenticated(
        userId: 'firebase/user:b',
        idToken: 'token-b',
      ),
    );
    final storeA = await createPublishDraftStoreForSession(
      sessionStore: userA,
      loadSupportDirectory: () async => root,
    );
    final storeB = await createPublishDraftStoreForSession(
      sessionStore: userB,
      loadSupportDirectory: () async => root,
    );

    await storeA!.saveDraft(
      PublishDraftSaveRequest(
        id: 'draft-a',
        createdAt: DateTime.utc(2026, 8, 11),
        updatedAt: DateTime.utc(2026, 8, 11, 1),
        videoFile: video,
        videoName: 'clip.mp4',
        videoSizeBytes: 3,
        caption: '',
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: const {},
      ),
    );

    expect(await storeA.listDrafts(), hasLength(1));
    expect(await storeB!.listDrafts(), isEmpty);
    final paths = await root
        .list(recursive: true, followLinks: false)
        .map((entity) => entity.path.replaceAll('\\', '/'))
        .toList();
    expect(paths.any((path) => path.contains('firebase/user:a')), isFalse);
    expect(paths.any((path) => path.contains('firebase/user:b')), isFalse);
  });
}
