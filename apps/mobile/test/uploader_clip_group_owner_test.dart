import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'uploader_video_english_test.dart'
    show VideoEnglishFixture, videoEnglishOwner, revealVideoEnglishControl;

const _privateCaption = 'Private caption belonging to the original owner';

class _Fixture extends VideoEnglishFixture {
  _Fixture() : ownerBinding = PostDeeAuthSessionStore.instance.captureSession();

  final AuthSessionBinding ownerBinding;
  late final String privateVideoPath;

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await super.mount(tester, settle: settle);
  }

  Future<void> seed() async {
    final video = makeVideo('owner-private-part.mp4');
    privateVideoPath = video.path;
    initialDraftId = 'private-part';
    final now = DateTime.utc(2026, 11, 5);
    await store.saveDraft(PublishDraftSaveRequest(
        id: initialDraftId!,
        createdAt: now,
        updatedAt: now,
        videoFile: File(video.path),
        videoName: video.name,
        videoSizeBytes: video.sizeBytes,
        videoWidth: video.width,
        videoHeight: video.height,
        caption: _privateCaption,
        aiGuidance: 'Private product details',
        watermarkEnabled: false,
        platformApiValues: const {'FACEBOOK_REELS'},
        clipGroupId: 'private-group'));
    store.savedRequests.clear();
    store.saveAttempts = 0;
  }

  @override
  UploaderScreen screen() => UploaderScreen(
        fullScreen: true,
        initialDraftId: initialDraftId,
        draftStore: store,
        clipGroupEditor: true,
        clipGroupOwnerSession: ownerBinding,
        enableRevenueCatBilling: false,
        readVideoMetadata: (_) async => const VideoDimensions(
            width: 1080, height: 1920, durationSeconds: 10),
        probePublishMedia: probeValidPublishMedia,
        loadTemplates: () async => const [],
        loadSubscription: () async => quota,
        loadPostQuota: () async => quota,
        loadCaptionQuota: () async => const CaptionQuotaResult(
            plan: 'PRO',
            quota: RealClipCaptionQuota(
                limit: 120, usedThisMonth: 0, remainingThisMonth: 120)),
        loadSocialConnections: () async => const [
          SocialConnectionResult(
              platform: 'FACEBOOK_REELS',
              connected: true,
              connectionId: 'owner-facebook',
              externalAccountId: 'owner-page',
              displayName: 'Original owner page'),
        ],
        loadSocialPublishingReadiness: () async => const [],
        createUpload: (_) async {
          apiWrites++;
          throw StateError('A stale member editor must not upload');
        },
        uploadVideoFile: (_, __) async {
          apiWrites++;
        },
        generateRealClipCaption: (_) async {
          apiWrites++;
          throw StateError('A stale member editor must not generate AI');
        },
        createPost: (_) async {
          apiWrites++;
          throw StateError('A member editor must never publish');
        },
      );
}

Finder _key(String value) => find.byKey(ValueKey(value));

void _expectPrivateFormCleared(WidgetTester tester, _Fixture fixture) {
  for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
    expect(field.controller?.text, isNot(_privateCaption));
    expect(field.controller?.text, isNot(fixture.privateVideoPath));
    expect(field.controller?.text, isNot('Private product details'));
  }
}

Future<void> _tryAiWithoutPrivateMedia(
    WidgetTester tester, _Fixture fixture) async {
  final ai = _key('uploader-ai-generate-button');
  if (ai.evaluate().isNotEmpty) {
    final button = tester.widget(ai);
    if (button is PostDeeGradientButton) {
      button.onPressed?.call();
    } else if (button is OutlinedButton) {
      button.onPressed?.call();
    } else {
      fail('Unknown AI control cannot prove stale media is blocked');
    }
    await tester.pumpAndSettle();
  }
  expect(fixture.apiWrites, 0);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: videoEnglishOwner, idToken: 'original-owner-token'));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  for (final sameOwner in [false, true]) {
    testWidgets(
        sameOwner
            ? 'injected member editor clears old media after same uid signs in again'
            : 'injected member editor clears old media when account changes',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.seed();
      await fixture.mount(tester);
      await revealVideoEnglishControl(tester, _key('uploader-caption-field'));
      expect(
          tester
              .widget<TextField>(_key('uploader-caption-field'))
              .controller!
              .text,
          _privateCaption);
      final save = tester
          .widget<FilledButton>(_key('clip-group-member-save'))
          .onPressed!;
      if (sameOwner) PostDeeAuthSessionStore.instance.clear();
      PostDeeAuthSessionStore.instance.signIn(AuthSession(
          userId: sameOwner ? videoEnglishOwner : 'replacement-owner',
          idToken: 'replacement-lifecycle-token'));
      await tester.pumpAndSettle();
      _expectPrivateFormCleared(tester, fixture);
      await _tryAiWithoutPrivateMedia(tester, fixture);
      // A callback retained by an in-flight interaction cannot save the old
      // owner's media after the route's owner lifecycle became invalid.
      if (find.byType(UploaderScreen).evaluate().isNotEmpty) {
        save();
        await tester.pumpAndSettle();
      }
      expect(fixture.store.saveAttempts, 0);
      expect(fixture.store.drafts['private-part']!.caption, _privateCaption);
      expect(fixture.apiWrites, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an already invalid owner binding cannot restore a member',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    PostDeeAuthSessionStore.instance.clear();
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: videoEnglishOwner, idToken: 'new-sign-in-same-owner'));
    await fixture.mount(tester);
    _expectPrivateFormCleared(tester, fixture);
    await _tryAiWithoutPrivateMedia(tester, fixture);
    expect(fixture.store.saveAttempts, 0);
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late member save cannot return an old draft under a new owner',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.mount(tester);
    final route = ModalRoute.of(tester.element(find.byType(UploaderScreen)))!;
    Object? returned;
    unawaited(route.popped.then((value) => returned = value));
    final gate = Completer<void>();
    fixture.store.saveGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.tap(_key('clip-group-member-save'));
    await tester.pump();
    expect(fixture.store.saveAttempts, 1);
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: 'replacement-owner', idToken: 'other-account-token'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(returned, isNull);
    _expectPrivateFormCleared(tester, fixture);
    await _tryAiWithoutPrivateMedia(tester, fixture);
    expect(fixture.store.saveAttempts, 1);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(
        fixture.store.drafts['private-part']!.ownerUserId, videoEnglishOwner);
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });
}
