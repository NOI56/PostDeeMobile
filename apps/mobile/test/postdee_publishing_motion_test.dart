import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/shared/postdee_publishing_motion.dart';

const _railKey = ValueKey('postdee-publishing-rail');

Widget _app(
  Widget child, {
  bool reduceMotion = false,
  bool tickerEnabled = true,
  double textScale = 1,
}) =>
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: TickerMode(
            enabled: tickerEnabled,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

Widget _sendingHost({
  bool sending = true,
  bool animate = true,
  bool reduceMotion = false,
  bool tickerEnabled = true,
  String label = 'กำลังส่ง',
}) =>
    _app(
      PostDeePublishingMotion(
        sending: sending,
        animate: animate,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PostDeePublishingBadge(
              label: label,
              background: Colors.green.shade50,
              foreground: Colors.green.shade800,
              sending: true,
            ),
            const SizedBox(height: 8),
            const PostDeePublishingRail(),
            const SizedBox(height: 8),
            const PostDeePlatformDeliveryRow(
              platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
              results: [
                PostPlatformResult(
                  postId: 'post-1',
                  platform: 'TIKTOK',
                  status: 'PUBLISHING',
                ),
                PostPlatformResult(
                  postId: 'post-1',
                  platform: 'YOUTUBE_SHORTS',
                  status: 'PENDING',
                ),
              ],
            ),
          ],
        ),
      ),
      reduceMotion: reduceMotion,
      tickerEnabled: tickerEnabled,
    );

Widget _guardedHost(String guard, bool blocked) => _sendingHost(
      sending: guard != 'sending' || !blocked,
      animate: guard != 'animate' || !blocked,
      reduceMotion: guard == 'reduced' && blocked,
      tickerEnabled: guard != 'ticker' || !blocked,
    );

Finder _syncRotations() => find.ancestor(
      of: find.byIcon(Icons.sync_rounded),
      matching: find.byType(RotationTransition),
    );

AnimationController _badgeController(WidgetTester tester) {
  final rotation = find.ancestor(
    of: find.descendant(
      of: find.byType(PostDeePublishingBadge),
      matching: find.byIcon(Icons.sync_rounded),
    ),
    matching: find.byType(RotationTransition),
  );
  final turns = tester.widget<RotationTransition>(rotation.first).turns;
  expect(turns, isA<AnimationController>());
  for (final transition in tester.widgetList<RotationTransition>(rotation)) {
    expect(transition.turns, same(turns),
        reason:
            'Incoming and outgoing badge icons keep the same motion phase.');
  }
  return turns as AnimationController;
}

void _resume(TestWidgetsFlutterBinding binding) {
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.binding.hasScheduledFrame, isFalse);
  expect(tester.takeException(), isNull);
}

PostPlatformResult _result({
  String platform = 'TIKTOK',
  required String status,
  String? outcome,
}) =>
    PostPlatformResult(
      postId: 'post-1',
      platform: platform,
      status: status,
      deliveryOutcome: outcome,
    );

