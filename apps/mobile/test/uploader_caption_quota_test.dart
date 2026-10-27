import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_audio_extractor.dart';
import 'package:postdee_mobile/features/uploader/caption_quota_strip.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _starter = SubscriptionStatusResult(
  userId: 'seller',
  plan: 'STARTER',
  status: 'ACTIVE',
  canSchedule: true,
  canUseAiCaptions: true,
  canUseAnalytics: false,
);

CaptionQuotaResult _quota({int used = 12, String plan = 'STARTER'}) =>
    CaptionQuotaResult(
        plan: plan,
        quota: RealClipCaptionQuota(
          limit: plan == 'BASIC' ? 0 : 50,
          usedThisMonth: used,
          remainingThisMonth: plan == 'BASIC' ? 0 : (50 - used).clamp(0, 50),
        ));

RealClipCaptionResult _generated() => RealClipCaptionResult(
      caption: 'แคปชั่นใหม่',
      captionOptions: const [],
      hooks: const [],
      hashtags: const [],
      seoKeywords: const [],
      searchTitle: '',
      source: const RealClipCaptionSource(
          videoS3Key: 'uploads/clip.mp4',
          mode: 'AUDIO_ONLY',
          selectedFrameCount: 0),
      quota: _quota(used: 13).quota,
    );

