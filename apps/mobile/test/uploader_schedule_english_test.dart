import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/uploader_wizard_test_navigation.dart';
import 'uploader_video_english_test.dart'
    show
        VideoEnglishFixture,
        videoEnglishOwner,
        expectVideoEnglishReadable,
        revealVideoEnglishControl;

SubscriptionStatusResult _subscription(String plan) => SubscriptionStatusResult(
    userId: videoEnglishOwner,
    plan: plan,
    status: 'ACTIVE',
    phoneVerified: true,
    requiresPhoneVerification: false,
    canSchedule: plan == 'PRO' || plan == 'STARTER',
    canUseAiCaptions: true,
    canUseAnalytics: true);

class _Fixture extends VideoEnglishFixture {
  _Fixture({super.dark, super.scale}) {
    initialVideo = makeVideo('คลิปกำหนดเวลาของลูกค้า.mp4');
  }

  DateTime clock = DateTime(2026, 10, 30, 12);
  DateTime? suggestion = DateTime(2026, 11, 3);
  String plan = 'PRO';
  int planReads = 0;
  int uploads = 0;
  final posts = <CreatePostRequest>[];
  final previewBoundary = GlobalKey();

  @override
  Widget app() => RepaintBoundary(key: previewBoundary, child: super.app());

  void restore(DateTime scheduledAt) {
    initialDraftId = 'schedule-draft';
    store.drafts[initialDraftId!] = PublishDraft(
        version: publishDraftManifestVersion,
        id: initialDraftId!,
        ownerUserId: videoEnglishOwner,
        submissionRequestId: 'submit_${List.filled(64, 'b').join()}',
        createdAt: DateTime.utc(2026, 10, 30),
        updatedAt: DateTime.utc(2026, 10, 30),
        videoPath: initialVideo!.path,
        videoName: initialVideo!.name,
        videoSizeBytes: File(initialVideo!.path).lengthSync(),
        videoWidth: 1080,
        videoHeight: 1920,
        caption: 'แคปชันของลูกค้า #สินค้า',
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: const {'INSTAGRAM_REELS'},
        platformSettings:
            const PlatformPublishSettings(instagramShareToFeed: false),
        scheduledAt: scheduledAt.toUtc());
  }

