import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_segmenter.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_store.dart';
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
        initialDraftId: initialDraftId,
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
  testWidgets('split advice is conditional until posting channels are selected',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('en'));
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('long.mp4', duration: 270);
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-prompt'));
    expect(find.text('These channels need shorter parts if you choose them'),
        findsOneWidget);
    expect(fixture.segmentCalls, 0);
    expect(fixture.store.savedRequests, isEmpty);
  });

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
    expect(_key('uploader-step-caption'), findsOneWidget);
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
    expect(find.text('กำลังเตรียมชุดคลิป'), findsOneWidget);
    expect(
        find.text(
            'ต้นฉบับเก็บเป็นร่างแล้ว · ยังไม่อัปโหลด ไม่โพสต์ และไม่ใช้โควตา'),
        findsOneWidget);
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

  testWidgets('split returns to the same normal caption composer and keeps '
      'shared and explicitly blank part captions separate', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('mixed-targets.mp4', duration: 180);
    await fixture.mount(tester);
    final originalState = tester.state(find.byType(UploaderScreen));
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    await _tap(tester, 'uploader-clip-split-open');
    await _tap(tester, 'clip-split-review');
    await _tap(tester, 'clip-split-confirm');
    expect(tester.state(find.byType(UploaderScreen)), same(originalState));
    expect(_key('uploader-step-caption'), findsOneWidget);
    expect(_key('clip-group-caption-scopes'), findsOneWidget);
    expect(_key('clip-group-main-caption-page'), findsNothing);
    final groups = await (fixture.store as ClipGroupDraftStore).listClipGroups();
    final group = groups.single;
    final firstPart = group.items.firstWhere((item) =>
        item.platformApiValues.contains('FACEBOOK_REELS') &&
        item.sourceStartSeconds == 0);
    await tester.enterText(_key('uploader-caption-field'), 'แคปชันหลักทุกคลิป');
    await _tap(tester, 'clip-group-caption-scope-${firstPart.draftId}');
    expect(tester.widget<TextField>(_key('uploader-caption-field')).readOnly,
        isTrue);
    await _tap(tester, 'clip-group-caption-custom-${firstPart.draftId}');
    await tester.enterText(_key('uploader-caption-field'), '');
    await _tap(tester, 'clip-group-caption-scope-all');
    await tester.enterText(_key('uploader-caption-field'), 'ข้อความหลักใหม่');
    await _tap(tester, 'uploader-save-draft-button');
    final saved = (await (fixture.store as ClipGroupDraftStore)
            .listClipGroups()).single;
    expect(saved.sharedCaption, 'ข้อความหลักใหม่');
    expect(saved.items.firstWhere((i) => i.draftId == firstPart.draftId)
        .usesSharedCaption, isFalse);
    expect(fixture.store.drafts[firstPart.draftId]!.caption, '');
    expect(fixture.store.drafts[group.sourceDraftId]!.isClipGroupSource, isTrue);
    expect(fixture.apiWrites, 0);
  });

  for (final facebookOnly in [false, true]) {
    testWidgets(
        'composer channel footer counts ${facebookOnly ? 1 : 4} distinct '
        'planned destinations instead of delivery members', (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.initialVideo =
          fixture.makeVideo('footer-targets.mp4', duration: 180);
      await fixture.mount(tester);
      final summary = _key('uploader-sticky-summary');
      await _tap(tester, 'uploader-progress-2');
      expect(
          find.descendant(
              of: summary, matching: find.text('เลือกแล้ว 0 ช่องทาง')),
          findsOneWidget);
      await _tap(tester, 'uploader-progress-0');
      await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
      await _tap(tester, 'uploader-clip-split-open');
      if (facebookOnly) {
        for (final platform in [
          'TIKTOK',
          'YOUTUBE_SHORTS',
          'INSTAGRAM_REELS'
        ]) {
          await _tap(tester, 'clip-split-channel-$platform');
        }
      }
      await _tap(tester, 'clip-split-review');
      await _tap(tester, 'clip-split-confirm');
      final group =
          (await (fixture.store as ClipGroupDraftStore).listClipGroups())
              .single;
      expect(group.items, hasLength(facebookOnly ? 2 : 3));
      final part = group.items.firstWhere(
          (item) => item.platformApiValues.contains('FACEBOOK_REELS'));
      await _tap(tester, 'clip-group-caption-scope-${part.draftId}');
      expect(
          find.descendant(of: summary, matching: find.text('แคปชันแก้ไขได้')),
          findsOneWidget);
      await _tap(tester, 'uploader-wizard-next');
      expect(_key('uploader-step-platforms'), findsOneWidget);
      expect(
          find.descendant(
              of: summary,
              matching: find.text('เลือกแล้ว ${facebookOnly ? 1 : 4} ช่องทาง')),
          findsOneWidget);
      expect(fixture.apiWrites, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final save in [false, true]) {
    testWidgets(
        'composer part-only edits prompt on Close and ${save ? 'save' : 'discard'} '
        'retains the expected caption after reopen', (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.initialVideo = fixture.makeVideo('part-only.mp4', duration: 180);
      await fixture.mount(tester);
      await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
      await _tap(tester, 'uploader-clip-split-open');
      await _tap(tester, 'clip-split-review');
      await _tap(tester, 'clip-split-confirm');
      final group =
          (await (fixture.store as ClipGroupDraftStore).listClipGroups()).single;
      final original = fixture.store.drafts[group.sourceDraftId]!;
      final part = group.items.firstWhere((item) =>
          item.platformApiValues.contains('FACEBOOK_REELS') &&
          item.sourceStartSeconds == 0);
      await _tap(tester, 'clip-group-caption-scope-${part.draftId}');
      await _tap(tester, 'clip-group-caption-custom-${part.draftId}');
      await tester.enterText(
          _key('uploader-caption-field'), 'ข้อความเฉพาะตอนที่หนึ่ง');
      await _tap(tester, 'uploader-close');
      expect(_key('uploader-exit-dialog'), findsOneWidget);
      await tester.tap(find.text('แก้ไขต่อ'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(_key('uploader-caption-field'))
              .controller!.text,
          'ข้อความเฉพาะตอนที่หนึ่ง');
      await _tap(tester, 'uploader-close');
      expect(_key('uploader-exit-dialog'), findsOneWidget);
      await tester.tap(find.text(save ? 'บันทึกแล้วออก' : 'ออกโดยไม่บันทึก'));
      await tester.pumpAndSettle();
      expect(find.byType(UploaderScreen), findsNothing);
      expect(find.text('Uploader test home'), findsOneWidget);
      expect(fixture.store.drafts[group.sourceDraftId], same(original));
      final savedGroup =
          (await (fixture.store as ClipGroupDraftStore).listClipGroups()).single;
      expect(savedGroup.sharedCaption, '');
      expect(savedGroup.items.firstWhere((i) => i.draftId == part.draftId)
          .usesSharedCaption, !save);
      expect(fixture.store.drafts[part.draftId]!.caption,
          save ? 'ข้อความเฉพาะตอนที่หนึ่ง' : '');

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.initialVideo = null;
      fixture.initialDraftId = group.sourceDraftId;
      await fixture.mount(tester);
      await _tap(tester, 'clip-group-caption-scope-${part.draftId}');
      final field = tester.widget<TextField>(_key('uploader-caption-field'));
      expect(field.controller!.text, save ? 'ข้อความเฉพาะตอนที่หนึ่ง' : '');
      expect(field.readOnly, !save);
      expect(fixture.apiWrites, 0);
    });
  }

  testWidgets('composer refuses missing backup media without adopting another '
      'clip or writing drafts', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('missing-backup.mp4', duration: 180);
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    await _tap(tester, 'uploader-clip-split-open');
    // Keep only Facebook so the backup is the only draft referencing this
    // test-owned input file; the two encoded member fixtures stay readable.
    await _tap(tester, 'clip-split-channel-TIKTOK');
    await _tap(tester, 'clip-split-channel-YOUTUBE_SHORTS');
    await _tap(tester, 'clip-split-channel-INSTAGRAM_REELS');
    await _tap(tester, 'clip-split-review');
    await _tap(tester, 'clip-split-confirm');
    final group =
        (await (fixture.store as ClipGroupDraftStore).listClipGroups()).single;
    final before = group.toJson();
    final source = fixture.store.drafts[group.sourceDraftId]!;
    final memberSnapshots = {
      for (final item in group.items)
        item.draftId: fixture.store.drafts[item.draftId],
    };
    await tester.pumpWidget(const SizedBox.shrink());
    // makeVideo owns this temporary file and registers an existence-aware
    // teardown. No owner/device data is involved in this failure fixture.
    final missing = File(source.videoPath);
    expect(missing.parent.parent.absolute.path,
        Directory.systemTemp.absolute.path);
    missing.deleteSync();
    final writesBefore = fixture.store.savedRequests.length;
    fixture.initialVideo = fixture.makeVideo('unrelated.mp4', duration: 30);
    fixture.initialDraftId = null;
    await fixture.mount(tester);
    await _tap(tester, 'uploader-open-drafts');
    await _tap(tester, 'publish-draft-${group.sourceDraftId}');
    expect(_key('clip-group-caption-scopes'), findsNothing);
    expect(_key('uploader-step-caption'), findsNothing);
    expect(_key('uploader-ai-generate-button'), findsNothing);
    expect(find.text('unrelated.mp4'), findsWidgets);
    expect(fixture.store.savedRequests, hasLength(writesBefore));
    expect((await (fixture.store as ClipGroupDraftStore)
            .loadClipGroup(group.id))!.toJson(), before);
    for (final item in group.items) {
      expect(fixture.store.drafts[item.draftId],
          same(memberSnapshots[item.draftId]));
      expect(File(fixture.store.drafts[item.draftId]!.videoPath).existsSync(),
          isTrue);
    }
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer platform mode and explicit blank overrides persist only '
      'for the selected part', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('same-parts.mp4', duration: 180);
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    await _tap(tester, 'uploader-clip-split-open');
    await _tap(tester, 'clip-split-mode-all');
    await _tap(tester, 'clip-split-review');
    await _tap(tester, 'clip-split-confirm');
    final group =
        (await (fixture.store as ClipGroupDraftStore).listClipGroups()).single;
    expect(group.items, hasLength(2));
    final first = group.items.first;
    final second = group.items.last;
    final source = fixture.store.drafts[group.sourceDraftId]!;
    final firstTargets = Set<String>.of(first.platformApiValues);
    final secondTargets = Set<String>.of(second.platformApiValues);
    await _tap(tester, 'clip-group-caption-scope-${first.draftId}');
    await _tap(tester, 'clip-group-platform-captions-toggle');
    await _tap(tester, 'uploader-save-draft-button');
    expect(fixture.store.drafts[first.draftId]!
        .platformSettings.usePlatformCaptions, isTrue);
    expect(fixture.store.drafts[second.draftId]!
        .platformSettings.usePlatformCaptions, isFalse);
    await _tap(tester,
        'clip-group-platform-custom-${first.draftId}-TIKTOK');
    await tester.enterText(
        _key('clip-group-platform-caption-${first.draftId}-TIKTOK'),
        'เฉพาะ TikTok ของตอนแรก');
    await _tap(tester, 'clip-group-caption-platform');
    await tester.tap(find.text('Instagram Reels').last);
    await tester.pumpAndSettle();
    await _tap(tester,
        'clip-group-platform-custom-${first.draftId}-INSTAGRAM_REELS');
    await tester.enterText(
        _key('clip-group-platform-caption-${first.draftId}-INSTAGRAM_REELS'),
        '');
    await _tap(tester, 'uploader-save-draft-button');
    final firstSettings =
        fixture.store.drafts[first.draftId]!.platformSettings;
    expect(firstSettings.platformCaptions[SocialPlatform.tiktok],
        'เฉพาะ TikTok ของตอนแรก');
    expect(firstSettings.platformCaptions
        .containsKey(SocialPlatform.instagramReels), isTrue);
    expect(firstSettings.platformCaptions[SocialPlatform.instagramReels], '');
    expect(firstSettings.platformCaptions
        .containsKey(SocialPlatform.youtubeShorts), isFalse);
    expect(fixture.store.drafts[second.draftId]!
        .platformSettings.platformCaptions, isEmpty);
    expect(fixture.store.drafts[second.draftId]!
        .platformSettings.usePlatformCaptions, isFalse);
    expect(fixture.store.drafts[first.draftId]!.platformApiValues, firstTargets);
    expect(fixture.store.drafts[second.draftId]!.platformApiValues, secondTargets);
    expect(fixture.store.drafts[group.sourceDraftId], same(source));

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.initialVideo = null;
    fixture.initialDraftId = group.sourceDraftId;
    await fixture.mount(tester);
    await _tap(tester, 'clip-group-caption-scope-${first.draftId}');
    expect(tester.widget<SwitchListTile>(
        _key('clip-group-platform-captions-toggle')).value, isTrue);
    expect(tester.widget<TextField>(
        _key('clip-group-platform-caption-${first.draftId}-TIKTOK'))
        .controller!.text, 'เฉพาะ TikTok ของตอนแรก');
    await _tap(tester, 'clip-group-caption-scope-${second.draftId}');
    expect(tester.widget<SwitchListTile>(
        _key('clip-group-platform-captions-toggle')).value, isFalse);
    expect(_key('clip-group-platform-caption-${second.draftId}-TIKTOK'),
        findsNothing);
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer platform choices contain only the selected full member '
      'planned destinations', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('eligible-targets.mp4', duration: 180);
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    await _tap(tester, 'uploader-clip-split-open');
    await _tap(tester, 'clip-split-review');
    await _tap(tester, 'clip-split-confirm');
    final group =
        (await (fixture.store as ClipGroupDraftStore).listClipGroups()).single;
    final full = group.items.singleWhere((item) =>
        item.platformApiValues.contains('INSTAGRAM_REELS'));
    expect(full.platformApiValues, {'TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS'});
    await _tap(tester, 'clip-group-caption-scope-${full.draftId}');
    await _tap(tester, 'clip-group-platform-captions-toggle');
    final picker = tester.widget<DropdownButtonFormField<SocialPlatform>>(
        _key('clip-group-caption-platform'));
    final dropdown = find.descendant(
        of: _key('clip-group-caption-platform'),
        matching: find.byType(DropdownButton<SocialPlatform>));
    expect(picker, isNotNull);
    expect(tester.widget<DropdownButton<SocialPlatform>>(dropdown)
        .items!.map((item) => item.value).toSet(),
        {SocialPlatform.tiktok, SocialPlatform.youtubeShorts,
          SocialPlatform.instagramReels});
    expect(fixture.apiWrites, 0);
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

  testWidgets('saving a set shows one draft entry and reopens the entire set',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.initialVideo = fixture.makeVideo('long.mp4', duration: 270);
    await fixture.mount(tester);
    await revealVideoEnglishControl(tester, _key('uploader-clip-split-open'));
    await _tap(tester, 'uploader-clip-split-open');
    await _tap(tester, 'clip-split-review');
    await _tap(tester, 'clip-split-confirm');
    expect(_key('uploader-step-caption'), findsOneWidget);
    await _tap(tester, 'uploader-save-draft-button');
    final groups = await (fixture.store as ClipGroupDraftStore).listClipGroups();
    expect(groups, hasLength(1));
    final group = groups.single;
    expect(group.items, hasLength(6));
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('Uploader test home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.initialVideo=null;
    fixture.initialDraftId=null;
    await fixture.mount(tester);
    expect(find.text('ฉบับร่าง (1)'), findsOneWidget);
    await _tap(tester, 'uploader-open-drafts');
    expect(find.byType(ListTile), findsOneWidget);
    await _tap(tester, 'publish-draft-${group.sourceDraftId}');
    expect(_key('uploader-step-caption'), findsOneWidget);
    expect(fixture.apiWrites, 0);
    expect(fixture.store.drafts, hasLength(7));
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.initialVideo = null;
    fixture.initialDraftId = group.sourceDraftId;
    await fixture.mount(tester);
    expect(_key('uploader-step-caption'), findsOneWidget);
    expect(fixture.apiWrites, 0);
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
