import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';

const videoEnglishOwner = 'english-uploader-owner';

class VideoEnglishDrafts extends TestPublishDraftStore {
  VideoEnglishDrafts() : super(ownerUserId: videoEnglishOwner);
  int lists = 0;
  int loads = 0;
  int deletes = 0;
  int saveAttempts = 0;
  Object? listError;
  Object? saveError;
  Object? loadError;
  Object? deleteError;
  Completer<void>? saveGate;
  Future<PublishDraft?>? loadGate;

  @override
  Future<PublishDraft?> loadDraft(String id) async {
    loads++;
    if (loadError != null) throw loadError!;
    return loadGate == null ? super.loadDraft(id) : await loadGate!;
  }

  @override
  Future<void> deleteDraft(String id) async {
    deletes++;
    if (deleteError != null) throw deleteError!;
    return super.deleteDraft(id);
  }

  @override
  Future<List<PublishDraft>> listDrafts() async {
    lists++;
    if (listError != null) throw listError!;
    return super.listDrafts();
  }

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    saveAttempts++;
    if (saveGate != null) await saveGate!.future;
    if (saveError != null) throw saveError!;
    return super.saveDraft(request);
  }
}

class VideoEnglishFixture {
  VideoEnglishFixture(
      {Locale locale = const Locale('en'), this.dark = false, this.scale = 1})
      : language = ValueNotifier(locale);

  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final store = VideoEnglishDrafts();
  PickedVideoFile? picked;
  Future<PickedVideoFile?>? pickerGate;
  Object? pickerError;
  int picks = 0;
  int quotaReads = 0;
  int captionQuotaReads = 0;
  int connectionReads = 0;
  int apiWrites = 0;
  final metadataReads = <String>[];
  Future<VideoDimensions?>? metadataGate;
  Object? metadataError;
  Future<SubscriptionStatusResult>? quotaGate;
  Object? quotaError;
  Future<SubscriptionStatusResult> Function()? quotaRespond;
  String? initialDraftId;
  PickedVideoFile? initialVideo;
  SubscriptionStatusResult quota = const SubscriptionStatusResult(
      userId: videoEnglishOwner,
      plan: 'PRO',
      status: 'ACTIVE',
      monthlyPostLimit: 250,
      usedPostsThisMonth: 10,
      remainingPostsThisMonth: 240,
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true);

