import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

SubscriptionStatusResult _subscription(String plan) => SubscriptionStatusResult(
      userId: 'calendar-seller',
      plan: plan,
      status: plan == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
      canSchedule: plan != 'BASIC',
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );

Future<void> _showSchedule(WidgetTester tester) async {
  await goToUploaderStep(tester, 3);
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('uploader-schedule-later')),
    250,
    scrollable: uploaderMainScroll,
  );
}

Future<void> _chooseSchedule(WidgetTester tester) async {
  await _showSchedule(tester);
  await tester.tap(find.byKey(const ValueKey('uploader-schedule-later')));
  await tester.pumpAndSettle();
}

Future<TestPublishDraftStore> _openCustomTime(WidgetTester tester,
    {bool withClip = false}) async {
  final store = TestPublishDraftStore(ownerUserId: 'calendar-seller');
  File? clip;
  if (withClip) {
    clip = File('${Directory.systemTemp.path}/wheel-time-'
        '${DateTime.now().microsecondsSinceEpoch}.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    final clipFile = clip;
    addTearDown(() {
      if (clipFile.existsSync()) clipFile.deleteSync();
    });
  }
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: UploaderScreen(
    probePublishMedia: probeValidPublishMedia,
    loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
    initialScheduleDate: DateTime(2026, 10, 15),
    initialVideoPath: clip?.path,
    initialVideoName: clip == null ? null : 'wheel-time.mp4',
    initialVideoSizeBytes: clip == null ? null : 512,
    initialVideoWidth: clip == null ? null : 1080,
    initialVideoHeight: clip == null ? null : 1920,
    now: () => DateTime(2026, 10, 11, 12),
    draftStore: store,
    loadSocialConnections: () async => const [],
    loadSubscription: () async => _subscription('PRO'),
    createUpload: (_) async => throw StateError('Draft saves must not upload'),
    createPost: (_) async => throw StateError('Draft saves must not publish'),
  ))));
  await tester.pumpAndSettle();
  await _chooseSchedule(tester);
  final custom = find.byKey(const ValueKey('uploader-schedule-time-custom'));
  await tester.ensureVisible(custom);
  await tester.tap(custom);
  await tester.pumpAndSettle();
  return store;
}

