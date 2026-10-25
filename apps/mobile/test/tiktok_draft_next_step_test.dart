import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/shared/tiktok_draft_next_step.dart';

void main() {
  PostPlatformResult result({
    String platform = 'TIKTOK',
    String status = 'PUBLISHED',
    String? outcome = 'DRAFT',
  }) =>
      PostPlatformResult(
        postId: 'post-1',
        platform: platform,
        status: status,
        deliveryOutcome: outcome,
      );

  test(
      'requires a confirmed TikTok draft and keeps other channel results independent',
      () {
    expect(hasConfirmedTikTokDraft([result()]), isTrue);
    expect(
        hasConfirmedTikTokDraft([
          result(),
          result(platform: 'YOUTUBE_SHORTS', status: 'FAILED', outcome: null),
        ]),
        isTrue);
    expect(hasConfirmedTikTokDraft(const []), isFalse);
    expect(
        hasConfirmedTikTokDraft([result(platform: 'FACEBOOK_REELS')]), isFalse);
    for (final status in ['FAILED', 'PENDING', 'PUBLISHING', 'QUEUED']) {
      expect(hasConfirmedTikTokDraft([result(status: status)]), isFalse);
    }
    for (final outcome in [null, 'LIVE', 'PRIVATE', 'UNLISTED', 'FUTURE']) {
      expect(hasConfirmedTikTokDraft([result(outcome: outcome)]), isFalse);
    }
  });

  testWidgets('opens only the fixed public TikTok URL after an explicit tap',
      (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TikTokDraftNextStepCard(launchTikTokUrl: (uri) async {
          opened.add(uri);
          return true;
        }),
      ),
    ));
    expect(opened, isEmpty);
    expect(find.textContaining('ยังไม่ใช่การเผยแพร่ให้ผู้ชม'), findsOneWidget);
    expect(find.textContaining('Inbox'), findsOneWidget);
    expect(find.textContaining('อาจเปิดเป็นเว็บไซต์'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tiktok-draft-open')));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://www.tiktok.com/')]);
  });

  for (final throws in [false, true]) {
    testWidgets(
        'keeps manual instructions when TikTok launch fails (throws=$throws)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TikTokDraftNextStepCard(launchTikTokUrl: (_) async {
            if (throws) throw StateError('no external application');
            return false;
          }),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('tiktok-draft-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tiktok-draft-open-error')),
          findsOneWidget);
      expect(find.textContaining('เปิดแอป TikTok ด้วยตนเอง'), findsOneWidget);
      expect(find.textContaining('Inbox'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('prevents repeated launches while the external opener is pending',
      (tester) async {
    final opening = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TikTokDraftNextStepCard(launchTikTokUrl: (_) {
          calls++;
          return opening.future;
        }),
      ),
    ));
    final button = find.byKey(const ValueKey('tiktok-draft-open'));
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(calls, 1);
    opening.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  testWidgets('instructions remain readable on a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
            body: ListView(children: const [TikTokDraftNextStepCard()])),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('เผยแพร่ต่อใน TikTok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
