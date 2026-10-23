import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _mode = ValueKey('uploader-platform-captions-toggle');
const _main = ValueKey('uploader-caption-field');
Finder _field(String platform) =>
    find.byKey(ValueKey('uploader-caption-$platform'));

RealClipCaptionResult _result() => RealClipCaptionResult.fromJson({
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
        for (final platform in _platforms)
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
  double textScale = 1;

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
            initialVideoPath: file.path,
            initialVideoName: 'clip.mp4',
            initialVideoSizeBytes: 512,
            initialVideoWidth: 1080,
            initialVideoHeight: 1920,
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
            createUpload: (request) async => UploadResult(
                id: 'upload',
                videoS3Key: 'uploads/owner-a/${request.fileName}',
                storageProvider: 's3'),
            uploadVideoFile: (_, __) async {},
            generateRealClipCaption: (request) async {
              requests.add(request);
              return gate?.future ?? _result();
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

Future<void> _generate(WidgetTester tester, {bool pending = false}) async {
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
