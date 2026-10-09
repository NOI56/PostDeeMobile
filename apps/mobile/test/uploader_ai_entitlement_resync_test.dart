import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/config/app_config.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _captionKey = ValueKey('uploader-caption-field');
const _guidanceKey = ValueKey('uploader-ai-guidance-field');
const _generateKey = ValueKey('uploader-ai-generate-button');
const _verificationFailure = 'ตรวจสอบสิทธิ์แพ็กเกจไม่สำเร็จ กรุณาลองใหม่';
const _paidRequired =
    'AI แคปชั่นใช้ได้ในแพ็กเกจ Starter หรือ Pro กรุณาตรวจสอบแพ็กเกจของคุณ';

PickedVideoFile _video(String name) {
  final path = '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'postdee-ai-resync-${DateTime.now().microsecondsSinceEpoch}-$name';
  final file = File(path)..writeAsBytesSync(List<int>.filled(512, 1));
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });
  return PickedVideoFile(
    path: path,
    name: name,
    sizeBytes: file.lengthSync(),
    width: 1080,
    height: 1920,
  );
}

SubscriptionStatusResult _subscription(String plan) => SubscriptionStatusResult(
      userId: 'owner-a',
      plan: plan,
      status: plan == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
      canUseAiCaptions: plan != 'BASIC',
      canSchedule: plan != 'BASIC',
      canUseAnalytics: plan == 'PRO',
    );

RealClipCaptionResult _captionResult() => const RealClipCaptionResult(
      caption: 'แคปชั่นที่ยืนยันสิทธิ์แล้ว',
      captionOptions: [],
      hooks: [],
      hashtags: [],
      seoKeywords: [],
      searchTitle: 'คลิป',
      source: RealClipCaptionSource(
        videoS3Key: 'uploads/owner-a/clip.mp4',
        mode: 'AUDIO_ONLY',
        selectedFrameCount: 0,
      ),
      quota: RealClipCaptionQuota(
        limit: 50,
        usedThisMonth: 1,
        remainingThisMonth: 49,
      ),
    );

class _ResyncFixture {
  _ResyncFixture({
    this.plans = const ['BASIC', 'PRO'],
    this.enabled = true,
    this.load,
    this.resync,
  }) : video = _video('clip.mp4');

  final PickedVideoFile video;
  final List<String> plans;
  final bool enabled;
  final Future<SubscriptionStatusResult> Function(int call)? load;
  final Future<void> Function()? resync;
  final List<String> events = [];
  final List<CreateUploadRequest> uploads = [];
  final List<GenerateRealClipCaptionRequest> captions = [];
  final List<String> uploadedPaths = [];
  PickedVideoFile? replacement;
  int loads = 0;
  int resyncs = 0;
  int extractions = 0;

  Future<SubscriptionStatusResult> _load() async {
    loads++;
    events.add('get-$loads');
    return load?.call(loads) ??
        _subscription(plans[(loads - 1).clamp(0, plans.length - 1)]);
  }

  Future<void> _resync() async {
    resyncs++;
    events.add('resync');
    await resync?.call();
  }

  Widget app() {
    final uploader = UploaderScreen(
      draftStore: TestPublishDraftStore(),
      loadSocialConnections: () async => const [],
      loadSubscription: _load,
      resyncRevenueCatSubscription: _resync,
      enableRevenueCatBilling: enabled,
      pickVideo: () async => replacement ?? video,
      extractFrames: (_, {int maxFrames = 3}) async {
        extractions++;
        expect(maxFrames, 3);
        return [File(_video('frame.jpg').path)];
      },
      createUpload: (request) async {
        events.add('upload');
        uploads.add(request);
        return UploadResult(
          id: 'upload-${uploads.length}',
          videoS3Key: 'uploads/owner-a/${request.fileName}',
          storageProvider: 's3',
        );
      },
      uploadVideoFile: (_, file) async => uploadedPaths.add(file.path),
      generateRealClipCaption: (request) async {
        events.add('caption');
        captions.add(request);
        return _captionResult();
      },
      initialVideoPath: video.path,
      initialVideoName: video.name,
      initialVideoSizeBytes: video.sizeBytes,
      initialVideoWidth: video.width,
      initialVideoHeight: video.height,
    );
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: uploader),
    );
  }

  void expectNoMediaWork() {
    expect(uploads, isEmpty);
    expect(uploadedPaths, isEmpty);
    expect(captions, isEmpty);
    expect(extractions, 0);
  }
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _prepare(WidgetTester tester, _ResyncFixture fixture) async {
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await goToUploaderStep(tester, 1);
  await _show(tester, find.byKey(_captionKey));
  await tester.enterText(find.byKey(_captionKey), 'ข้อความเดิมที่ต้องเก็บไว้');
  final panel = find.byKey(const ValueKey('uploader-ai-open-panel'));
  await _show(tester, panel);
  await tester.tap(panel);
  await tester.pumpAndSettle();
  await _show(tester, find.byKey(_guidanceKey));
  await tester.enterText(find.byKey(_guidanceKey), 'คำแนะนำเดิม');
  await _show(tester, find.byKey(_generateKey));
}