  @override
  UploaderScreen screen() => UploaderScreen(
      fullScreen: true,
      draftStore: store,
      enableRevenueCatBilling: false,
      initialDraftId: initialDraftId,
      initialScheduleDate: suggestion,
      initialVideoPath: initialDraftId == null ? initialVideo!.path : null,
      initialVideoName: initialVideo!.name,
      initialVideoSizeBytes: initialVideo!.sizeBytes,
      initialVideoWidth: initialVideo!.width,
      initialVideoHeight: initialVideo!.height,
      initialVideoDurationSeconds: initialVideo!.durationSeconds,
      now: () => clock,
      probePublishMedia: probeValidPublishMedia,
      loadTemplates: () async => const [],
      loadSubscription: () async {
        planReads++;
        return _subscription(plan);
      },
      loadPostQuota: () async => _subscription(plan),
      loadCaptionQuota: () async => const CaptionQuotaResult(
          plan: 'PRO',
          quota: RealClipCaptionQuota(
              limit: 120, usedThisMonth: 0, remainingThisMonth: 120)),
      loadSocialConnections: () async {
        connectionReads++;
        return const [
          SocialConnectionResult(
              platform: 'INSTAGRAM_REELS',
              connected: true,
              connectionId: 'local-instagram',
              externalAccountId: 'merchant-instagram',
              displayName: 'ร้านภาษาไทย')
        ];
      },
      loadSocialPublishingReadiness: () async => const [
            SocialPublishingConnectionReadiness(
                platform: 'INSTAGRAM_REELS',
                state: SocialPublishingState.connected,
                connectionId: 'local-instagram')
          ],
      checkPublishingReadiness: () async {},
      createUpload: (_) async {
        uploads++;
        return const UploadResult(
            id: 'upload',
            videoS3Key: 'uploads/schedule/video.mp4',
            storageProvider: 'mock');
      },
      uploadVideoFile: (_, __) async {},
      createPost: (request) async {
        posts.add(request);
        return QueuedPostResult(
            id: 'post',
            videoS3Key: request.videoS3Key,
            platforms: request.platforms,
            status: 'QUEUED');
      });
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await revealVideoEnglishControl(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _mount(WidgetTester tester, _Fixture fixture) async {
  addTearDown(fixture.dispose);
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await fixture.mount(tester);
  if (fixture.initialDraftId == null) {
    await goToUploaderStep(tester, 1);
    await tester.enterText(find.byKey(const ValueKey('uploader-caption-field')),
        'แคปชันของลูกค้า #สินค้า');
    await goToUploaderStep(tester, 2);
    await _tap(tester, 'uploader-platform-INSTAGRAM_REELS');
  }
  await goToUploaderStep(tester, 3);
  await revealVideoEnglishControl(
      tester, find.byKey(const ValueKey('uploader-schedule-panel')));
}

Future<void> _later(WidgetTester tester) =>
    _tap(tester, 'uploader-schedule-later');

Future<void> _wheels(WidgetTester tester, int hour, int minute) async {
  tester
      .widget<CupertinoPicker>(
          find.byKey(const ValueKey('postdee-time-hour-picker')))
      .scrollController!
      .jumpToItem(hour);
  tester
      .widget<CupertinoPicker>(
          find.byKey(const ValueKey('postdee-time-minute-picker')))
      .scrollController!
      .jumpToItem(minute);
  await tester.pumpAndSettle();
}

Future<void> _nativeButton(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Anuphan');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts
          .addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: videoEnglishOwner, idToken: 'fake-token'));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets(
      'English schedule labels and calendar hint leave suggestion uncommitted',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    for (final text in [
      'Post timing',
      'Post now',
      'Schedule',
      'Calendar date: 3 Nov 2026 · Tap Schedule to choose a time.',
      'Starter: schedule up to 14 days ahead · Pro: 30 days'
    ]) {
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('uploader-schedule-panel')),
              matching: find.text(text)),
          findsOneWidget);
    }
    expect(
        find.byKey(const ValueKey('uploader-schedule-summary')), findsNothing);
    expect(fixture.planReads, 0);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Post now clears the calendar suggestion and sends no scheduledAt',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _later(tester);
    expect(find.text('Post 3 Nov 2026 at 18:30'), findsOneWidget);
    await _tap(tester, 'uploader-schedule-now');
    expect(
        find.byKey(const ValueKey('uploader-schedule-summary')), findsNothing);
    expect(find.byKey(const ValueKey('uploader-calendar-date-hint')),
        findsNothing);
    await _tap(tester, 'publish-review-confirm');
    expect(fixture.posts, hasLength(1));
    expect(fixture.posts.single.scheduledAt, isNull);
    expect(fixture.posts.single.caption, 'แคปชันของลูกค้า #สินค้า');
    expect(fixture.uploads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English quick dates and times retain local intent in UTC draft',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _later(tester);
    for (final text in [
      'Today',
      'Tomorrow',
      'Choose date',
      'Choose time',
      'Custom'
    ]) {
      expect(find.text(text), findsWidgets);
    }
    await _tap(tester, 'uploader-schedule-day-today');
    expect(find.text('Post Today at 18:30'), findsOneWidget);
    await _tap(tester, 'uploader-schedule-day-tomorrow');
    await _tap(tester, 'uploader-schedule-time-0900');
    expect(find.text('Post Tomorrow at 09:00'), findsOneWidget);
    final previewDirectory =
        Platform.environment['POSTDEE_SCHEDULE_PREVIEW_DIR'];
    if (previewDirectory != null && previewDirectory.trim().isNotEmpty) {
      await tester
          .ensureVisible(find.byKey(const ValueKey('uploader-schedule-panel')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(
                find.byKey(fixture.previewBoundary))
            .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(previewDirectory).createSync(recursive: true);
        await File('$previewDirectory/review-schedule-en.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await _tap(tester, 'uploader-save-draft-button');
    expect(fixture.store.savedRequests.single.scheduledAt,
        DateTime(2026, 10, 31, 9).toUtc());
    expect(fixture.store.savedRequests.single.scheduledAt!.isUtc, isTrue);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English time wheel cancels then confirms exact custom UTC instant',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _later(tester);
    await _tap(tester, 'uploader-schedule-time-custom');
    for (final text in [
      'Choose posting time',
      'Hours',
      'Minutes',
      '3 Nov 2026 · Local device time',
      'Use 18:30'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    await _wheels(tester, 23, 59);
    await _tap(tester, 'postdee-time-cancel');
    expect(find.text('Post 3 Nov 2026 at 18:30'), findsOneWidget);
    await _tap(tester, 'uploader-schedule-time-custom');
    await _wheels(tester, 25, 61);
    await _tap(tester, 'postdee-time-confirm');
    expect(find.text('Post 3 Nov 2026 at 01:01'), findsOneWidget);
    await _tap(tester, 'uploader-save-draft-button');
    expect(fixture.store.savedRequests.single.scheduledAt,
        DateTime(2026, 11, 3, 1, 1).toUtc());
    expect(fixture.store.savedRequests.single.scheduledAt!.isUtc, isTrue);
    expect(fixture.uploads, 0);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English native date picker changes a date and preserves it on Cancel',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _later(tester);
    await _tap(tester, 'uploader-schedule-day-custom');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('November 2026'), findsWidgets);
    final picker =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    expect(picker.firstDate, DateTime(2026, 10, 30));
    expect(picker.lastDate, DateTime(2026, 11, 29));
    await _nativeButton(tester, '4');
    await _nativeButton(tester, 'OK');
    expect(find.text('Post 4 Nov 2026 at 18:30'), findsOneWidget);
    await _tap(tester, 'uploader-schedule-day-custom');
    await _nativeButton(tester, '5');
    await _nativeButton(tester, 'Cancel');
    expect(find.text('Post 4 Nov 2026 at 18:30'), findsOneWidget);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Schedule locale changes render only and keep saved UTC unchanged',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _later(tester);
    final checks = fixture.planReads;
    final reads = fixture.connectionReads;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ลงโพสต์ 3 พ.ย. 2026 เวลา 18:30 น.'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Post 3 Nov 2026 at 18:30'), findsOneWidget);
    expect(fixture.planReads, checks);
    expect(fixture.connectionReads, reads);
    expect(fixture.store.savedRequests, isEmpty);
    await _tap(tester, 'uploader-save-draft-button');
    expect(fixture.store.savedRequests.single.scheduledAt,
        DateTime(2026, 11, 3, 18, 30).toUtc());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Restored custom time overrides calendar hint and reaches API in UTC',
      (tester) async {
    final fixture = _Fixture();
    final instant = DateTime(2026, 11, 11, 16, 45);
    fixture.restore(instant);
    await _mount(tester, fixture);
    expect(find.text('Post 11 Nov 2026 at 16:45'), findsOneWidget);
    await _tap(tester, 'uploader-schedule-time-custom');
    final hour = tester
        .widget<CupertinoPicker>(
            find.byKey(const ValueKey('postdee-time-hour-picker')))
        .scrollController!;
    final minute = tester
        .widget<CupertinoPicker>(
            find.byKey(const ValueKey('postdee-time-minute-picker')))
        .scrollController!;
    expect(hour.selectedItem % 24, 16);
    expect(minute.selectedItem % 60, 45);
    await _tap(tester, 'postdee-time-cancel');
    await _tap(tester, 'publish-review-confirm');
    expect(fixture.posts.single.scheduledAt, instant.toUtc());
    expect(fixture.posts.single.scheduledAt!.isUtc, isTrue);
    expect(fixture.posts.single.platformSettings['INSTAGRAM_REELS'],
        {'shareToFeed': false});
    expect(tester.takeException(), isNull);
  });

  for (final plan in ['STARTER', 'PRO']) {
    testWidgets('English $plan date picker respects exact existing plan range',
        (tester) async {
      final fixture = _Fixture()..plan = plan;
      await _mount(tester, fixture);
      await _later(tester);
      await _tap(tester, 'uploader-schedule-day-custom');
      final picker =
          tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
      expect(picker.firstDate, DateTime(2026, 10, 30));
      expect(
          picker.lastDate,
          DateTime(2026, 10, 30)
              .add(Duration(days: plan == 'STARTER' ? 14 : 30)));
      await _nativeButton(tester, 'Cancel');
      expect(fixture.posts, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Downgrade clamps picker focus without changing restored schedule',
      (tester) async {
    final fixture = _Fixture()..plan = 'STARTER';
    final saved = DateTime(2026, 11, 24, 18, 30);
    fixture.restore(saved);
    await _mount(tester, fixture);
    expect(find.text('Post 24 Nov 2026 at 18:30'), findsOneWidget);
    await _tap(tester, 'uploader-schedule-day-custom');
    final picker =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    expect(picker.initialDate, DateTime(2026, 11, 13));
    expect(picker.lastDate, DateTime(2026, 11, 13));
    await _nativeButton(tester, 'Cancel');
    expect(find.text('Post 24 Nov 2026 at 18:30'), findsOneWidget);
    await _tap(tester, 'uploader-save-draft-button');
    expect(fixture.store.savedRequests.last.scheduledAt, saved.toUtc());
    await _tap(tester, 'publish-review-confirm');
    expect(fixture.uploads, 0);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Time wheel ignores stale owner session after A to B to A',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _later(tester);
    await _tap(tester, 'uploader-schedule-time-custom');
    await _wheels(tester, 23, 59);
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(const AuthSession(userId: 'other-owner', idToken: 'other'));
    sessions.signIn(
        const AuthSession(userId: videoEnglishOwner, idToken: 'fake-token'));
    await tester.pumpAndSettle();
    await _tap(tester, 'postdee-time-confirm');
    expect(find.text('Post 3 Nov 2026 at 18:30'), findsOneWidget);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Free plan stays immediate and shows existing English paid requirement',
      (tester) async {
    final fixture = _Fixture()..plan = 'BASIC';
    await _mount(tester, fixture);
    await _later(tester);
    expect(
        find.byKey(const ValueKey('uploader-schedule-summary')), findsNothing);
    expect(find.text('Scheduling requires Starter (199 THB) or Pro (299 THB).'),
        findsOneWidget);
    expect(fixture.posts, isEmpty);
    expect(fixture.uploads, 0);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('English schedule fits 320dp at ${scale}x dark=$dark',
          (tester) async {
        final fixture = _Fixture(dark: dark, scale: scale);
        await _mount(tester, fixture);
        await _later(tester);
        tester.view.physicalSize = const Size(320, 640);
        await tester.pumpAndSettle();
        for (final text in [
          'Post timing',
          'Post now',
          'Schedule',
          'Post 3 Nov 2026 at 18:30',
          'Today',
          'Tomorrow',
          'Choose date',
          'Choose time',
          'Custom',
          'Pro: schedule up to 30 days ahead'
        ]) {
          final finder = find.descendant(
              of: find.byKey(const ValueKey('uploader-schedule-panel')),
              matching: find.text(text));
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expectVideoEnglishReadable(tester, finder);
        }
        await _tap(tester, 'uploader-schedule-time-custom');
        expect(find.text('Choose posting time'), findsOneWidget);
        await _tap(tester, 'postdee-time-cancel');
        expect(fixture.posts, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