Future<void> _setTimeWheels(WidgetTester tester, int hour, int minute) async {
  final hourPicker = tester.widget<CupertinoPicker>(
      find.byKey(const ValueKey('postdee-time-hour-picker')));
  final minutePicker = tester.widget<CupertinoPicker>(
      find.byKey(const ValueKey('postdee-time-minute-picker')));
  hourPicker.scrollController!.jumpToItem(hour);
  minutePicker.scrollController!.jumpToItem(minute);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(userId: 'calendar-seller', idToken: 'test-token'),
    );
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets('custom looping time keeps the suggested calendar date',
      (tester) async {
    final store = await _openCustomTime(tester);
    expect(find.byKey(const ValueKey('postdee-time-picker')), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
    await _setTimeWheels(tester, 25, 61);
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('ลงโพสต์ 15 ต.ค. 2026 เวลา 01:01 น.'), findsOneWidget);
    expect(store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom time cancellation keeps the previous time on reopen',
      (tester) async {
    final store = await _openCustomTime(tester);
    expect(find.byKey(const ValueKey('postdee-time-picker')), findsOneWidget);
    await _setTimeWheels(tester, 23, 59);
    await tester.tap(find.byKey(const ValueKey('postdee-time-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('ลงโพสต์ 15 ต.ค. 2026 เวลา 18:30 น.'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('uploader-schedule-time-custom')));
    await tester.pumpAndSettle();
    final hour = tester.widget<CupertinoPicker>(
        find.byKey(const ValueKey('postdee-time-hour-picker')));
    final minute = tester.widget<CupertinoPicker>(
        find.byKey(const ValueKey('postdee-time-minute-picker')));
    expect(hour.scrollController!.selectedItem % 24, 18);
    expect(minute.scrollController!.selectedItem % 60, 30);
    expect(store.savedRequests, isEmpty);
    await tester.tap(find.byKey(const ValueKey('postdee-time-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('confirmed custom time saves the same local instant in UTC',
      (tester) async {
    final store = await _openCustomTime(tester, withClip: true);
    await _setTimeWheels(tester, 25, 61);
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('uploader-save-draft-button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.savedRequests, hasLength(1));
    final scheduled = store.savedRequests.single.scheduledAt!;
    expect(scheduled.isUtc, isTrue);
    expect(scheduled, DateTime(2026, 10, 15, 1, 1).toUtc());
  });

  testWidgets('custom time ignores an earlier signed-in session after A-B-A',
      (tester) async {
    final store = await _openCustomTime(tester);
    expect(find.byKey(const ValueKey('postdee-time-picker')), findsOneWidget);
    await _setTimeWheels(tester, 23, 59);
    final sessions = PostDeeAuthSessionStore.instance;
    sessions
        .signIn(const AuthSession(userId: 'other-seller', idToken: 'other'));
    sessions.signIn(
        const AuthSession(userId: 'calendar-seller', idToken: 'test-token'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('ลงโพสต์ 15 ต.ค. 2026 เวลา 18:30 น.'), findsOneWidget);
    expect(store.savedRequests, isEmpty);
  });

  testWidgets('calendar date is a suggestion until scheduling is chosen',
      (tester) async {
    var planChecks = 0;
    final store = TestPublishDraftStore();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      initialScheduleDate: DateTime(2026, 10, 15, 8),
      now: () => DateTime(2026, 10, 11, 12),
      draftStore: store,
      loadSocialConnections: () async => const [],
      loadSubscription: () async {
        planChecks++;
        return _subscription('PRO');
      },
    ))));
    await tester.pumpAndSettle();
    await _showSchedule(tester);
    expect(find.textContaining('15 ต.ค. 2026'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('uploader-schedule-summary')), findsNothing);
    expect(planChecks, 0);
    expect(store.savedRequests, isEmpty);
    await _chooseSchedule(tester);
    expect(find.text('ลงโพสต์ 15 ต.ค. 2026 เวลา 18:30 น.'), findsOneWidget);
    expect(planChecks, 1);
    expect(store.savedRequests, isEmpty);
  });

  testWidgets('schedule choices provide at least 48dp touch targets',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      now: () => DateTime(2026, 10, 11, 12),
      draftStore: TestPublishDraftStore(),
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _subscription('PRO'),
    ))));
    await tester.pumpAndSettle();
    await _showSchedule(tester);
    for (final key in ['uploader-schedule-now', 'uploader-schedule-later']) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height,
          greaterThanOrEqualTo(48));
    }
    await _chooseSchedule(tester);
    for (final key in [
      'uploader-schedule-day-custom',
      'uploader-schedule-time-custom'
    ]) {
      final choice = find.byKey(ValueKey(key));
      await tester.ensureVisible(choice);
      expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar suggestion does not enable scheduling on Free',
      (tester) async {
    final store = TestPublishDraftStore();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      initialScheduleDate: DateTime(2026, 10, 15),
      now: () => DateTime(2026, 10, 11, 12),
      draftStore: store,
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _subscription('BASIC'),
    ))));
    await tester.pumpAndSettle();
    await _chooseSchedule(tester);
    expect(
        find.byKey(const ValueKey('uploader-schedule-summary')), findsNothing);
    expect(find.text(schedulePaidPlanMessage), findsOneWidget);
    expect(store.savedRequests, isEmpty);
  });

  testWidgets('calendar today suggests a future time after the default passed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      initialScheduleDate: DateTime(2026, 10, 11),
      now: () => DateTime(2026, 10, 11, 20),
      draftStore: TestPublishDraftStore(),
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _subscription('PRO'),
    ))));
    await tester.pumpAndSettle();
    await _chooseSchedule(tester);
    expect(find.text('ลงโพสต์ วันนี้ เวลา 20:05 น.'), findsOneWidget);
  });

  testWidgets('UTC injected clock formats the selected local day and time',
      (tester) async {
    final clockUtc = DateTime.utc(2026, 10, 11, 23, 30);
    final localNow = clockUtc.toLocal();
    final localDay = DateTime(localNow.year, localNow.month, localNow.day);
    final defaultTime =
        DateTime(localNow.year, localNow.month, localNow.day, 18, 30);
    final expectedTime = defaultTime.isAfter(localNow)
        ? defaultTime
        : localNow.add(const Duration(minutes: 5));
    final expectedHour = expectedTime.hour.toString().padLeft(2, '0');
    final expectedMinute = expectedTime.minute.toString().padLeft(2, '0');
    final store = TestPublishDraftStore();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      initialScheduleDate: localDay,
      now: () => clockUtc,
      draftStore: store,
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _subscription('PRO'),
    ))));
    await tester.pumpAndSettle();
    await _chooseSchedule(tester);
    expect(find.text('ลงโพสต์ วันนี้ เวลา $expectedHour:$expectedMinute น.'),
        findsOneWidget);
    expect(store.savedRequests, isEmpty);
  });

  testWidgets('past calendar suggestion is ignored', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      initialScheduleDate: DateTime(2026, 10, 10),
      now: () => DateTime(2026, 10, 11, 12),
      draftStore: TestPublishDraftStore(),
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _subscription('PRO'),
    ))));
    await tester.pumpAndSettle();
    await _chooseSchedule(tester);
    expect(find.text('ลงโพสต์ พรุ่งนี้ เวลา 18:30 น.'), findsOneWidget);
  });

  testWidgets('calendar today never rolls silently into tomorrow at midnight',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      initialScheduleDate: DateTime(2026, 10, 11),
      now: () => DateTime(2026, 10, 11, 23, 59, 30),
      draftStore: TestPublishDraftStore(),
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _subscription('PRO'),
    ))));
    await tester.pumpAndSettle();
    await _chooseSchedule(tester);
    expect(
        find.byKey(const ValueKey('uploader-schedule-summary')), findsNothing);
    expect(find.textContaining('วันนี้ไม่มีเวลาเหลือสำหรับตั้งโพสต์'),
        findsOneWidget);
  });

  testWidgets('post now discards the calendar suggestion', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      initialScheduleDate: DateTime(2026, 10, 15),
      now: () => DateTime(2026, 10, 11, 12),
      draftStore: TestPublishDraftStore(),
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _subscription('PRO'),
    ))));
    await tester.pumpAndSettle();
    await _showSchedule(tester);
    await tester.tap(find.byKey(const ValueKey('uploader-schedule-now')));
    await tester.pumpAndSettle();
    await _chooseSchedule(tester);
    expect(find.text('ลงโพสต์ พรุ่งนี้ เวลา 18:30 น.'), findsOneWidget);
  });

  testWidgets('calendar date never overrides a resumed draft schedule',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('calendar-draft-');
    final video = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = TestPublishDraftStore(ownerUserId: 'calendar-seller');
    store.drafts['saved'] = PublishDraft(
      version: publishDraftManifestVersion,
      id: 'saved',
      ownerUserId: 'calendar-seller',
      submissionRequestId: 'submit_${List.filled(64, 'a').join()}',
      createdAt: DateTime(2026, 10, 11).toUtc(),
      updatedAt: DateTime(2026, 10, 11).toUtc(),
      videoPath: video.path,
      videoName: 'clip.mp4',
      videoSizeBytes: video.lengthSync(),
      videoWidth: 1080,
      videoHeight: 1920,
      caption: 'แคปชันเดิม',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: const {},
      scheduledAt: DateTime(2026, 10, 12, 16).toUtc(),
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      probePublishMedia: probeValidPublishMedia,
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      initialScheduleDate: DateTime(2026, 10, 15),
      initialDraftId: 'saved',
      now: () => DateTime(2026, 10, 11, 12),
      draftStore: store,
      loadSocialConnections: () async => const [],
      loadSubscription: () async => _subscription('PRO'),
    ))));
    await tester.pumpAndSettle();
    await _showSchedule(tester);
    expect(find.text('ลงโพสต์ พรุ่งนี้ เวลา 16:00 น.'), findsOneWidget);
    expect(find.textContaining('15 ต.ค. 2026'), findsNothing);
    expect(store.savedRequests, isEmpty);
  });
}
