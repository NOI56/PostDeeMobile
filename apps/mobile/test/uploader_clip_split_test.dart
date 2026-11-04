import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/clip_segmenter.dart';
import 'package:postdee_mobile/features/uploader/clip_split_screen.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_preflight.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'uploader_video_english_test.dart';

class _Fixture extends VideoEnglishFixture {
  _Fixture({super.locale = const Locale('th')});

  var segmentCalls = 0;
  var cleanups = 0;
  ClipSegmentRequest? lastRequest;
  Completer<ClipSegmentBatchResult>? segmentGate;
  final durations = <String, double>{};

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await super.mount(tester, settle: settle);
  }

  @override
  UploaderScreen screen() => UploaderScreen(
        fullScreen: true,
        draftStore: store,
        enableRevenueCatBilling: false,
        initialVideoPath: initialVideo?.path,
        initialVideoName: initialVideo?.name,
        initialVideoSizeBytes: initialVideo?.sizeBytes,
        initialVideoWidth: initialVideo?.width,
        initialVideoHeight: initialVideo?.height,
        initialVideoDurationSeconds: initialVideo?.durationSeconds,
        readVideoMetadata: (path) async => VideoDimensions(
            width: 1080,
            height: 1920,
            durationSeconds: durations[path] ?? initialVideo?.durationSeconds),
        loadTemplates: () async => const [],
        loadSubscription: () async => quota,
        loadPostQuota: () async => quota,
        loadCaptionQuota: () async => const CaptionQuotaResult(
          plan: 'PRO',
          quota: RealClipCaptionQuota(
              limit: 120, usedThisMonth: 0, remainingThisMonth: 120),
        ),
        loadSocialConnections: () async => const [],
        loadSocialPublishingReadiness: () async => const [],
        probePublishMedia: probeValidPublishMedia,
        segmentClip: (request) async {
          segmentCalls++;
          lastRequest = request;
          return segmentGate == null ? result(request) : segmentGate!.future;
        },
        createUpload: (_) async {
          apiWrites++;
          throw StateError('Splitting must not upload');
        },
        createPost: (_) async {
          apiWrites++;
          throw StateError('Splitting must not publish');
        },
      );

  ClipSegmentBatchResult result(ClipSegmentRequest request) {
    final outputs = <ClipSegmentResult>[];
    for (final range in request.ranges) {
      final video = makeVideo('part-${range.index}.mp4',
          duration: range.endSeconds - range.startSeconds);
      durations[video.path] = video.durationSeconds!;
      outputs.add(ClipSegmentResult(
          file: File(video.path),
          fileName: video.name,
          index: range.index,
          startSeconds: range.startSeconds,
          endSeconds: range.endSeconds,
          metadata: PublishMediaMetadata(
              durationSeconds: video.durationSeconds,
              width: 1080,
              height: 1920,
              sizeBytes: video.sizeBytes,
              hasVideo: true,
              hasAudio: true,
              videoCodec: 'h264',
              audioCodec: 'aac',
              fps: 30)));
    }
    return ClipSegmentBatchResult(
        parts: outputs,
        // The in-memory draft fixture references these files. Native cleanup
        // is observed here; test-owned files are removed by makeVideo teardown.
        cleanup: () async => cleanups++);
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  if (key == 'clip-split-confirm') {
    // The draft service checks real files; let those OS futures complete.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
      if (i > 5 && _key('uploader-clip-split-progress').evaluate().isEmpty) {
        break;
      }
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    final before = sessions.session;
    sessions.signIn(AuthSession.authenticated(
        userId: videoEnglishOwner, idToken: 'clip-split-test'));
    addTearDown(
        () => before.isSignedIn ? sessions.signIn(before) : sessions.clear());
  });

  testWidgets(
      'only offers inline splitting after a measured clip exceeds a limit',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('short.mp4', duration: 30);
    await fixture.mount(tester);
    expect(_key('uploader-clip-split-open'), findsNothing);
    expect(fixture.segmentCalls, 0);
    expect(fixture.store.savedRequests, isEmpty);
  });

  testWidgets('reviewing then cancelling preserves the source without writes',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('long.mp4', duration: 270);
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    await _tap(tester, 'uploader-clip-split-open');
    expect(find.byType(ClipSplitScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fixture.segmentCalls, 0);
    expect(fixture.store.savedRequests, isEmpty);
    expect(File(fixture.initialVideo!.path).existsSync(), isTrue);
    expect(find.byType(ClipSplitScreen), findsNothing);
    expect(_key('uploader-clip-split-open'), findsOneWidget);
  });

  testWidgets(
      'confirmed plan keeps independent requests together in one review group',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('long.mp4', duration: 270);
    final source = File(fixture.initialVideo!.path).readAsBytesSync();
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    await _tap(tester, 'uploader-clip-split-open');
    await _tap(tester, 'clip-split-review');
    await _tap(tester, 'clip-split-confirm');
    expect(fixture.segmentCalls, 1);
    expect(fixture.lastRequest!.ranges, hasLength(5));
    // Source and all six independent media drafts stay on the device, while
    // the seller sees one group rather than opening the first child alone.
    expect(fixture.store.drafts, hasLength(7));
    expect(
        fixture.store.drafts.values
            .skip(1)
            .map((d) => d.submissionRequestId)
            .toSet(),
        hasLength(6));
    expect(
        fixture.store.savedRequests.every((d) =>
            d.uploadedMedia == null &&
            d.scheduledAt == null &&
            d.coverDesign == null),
        isTrue);
    expect(_key('clip-group-review'), findsOneWidget);
    expect(fixture.store.drafts.values.every((d) => d.clipGroupId != null),
        isTrue);
    expect(
        fixture.store.drafts.values.where((d) => d.isClipGroupSource),
        hasLength(1));
    expect(File(fixture.initialVideo!.path).readAsBytesSync(), source);
    expect(fixture.cleanups, 1);
    expect(fixture.apiWrites, 0);
  });

  testWidgets('cancelling preparation leaves no generated drafts',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('long.mp4', duration: 270);
    fixture.segmentGate = Completer<ClipSegmentBatchResult>();
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    await _tap(tester, 'uploader-clip-split-open');
    await _tap(tester, 'clip-split-review');
    await tester.ensureVisible(_key('clip-split-confirm'));
    await tester.tap(_key('clip-split-confirm'));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(fixture.segmentCalls, 1);
    await tester.tap(_key('uploader-clip-split-cancel'));
    await tester.pump();
    expect(fixture.lastRequest!.isCancelled!(), isTrue);
    fixture.segmentGate!.complete(fixture.result(fixture.lastRequest!));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.store.savedRequests.single.videoName, 'long.mp4');
    expect(fixture.cleanups, 1);
    expect(File(fixture.initialVideo!.path).existsSync(), isTrue);
  });

  testWidgets('English inline prompt uses translated actions', (tester) async {
    final fixture = _Fixture(locale: const Locale('en'));
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('long.mp4', duration: 270);
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    expect(find.text('Review split plan'), findsOneWidget);
    expect(find.text('ดูแผนแบ่งคลิป'), findsNothing);
  });

  for (final sameOwner in [false, true]) {
    testWidgets(
        'stale ${sameOwner ? 'same-owner sign-in' : 'owner change'} cancels pending split',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.initialVideo = fixture.makeVideo('long.mp4', duration: 270);
      fixture.segmentGate = Completer<ClipSegmentBatchResult>();
      await fixture.mount(tester);
      await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
      await _tap(tester, 'uploader-clip-split-open');
      await _tap(tester, 'clip-split-review');
      await tester.ensureVisible(_key('clip-split-confirm'));
      await tester.tap(_key('clip-split-confirm'));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fixture.segmentCalls, 1);
      final sessions = PostDeeAuthSessionStore.instance;
      sessions.clear();
      sessions.signIn(AuthSession.authenticated(
          userId: sameOwner ? videoEnglishOwner : 'another-owner',
          idToken: 'new-sign-in'));
      expect(fixture.lastRequest!.isCancelled!(), isTrue);
      fixture.segmentGate!.complete(fixture.result(fixture.lastRequest!));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(fixture.store.savedRequests, hasLength(1));
      expect(fixture.store.savedRequests.single.videoName, 'long.mp4');
      expect(fixture.cleanups, 1);
      expect(fixture.apiWrites, 0);
      expect(find.byType(ClipSplitScreen), findsNothing);
    });
  }
}
