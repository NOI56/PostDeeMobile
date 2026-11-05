import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'uploader_video_english_test.dart';

void main() {
  testWidgets(
      'leaving a saved group returns the empty selector to its top '
      'without changing the original draft or posting', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: videoEnglishOwner, idToken: 'group-exit-token'));
    addTearDown(PostDeeAuthSessionStore.instance.clear);
    final fixture = VideoEnglishFixture()..initialDraftId = 'exit-source';
    addTearDown(fixture.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    for (final id in ['exit-source', 'exit-part']) {
      final video = fixture.makeVideo('$id.mp4', duration: 10);
      await fixture.store.saveDraft(PublishDraftSaveRequest(
          id: id,
          createdAt: now,
          updatedAt: now,
          videoFile: File(video.path),
          videoName: video.name,
          videoSizeBytes: video.sizeBytes,
          videoWidth: 1080,
          videoHeight: 1920,
          caption: 'Shared caption',
          aiGuidance: '',
          watermarkEnabled: false,
          platformApiValues: const {'INSTAGRAM_REELS'},
          clipGroupId: 'exit-group',
          isClipGroupSource: id == 'exit-source'));
    }
    await fixture.store.saveClipGroup(
        ClipGroupDraft(
            id: 'exit-group',
            ownerUserId: videoEnglishOwner,
            sourceDraftId: 'exit-source',
            title: 'Saved group',
            sharedCaption: 'Shared caption',
            deliveryMode: ClipGroupDeliveryMode.immediate,
            createdAt: now,
            updatedAt: now,
            items: [
              ClipGroupItem(
                  draftId: 'exit-part',
                  index: 0,
                  sourceStartSeconds: 0,
                  sourceEndSeconds: 10,
                  platformApiValues: const {'INSTAGRAM_REELS'})
            ]),
        expectedRevision: null);
    final original = fixture.store.drafts['exit-source'];
    await fixture.mount(tester);
    expect(find.byKey(const ValueKey('clip-group-review')), findsOneWidget);
    final scroll = find
        .descendant(
            of: find.byKey(const ValueKey('uploader-scroll'),
                skipOffstage: false),
            matching: find.byType(Scrollable, skipOffstage: false),
            skipOffstage: false)
        .first;
    final position = tester.state<ScrollableState>(scroll).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clip-group-review')), findsNothing);
    final heading = find.byKey(const ValueKey('uploader-step-video'));
    final picker = find.text('Choose a 9:16 video');
    expect(heading, findsOneWidget);
    expect(picker, findsOneWidget);
    final viewport =
        tester.getRect(find.byKey(const ValueKey('uploader-scroll')));
    expect(tester.getRect(heading).top, greaterThanOrEqualTo(viewport.top));
    final pickerAction = find.ancestor(
        of: picker,
        matching: find.byWidgetPredicate(
            (widget) => widget is InkWell || widget is GestureDetector)).first;
    expect(tester.getRect(pickerAction).overlaps(viewport), isTrue);
    expect(find.text('The clip set is saved. Continue from Drafts.'),
        findsOneWidget);
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(fixture.picks, 1);
    expect(fixture.store.drafts['exit-source'], same(original));
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });
}
