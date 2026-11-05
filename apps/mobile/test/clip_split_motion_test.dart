import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_split_plan.dart';
import 'package:postdee_mobile/features/uploader/clip_split_screen.dart';

const _pairedChannels = {
  SocialPlatform.youtubeShorts,
  SocialPlatform.tiktok,
};

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _mount(
  WidgetTester tester, {
  double duration = 360,
  Set<SocialPlatform> platforms = _pairedChannels,
  bool reducedMotion = false,
  bool dark = false,
  bool english = false,
  double width = 430,
  double scale = 1,
  Future<void> Function(ClipSplitSegment)? preview,
  ValueChanged<ClipSplitPlan?>? onResult,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  await tester.pumpWidget(MaterialApp(
    locale: Locale(english ? 'en' : 'th'),
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reducedMotion,
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              final plan = await Navigator.of(context).push<ClipSplitPlan>(
                MaterialPageRoute(
                  builder: (_) => ClipSplitScreen(
                    sourceDurationSeconds: duration,
                    videoName: 'สินค้าของฉัน.mp4',
                    initialPlatforms: platforms,
                    tikTokDirectPost: platforms.contains(SocialPlatform.tiktok),
                    tikTokMaxDurationSeconds: 180,
                    previewSegment: preview,
                  ),
                ),
              );
              onResult?.call(plan);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, String key) async {
  final target = _key(key);
  if (target.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: _key('clip-split-scroll'),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await _reveal(tester, key);
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

// Keep each interaction within the preceding selection's transition. The
// controls must represent the current plan even before its decoration settles.
Future<void> _tapDuringMotion(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  expect(_key(key), findsOneWidget);
  await tester.tap(_key(key));
  await tester.pump(const Duration(milliseconds: 16));
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    final previousMode =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    sessions.signIn(AuthSession.authenticated(
        userId: 'split-motion-owner', idToken: 'split-motion-token'));
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
      AppTheme.applyThemeMode(previousMode);
    });
  });

  testWidgets('shows a source-interval overview beside the editable plan',
      (tester) async {
    await _mount(tester, platforms: const {SocialPlatform.youtubeShorts});
    await _reveal(tester, 'clip-split-range-0');
    expect(_key('clip-split-timeline'), findsOneWidget);
    expect(find.text('0:00–3:00'), findsOneWidget);
    expect(find.text('3:00–6:00'), findsOneWidget);
    expect(_key('clip-split-range-0'), findsOneWidget);
    expect(_key('clip-split-range-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rapid mode and channel changes retain exact edited ranges without '
      'duplicate controls or unsolicited previews', (tester) async {
    final previews = <ClipSplitSegment>[];
    ClipSplitPlan? confirmed;
    await _mount(tester,
        preview: (part) async => previews.add(part),
        onResult: (plan) => confirmed = plan);
    await _tap(tester, 'clip-split-mode-all');
    await _tap(tester, 'clip-split-range-0');
    await tester.enterText(_key('clip-split-range-start'), '0:05.125');
    await tester.enterText(_key('clip-split-range-end'), '2:55.125');
    await _tap(tester, 'clip-split-range-save');

    for (var index = 0; index < 3; index++) {
      await _tapDuringMotion(tester, 'clip-split-tab-TIKTOK');
      await _tapDuringMotion(tester, 'clip-split-tab-YOUTUBE_SHORTS');
      await _tapDuringMotion(tester, 'clip-split-mode-affected');
      await _tapDuringMotion(tester, 'clip-split-mode-all');
    }
    await _reveal(tester, 'clip-split-preview-0');
    expect(_key('clip-split-preview-0'), findsOneWidget);
    expect(_key('clip-split-preview-1'), findsOneWidget);
    expect(_key('clip-split-range-0'), findsOneWidget);
    expect(_key('clip-split-range-1'), findsOneWidget);
    expect(previews, isEmpty);
    await _tapDuringMotion(tester, 'clip-split-preview-0');
    expect(previews, hasLength(1));
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (5.125, 175.125));
    expect(find.text('4 หน่วยโพสต์'), findsOneWidget);

    await _tapDuringMotion(tester, 'clip-split-review');
    expect(_key('clip-split-review'), findsNothing);
    expect(_key('clip-split-confirm'), findsOneWidget);
    expect(confirmed, isNull);
    await _tap(tester, 'clip-split-confirm');
    expect(confirmed!.totalPostUnits, 4);
    expect(confirmed!.groupedParts, hasLength(2));
    for (final channel in confirmed!.channelPlans) {
      expect(
          channel.segments.map((part) => (part.startSeconds, part.endSeconds)),
          [(5.125, 175.125), (180, 360)]);
    }
    expect(previews, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reduced motion permits immediate selection and locks duplicate preview '
      'until the current preview completes', (tester) async {
    final gate = Completer<void>();
    final previews = <ClipSplitSegment>[];
    ClipSplitPlan? confirmed;
    await _mount(tester,
        english: true,
        reducedMotion: true,
        preview: (part) {
          previews.add(part);
          return gate.future;
        },
        onResult: (plan) => confirmed = plan);
    await _tapDuringMotion(tester, 'clip-split-mode-all');
    await _tapDuringMotion(tester, 'clip-split-tab-TIKTOK');
    await _reveal(tester, 'clip-split-preview-0');
    await tester.tap(_key('clip-split-preview-0'));
    await tester.pump();
    await tester.tap(_key('clip-split-preview-0'));
    await tester.pump();
    expect(previews, hasLength(1));
    expect(_key('clip-split-preview-0'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('clip-split-review')).onPressed,
        isNull);
    gate.complete();
    await tester.pump();
    await _tapDuringMotion(tester, 'clip-split-review');
    expect(find.text('Review split plan'), findsOneWidget);
    expect(_key('clip-split-confirm'), findsOneWidget);
    await _tap(tester, 'clip-split-confirm');
    expect(confirmed!.totalPostUnits, 4);
    expect(confirmed!.mode, ClipSplitMode.sameParts);
    expect(previews, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '64 parts remain scrollable with correct units at 320dp dark large text',
      (tester) async {
    ClipSplitPlan? confirmed;
    final previews = <ClipSplitSegment>[];
    await _mount(tester,
        duration: 90 * maxClipSplitParts.toDouble(),
        platforms: const {SocialPlatform.facebookReels},
        dark: true,
        width: 320,
        scale: 1.7,
        preview: (part) async => previews.add(part),
        onResult: (plan) => confirmed = plan);
    expect(find.text('64 หน่วยโพสต์'), findsOneWidget);
    await _reveal(tester, 'clip-split-preview-63');
    expect(_key('clip-split-preview-63'), findsOneWidget);
    expect(_key('clip-split-range-63'), findsOneWidget);
    await tester.tap(_key('clip-split-preview-63'));
    await tester.pumpAndSettle();
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (5670, 5760));
    final reviewBounds = tester.getRect(_key('clip-split-review'));
    expect(reviewBounds.left, greaterThanOrEqualTo(0));
    expect(reviewBounds.right, lessThanOrEqualTo(320));
    expect(reviewBounds.bottom, lessThanOrEqualTo(1100));
    expect(tester.takeException(), isNull);
    await _tap(tester, 'clip-split-review');
    expect(find.text('64 หน่วยโพสต์'), findsOneWidget);
    await _tap(tester, 'clip-split-confirm');
    expect(confirmed!.totalPostUnits, 64);
    expect(confirmed!.groupedParts, hasLength(64));
    expect(
        confirmed!.channelPlans.single.platform, SocialPlatform.facebookReels);
    expect(confirmed!.channelPlans.single.segments.last.endSeconds, 5760);
    expect(tester.takeException(), isNull);
  });
}
