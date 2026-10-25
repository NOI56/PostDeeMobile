import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/post_quota_strip.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

SubscriptionStatusResult quota(
        {String owner = 'post-quota-a',
        int used = 12,
        int? remaining,
        bool missing = false}) =>
    SubscriptionStatusResult(
      userId: owner,
      plan: 'STARTER',
      status: 'ACTIVE',
      monthlyPostLimit: missing ? null : 120,
      usedPostsThisMonth: missing ? null : used,
      remainingPostsThisMonth: missing ? null : remaining ?? 120 - used,
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: false,
    );

void main() {
  late PickedVideoFile clip;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(
        AuthSession.authenticated(userId: 'post-quota-a', idToken: 'token-a'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    final file = File(
        '${Directory.systemTemp.path}/post-quota-${DateTime.now().microsecondsSinceEpoch}.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    clip = PickedVideoFile(
        name: 'clip.mp4',
        path: file.path,
        sizeBytes: 512,
        width: 1080,
        height: 1920);
  });

  Future<void> pump(WidgetTester tester,
      {required UploaderSubscriptionLoader load,
      bool initialClip = true,
      UploaderVideoPicker? pick}) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UploaderScreen(
      draftStore: TestPublishDraftStore(ownerUserId: 'post-quota-a'),
      initialVideoPath: initialClip ? clip.path : null,
      initialVideoName: initialClip ? clip.name : null,
      initialVideoSizeBytes: initialClip ? clip.sizeBytes : null,
      initialVideoWidth: initialClip ? 1080 : null,
      initialVideoHeight: initialClip ? 1920 : null,
      pickVideo: pick ?? () async => clip,
      loadPostQuota: load,
      loadSocialConnections: () async => const [],
      loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
      probePublishMedia: probeValidPublishMedia,
      createUpload: (_) async =>
          throw StateError('Selecting a clip must not upload'),
      createPost: (_) async =>
          throw StateError('Selecting a clip must not publish'),
    ))));
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 100,
        scrollable: uploaderMainScroll);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'loads only after picking a clip and displays real monthly post units',
      (tester) async {
    var reads = 0;
    await pump(tester, initialClip: false, load: () async {
      reads++;
      return quota();
    });
    expect(reads, 0);
    expect(find.byType(PostQuotaStrip), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('uploader-video-preview-picker')));
    await tester.pumpAndSettle();
    await show(tester, find.byType(PostQuotaStrip));
    expect(reads, 1);
    expect(find.text('โพสต์คงเหลือ'), findsOneWidget);
    expect(find.text('108 / 120 หน่วย'), findsOneWidget);
    expect(find.text('ใช้ไป 12 หน่วย'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial clip loads quota but the strip stays on the clip step',
      (tester) async {
    await pump(tester, load: () async => quota());
    await show(tester, find.byType(PostQuotaStrip));
    await goToUploaderStep(tester, 1);
    expect(find.byType(PostQuotaStrip), findsNothing);
    await goToUploaderStep(tester, 0);
    expect(find.byType(PostQuotaStrip), findsOneWidget);
  });

  testWidgets('pending quota shows loading and never invents zero',
      (tester) async {
    final pending = Completer<SubscriptionStatusResult>();
    await pump(tester, load: () => pending.future);
    expect(find.byKey(const ValueKey('uploader-post-quota-loading')),
        findsOneWidget);
    expect(find.byType(PostQuotaStrip), findsNothing);
    pending.complete(quota());
    await tester.pumpAndSettle();
    expect(find.text('108 / 120 หน่วย'), findsOneWidget);
  });

  testWidgets('failed read has independent retry and does not block video flow',
      (tester) async {
    var reads = 0;
    await pump(tester, load: () async {
      if (++reads == 1) throw const ApiException('offline');
      return quota(used: 15);
    });
    final retry = find.byKey(const ValueKey('uploader-post-quota-retry'));
    await show(tester, retry);
    expect(find.byType(PostQuotaStrip), findsNothing);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('105 / 120 หน่วย'), findsOneWidget);
    await goToUploaderStep(tester, 1);
    expect(find.byKey(const ValueKey('uploader-step-caption')), findsOneWidget);
  });

  testWidgets(
      'missing quota fields and wrong-owner data show unavailable instead of numbers',
      (tester) async {
    var reads = 0;
    await pump(tester,
        load: () async =>
            ++reads == 1 ? quota(missing: true) : quota(owner: 'wrong-owner'));
    final retry = find.byKey(const ValueKey('uploader-post-quota-retry'));
    await show(tester, retry);
    expect(find.byType(PostQuotaStrip), findsNothing);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(retry, findsOneWidget);
    expect(find.byType(PostQuotaStrip), findsNothing);
  });

  testWidgets('resume refresh wins over an older in-flight read',
      (tester) async {
    final older = Completer<SubscriptionStatusResult>();
    var reads = 0;
    await pump(tester,
        load: () =>
            ++reads == 1 ? older.future : Future.value(quota(used: 18)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('102 / 120 หน่วย'), findsOneWidget);
    older.complete(quota());
    await tester.pumpAndSettle();
    expect(find.text('102 / 120 หน่วย'), findsOneWidget);
    expect(find.text('108 / 120 หน่วย'), findsNothing);
  });

  testWidgets(
      'reselecting even the same clip refreshes without waiting for an older read',
      (tester) async {
    final older = Completer<SubscriptionStatusResult>();
    var reads = 0;
    await pump(tester,
        load: () =>
            ++reads == 1 ? older.future : Future.value(quota(used: 20)));
    final change = find.byKey(const ValueKey('uploader-video-preview-picker'));
    await show(tester, change);
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(reads, 2);
    older.complete(quota());
    await tester.pumpAndSettle();
    expect(find.text('100 / 120 หน่วย'), findsOneWidget);
  });

  testWidgets('logout clears quota and ignores the old account response',
      (tester) async {
    final old = Completer<SubscriptionStatusResult>();
    var reads = 0;
    await pump(tester,
        load: () => ++reads == 1 ? Future.value(quota()) : old.future);
    expect(find.byType(PostQuotaStrip), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    PostDeeAuthSessionStore.instance.clear();
    await tester.pumpAndSettle();
    old.complete(quota(used: 20));
    await tester.pumpAndSettle();
    expect(find.byType(PostQuotaStrip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a different clip rejects the earlier quota response',
      (tester) async {
    final older = Completer<SubscriptionStatusResult>();
    final replacement = File('${clip.path}.replacement.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    addTearDown(() {
      if (replacement.existsSync()) replacement.deleteSync();
    });
    var reads = 0;
    await pump(tester,
        load: () => ++reads == 1 ? older.future : Future.value(quota(used: 20)),
        pick: () async => PickedVideoFile(
            name: 'replacement.mp4',
            path: replacement.path,
            sizeBytes: 512,
            width: 1080,
            height: 1920));
    final change = find.byKey(const ValueKey('uploader-video-preview-picker'));
    await show(tester, change);
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(reads, 2);
    older.complete(quota());
    await tester.pumpAndSettle();
    expect(find.text('100 / 120 หน่วย'), findsOneWidget);
    expect(find.text('108 / 120 หน่วย'), findsNothing);
  });

  testWidgets('same-owner re-sign-in rejects quota from the previous session',
      (tester) async {
    final older = Completer<SubscriptionStatusResult>();
    var reads = 0;
    await pump(tester,
        load: () => ++reads == 1 ? older.future : Future.value(quota(used: 5)));
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'post-quota-a', idToken: 'new-session-token'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    older.complete(quota());
    await tester.pumpAndSettle();
    expect(find.text('115 / 120 หน่วย'), findsOneWidget);
    expect(find.text('108 / 120 หน่วย'), findsNothing);
  });

  testWidgets('a disposed composer ignores a pending quota response',
      (tester) async {
    final pending = Completer<SubscriptionStatusResult>();
    await pump(tester, load: () => pending.future);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    pending.complete(quota());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