void main() {
  setUp(() => _resume(TestWidgetsFlutterBinding.ensureInitialized()));
  tearDown(() => _resume(TestWidgetsFlutterBinding.ensureInitialized()));

  testWidgets('badge and sending channel share a running motion phase',
      (tester) async {
    await tester.pumpWidget(_sendingHost());
    expect(find.byKey(_railKey), findsOneWidget);
    expect(_syncRotations(), findsNWidgets(2));
    final controller = _badgeController(tester);
    for (final rotation
        in tester.widgetList<RotationTransition>(_syncRotations())) {
      expect(rotation.turns, same(controller));
    }
    expect(controller.isAnimating, isTrue);
    expect(controller.value, 0);
    await tester.pump(const Duration(milliseconds: 260));
    final phase = controller.value;
    expect(phase, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.value, isNot(phase));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await _dispose(tester);
  });

  for (final guard in [
    'sending',
    'animate',
    'reduced',
    'ticker',
    'background'
  ]) {
    testWidgets('$guard stops and resets sending motion, then restarts fresh',
        (tester) async {
      await tester.pumpWidget(_guardedHost(guard, false));
      await tester.pump(const Duration(milliseconds: 260));
      final controller = _badgeController(tester);
      expect(controller.isAnimating, isTrue);
      expect(controller.value, greaterThan(0));

      if (guard == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
        await tester.pump();
      } else {
        await tester.pumpWidget(_guardedHost(guard, true));
      }
      expect(_badgeController(tester), same(controller));
      expect(controller.isAnimating, isFalse);
      expect(controller.value, 0);
      expect(find.byKey(_railKey), findsOneWidget,
          reason: 'Static motion must keep the sending information visible.');
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      if (guard == 'background') {
        _resume(tester.binding);
        await tester.pump();
      } else {
        await tester.pumpWidget(_guardedHost(guard, false));
      }
      expect(_badgeController(tester), same(controller));
      expect(controller.isAnimating, isTrue);
      expect(controller.value, 0,
          reason: 'Re-enabling motion must not replay an old phase.');
      await tester.pump(const Duration(milliseconds: 120));
      expect(controller.value, greaterThan(0));
      await _dispose(tester);
    });

    testWidgets('$guard at creation remains static without scheduling frames',
        (tester) async {
      if (guard == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
      }
      await tester.pumpWidget(_guardedHost(guard, true));
      final controller = _badgeController(tester);
      expect(controller.isAnimating, isFalse);
      expect(controller.value, 0);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.byKey(_railKey), findsOneWidget);
      await _dispose(tester);
    });
  }

  testWidgets('ordinary content rebuild keeps the current sending phase',
      (tester) async {
    await tester.pumpWidget(_sendingHost());
    await tester.pump(const Duration(milliseconds: 260));
    final controller = _badgeController(tester);
    final phase = controller.value;
    await tester.pumpWidget(_sendingHost(label: 'กำลังส่งไปยังช่องทาง'));
    expect(find.text('กำลังส่งไปยังช่องทาง'), findsOneWidget);
    expect(_badgeController(tester), same(controller));
    expect(controller.value, phase);
    expect(controller.isAnimating, isTrue);
    await _dispose(tester);
  });

  testWidgets('removing an active motion scope leaves no scheduled frames',
      (tester) async {
    await tester.pumpWidget(_sendingHost());
    await tester.pump(const Duration(milliseconds: 260));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await _dispose(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  final publishedLabels = <String, String>{
    'DRAFT': 'ส่งเป็นร่างแล้ว',
    'PRIVATE': 'ส่วนตัว',
    'UNLISTED': 'ไม่แสดงในรายการ',
    'LIVE': 'เผยแพร่แล้ว',
  };
  for (final entry in publishedLabels.entries) {
    testWidgets('published ${entry.key} uses the confirmed delivery outcome',
        (tester) async {
      await tester.pumpWidget(_app(PostDeePlatformDeliveryRow(
        platforms: const ['TIKTOK'],
        results: [_result(status: 'PUBLISHED', outcome: entry.key)],
      )));
      expect(find.textContaining(entry.value), findsOneWidget);
      if (entry.key != 'LIVE') {
        expect(find.textContaining('เผยแพร่แล้ว'), findsNothing);
      }
      expect(_syncRotations(), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await _dispose(tester);
    });
  }

  final statusLabels = <String, String>{
    'PUBLISHED': 'เผยแพร่แล้ว',
    'FAILED': 'ส่งไม่สำเร็จ',
    'PUBLISHING': 'กำลังส่ง',
    'PENDING': 'รอส่ง',
    'UNRECOGNIZED': 'ผลยังไม่ยืนยัน',
  };
  test('English platform labels preserve delivery and missing-result states',
      () {
    expect(
        postPlatformDeliveryLabel(null, languageCode: 'en'), 'Awaiting result');
    for (final entry in {
      'PUBLISHED': 'Published',
      'FAILED': 'Failed',
      'PUBLISHING': 'Sending',
      'PENDING': 'Pending',
      'UNRECOGNIZED': 'Delivery unconfirmed',
    }.entries) {
      expect(
        postPlatformDeliveryLabel(_result(status: entry.key),
            languageCode: 'en'),
        entry.value,
      );
    }
    for (final entry in {
      'DRAFT': 'Sent as draft',
      'PRIVATE': 'Private',
      'UNLISTED': 'Unlisted',
      'LIVE': 'Published',
      'NEW_PROVIDER_OUTCOME': 'Delivery unconfirmed',
    }.entries) {
      expect(
        postPlatformDeliveryLabel(
            _result(status: 'PUBLISHED', outcome: entry.key),
            languageCode: 'en'),
        entry.value,
      );
    }
    expect(
      postPlatformDeliveryLabel(_result(status: 'FAILED', outcome: 'LIVE'),
          languageCode: 'en'),
      'Failed',
    );
  });

  testWidgets('English channel row forwards its language to visible labels',
      (tester) async {
    await tester.pumpWidget(_app(PostDeePlatformDeliveryRow(
      languageCode: 'en',
      platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
      results: [_result(status: 'PUBLISHED', outcome: 'DRAFT')],
    )));
    expect(find.text('TikTok · Sent as draft'), findsOneWidget);
    expect(find.text('Shorts · Awaiting result'), findsOneWidget);
    expect(find.textContaining('เผยแพร่แล้ว'), findsNothing);
    await _dispose(tester);
  });

  for (final entry in statusLabels.entries) {
    testWidgets('${entry.key} keeps its own platform delivery label',
        (tester) async {
      await tester.pumpWidget(_app(PostDeePublishingMotion(
        sending: entry.key == 'PUBLISHING',
        child: PostDeePlatformDeliveryRow(
          platforms: const ['TIKTOK'],
          results: [_result(status: entry.key)],
        ),
      )));
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(_syncRotations(),
          entry.key == 'PUBLISHING' ? findsOneWidget : findsNothing);
      await _dispose(tester);
    });
  }

  testWidgets('a failed status overrides a stale successful outcome',
      (tester) async {
    await tester.pumpWidget(_app(PostDeePlatformDeliveryRow(
      platforms: const ['TIKTOK'],
      results: [_result(status: 'FAILED', outcome: 'LIVE')],
    )));
    expect(find.textContaining('ส่งไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('เผยแพร่แล้ว'), findsNothing);
    expect(_syncRotations(), findsNothing);
    await _dispose(tester);
  });

  testWidgets('an unknown non-null outcome never claims live publication',
      (tester) async {
    await tester.pumpWidget(_app(PostDeePlatformDeliveryRow(
      platforms: const ['TIKTOK'],
      results: [_result(status: 'PUBLISHED', outcome: 'NEW_PROVIDER_OUTCOME')],
    )));
    expect(find.textContaining('ผลยังไม่ยืนยัน'), findsOneWidget);
    expect(find.textContaining('เผยแพร่แล้ว'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('missing selected results stay distinct from confirmed pending',
      (tester) async {
    await tester.pumpWidget(_app(PostDeePlatformDeliveryRow(
      platforms: const ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS'],
      results: [
        _result(platform: 'YOUTUBE_SHORTS', status: 'PENDING'),
        _result(platform: 'TIKTOK', status: 'PUBLISHED', outcome: 'DRAFT'),
        _result(platform: 'FACEBOOK', status: 'FAILED'),
      ],
    )));
    expect(find.textContaining('ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(find.textContaining('รอส่ง'), findsOneWidget);
    expect(find.textContaining('รอผล'), findsOneWidget);
    expect(find.textContaining('ส่งไม่สำเร็จ'), findsNothing,
        reason: 'Unselected platforms must not appear in this post row.');
    await _dispose(tester);
  });

  testWidgets('sending information fits 320px with large accessible text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(
      PostDeePublishingMotion(
        sending: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PostDeePublishingBadge(
              label: 'กำลังส่งไปยังช่องทางที่เลือก',
              background: Color(0xFFE7F7EE),
              foreground: Color(0xFF137A47),
              sending: true,
            ),
            const SizedBox(height: 8),
            const PostDeePublishingRail(),
            const SizedBox(height: 8),
            PostDeePlatformDeliveryRow(
              platforms: const [
                'TIKTOK',
                'YOUTUBE_SHORTS',
                'INSTAGRAM_REELS',
                'FACEBOOK',
              ],
              results: [
                _result(platform: 'TIKTOK', status: 'PUBLISHING'),
                _result(
                  platform: 'YOUTUBE_SHORTS',
                  status: 'PUBLISHED',
                  outcome: 'UNLISTED',
                ),
                _result(platform: 'INSTAGRAM_REELS', status: 'FAILED'),
              ],
            ),
          ],
        ),
      ),
      textScale: 2,
    ));
    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.takeException(), isNull,
        reason: 'A small screen and large text must not overflow.');
    expect(find.byKey(_railKey), findsOneWidget);
    expect(find.textContaining('ไม่แสดงในรายการ'), findsOneWidget);
    expect(find.textContaining('ส่งไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('รอผล'), findsOneWidget);
    final percentage = RegExp(r'\d+\s*%');
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(
          percentage.hasMatch(text.data ?? text.textSpan?.toPlainText() ?? ''),
          isFalse,
          reason:
              'Indeterminate sending must not invent a completion percent.');
    }
    await _dispose(tester);
  });
}