Future<void> _generate(WidgetTester tester) async {
  await tester.tap(find.byKey(_generateKey));
  await tester.pumpAndSettle();
}

void _expectOriginalText(WidgetTester tester) {
  expect(tester.widget<TextField>(find.byKey(_captionKey)).controller!.text,
      'ข้อความเดิมที่ต้องเก็บไว้');
  expect(tester.widget<TextField>(find.byKey(_guidanceKey)).controller!.text,
      'คำแนะนำเดิม');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
    });
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
  });

  test('resync defaults to the existing RevenueCat build flag', () {
    expect(const UploaderScreen().enableRevenueCatBilling,
        AppConfig.enableRevenueCatBilling);
  });

  for (final plan in ['PRO', 'STARTER']) {
    testWidgets('delayed webhook reconciles Basic to verified $plan once',
        (tester) async {
      final fixture = _ResyncFixture(plans: ['BASIC', plan]);
      await _prepare(tester, fixture);
      await _generate(tester);
      expect(fixture.events.take(3), ['get-1', 'resync', 'get-2']);
      expect(fixture.loads, 2);
      expect(fixture.resyncs, 1);
      expect(fixture.captions, hasLength(1));
      expect(fixture.captions.single.guidance, 'คำแนะนำเดิม');
      expect(fixture.captions.single.selectedFrameKeys,
          plan == 'PRO' ? hasLength(1) : isEmpty);
      expect(fixture.extractions, plan == 'PRO' ? 1 : 0);
      expect(
          fixture.uploads.where((upload) => upload.contentType == 'video/mp4'),
          hasLength(1));
      expect(tester.widget<TextField>(find.byKey(_captionKey)).controller!.text,
          'แคปชั่นที่ยืนยันสิทธิ์แล้ว');
    });
  }

  testWidgets('a Pro resync response cannot override a fresh Free subscription',
      (tester) async {
    var echoedPlan = '';
    final fixture = _ResyncFixture(
      plans: ['BASIC', 'BASIC'],
      resync: () async {
        // The existing API returns a String; the callback discards that echo.
        echoedPlan = await Future.value('PRO');
      },
    );
    await _prepare(tester, fixture);
    await _generate(tester);
    expect(echoedPlan, 'PRO');
    expect(fixture.loads, 2);
    expect(fixture.resyncs, 1);
    fixture.expectNoMediaWork();
    expect(find.text(_paidRequired), findsOneWidget);
    _expectOriginalText(tester);
    expect(
        tester
            .widget<PostDeeGradientButton>(find.byKey(_generateKey))
            .onPressed,
        isNotNull);
  });

  testWidgets('expired access stays blocked without an automatic loop',
      (tester) async {
    final fixture = _ResyncFixture(plans: ['BASIC']);
    await _prepare(tester, fixture);
    await _generate(tester);
    expect(fixture.events, ['get-1', 'resync', 'get-2']);
    fixture.expectNoMediaWork();
    expect(find.text(_paidRequired), findsOneWidget);
  });

  for (final plan in ['PRO', 'STARTER']) {
    testWidgets('already verified $plan skips resync', (tester) async {
      final fixture = _ResyncFixture(plans: [plan]);
      await _prepare(tester, fixture);
      await _generate(tester);
      expect(fixture.loads, 1);
      expect(fixture.resyncs, 0);
      expect(fixture.captions, hasLength(1));
      expect(fixture.extractions, plan == 'PRO' ? 1 : 0);
    });
  }

  testWidgets('disabled RevenueCat keeps Basic denial without any resync',
      (tester) async {
    final fixture = _ResyncFixture(plans: ['BASIC'], enabled: false);
    await _prepare(tester, fixture);
    await _generate(tester);
    expect(fixture.loads, 1);
    expect(fixture.resyncs, 0);
    fixture.expectNoMediaWork();
    expect(find.text(_paidRequired), findsOneWidget);
  });

  final failures = <String, Object>{
    'not configured': const ApiException('Not configured',
        statusCode: 501, code: 'REVENUECAT_RESYNC_NOT_CONFIGURED'),
    'upstream failed': const ApiException('Upstream failed',
        statusCode: 502, code: 'REVENUECAT_RESYNC_FAILED'),
    'rate limited': const ApiException('Rate limited',
        statusCode: 429, code: 'RATE_LIMITED'),
    'network failed': const SocketException('Network failed'),
    'timed out': TimeoutException('Resync timed out'),
  };
  for (final failure in failures.entries) {
    testWidgets('resync ${failure.key} fails closed and allows a manual retry',
        (tester) async {
      var shouldFail = true;
      final fixture = _ResyncFixture(
        resync: () async {
          if (shouldFail) throw failure.value;
        },
        load: (call) async => _subscription(call <= 2 ? 'BASIC' : 'STARTER'),
      );
      await _prepare(tester, fixture);
      await _generate(tester);
      expect(fixture.loads, 1);
      expect(fixture.resyncs, 1);
      fixture.expectNoMediaWork();
      expect(find.text(_verificationFailure), findsOneWidget);
      expect(find.text(_paidRequired), findsNothing);
      _expectOriginalText(tester);
      expect(
          tester
              .widget<PostDeeGradientButton>(find.byKey(_generateKey))
              .onPressed,
          isNotNull);
      shouldFail = false;
      await _generate(tester);
      expect(fixture.loads, 3);
      expect(fixture.resyncs, 2);
      expect(fixture.captions, hasLength(1));
      expect(find.text(_verificationFailure), findsNothing);
    });
  }

  testWidgets('a failed second subscription read cannot upload or generate',
      (tester) async {
    final fixture = _ResyncFixture(load: (call) async {
      if (call == 2) throw const SocketException('Subscription read failed');
      return _subscription('BASIC');
    });
    await _prepare(tester, fixture);
    await _generate(tester);
    expect(fixture.loads, 2);
    expect(fixture.resyncs, 1);
    fixture.expectNoMediaWork();
    expect(find.text(_verificationFailure), findsOneWidget);
    _expectOriginalText(tester);
  });

  testWidgets('a failed initial subscription read never starts resync',
      (tester) async {
    final fixture = _ResyncFixture(load: (_) async {
      throw const ApiException('Subscription read failed', statusCode: 502);
    });
    await _prepare(tester, fixture);
    await _generate(tester);
    expect(fixture.loads, 1);
    expect(fixture.resyncs, 0);
    fixture.expectNoMediaWork();
    _expectOriginalText(tester);
    expect(
        tester
            .widget<PostDeeGradientButton>(find.byKey(_generateKey))
            .onPressed,
        isNotNull);
  });

  for (final stage in ['initial read', 'resync', 'second read']) {
    for (final interruption in ['owner change', 'source change', 'disposal']) {
      testWidgets('$interruption during $stage ignores the late verification',
          (tester) async {
        final readGate = Completer<SubscriptionStatusResult>();
        final resyncGate = Completer<void>();
        final fixture = _ResyncFixture(
          load: (call) async {
            if ((stage == 'initial read' && call == 1) ||
                (stage == 'second read' && call == 2)) {
              return readGate.future;
            }
            return _subscription('BASIC');
          },
          resync: () async {
            if (stage == 'resync') await resyncGate.future;
          },
        )..replacement = _video('replacement.mp4');
        await _prepare(tester, fixture);
        await _generate(tester);
        expect(fixture.loads, stage == 'second read' ? 2 : 1);
        expect(fixture.resyncs, stage == 'initial read' ? 0 : 1);

        if (interruption == 'owner change') {
          PostDeeAuthSessionStore.instance.signIn(
              AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
        } else if (interruption == 'source change') {
          await goToUploaderStep(tester, 0);
          final picker =
              find.byKey(const ValueKey('uploader-video-preview-picker'));
          await _show(tester, picker);
          await tester.tap(picker);
          await tester.pumpAndSettle();
          await goToUploaderStep(tester, 1);
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }

        if (stage == 'resync') {
          resyncGate.complete();
        } else {
          readGate.complete(
              _subscription(stage == 'initial read' ? 'BASIC' : 'PRO'));
        }
        await tester.pumpAndSettle();
        expect(fixture.loads, stage == 'second read' ? 2 : 1);
        expect(fixture.resyncs, stage == 'initial read' ? 0 : 1);
        fixture.expectNoMediaWork();
        expect(find.text(_verificationFailure), findsNothing);
        expect(find.text(_paidRequired), findsNothing);
        expect(tester.takeException(), isNull);
        if (interruption == 'source change') {
          await _show(tester, find.byKey(_captionKey));
          expect(
              tester
                  .widget<TextField>(find.byKey(_captionKey))
                  .controller!
                  .text,
              'ข้อความเดิมที่ต้องเก็บไว้');
        }
      });
    }
  }
}
