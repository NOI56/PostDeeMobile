import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

class _HomeDraftStore extends TestPublishDraftStore {
  _HomeDraftStore() : super(ownerUserId: 'home-owner');

  Future<PublishDraft?> Function(String)? load;
  final loadedIds = <String>[];

  @override
  Future<PublishDraft?> loadDraft(String draftId) async {
    loadedIds.add(draftId);
    return load == null ? super.loadDraft(draftId) : load!(draftId);
  }
}

void _signIn([String owner = 'home-owner']) {
  PostDeeAuthSessionStore.instance.signIn(
    AuthSession(userId: owner, idToken: 'test-token'),
  );
}

File _video() {
  final root = Directory.systemTemp.createTempSync('home-draft-test-');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  return File('${root.path}${Platform.pathSeparator}clip.mp4')
    ..writeAsBytesSync(List.filled(128, 1));
}

PublishDraft _draft(File video, {String owner = 'home-owner'}) => PublishDraft(
      version: publishDraftManifestVersion,
      id: 'latest-draft',
      ownerUserId: owner,
      submissionRequestId: 'submit_${List.filled(64, 'a').join()}',
      createdAt: DateTime.utc(2026, 10, 10),
      updatedAt: DateTime.utc(2026, 10, 11),
      videoPath: video.path,
      videoName: 'ร่างล่าสุด.mp4',
      videoSizeBytes: video.lengthSync(),
      videoWidth: 1080,
      videoHeight: 1920,
      caption: 'แคปชันของฉบับร่าง',
      aiGuidance: 'พูดคุยเป็นกันเอง',
      watermarkEnabled: false,
      platformApiValues: const {},
    );

Widget _app(_HomeDraftStore store, {File? initialVideo}) => MaterialApp(
      home: Scaffold(
        body: UploaderScreen(
          probePublishMedia: probeValidPublishMedia,
          loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
          draftStore: store,
          initialDraftId: 'latest-draft',
          loadSocialConnections: () async => const [],
          initialVideoPath: initialVideo?.path,
          initialVideoName: initialVideo == null ? null : 'เลือกใหม่.mp4',
          initialVideoSizeBytes: initialVideo?.lengthSync(),
          initialVideoWidth: initialVideo == null ? null : 1080,
          initialVideoHeight: initialVideo == null ? null : 1920,
        ),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _signIn();
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets(
      'Home resume reloads and restores the saved draft without writing',
      (tester) async {
    final video = _video();
    final store = _HomeDraftStore();
    store.drafts['latest-draft'] = _draft(video);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text('ร่างล่าสุด.mp4'), findsOneWidget);
    await goToUploaderStep(tester, 1);
    final caption = tester.widget<TextField>(
      find.byKey(const ValueKey('uploader-caption-field')),
    );
    expect(caption.controller!.text, 'แคปชันของฉบับร่าง');
    expect(store.loadedIds, ['latest-draft']);
    expect(store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final unavailable in ['deleted', 'load-error']) {
    testWidgets('Home resume $unavailable leaves the saved-draft picker usable',
        (tester) async {
      final store = _HomeDraftStore();
      if (unavailable == 'load-error') {
        store.load =
            (_) async => throw const FileSystemException('read failed');
      }
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('uploader-open-drafts')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('เปิดฉบับร่าง'), findsWidgets);
      expect(store.savedRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home resume never restores a draft belonging to another owner',
      (tester) async {
    final video = _video();
    final store = _HomeDraftStore();
    store.drafts['latest-draft'] = _draft(video, owner: 'other-owner');
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text('ร่างล่าสุด.mp4'), findsNothing);
    expect(find.textContaining('บัญชี'), findsWidgets);
    expect(store.savedRequests, isEmpty);
  });

  testWidgets('Home resume ignores a late draft after the account changes',
      (tester) async {
    final video = _video();
    final pending = Completer<PublishDraft?>();
    final store = _HomeDraftStore()..load = (_) => pending.future;
    await tester.pumpWidget(_app(store));
    await tester.pump();
    await tester.pump();
    expect(store.loadedIds, ['latest-draft']);
    _signIn('other-owner');
    pending.complete(_draft(video));
    await tester.pumpAndSettle();
    expect(find.text('ร่างล่าสุด.mp4'), findsNothing);
    expect(store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home resume preserves an explicitly handed-over clip',
      (tester) async {
    final video = _video();
    final store = _HomeDraftStore();
    store.drafts['latest-draft'] = _draft(video);
    await tester.pumpWidget(_app(store, initialVideo: video));
    await tester.pumpAndSettle();
    expect(find.text('เลือกใหม่.mp4'), findsOneWidget);
    expect(store.loadedIds, isEmpty);
    await goToUploaderStep(tester, 1);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('uploader-caption-field')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(store.savedRequests, isEmpty);
  });

  testWidgets('Home resume ignores completion after the composer is disposed',
      (tester) async {
    final video = _video();
    final pending = Completer<PublishDraft?>();
    final store = _HomeDraftStore()..load = (_) => pending.future;
    await tester.pumpWidget(_app(store));
    await tester.pump();
    await tester.pump();
    expect(store.loadedIds, ['latest-draft']);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    pending.complete(_draft(video));
    await tester.pumpAndSettle();
    expect(find.text('ร่างล่าสุด.mp4'), findsNothing);
    expect(store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home resume times out without applying a later draft response',
      (tester) async {
    final video = _video();
    final pending = Completer<PublishDraft?>();
    final store = _HomeDraftStore()..load = (_) => pending.future;
    await tester.pumpWidget(_app(store));
    await tester.pump();
    await tester.pump();
    expect(find.text('กำลังเปิดฉบับร่าง...'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('uploader-open-drafts')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('เปิดฉบับร่างไม่สำเร็จ'), findsWidgets);
    pending.complete(_draft(video));
    await tester.pumpAndSettle();
    expect(find.text('ร่างล่าสุด.mp4'), findsNothing);
    expect(store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
