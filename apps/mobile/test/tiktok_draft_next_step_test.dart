import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
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

  testWidgets('English TikTok instructions open only the fixed public URL',
      (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TikTokDraftNextStepCard(
          languageCode: 'en',
          launchTikTokUrl: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    ));
    expect(find.text('Continue in TikTok'), findsOneWidget);
    expect(
        find.text('A draft is not published to viewers. Open the TikTok app '
            'with your connected account, go to Inbox, and tap the notification '
            'to review, edit, and publish it yourself.'),
        findsOneWidget);
    expect(
        find.text('This button may open a website. If it does, open the TikTok '
            'app yourself. This does not send your video again.'),
        findsOneWidget);
    expect(find.text('Open TikTok'), findsOneWidget);
    expect(opened, isEmpty);
    await tester.tap(find.byKey(const ValueKey('tiktok-draft-open')));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://www.tiktok.com/')]);
    expect(tester.takeException(), isNull);
  });

  for (final throws in [false, true]) {
    testWidgets(
        'English launch failure offers manual Inbox steps (throws=$throws)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TikTokDraftNextStepCard(
            languageCode: 'en',
            launchTikTokUrl: (_) async {
              if (throws) throw StateError('no external application');
              return false;
            },
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('tiktok-draft-open')));
      await tester.pumpAndSettle();
      expect(
          find.text('Could not open TikTok. Open the TikTok app yourself '
              'and check Inbox.'),
          findsOneWidget);
      expect(find.text('Open TikTok'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'failed TikTok launch changes Thai to English without relaunching',
      (tester) async {
    var calls = 0;
    Future<bool> open(Uri _) async {
      calls++;
      return false;
    }

    Widget app(String languageCode) => MaterialApp(
          home: Scaffold(
            body: TikTokDraftNextStepCard(
              key: const ValueKey('stable-tiktok-card'),
              languageCode: languageCode,
              launchTikTokUrl: open,
            ),
          ),
        );
    await tester.pumpWidget(app('th'));
    await tester.tap(find.byKey(const ValueKey('tiktok-draft-open')));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'เปิด TikTok ไม่สำเร็จ กรุณาเปิดแอป TikTok ด้วยตนเอง แล้วตรวจ Inbox'),
        findsOneWidget);
    expect(calls, 1);
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();
    expect(find.text('Continue in TikTok'), findsOneWidget);
    expect(
        find.text('Could not open TikTok. Open the TikTok app yourself '
            'and check Inbox.'),
        findsOneWidget);
    expect(calls, 1);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.data ?? '', isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('English opening label stays disabled until one launch completes',
      (tester) async {
    final opening = Completer<bool>();
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TikTokDraftNextStepCard(
          languageCode: 'en',
          launchTikTokUrl: (uri) {
            opened.add(uri);
            return opening.future;
          },
        ),
      ),
    ));
    final button = find.byKey(const ValueKey('tiktok-draft-open'));
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Opening TikTok...'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    await tester.tap(button);
    await tester.pump();
    expect(opened, [Uri.parse('https://www.tiktok.com/')]);
    opening.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Open TikTok'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  for (final dark in [false, true]) {
    testWidgets('English TikTok instructions fit 320dp at 2x text (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
      addTearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));
      await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(children: const [
            TikTokDraftNextStepCard(languageCode: 'en'),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Continue in TikTok'), findsOneWidget);
      final button = find.byKey(const ValueKey('tiktok-draft-open'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
