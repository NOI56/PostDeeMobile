import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'uploader_video_english_test.dart'
    show VideoEnglishFixture, videoEnglishOwner;

class _RouteFixture extends VideoEnglishFixture {
  _RouteFixture({required super.locale, required super.dark}) {
    initialDraftId = 'material-source';
  }

  Future<void> seed() async {
    final now = DateTime.now().toUtc();
    for (final id in ['material-source', 'material-part']) {
      final video = makeVideo('$id.mp4');
      await store.saveDraft(PublishDraftSaveRequest(
          id: id,
          createdAt: now,
          updatedAt: now,
          videoFile: File(video.path),
          videoName: video.name,
          videoSizeBytes: video.sizeBytes,
          videoWidth: video.width,
          videoHeight: video.height,
          caption: 'Shared group caption',
          aiGuidance: '',
          watermarkEnabled: false,
          platformApiValues: const {'INSTAGRAM_REELS'},
          clipGroupId: 'material-group',
          isClipGroupSource: id == 'material-source'));
    }
    await store.saveClipGroup(
        ClipGroupDraft(
            id: 'material-group',
            ownerUserId: videoEnglishOwner,
            sourceDraftId: 'material-source',
            title: 'Material route group',
            sharedCaption: 'Shared group caption',
            deliveryMode: ClipGroupDeliveryMode.immediate,
            createdAt: now,
            updatedAt: now,
            items: [
              ClipGroupItem(
                  draftId: 'material-part',
                  index: 0,
                  sourceStartSeconds: 0,
                  sourceEndSeconds: 10,
                  platformApiValues: const {'INSTAGRAM_REELS'})
            ]),
        expectedRevision: null);
  }
}

void _expectRouteMaterial(WidgetTester tester, Finder content) {
  expect(tester.takeException(), isNull);
  expect(content, findsOneWidget);
  expect(find.ancestor(of: content, matching: find.byType(Scaffold)),
      findsOneWidget);
  expect(find.ancestor(of: content, matching: find.byType(Material)),
      findsWidgets);
  final context = tester.element(content);
  expect(ModalRoute.of(context)!.isCurrent, isTrue);
  final inheritedStyle = DefaultTextStyle.of(context).style;
  expect(inheritedStyle.fontSize, lessThan(48),
      reason: 'A pushed member editor must not inherit the debug text style');
  expect(inheritedStyle.decoration, isNot(TextDecoration.underline));
}

void main() {
  for (final captionRoute in [true, false]) {
    testWidgets(
        'real group ${captionRoute ? 'caption AI' : 'channels'} route supplies '
        'Material and app typography (${captionRoute ? 'Thai light' : 'English dark'})',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final previous = PostDeeAuthSessionStore.instance.session;
      PostDeeAuthSessionStore.instance.signIn(const AuthSession(
          userId: videoEnglishOwner, idToken: 'material-route-token'));
      addTearDown(() {
        PostDeeAuthSessionStore.instance.signIn(previous);
        AppTheme.applyThemeMode(ThemeMode.light);
      });
      final fixture = _RouteFixture(
          locale: Locale(captionRoute ? 'th' : 'en'), dark: !captionRoute);
      addTearDown(fixture.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await fixture.seed();
      final source = fixture.store.drafts['material-source'];
      await fixture.mount(tester);
      expect(find.byKey(const ValueKey('uploader-step-caption')), findsOneWidget);
      expect(find.byType(UploaderScreen), findsOneWidget,
          reason: 'The original uploader owns the normal caption page');

      for(var step=0;step<2;step++) {
        final next=find.byKey(const ValueKey('uploader-wizard-next'));
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('clip-group-review')), findsOneWidget);

      final action = find.byKey(ValueKey(captionRoute
          ? 'clip-group-ai-material-part'
          : 'clip-group-edit-material-part'));
      final groupScroll = find
          .descendant(
              of: find.byKey(const ValueKey('clip-group-scroll')),
              matching: find.byType(Scrollable))
          .first;
      expect(fixture.apiWrites, 0);
      expect(fixture.store.drafts['material-source'], same(source));
      await tester.scrollUntilVisible(action, 240, scrollable: groupScroll);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      if (!captionRoute) {
        await tester.tap(find.text('Channel settings'));
        await tester.pumpAndSettle();
      }

      _expectRouteMaterial(
          tester,
          find.byKey(ValueKey(captionRoute
              ? 'uploader-caption-field'
              : 'uploader-step-body-2')));
      if (captionRoute) {
        final caption = find.byKey(const ValueKey('uploader-caption-field'));
        await tester.enterText(caption, 'Typed without invoking AI');
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(caption).controller!.text,
            'Typed without invoking AI');
      }
      expect(fixture.apiWrites, 0);
      expect(fixture.store.drafts['material-source'], same(source));
      expect(tester.takeException(), isNull);
    });
  }
}
