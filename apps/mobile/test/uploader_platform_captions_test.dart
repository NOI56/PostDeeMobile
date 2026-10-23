import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _mode = ValueKey('uploader-platform-captions-toggle');
const _main = ValueKey('uploader-caption-field');
Finder _field(String platform) =>
    find.byKey(ValueKey('uploader-caption-$platform'));

RealClipCaptionResult _result({List<String> platforms = _platforms}) =>
    RealClipCaptionResult.fromJson({
      'caption': 'ข้อความกลางจาก AI',
      'captionOptions': <String>[],
      'hooks': <String>[],
      'hashtags': <String>[],
      'seoKeywords': <String>[],
      'searchTitle': 'รีวิวคลิป',
      'source': <String, Object?>{
        'videoS3Key': 'uploads/owner-a/clip.mp4',
        'mode': 'AUDIO_ONLY',
        'selectedFrameCount': 0,
      },
      'quota': <String, Object?>{
        'limit': 50,
        'usedThisMonth': 1,
        'remainingThisMonth': 49,
      },
      'platformCaptions': <String, Object?>{
        for (final platform in platforms)
          platform: <String, Object?>{
            'caption': 'AI สำหรับ $platform',
            'hashtags': <String>['#รีวิว'],
          },
      },
    });

const _platforms = [
  'TIKTOK',
  'YOUTUBE_SHORTS',
  'INSTAGRAM_REELS',
  'FACEBOOK_REELS',
];

class _Fixture {
  _Fixture() {
    file = File('${Directory.systemTemp.path}/postdee-platform-captions-'
        '${DateTime.now().microsecondsSinceEpoch}.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
  }

  late final File file;
  final store = TestPublishDraftStore(ownerUserId: 'owner-a');
  final requests = <GenerateRealClipCaptionRequest>[];
  Completer<RealClipCaptionResult>? gate;
  RealClipCaptionResult Function()? response;
  int uploadCount = 0;
  double textScale = 1;
  String? initialDraftId;

  Future<void> seedReviewDraft() async {
    final draft = await store.saveDraft(PublishDraftSaveRequest(
      id: 'review-draft',
      createdAt: DateTime.utc(2026, 10, 23),
      updatedAt: DateTime.utc(2026, 10, 23),
      videoFile: file,
      videoName: 'clip.mp4',
      videoSizeBytes: 512,
      videoWidth: 1080,
      videoHeight: 1920,
      caption: 'ข้อความหลัก',
      captionNeedsReview: true,
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: const {},
      platformSettings: const PlatformPublishSettings(
        usePlatformCaptions: true,
        aiCaptionPlatforms: {SocialPlatform.youtubeShorts},
        platformCaptions: {
          SocialPlatform.tiktok: 'ข้อความเดิมจากคลิปเก่า',
          SocialPlatform.youtubeShorts: 'ข้อความเดิม YouTube',
        },
      ),
    ));
    initialDraftId = draft.id;
  }

  Widget app() => MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: UploaderScreen(
            draftStore: store,
            initialDraftId: initialDraftId,
            initialVideoPath: initialDraftId == null ? file.path : null,
            initialVideoName: initialDraftId == null ? 'clip.mp4' : null,
            initialVideoSizeBytes: initialDraftId == null ? 512 : null,
            initialVideoWidth: initialDraftId == null ? 1080 : null,
            initialVideoHeight: initialDraftId == null ? 1920 : null,
            probePublishMedia: probeValidPublishMedia,
            loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
            loadSocialConnections: () async => const [],
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'owner-a',
              plan: 'STARTER',
              status: 'ACTIVE',
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            createUpload: (request) async {
              uploadCount++;
              return UploadResult(
                  id: 'upload',
                  videoS3Key: 'uploads/owner-a/${request.fileName}',
                  storageProvider: 's3');
            },
            uploadVideoFile: (_, __) async {},
            generateRealClipCaption: (request) async {
              requests.add(request);
              return gate?.future ?? response?.call() ?? _result();
            },
          ),
        ),
      );
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 250, scrollable: uploaderMainScroll);
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pump(const Duration(milliseconds: 350));
  if (find
      .byKey(const ValueKey('uploader-ai-waiting-indicator'))
      .evaluate()
      .isEmpty) {
    await tester.pumpAndSettle();
  }
}

