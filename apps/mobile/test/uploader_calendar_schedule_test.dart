import 'dart:io';

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
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> _chooseSchedule(WidgetTester tester) async {
  await _showSchedule(tester);
  await tester.tap(find.byKey(const ValueKey('uploader-schedule-later')));
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