Future<void> _show(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 250,
      scrollable: find
          .descendant(
              of: find.byKey(const ValueKey('uploader-scroll')),
              matching: find.byType(Scrollable))
          .first);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpUploader(
    WidgetTester tester, {
    required UploaderCaptionQuotaLoader loadQuota,
    UploaderRealClipCaptionGenerator? generate,
    UploaderUploadCreator? createUpload,
    bool isActive = true,
  }) async {
    final directory = Directory.systemTemp.createTempSync('caption-quota-');
    final file = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      isActive: isActive,
      loadCaptionQuota: loadQuota,
      initialVideoPath: file.path,
      initialVideoName: 'clip.mp4',
      initialVideoSizeBytes: 3,
      initialVideoWidth: 1080,
      initialVideoHeight: 1920,
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _starter,
      extractCaptionAudio: (_) async {
        final audioDirectory =
            Directory.systemTemp.createTempSync('caption-quota-audio-');
        addTearDown(() {
          if (audioDirectory.existsSync()) {
            audioDirectory.deleteSync(recursive: true);
          }
        });
        return AiEditAudioArtifact(
          file: File('${audioDirectory.path}/audio.m4a')
            ..writeAsBytesSync([1, 2, 3]),
          workingDirectory: audioDirectory,
        );
      },
      createUpload: createUpload ??
          (_) async => const UploadResult(
              id: 'clip',
              videoS3Key: 'uploads/clip.m4a',
              storageProvider: 'mock'),
      uploadVideoFile: (_, __) async {},
      generateRealClipCaption: generate ?? (_) async => _generated(),
    ))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'loads real quota on entry and places compact strip above AI action',
      (tester) async {
    var loads = 0;
    await pumpUploader(tester, loadQuota: () async {
      loads++;
      return _quota();
    });
    final strip = find.byType(CaptionQuotaStrip);
    await _show(tester, strip);
    expect(loads, 1);
    expect(find.descendant(of: strip, matching: find.text('38 / 50 ครั้ง')),
        findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('Starter')),
        findsOneWidget);
    expect(
        tester.getBottomLeft(strip).dy,
        lessThanOrEqualTo(tester
            .getTopLeft(
                find.byKey(const ValueKey('uploader-ai-generate-button')))
            .dy));
    expect(find.byKey(const ValueKey('uploader-quota-strip')), findsNothing);
  });

  testWidgets('initial loading does not display an invented balance',
      (tester) async {
    final loaded = Completer<CaptionQuotaResult>();
    await pumpUploader(tester, loadQuota: () => loaded.future);
    await _show(
        tester, find.byKey(const ValueKey('uploader-ai-quota-loading')));
    expect(find.byType(CaptionQuotaStrip), findsNothing);
    loaded.complete(_quota());
    await tester.pumpAndSettle();
    expect(find.byType(CaptionQuotaStrip), findsOneWidget);
  });

  testWidgets('load failure can retry without showing zero quota',
      (tester) async {
    var calls = 0;
    await pumpUploader(tester, loadQuota: () async {
      if (++calls == 1) throw const SocketException('offline');
      return _quota();
    });
    await _show(tester, find.byKey(const ValueKey('uploader-ai-quota-retry')));
    expect(find.byType(CaptionQuotaStrip), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-ai-quota-retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
        tester
            .widget<CaptionQuotaStrip>(find.byType(CaptionQuotaStrip))
            .quota
            .remainingThisMonth,
        38);
  });

  testWidgets(
      'successful generation replaces quota and ignores late initial read',
      (tester) async {
    final initial = Completer<CaptionQuotaResult>();
    await pumpUploader(tester, loadQuota: () => initial.future);
    final generate = find.byKey(const ValueKey('uploader-ai-generate-button'));
    await _show(tester, generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    initial.complete(_quota());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CaptionQuotaStrip>(find.byType(CaptionQuotaStrip))
            .quota
            .remainingThisMonth,
        37);
    final caption = tester.widget<TextField>(
        find.byKey(const ValueKey('uploader-caption-field')));
    expect(caption.controller!.text, 'แคปชั่นใหม่');
  });

  testWidgets('failed generation refreshes any quota reserved on server',
      (tester) async {
    var reads = 0;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: ++reads == 1 ? 12 : 13),
        generate: (_) async =>
            throw const ApiException('ลองใหม่อีกครั้ง', statusCode: 502));
    final action = find.byKey(const ValueKey('uploader-ai-generate-button'));
    await _show(tester, action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(
        tester
            .widget<CaptionQuotaStrip>(find.byType(CaptionQuotaStrip))
            .quota
            .remainingThisMonth,
        37);
  });

  testWidgets(
      'exhausted AI quota keeps manual captions editable and avoids upload',
      (tester) async {
    var uploads = 0;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: 50),
        createUpload: (_) async {
          uploads++;
          return const UploadResult(
              id: 'clip',
              videoS3Key: 'uploads/clip.mp4',
              storageProvider: 'mock');
        });
    final action = find.byKey(const ValueKey('uploader-ai-generate-button'));
    await _show(tester, action);
    expect(find.text('โควตา AI เดือนนี้หมดแล้ว'), findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(uploads, 0);
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await _show(tester, caption);
    await tester.enterText(caption, 'เขียนเองได้');
    expect(tester.widget<TextField>(caption).controller!.text, 'เขียนเองได้');
  });

  testWidgets('Basic does not look like a paid account with exhausted quota',
      (tester) async {
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: 0, plan: 'BASIC'));
    await _show(
        tester, find.byKey(const ValueKey('uploader-ai-generate-button')));
    expect(find.byType(CaptionQuotaStrip), findsNothing);
    expect(find.text('ให้ AI ช่วยเขียน'), findsOneWidget);
  });

  testWidgets('a late quota read cannot overwrite another account balance',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(const AuthSession(idToken: 'account-a'));
    final initial = Completer<CaptionQuotaResult>();
    var reads = 0;
    await pumpUploader(tester, loadQuota: () {
      return ++reads == 1 ? initial.future : Future.value(_quota(used: 2));
    });
    sessions.signIn(const AuthSession(idToken: 'account-b'));
    await tester.pumpAndSettle();
    initial.complete(_quota());
    await tester.pumpAndSettle();
    await _show(tester, find.byType(CaptionQuotaStrip));
    expect(reads, 2);
    expect(
        tester
            .widget<CaptionQuotaStrip>(find.byType(CaptionQuotaStrip))
            .quota
            .remainingThisMonth,
        48);
    await tester.pumpWidget(const SizedBox());
    sessions.signOut();
  });

  testWidgets(
      'late generation cannot insert a previous account quota or caption',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(const AuthSession(idToken: 'account-a'));
    final generated = Completer<RealClipCaptionResult>();
    var reads = 0;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: ++reads == 1 ? 12 : 2),
        generate: (_) => generated.future);
    final action = find.byKey(const ValueKey('uploader-ai-generate-button'));
    await _show(tester, action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    sessions.signIn(const AuthSession(idToken: 'account-b'));
    await tester.pumpAndSettle();
    generated.complete(_generated());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CaptionQuotaStrip>(find.byType(CaptionQuotaStrip))
            .quota
            .remainingThisMonth,
        48);
    final caption = tester.widget<TextField>(
        find.byKey(const ValueKey('uploader-caption-field')));
    expect(caption.controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    sessions.signOut();
  });

  testWidgets('refreshes when returning to upload tab and resuming the app',
      (tester) async {
    var active = false;
    var calls = 0;
    late StateSetter change;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      change = setState;
      return UploaderScreen(
          isActive: active,
          loadSocialConnections: () async => const [],
          loadCaptionQuota: () async {
            calls++;
            return _quota(used: calls);
          });
    }))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    change(() => active = true);
    await tester.pumpAndSettle();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