Future<void> _start(WidgetTester tester, _Fixture fixture) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await goToUploaderStep(tester, 1);
}

Future<void> _toggle(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _show(tester, find.byKey(_mode));
  await tester.tap(find.byKey(_mode));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

Future<void> _selectTargets(WidgetTester tester, List<String> platforms) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  for (final platform in platforms) {
    final chip = find.byKey(ValueKey('ai-caption-target-$platform'));
    await _show(tester, chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }
}

Future<void> _generate(WidgetTester tester,
    {bool pending = false, bool selectAll = true}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (selectAll) {
    final all = find.byKey(const ValueKey('ai-caption-select-all'));
    await _show(tester, all);
    await tester.tap(all);
    await tester.pumpAndSettle();
  }
  final button = find.byKey(const ValueKey('uploader-ai-generate-button'));
  await _show(tester, button);
  await tester.tap(button);
  if (pending) {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
  });

  testWidgets('advanced hides shared caption and preserves all four drafts',
      (tester) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await tester.enterText(find.byKey(_main), 'แคปชั่นหลักเดิม');
    await _toggle(tester);
    expect(find.byKey(_main), findsNothing);
    for (final platform in _platforms) {
      await _show(tester, _field(platform));
      expect(_text(tester, _field(platform)), 'แคปชั่นหลักเดิม');
      await tester.enterText(_field(platform), 'เขียนเอง $platform');
    }
    await _toggle(tester);
    expect(_text(tester, find.byKey(_main)), 'แคปชั่นหลักเดิม');
    await _toggle(tester);
    for (final platform in _platforms) {
      expect(_text(tester, _field(platform)), 'เขียนเอง $platform');
    }
    expect(fixture.requests, isEmpty);
  });

  testWidgets(
      'advanced starts without AI targets and cannot upload or generate',
      (tester) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _toggle(tester);
    for (final platform in _platforms) {
      expect(
          tester
              .widget<FilterChip>(
                  find.byKey(ValueKey('ai-caption-target-$platform')))
              .selected,
          isFalse);
    }
    final button = find.byKey(const ValueKey('uploader-ai-generate-button'));
    await _show(tester, button);
    expect(tester.widget<PostDeeGradientButton>(button).onPressed, isNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadCount, 0);
  });

  testWidgets('one chosen target previews and applies only that caption',
      (tester) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await tester.enterText(find.byKey(_main), 'เขียนเองทุกช่อง');
    await _toggle(tester);
    await _selectTargets(tester, ['YOUTUBE_SHORTS']);
    await _generate(tester, selectAll: false);
    expect(fixture.requests.single.toJson()['platforms'], ['YOUTUBE_SHORTS']);
    final preview = find.byKey(const ValueKey('uploader-platform-ai-preview'));
    expect(preview, findsOneWidget);
    expect(
        find.descendant(
            of: preview, matching: find.textContaining('AI สำหรับ TIKTOK')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-platform-ai-apply')));
    await tester.pumpAndSettle();
    expect(_text(tester, _field('YOUTUBE_SHORTS')),
        'AI สำหรับ YOUTUBE_SHORTS\n\n#รีวิว');
    for (final platform in ['TIKTOK', 'INSTAGRAM_REELS', 'FACEBOOK_REELS']) {
      expect(_text(tester, _field(platform)), 'เขียนเองทุกช่อง');
    }
    await _toggle(tester);
    await _toggle(tester);
    expect(
        tester
            .widget<FilterChip>(
                find.byKey(const ValueKey('ai-caption-target-YOUTUBE_SHORTS')))
            .selected,
        isTrue);
    expect(
        tester
            .widget<FilterChip>(
                find.byKey(const ValueKey('ai-caption-target-TIKTOK')))
            .selected,
        isFalse);
  });

  testWidgets('two targets preserve unrelated edits during generation and undo',
      (tester) async {
    final fixture = _Fixture()..gate = Completer<RealClipCaptionResult>();
    await _start(tester, fixture);
    await tester.enterText(find.byKey(_main), 'ข้อความเดิม');
    await _toggle(tester);
    await _selectTargets(tester, ['INSTAGRAM_REELS', 'TIKTOK']);
    await _generate(tester, selectAll: false, pending: true);
    expect(fixture.requests.single.toJson()['platforms'],
        ['TIKTOK', 'INSTAGRAM_REELS']);
    expect(
        tester
            .widget<FilterChip>(
                find.byKey(const ValueKey('ai-caption-target-TIKTOK')))
            .onSelected,
        isNull);
    await _show(tester, _field('YOUTUBE_SHORTS'));
    await tester.enterText(_field('YOUTUBE_SHORTS'), 'แก้ YouTube ระหว่างรอ');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    fixture.gate!.complete(_result());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('uploader-platform-ai-apply')));
    await tester.pumpAndSettle();
    expect(_text(tester, _field('YOUTUBE_SHORTS')), 'แก้ YouTube ระหว่างรอ');
    expect(_text(tester, _field('TIKTOK')), 'AI สำหรับ TIKTOK\n\n#รีวิว');
    await _show(tester, _field('FACEBOOK_REELS'));
    await tester.enterText(_field('FACEBOOK_REELS'), 'แก้ Facebook หลังใช้ AI');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final undo = find.byKey(const ValueKey('uploader-platform-ai-undo'));
    await _show(tester, undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(_text(tester, _field('TIKTOK')), 'ข้อความเดิม');
    expect(_text(tester, _field('INSTAGRAM_REELS')), 'ข้อความเดิม');
    expect(_text(tester, _field('YOUTUBE_SHORTS')), 'แก้ YouTube ระหว่างรอ');
    expect(_text(tester, _field('FACEBOOK_REELS')), 'แก้ Facebook หลังใช้ AI');
  });

  testWidgets('missing a requested result never replaces any caption',
      (tester) async {
    final fixture = _Fixture()..response = () => _result(platforms: ['TIKTOK']);
    await _start(tester, fixture);
    await tester.enterText(find.byKey(_main), 'เก็บข้อความเดิม');
    await _toggle(tester);
    await _selectTargets(tester, ['TIKTOK', 'YOUTUBE_SHORTS']);
    await _generate(tester, selectAll: false);
    expect(fixture.requests, hasLength(1));
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsNothing);
    expect(find.textContaining('ระบบ AI ยังส่งแคปชั่นไม่ครบช่องทางที่เลือก'),
        findsOneWidget);
    for (final platform in _platforms) {
      expect(_text(tester, _field(platform)), 'เก็บข้อความเดิม');
    }
  });

  testWidgets('saved draft restores AI targets after reopening the composer',
      (tester) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await tester.enterText(find.byKey(_main), 'แคปชั่นในร่าง');
    await _toggle(tester);
    await _selectTargets(tester, ['YOUTUBE_SHORTS', 'FACEBOOK_REELS']);
    final save = find.byKey(const ValueKey('uploader-save-draft-button'));
    await _show(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(fixture.store.drafts, hasLength(1));
    final draft = fixture.store.drafts.values.single;
    expect(draft.platformApiValues, isEmpty,
        reason: 'AI selection must not select publishing destinations');
    fixture.initialDraftId = draft.id;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    for (final platform in _platforms) {
      expect(
          tester
              .widget<FilterChip>(
                  find.byKey(ValueKey('ai-caption-target-$platform')))
              .selected,
          ['YOUTUBE_SHORTS', 'FACEBOOK_REELS'].contains(platform));
      expect(_text(tester, _field(platform)), 'แคปชั่นในร่าง');
    }
    expect(fixture.requests, isEmpty);
  });

  testWidgets('partial AI generation keeps the review gate for other captions',
      (tester) async {
    final fixture = _Fixture();
    await fixture.seedReviewDraft();
    await _start(tester, fixture);
    await _generate(tester, selectAll: false);
    await tester.tap(find.byKey(const ValueKey('uploader-platform-ai-apply')));
    await tester.pumpAndSettle();
    expect(_text(tester, _field('YOUTUBE_SHORTS')),
        'AI สำหรับ YOUTUBE_SHORTS\n\n#รีวิว');
    expect(_text(tester, _field('TIKTOK')), 'ข้อความเดิมจากคลิปเก่า');
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsOneWidget);
  });

  testWidgets('one AI request previews four captions before replacing text',
      (tester) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _toggle(tester);
    await tester.enterText(_field('TIKTOK'), 'ข้อความที่พิมพ์ไว้');
    await _generate(tester);
    expect(fixture.requests, hasLength(1));
    expect(fixture.requests.single.toJson()['platforms'], _platforms);
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsOneWidget);
    expect(_text(tester, _field('TIKTOK')), 'ข้อความที่พิมพ์ไว้');
    await tester.tap(find.byKey(const ValueKey('uploader-platform-ai-apply')));
    await tester.pumpAndSettle();
    for (final platform in _platforms) {
      expect(_text(tester, _field(platform)), 'AI สำหรับ $platform\n\n#รีวิว');
    }
    await _show(tester, _field('TIKTOK'));
    await tester.enterText(_field('TIKTOK'), 'แก้หลังใช้ AI');
    expect(_text(tester, _field('TIKTOK')), 'แก้หลังใช้ AI');
    await _toggle(tester);
    await _toggle(tester);
    final undo = find.byKey(const ValueKey('uploader-platform-ai-undo'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _show(tester, undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(_text(tester, _field('TIKTOK')), 'ข้อความที่พิมพ์ไว้');
  });

  testWidgets('manual changes during AI generation are not overwritten',
      (tester) async {
    final fixture = _Fixture()..gate = Completer<RealClipCaptionResult>();
    await _start(tester, fixture);
    await _toggle(tester);
    await _generate(tester, pending: true);
    await _show(tester, _field('TIKTOK'));
    await tester.enterText(_field('TIKTOK'), 'ข้อความใหม่ระหว่างรอ');
    fixture.gate!.complete(_result());
    await tester.pumpAndSettle();
    expect(_text(tester, _field('TIKTOK')), 'ข้อความใหม่ระหว่างรอ');
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsNothing);
  });

  testWidgets('dismissing AI preview keeps the manually written captions',
      (tester) async {
    await _start(tester, _Fixture());
    await _toggle(tester);
    await tester.enterText(_field('TIKTOK'), 'ยังไม่ใช้ AI');
    await _generate(tester);
    await tester.tap(find.byTooltip('กลับไปเขียนเอง'));
    await tester.pumpAndSettle();
    expect(_text(tester, _field('TIKTOK')), 'ยังไม่ใช้ AI');
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsNothing);
  });

  testWidgets('leaving advanced mode rejects a late AI response',
      (tester) async {
    final fixture = _Fixture()..gate = Completer<RealClipCaptionResult>();
    await _start(tester, fixture);
    await tester.enterText(find.byKey(_main), 'หลัก');
    await _toggle(tester);
    await _generate(tester, pending: true);
    await _show(tester, find.byKey(_mode));
    await tester.tap(find.byKey(_mode));
    await tester.pump();
    fixture.gate!.complete(_result());
    await tester.pumpAndSettle();
    expect(_text(tester, find.byKey(_main)), 'หลัก');
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsNothing);
  });

  testWidgets('changing owner dismisses an open AI preview without applying',
      (tester) async {
    await _start(tester, _Fixture());
    await _toggle(tester);
    await _generate(tester);
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsOneWidget);
    PostDeeAuthSessionStore.instance.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsNothing);
  });

  testWidgets('four caption cards and AI preview fit a narrow large-text phone',
      (tester) async {
    final fixture = _Fixture()..textScale = 1.7;
    await _start(tester, fixture);
    await tester.binding.setSurfaceSize(const Size(320, 900));
    await tester.pumpAndSettle();
    await _toggle(tester);
    for (final platform in _platforms) {
      await _show(tester, _field(platform));
      await tester.enterText(_field(platform), 'ข้อความของฉัน $platform');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _generate(tester);
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('กลับไปเขียนเอง'));
    await tester.pumpAndSettle();
  });
}