  PickedVideoFile makeVideo(String name,
      {int sizeBytes = 2048,
      int width = 1080,
      int height = 1920,
      double? duration = 10}) {
    final directory = Directory.systemTemp.createTempSync('postdee-en-video-');
    final file = File('${directory.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(List.filled(sizeBytes, 1));
    addTearDown(() {
      expect(
          directory.parent.absolute.path, Directory.systemTemp.absolute.path);
      if (file.existsSync()) file.deleteSync();
      if (directory.existsSync()) directory.deleteSync();
    });
    return PickedVideoFile(
        name: name,
        path: file.path,
        sizeBytes: sizeBytes,
        width: width,
        height: height,
        durationSeconds: duration);
  }

  UploaderScreen screen() => UploaderScreen(
      fullScreen: true,
      draftStore: store,
      enableRevenueCatBilling: false,
      initialDraftId: initialDraftId,
      initialVideoPath: initialVideo?.path,
      initialVideoName: initialVideo?.name,
      initialVideoSizeBytes: initialVideo?.sizeBytes,
      initialVideoWidth: initialVideo?.width,
      initialVideoHeight: initialVideo?.height,
      initialVideoDurationSeconds: initialVideo?.durationSeconds,
      pickVideo: () async {
        picks++;
        if (pickerError != null) throw pickerError!;
        return pickerGate == null ? picked : await pickerGate!;
      },
      readVideoMetadata: (path) async {
        metadataReads.add(path);
        if (metadataError != null) throw metadataError!;
        return metadataGate == null
            ? const VideoDimensions(
                width: 1080, height: 1920, durationSeconds: 10)
            : await metadataGate!;
      },
      probePublishMedia: probeValidPublishMedia,
      loadTemplates: () async => const [],
      loadSubscription: () async => quota,
      loadPostQuota: () async {
        quotaReads++;
        if (quotaError != null) throw quotaError!;
        if (quotaRespond != null) return quotaRespond!();
        return quotaGate == null ? quota : await quotaGate!;
      },
      loadCaptionQuota: () async {
        captionQuotaReads++;
        return const CaptionQuotaResult(
            plan: 'PRO',
            quota: RealClipCaptionQuota(
                limit: 120, usedThisMonth: 0, remainingThisMonth: 120));
      },
      loadSocialConnections: () async {
        connectionReads++;
        return const [];
      },
      loadSocialPublishingReadiness: () async => const [],
      createUpload: (_) async {
        apiWrites++;
        throw StateError('Unexpected upload');
      },
      uploadVideoFile: (_, __) async {
        apiWrites++;
      },
      createPost: (_) async {
        apiWrites++;
        throw StateError('Unexpected publish');
      },
      generateRealClipCaption: (_) async {
        apiWrites++;
        throw StateError('Unexpected AI');
      });

  Widget app() => ValueListenableBuilder<Locale>(
      valueListenable: language,
      builder: (_, locale, __) {
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        return MaterialApp(
            locale: locale,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const Scaffold(body: Text('Uploader test home')),
            initialRoute: '/create',
            routes: {
              '/create': (_) => Scaffold(body: SafeArea(child: screen()))
            });
      });

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(app());
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  void dispose() {
    expect(apiWrites, 0);
    language.dispose();
  }
}

Future<void> tapVideoEnglishControl(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await revealVideoEnglishControl(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get videoEnglishMainScroll => find.descendant(
    of: find.byKey(const ValueKey('uploader-scroll')),
    matching: find.byType(Scrollable));

Future<void> revealVideoEnglishControl(WidgetTester tester, Finder finder,
    {bool header = false}) async {
  if (finder.evaluate().isEmpty) {
    final scroll = header
        ? find.descendant(
            of: find.byKey(const ValueKey('uploader-header-scroll')),
            matching: find.byType(Scrollable))
        : videoEnglishMainScroll;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 140, scrollable: scroll);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void expectVideoEnglishReadable(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)).first);
  final label = text.data ?? text.textSpan?.toPlainText();
  expect(paragraph.didExceedMaxLines, isFalse, reason: label);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5),
      reason: label);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: videoEnglishOwner, idToken: 'fake-token'));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('English first step labels the selector and shared controls',
      (tester) async {
    final fixture = VideoEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    for (final text in [
      'Create post',
      'Step 1 of 4 · Choose video',
      'Start with the vertical video you want to post.',
      'Choose a 9:16 video',
      'Drafts (0)',
      'Save draft',
      'Next: Caption',
      'Choose a video first'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('uploader-caption-field')), findsNothing);
    expect(fixture.picks, 0);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English selected-video status retains the raw Thai file name',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('เลือกคลิปขายสินค้า.mp4');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    expect(find.text('เลือกคลิปขายสินค้า.mp4'), findsOneWidget);
    expect(find.text('Video selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-video-preview-open')),
        findsOneWidget);
    expect(fixture.picks, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored missing-video error follows locale without picking a file',
      (tester) async {
    final fixture = VideoEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    expect(find.text('เลือกวิดีโอจากเครื่องก่อน'), findsOneWidget);
    final quotaReads = fixture.quotaReads;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Choose a video from your device first.'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
    expect(fixture.picks, 0);
    expect(fixture.quotaReads, quotaReads);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English post quota preserves units and accessibility counts',
      (tester) async {
    final fixture = VideoEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await revealVideoEnglishControl(
        tester, find.byKey(const ValueKey('uploader-post-quota-strip')));
    expect(find.text('Post units remaining'), findsOneWidget);
    expect(find.text('10 units used'), findsOneWidget);
    expect(find.text('240 / 250 units', findRichText: true), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('uploader-post-quota-progress')));
    expect(indicator.value, 240 / 250);
    expect(indicator.semanticsLabel, '240 of 250 post units remaining');
    expect(fixture.quotaReads, 1);
    expect(fixture.picks, 0);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing language retains selected clip and read counts',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('คลิปขายสินค้า.mp4');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    final quotaReads = fixture.quotaReads;
    final metadataReads = fixture.metadataReads.length;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('สร้างโพสต์ใหม่'), findsOneWidget);
    expect(find.text('คลิปขายสินค้า.mp4'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Create post'), findsOneWidget);
    expect(find.text('คลิปขายสินค้า.mp4'), findsOneWidget);
    expect(
        find.text('0:10 min · 1080 × 1920 px · 9:16 · 2.0 KB'), findsOneWidget);
    expect(fixture.picks, 1);
    expect(fixture.quotaReads, quotaReads);
    expect(fixture.metadataReads, hasLength(metadataReads));
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a video name matching Thai interface copy remains customer data',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('เลือกคลิป');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    expect(find.text('เลือกคลิป'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('เลือกคลิป'), findsOneWidget);
    expect(fixture.picks, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final size in {
    1: '1 byte',
    512: '512 bytes',
    1024: '1.0 KB',
    1048576: '1.0 MB'
  }.entries) {
    testWidgets('English video metadata preserves byte boundary ${size.key}',
        (tester) async {
      final fixture = VideoEnglishFixture();
      fixture.picked = fixture.makeVideo('clip.mp4', sizeBytes: size.key);
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
      expect(find.text('0:10 min · 1080 × 1920 px · 9:16 · ${size.value}'),
          findsOneWidget);
      expect(fixture.picked!.sizeBytes, size.key);
      expect(fixture.picks, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('canceling the first file picker keeps the English empty state',
      (tester) async {
    final fixture = VideoEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    final quotaReads = fixture.quotaReads;
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    expect(find.text('Choose a video first'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-video-preview-open')),
        findsNothing);
    expect(fixture.picks, 1);
    expect(fixture.quotaReads, quotaReads);
    expect(fixture.metadataReads, isEmpty);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling a replacement keeps the original clip and metadata',
      (tester) async {
    final fixture = VideoEnglishFixture();
    fixture.picked = fixture.makeVideo('คลิปเดิม.mp4');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    fixture.picked = null;
    final quotaReads = fixture.quotaReads;
    final metadataReads = fixture.metadataReads.length;
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    expect(find.text('คลิปเดิม.mp4'), findsOneWidget);
    expect(find.text('Video selected'), findsOneWidget);
    expect(fixture.picks, 2);
    expect(fixture.quotaReads, quotaReads);
    expect(fixture.metadataReads, hasLength(metadataReads));
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored picker errors translate the prefix and retain raw details',
      (tester) async {
    final failure = StateError('รายละเอียดจากเครื่อง');
    final fixture = VideoEnglishFixture(locale: const Locale('th'))
      ..pickerError = failure;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    expect(find.text('เลือกวิดีโอไม่ได้: $failure'), findsOneWidget);
    final quotaReads = fixture.quotaReads;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not select the video: $failure'), findsOneWidget);
    expect(fixture.picks, 1);
    expect(fixture.quotaReads, quotaReads);
    expect(fixture.metadataReads, isEmpty);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final invalid in ['path', 'size']) {
    testWidgets('incomplete picked $invalid retains the previous video',
        (tester) async {
      final fixture = VideoEnglishFixture();
      final original = fixture.makeVideo('คลิปเดิม.mp4');
      fixture.picked = original;
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
      fixture.picked = PickedVideoFile(
          name: 'invalid.mp4',
          path: invalid == 'path' ? ' ' : original.path,
          sizeBytes: invalid == 'size' ? 0 : original.sizeBytes);
      await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
      tester.state<ScrollableState>(videoEnglishMainScroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
          find.text('The selected video file is missing required information.'),
          findsOneWidget);
      expect(find.text('คลิปเดิม.mp4'), findsOneWidget);
      final reads = fixture.metadataReads.length;
      fixture.language.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(find.text('ไฟล์วิดีโอที่เลือกมีข้อมูลไม่ครบ'), findsOneWidget);
      expect(fixture.metadataReads, hasLength(reads));
      expect(fixture.picks, 2);
      expect(fixture.store.savedRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'pending picker follows locale without another pick or losing the result',
      (tester) async {
    final pending = Completer<PickedVideoFile?>();
    final fixture = VideoEnglishFixture()..pickerGate = pending.future;
    final video = fixture.makeVideo('ผลเลือกคลิป.mp4');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('สร้างโพสต์ใหม่'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(fixture.picks, 1);
    expect(find.text('Choose a video first'), findsOneWidget);
    pending.complete(video);
    await tester.pumpAndSettle();
    expect(find.text('ผลเลือกคลิป.mp4'), findsOneWidget);
    expect(find.text('Video selected'), findsOneWidget);
    expect(fixture.picks, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker result arriving after closing the route stays ignored',
      (tester) async {
    final pending = Completer<PickedVideoFile?>();
    final fixture = VideoEnglishFixture()..pickerGate = pending.future;
    final video = fixture.makeVideo('late.mp4');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    await tapVideoEnglishControl(tester, 'uploader-close');
    expect(find.byType(UploaderScreen), findsNothing);
    pending.complete(video);
    await tester.pumpAndSettle();
    expect(find.text('Uploader test home'), findsOneWidget);
    expect(find.text('late.mp4'), findsNothing);
    expect(fixture.metadataReads, isEmpty);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending duration labels follow locale without a second metadata read',
      (tester) async {
    final pending = Completer<VideoDimensions?>();
    final fixture = VideoEnglishFixture()..metadataGate = pending.future;
    fixture.picked = fixture.makeVideo('duration.mp4', duration: null);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    expect(find.text('Reading video duration...'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กำลังอ่านความยาวคลิป...'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(fixture.metadataReads, hasLength(1));
    pending.complete(const VideoDimensions(
        width: 1080, height: 1920, durationSeconds: 60.1));
    await tester.pumpAndSettle();
    expect(
        find.text('1:01 min · 1080 × 1920 px · 9:16 · 2.0 KB'), findsOneWidget);
    expect(fixture.metadataReads, hasLength(1));
    expect(fixture.picks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unavailable duration follows locale without retrying or fabricating time',
      (tester) async {
    final fixture = VideoEnglishFixture()
      ..metadataError = StateError('Private metadata failure');
    fixture.picked = fixture.makeVideo('unreadable.mp4', duration: null);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
    expect(
        find.text(
            'Video duration is not available yet. It will be checked again before sending.'),
        findsOneWidget);
    expect(find.textContaining('Private metadata failure'), findsNothing);
    expect(find.text('1080 × 1920 px · 9:16 · 2.0 KB'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(
        find.text('ยังอ่านความยาวคลิปไม่ได้ จะตรวจซ้ำก่อนส่ง'), findsOneWidget);
    expect(fixture.metadataReads, hasLength(1));
    expect(fixture.picks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('post quota failure follows locale and Retry reads once',
      (tester) async {
    final fixture = VideoEnglishFixture(locale: const Locale('th'))
      ..quotaError = StateError('offline');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await revealVideoEnglishControl(
        tester, find.byKey(const ValueKey('uploader-post-quota-retry')));
    expect(find.text('โหลดโควตาโพสต์ไม่สำเร็จ'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not load post quota.'), findsOneWidget);
    expect(find.byTooltip('Reload post quota'), findsOneWidget);
    expect(fixture.quotaReads, 1);
    fixture.quotaError = null;
    await tapVideoEnglishControl(tester, 'uploader-post-quota-retry');
    expect(find.text('Post units remaining'), findsOneWidget);
    expect(fixture.quotaReads, 2);
    expect(fixture.picks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late old-owner quota cannot replace the new account quota',
      (tester) async {
    final old = Completer<SubscriptionStatusResult>();
    final current = Completer<SubscriptionStatusResult>();
    var calls = 0;
    final fixture = VideoEnglishFixture()
      ..quotaRespond = () => ++calls == 1 ? old.future : current.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'new-video-owner', idToken: 'new-token'));
    await tester.pumpAndSettle();
    old.complete(fixture.quota);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('uploader-post-quota-strip')), findsNothing);
    current.complete(const SubscriptionStatusResult(
        userId: 'new-video-owner',
        plan: 'BASIC',
        status: 'INACTIVE',
        monthlyPostLimit: 3,
        usedPostsThisMonth: 0,
        remainingPostsThisMonth: 3,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false));
    await tester.pumpAndSettle();
    await revealVideoEnglishControl(
        tester, find.byKey(const ValueKey('uploader-post-quota-strip')));
    expect(find.text('3 / 3 units', findRichText: true), findsOneWidget);
    expect(find.text('240 / 250 units', findRichText: true), findsNothing);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(fixture.quotaReads, 2);
    expect(fixture.picks, 0);
    expect(tester.takeException(), isNull);
  });

  for (final paid in [false, true]) {
    testWidgets(
        'post quota keeps paid add-ons and Basic verification gates (paid=$paid)',
        (tester) async {
      final fixture = VideoEnglishFixture()
        ..quota = SubscriptionStatusResult(
            userId: videoEnglishOwner,
            plan: paid ? 'PRO' : 'BASIC',
            status: paid ? 'ACTIVE' : 'INACTIVE',
            monthlyPostLimit: paid ? 250 : 3,
            usedPostsThisMonth: paid ? 10 : 1,
            remainingPostsThisMonth: paid ? 240 : 2,
            addonPostUnits: 40,
            requiresPhoneVerification: !paid,
            canSchedule: paid,
            canUseAiCaptions: paid,
            canUseAnalytics: paid);
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      await revealVideoEnglishControl(
          tester, find.byKey(const ValueKey('uploader-post-quota-strip')));
      expect(find.text(paid ? 'Pro' : 'Basic'), findsOneWidget);
      if (paid) {
        expect(find.text('+ 40 add-on units'), findsOneWidget);
        expect(
            find.text('240 / 250 units', findRichText: true), findsOneWidget);
      } else {
        expect(find.text('+ 40 add-on units'), findsNothing);
        expect(find.text('Verify your phone number to use the free quota'),
            findsOneWidget);
        expect(find.text('1 unit used'), findsOneWidget);
        expect(find.text('2 / 3 units', findRichText: true), findsOneWidget);
      }
      expect(fixture.quota.addonPostUnits, 40);
      expect(fixture.store.savedRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('plain MaterialApp retains the existing Thai uploader fallback',
      (tester) async {
    final fixture = VideoEnglishFixture();
    addTearDown(fixture.dispose);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: fixture.screen())));
    await tester.pumpAndSettle();
    expect(find.text('สร้างโพสต์ใหม่'), findsOneWidget);
    expect(find.text('ขั้นตอนที่ 1 จาก 4 · เลือกคลิป'), findsOneWidget);
    expect(find.text('บันทึกร่าง'), findsOneWidget);
    expect(find.text('ถัดไป: เขียนแคปชัน'), findsOneWidget);
    expect(find.text('Create post'), findsNothing);
    expect(fixture.picks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'all four shared progress semantics use English without opening later bodies',
      (tester) async {
    final fixture = VideoEnglishFixture();
    addTearDown(fixture.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await fixture.mount(tester);
      final titles = [
        'Choose video',
        'Write caption',
        'Choose channels',
        'Review'
      ];
      for (var index = 0; index < 4; index++) {
        final step = tester
            .getSemantics(find.byKey(ValueKey('uploader-progress-$index')))
            .getSemanticsData();
        expect(
            step.label, contains('Step ${index + 1} of 4 · ${titles[index]}'));
        if (index == 0) {
          expect(step.flagsCollection.isSelected.toBoolOrNull(), isTrue);
        }
      }
      expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('uploader-caption-field')), findsNothing);
      expect(fixture.store.savedRequests, isEmpty);
      expect(fixture.picks, 0);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final dark in [false, true]) {
    testWidgets('empty video step and draft picker fit 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = VideoEnglishFixture(dark: dark, scale: 2);
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      expect(tester.takeException(), isNull);
      for (final text in [
        'Create post',
        'Drafts (0)',
        'Save draft',
        'Video',
        'Caption',
        'Channels',
        'Review'
      ]) {
        await revealVideoEnglishControl(tester, find.text(text), header: true);
        expectVideoEnglishReadable(tester, find.text(text));
      }
      for (final text in [
        'Step 1 of 4 · Choose video',
        'Start with the vertical video you want to post.',
        'Choose a 9:16 video',
        'Post units remaining',
        '10 units used',
        'Choose a video first',
        'Next: Caption'
      ]) {
        await revealVideoEnglishControl(tester, find.text(text));
        expectVideoEnglishReadable(tester, find.text(text));
        expect(tester.takeException(), isNull);
      }
      await tapVideoEnglishControl(tester, 'uploader-wizard-next');
      await revealVideoEnglishControl(
          tester, find.text('Choose a video from your device first.'));
      expectVideoEnglishReadable(
          tester, find.text('Choose a video from your device first.'));
      await tapVideoEnglishControl(tester, 'uploader-open-drafts');
      await tester.drag(find.byKey(const ValueKey('uploader-drafts-scroll')),
          const Offset(0, -220));
      await tester.pumpAndSettle();
      for (final text in [
        'Drafts on this device',
        'Not uploaded, not sent to platforms, and no quota used.',
        'The app copies your video and cover into app storage on this device. Drafts do not sync across devices and may be included in system backups.',
        'No drafts on this device yet'
      ]) {
        await Scrollable.ensureVisible(tester.element(find.text(text)),
            alignment: 0.5);
        await tester.pumpAndSettle();
        expectVideoEnglishReadable(tester, find.text(text));
        expect(find.text(text).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(fixture.store.savedRequests, isEmpty);
      expect(fixture.picks, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected video and exit actions fit 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = VideoEnglishFixture(dark: dark, scale: 2);
      fixture.picked = fixture.makeVideo('ขาย.mp4');
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      await tapVideoEnglishControl(tester, 'uploader-video-preview-picker');
      expect(find.text('Video selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final text in [
        'ขาย.mp4',
        'Watch',
        'Change video',
        'Create cover',
        '0:10 min · 1080 × 1920 px · 9:16 · 2.0 KB',
        'Video selected',
        'Next: Caption'
      ]) {
        await revealVideoEnglishControl(tester, find.text(text));
        expectVideoEnglishReadable(tester, find.text(text));
      }
      await tapVideoEnglishControl(tester, 'uploader-close');
      for (final text in [
        'Keep this post?',
        'You have unsaved changes. You can continue editing from drafts.',
        'Keep editing',
        'Leave without saving',
        'Save and exit'
      ]) {
        await Scrollable.ensureVisible(tester.element(find.text(text)),
            alignment: 0.5);
        await tester.pumpAndSettle();
        expectVideoEnglishReadable(tester, find.text(text));
        expect(find.text(text).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await revealVideoEnglishControl(
          tester, find.byKey(const ValueKey('uploader-step-video')));
      expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
      expect(fixture.store.savedRequests, isEmpty);
      expect(fixture.picks, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
