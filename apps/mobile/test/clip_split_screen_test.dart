import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_split_localizations.dart';
import 'package:postdee_mobile/features/uploader/clip_split_plan.dart';
import 'package:postdee_mobile/features/uploader/clip_split_screen.dart';
// Reuses video_player's existing platform fake; no native player is started.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'post_video_preview_english_test.dart' show PreviewEnglishPlatform;

class _DelayedPlayPlatform extends PreviewEnglishPlatform {
  final playGate = Completer<void>();
  final commands = <String>[];

  @override
  Future<void> play(int playerId) async {
    await playGate.future;
    commands.add('play');
    await super.play(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    commands.add('pause');
    await super.pause(playerId);
  }
}

const _platforms = {
  SocialPlatform.tiktok,
  SocialPlatform.youtubeShorts,
  SocialPlatform.instagramReels,
  SocialPlatform.facebookReels,
};

void main() {
  late AuthSession previous;
  setUp(() {
    final sessions = PostDeeAuthSessionStore.instance;
    previous = sessions.session;
    sessions.signIn(AuthSession.authenticated(
        userId: 'split-owner', idToken: 'split-token'));
  });
  tearDown(() {
    final sessions = PostDeeAuthSessionStore.instance;
    previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
  });

  Future<void> mount(WidgetTester tester,
      {bool english = false,
      bool dark = false,
      double scale = 1,
      double duration = 270,
      bool direct = false,
      Set<SocialPlatform> platforms = _platforms,
      File? videoFile,
      Future<void> Function(ClipSplitSegment)? preview,
      ValueChanged<ClipSplitPlan?>? onResult}) async {
    AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    await tester.pumpWidget(MaterialApp(
      locale: Locale(english ? 'en' : 'th'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
                  body: Center(
                      child: FilledButton(
                onPressed: () async {
                  final plan = await Navigator.of(context)
                      .push<ClipSplitPlan>(MaterialPageRoute(
                          builder: (_) => ClipSplitScreen(
                                sourceDurationSeconds: duration,
                                videoName: 'คลิปสินค้าของฉัน.mp4',
                                initialPlatforms: platforms,
                                videoFile: videoFile,
                                tikTokDirectPost: direct,
                                previewSegment: preview,
                              )));
                  onResult?.call(plan);
                },
                child: const Text('open'),
              )))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) {
      await tester.fling(find.byKey(const ValueKey('clip-split-scroll')),
          const Offset(0, 2000), 5000);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find
              .descendant(
                  of: find.byKey(const ValueKey('clip-split-scroll')),
                  matching: find.byType(Scrollable))
              .first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<RangeValues> dragRangeThumb(WidgetTester tester,
      {required bool start, required double dx}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('clip-split-range-slider'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final slider = tester.widget<RangeSlider>(finder);
    final bounds = tester.getRect(finder);
    final box = tester.renderObject<RenderBox>(finder);
    final inheritedTheme = SliderTheme.of(tester.element(finder));
    final sliderTheme = inheritedTheme.copyWith(
      rangeThumbShape:
          inheritedTheme.rangeThumbShape ?? const RoundRangeSliderThumbShape(),
      overlayShape: inheritedTheme.overlayShape ??
          const RoundSliderOverlayShape(overlayRadius: 24),
      trackHeight: inheritedTheme.trackHeight ?? 4,
    );
    final track = (sliderTheme.rangeTrackShape ??
            const RoundedRectRangeSliderTrackShape())
        .getPreferredRect(parentBox: box, sliderTheme: sliderTheme);
    final value = start ? slider.values.start : slider.values.end;
    final thumb = Offset(
        bounds.left +
            track.left +
            track.width * (value - slider.min) / (slider.max - slider.min),
        bounds.top + track.center.dy);
    await tester.dragFrom(thumb, Offset(dx, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return tester.widget<RangeSlider>(finder).values;
  }

  testWidgets('reviews exact channel units then returns a plan without posting',
      (tester) async {
    ClipSplitPlan? confirmed;
    await mount(tester, onResult: (result) => confirmed = result);
    expect(find.text('7 หน่วยโพสต์'), findsOneWidget);
    expect(confirmed, isNull);
    await tap(tester, 'clip-split-review');
    expect(find.text('ตรวจแผนแบ่งคลิป'), findsOneWidget);
    expect(confirmed, isNull);
    await tap(tester, 'clip-split-confirm');
    expect(confirmed?.totalPostUnits, 7);
    expect(confirmed?.groupedParts.length, 6);
    expect(find.text('open'), findsOneWidget);
  });

  for (final english in [false, true]) {
    testWidgets(
        'split confirmation describes one clip set (${english ? 'en' : 'th'})',
        (tester) async {
      await mount(tester, english: english, platforms: const {
        SocialPlatform.youtubeShorts,
        SocialPlatform.instagramReels,
      });
      await tap(tester, 'clip-split-review');
      expect(
          find.text(english
              ? 'Confirm split · Prepare set'
              : 'ยืนยันแบ่งคลิป · เตรียมทั้งชุด'),
          findsOneWidget);
      final storage = english
          ? 'Prepare 3 clips as one set and save them on this device.'
          : 'เตรียม 3 คลิปเป็นชุดเดียวและเก็บไว้ในเครื่อง';
      final next = english
          ? 'Review each clip’s caption, cover and posting time, then confirm the entire set before posting. Nothing is posted automatically.'
          : 'ตรวจแคปชั่น หน้าปก และเวลาส่งแยกแต่ละคลิป แล้วค่อยยืนยันส่งทั้งชุด ไม่มีการโพสต์อัตโนมัติ';
      final scroll = find.descendant(
          of: find.byKey(const ValueKey('clip-split-scroll')),
          matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(find.text(storage), 150,
          scrollable: scroll);
      expect(find.text(storage), findsOneWidget);
      await tester.scrollUntilVisible(find.text(next), 100, scrollable: scroll);
      expect(find.text(next), findsOneWidget);
      final context = tester.element(find.byType(ClipSplitScreen));
      expect(
          clipSplitProblemText(context, ClipSplitPlanProblem.tooManyParts),
          english
              ? 'Up to $maxClipSplitParts clips per set. Choose a shorter video or fewer channels.'
              : 'แบ่งได้สูงสุด $maxClipSplitParts คลิปต่อชุด กรุณาเลือกคลิปที่สั้นลงหรือลดช่องทาง');
    });
  }

  testWidgets('mode and selected intervals update before confirmation',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    await mount(tester, preview: (segment) async => previews.add(segment));
    await tap(tester, 'clip-split-tab-YOUTUBE_SHORTS');
    await tap(tester, 'clip-split-preview-0');
    expect(previews.single.startSeconds, 0);
    expect(previews.single.endSeconds, 135);
    await tap(tester, 'clip-split-mode-all');
    expect(find.text('12 หน่วยโพสต์'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each exact-ceiling part keeps its own chosen source range',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    ClipSplitPlan? confirmed;
    await mount(tester,
        duration: 360,
        platforms: const {SocialPlatform.youtubeShorts},
        preview: (segment) async => previews.add(segment),
        onResult: (plan) => confirmed = plan);
    await tap(tester, 'clip-split-range-0');
    expect(find.text('ช่วงที่เลือกได้ตอนนี้ 0:00–3:00'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-start')), '0:05');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-end')), '2:55');
    await tap(tester, 'clip-split-range-save');
    await tap(tester, 'clip-split-preview-0');
    await tap(tester, 'clip-split-preview-1');
    expect(previews.map((part) => (part.startSeconds, part.endSeconds)),
        [(5, 175), (180, 360)]);
    expect(
        find.text('ช่วงที่เว้นไว้จะไม่รวมอยู่ในคลิปที่เตรียม'), findsOneWidget);
    await tap(tester, 'clip-split-review');
    expect(find.textContaining('0:05–2:55'), findsOneWidget);
    await tap(tester, 'clip-split-confirm');
    expect(
        confirmed!
            .channelPlanFor(SocialPlatform.youtubeShorts)
            .segments
            .map((part) => (part.startSeconds, part.endSeconds)),
        [(5, 175), (180, 360)]);
  });

  testWidgets('invalid and cancelled range edits never move another part',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    await mount(tester,
        duration: 360,
        platforms: const {SocialPlatform.youtubeShorts},
        preview: (segment) async => previews.add(segment));
    await tap(tester, 'clip-split-range-0');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-start')), '0:10');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-end')), '3:10');
    await tap(tester, 'clip-split-range-save');
    expect(
        find.byKey(const ValueKey('clip-split-range-dialog')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('clip-split-range-error')), findsOneWidget);
    await tap(tester, 'clip-split-range-cancel');
    await tap(tester, 'clip-split-preview-0');
    await tap(tester, 'clip-split-preview-1');
    expect(previews.map((part) => (part.startSeconds, part.endSeconds)),
        [(0, 180), (180, 360)]);
  });

  testWidgets(
      'shared edits apply everywhere and keep compatible ranges on mode change',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    await mount(tester,
        duration: 360,
        platforms: const {
          SocialPlatform.youtubeShorts,
          SocialPlatform.instagramReels,
        },
        preview: (segment) async => previews.add(segment));
    await tap(tester, 'clip-split-mode-all');
    await tap(tester, 'clip-split-range-0');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-start')), '0:10');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-end')), '2:50');
    await tap(tester, 'clip-split-range-save');
    await tap(tester, 'clip-split-tab-INSTAGRAM_REELS');
    await tap(tester, 'clip-split-preview-0');
    expect((previews.last.startSeconds, previews.last.endSeconds), (10, 170));
    await tap(tester, 'clip-split-mode-affected');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('clip-split-ranges-reset-notice')), 150,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('clip-split-scroll')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.byKey(const ValueKey('clip-split-ranges-reset-notice')),
        findsOneWidget);
    await tap(tester, 'clip-split-preview-0');
    expect((previews.last.startSeconds, previews.last.endSeconds), (0, 360));
    await tap(tester, 'clip-split-tab-YOUTUBE_SHORTS');
    await tap(tester, 'clip-split-preview-0');
    expect((previews.last.startSeconds, previews.last.endSeconds), (10, 170));
    await tap(tester, 'clip-split-reset-ranges');
    await tap(tester, 'clip-split-preview-0');
    expect((previews.last.startSeconds, previews.last.endSeconds), (0, 180));
  });

  testWidgets('fractional split part uses a Material English editor at 320dp',
      (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previews = <ClipSplitSegment>[];
    await mount(tester,
        english: true,
        dark: true,
        scale: 2,
        duration: 270.125,
        platforms: const {SocialPlatform.youtubeShorts},
        preview: (segment) async => previews.add(segment));
    await tap(tester, 'clip-split-range-0');
    expect(find.textContaining('4:30'), findsWidgets);
    expect(find.textContaining('4:30.125'), findsNothing);
    expect(find.text('Available source range 0:00–2:15'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('clip-split-range-start')),
            matching: find.byType(Material)),
        findsWidgets);
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-start')), '0:10.125');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-end')), '2:00.125');
    await tap(tester, 'clip-split-range-preview');
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (10.125, 120.125));
    await tap(tester, 'clip-split-range-save');
    await tap(tester, 'clip-split-review');
    expect(find.text('Full video'), findsNothing);
    await tester.scrollUntilVisible(find.textContaining('0:10–2:00'), 150,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('clip-split-scroll')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.textContaining('0:10–2:00'), findsOneWidget);
    expect(find.textContaining('0:10.125–2:00.125'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a channel that fits keeps the full original without range editing',
      (tester) async {
    await mount(tester,
        duration: 90, platforms: const {SocialPlatform.instagramReels});
    final scroll = find.descendant(
        of: find.byKey(const ValueKey('clip-split-scroll')),
        matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('clip-split-preview-0')), 150,
        scrollable: scroll);
    expect(find.byKey(const ValueKey('clip-split-range-0')), findsNothing);
    expect(find.text('คลิปเต็ม'), findsWidgets);
  });

  testWidgets(
      'adding a compatible channel preserves ranges but a stricter shared plan resets explicitly',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    await mount(tester,
        duration: 360,
        platforms: const {SocialPlatform.youtubeShorts},
        preview: (segment) async => previews.add(segment));
    await tap(tester, 'clip-split-range-0');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-start')), '0:05');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-end')), '2:55');
    await tap(tester, 'clip-split-range-save');
    await tap(tester, 'clip-split-channel-INSTAGRAM_REELS');
    await tap(tester, 'clip-split-preview-0');
    expect((previews.last.startSeconds, previews.last.endSeconds), (5, 175));
    await tap(tester, 'clip-split-mode-all');
    await tap(tester, 'clip-split-channel-FACEBOOK_REELS');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('clip-split-ranges-reset-notice')), 150,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('clip-split-scroll')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.byKey(const ValueKey('clip-split-ranges-reset-notice')),
        findsOneWidget);
    await tap(tester, 'clip-split-tab-YOUTUBE_SHORTS');
    await tap(tester, 'clip-split-preview-0');
    expect((previews.last.startSeconds, previews.last.endSeconds), (0, 90));
  });

  for (final duration in [180.000001, 180.0000005]) {
    testWidgets(
        'opening and saving an untouched $duration range preserves canonical microseconds',
        (tester) async {
      ClipSplitPlan? confirmed;
      final previews = <ClipSplitSegment>[];
      await mount(tester,
          duration: duration,
          platforms: const {SocialPlatform.youtubeShorts},
          preview: (segment) async => previews.add(segment),
          onResult: (plan) => confirmed = plan);
      final automatic = ClipSplitPlan.create(
          sourceDurationSeconds: duration,
          platforms: const {SocialPlatform.youtubeShorts});
      await tap(tester, 'clip-split-range-1');
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('clip-split-range-end')))
              .controller!
              .text,
          '3:00');
      await tap(tester, 'clip-split-range-preview');
      expect((
        previews.single.startSeconds,
        previews.single.endSeconds
      ), (
        automatic.channelPlans.single.segments.last.startSeconds,
        automatic.channelPlans.single.segments.last.endSeconds
      ));
      await tap(tester, 'clip-split-range-save');
      await tap(tester, 'clip-split-review');
      await tap(tester, 'clip-split-confirm');
      expect(
          confirmed!
              .channelPlanFor(SocialPlatform.youtubeShorts)
              .segments
              .map((part) => (part.startSeconds, part.endSeconds)),
          automatic
              .channelPlanFor(SocialPlatform.youtubeShorts)
              .segments
              .map((part) => (part.startSeconds, part.endSeconds)));
    });
  }

  testWidgets('editing one short clock preserves the other exact endpoint',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    ClipSplitPlan? confirmed;
    await mount(tester,
        duration: 270.125,
        platforms: const {SocialPlatform.youtubeShorts},
        preview: (segment) async => previews.add(segment),
        onResult: (plan) => confirmed = plan);
    await tap(tester, 'clip-split-range-0');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('clip-split-range-end')))
            .controller!
            .text,
        '2:15');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-start')), '0:10');
    await tap(tester, 'clip-split-range-preview');
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (10, 135.0625));
    await tap(tester, 'clip-split-range-save');
    await tap(tester, 'clip-split-review');
    await tap(tester, 'clip-split-confirm');
    expect(
        confirmed!.channelPlans.single.segments
            .map((part) => (part.startSeconds, part.endSeconds)),
        [(10, 135.0625), (135.0625, 270.125)]);
  });

  testWidgets('dragging a fractional start snaps only the moved thumb',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    await mount(tester,
        duration: 360,
        platforms: const {SocialPlatform.youtubeShorts},
        preview: (segment) async => previews.add(segment));
    await tap(tester, 'clip-split-range-0');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-start')), '0:55.153966');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-end')), '2:35.067414');
    final values = await dragRangeThumb(tester, start: true, dx: 24);
    expect(values.start, greaterThan(55.153966));
    expect(values.start, values.start.roundToDouble());
    expect(values.end, 155.067414);
    final startText = tester
        .widget<TextField>(find.byKey(const ValueKey('clip-split-range-start')))
        .controller!
        .text;
    final endText = tester
        .widget<TextField>(find.byKey(const ValueKey('clip-split-range-end')))
        .controller!
        .text;
    expect(startText, matches(RegExp(r'^\d+:[0-5]\d$')));
    expect(endText, '2:35');
    await tap(tester, 'clip-split-range-preview');
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (values.start, 155.067414));
    await tap(tester, 'clip-split-range-save');
    await tap(tester, 'clip-split-preview-0');
    expect((previews.last.startSeconds, previews.last.endSeconds),
        (values.start, 155.067414));
  });

  testWidgets('dragging toward a fractional neighbor keeps a valid whole cut',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    ClipSplitPlan? confirmed;
    await mount(tester,
        duration: 270.125,
        platforms: const {SocialPlatform.youtubeShorts},
        preview: (segment) async => previews.add(segment),
        onResult: (plan) => confirmed = plan);
    await tap(tester, 'clip-split-range-1');
    final values = await dragRangeThumb(tester, start: true, dx: -40);
    expect(values.start, 136,
        reason: '135 would overlap the previous part ending at 135.0625');
    expect(values.end, 270.125);
    await tap(tester, 'clip-split-range-preview');
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (136, 270.125));
    await tap(tester, 'clip-split-range-save');
    expect(find.byKey(const ValueKey('clip-split-range-error')), findsNothing);
    await tap(tester, 'clip-split-review');
    await tap(tester, 'clip-split-confirm');
    expect(
        confirmed!.channelPlans.single.segments
            .map((part) => (part.startSeconds, part.endSeconds)),
        [(0, 135.0625), (136, 270.125)]);
  });

  testWidgets('a slider interval without a whole second retains its exact cut',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    ClipSplitPlan? confirmed;
    await mount(tester,
        duration: 180.375,
        platforms: const {SocialPlatform.facebookReels},
        preview: (segment) async => previews.add(segment),
        onResult: (plan) => confirmed = plan);
    await tap(tester, 'clip-split-range-1');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-end')), '1:03.625');
    final values = await dragRangeThumb(tester, start: true, dx: -30);
    expect(values.start, 60.125,
        reason: 'The legal 60.125–60.625 interval contains no whole second');
    expect(values.end, 63.625);
    await tap(tester, 'clip-split-range-preview');
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (60.125, 63.625));
    await tap(tester, 'clip-split-range-save');
    await tap(tester, 'clip-split-review');
    await tap(tester, 'clip-split-confirm');
    expect(
        confirmed!.channelPlans.single.segments
            .map((part) => (part.startSeconds, part.endSeconds)),
        [(0, 60.125), (60.125, 63.625), (120.25, 180.375)]);
  });

  testWidgets('a slider cut respects the Reel minimum and keeps the exact end',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    await mount(tester,
        duration: 180.375,
        platforms: const {SocialPlatform.facebookReels},
        preview: (segment) async => previews.add(segment));
    await tap(tester, 'clip-split-range-1');
    final values = await dragRangeThumb(tester, start: true, dx: 200);
    expect(values.start, greaterThan(60.125));
    expect(values.start, values.start.roundToDouble());
    expect(values.end, 120.25);
    expect(values.end - values.start, greaterThanOrEqualTo(3));
    await tap(tester, 'clip-split-range-preview');
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (values.start, 120.25));
    await tap(tester, 'clip-split-range-save');
    expect(find.byKey(const ValueKey('clip-split-range-dialog')), findsNothing);
    await tap(tester, 'clip-split-preview-1');
    expect((previews.last.startSeconds, previews.last.endSeconds),
        (values.start, 120.25));
  });

  testWidgets(
      'a slider cut clamps to the Reel maximum before a looser neighbor',
      (tester) async {
    final previews = <ClipSplitSegment>[];
    await mount(tester,
        duration: 180.375,
        platforms: const {SocialPlatform.facebookReels},
        preview: (segment) async => previews.add(segment));
    await tap(tester, 'clip-split-range-0');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-end')), '0:30');
    await tap(tester, 'clip-split-range-save');
    await tap(tester, 'clip-split-range-1');
    await tester.enterText(
        find.byKey(const ValueKey('clip-split-range-start')), '0:35');
    final values = await dragRangeThumb(tester, start: true, dx: -80);
    expect(values.start, 31,
        reason: '30 would be clear of its neighbor but exceed 90 seconds');
    expect(values.end, 120.25);
    expect(values.end - values.start, lessThanOrEqualTo(90));
    await tap(tester, 'clip-split-range-preview');
    expect((previews.single.startSeconds, previews.single.endSeconds),
        (31, 120.25));
    await tap(tester, 'clip-split-range-save');
    expect(find.byKey(const ValueKey('clip-split-range-dialog')), findsNothing);
    await tap(tester, 'clip-split-preview-1');
    expect(
        (previews.last.startSeconds, previews.last.endSeconds), (31, 120.25));
  });

  testWidgets(
      'range preview locks saving and changed owners cannot apply edits',
      (tester) async {
    final gate = Completer<void>();
    await mount(tester,
        platforms: const {SocialPlatform.youtubeShorts},
        preview: (_) => gate.future);
    await tap(tester, 'clip-split-range-0');
    await tester.tap(find.byKey(const ValueKey('clip-split-range-preview')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('clip-split-range-save')))
            .onPressed,
        isNull);
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'new-range-owner', idToken: 'new-range-token'));
    gate.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('clip-split-range-save')))
            .onPressed,
        isNull);
    await tap(tester, 'clip-split-range-cancel');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('clip-split-review')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'unknown Direct TikTok cap stays unselected and cannot be enabled',
      (tester) async {
    await mount(tester, direct: true);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('clip-split-channel-TIKTOK')), 100,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('clip-split-scroll')),
                matching: find.byType(Scrollable))
            .first);
    final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('clip-split-channel-TIKTOK')));
    expect(checkbox.value, isFalse);
    expect(checkbox.onChanged, isNull);
    expect(find.text('รอตรวจสิทธิ์บัญชี TikTok'), findsOneWidget);
    expect(find.text('6 หน่วยโพสต์'), findsOneWidget);
  });

  testWidgets('English dark small phone and large text do not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, english: true, dark: true, scale: 1.7);
    expect(find.text('Split into parts'), findsOneWidget);
    expect(find.text('7 post units'), findsOneWidget);
    await tap(tester, 'clip-split-review');
    expect(find.text('Review split plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account change disables final confirmation', (tester) async {
    await mount(tester);
    await tap(tester, 'clip-split-review');
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'other-owner', idToken: 'other-token'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('clip-split-confirm')))
            .onPressed,
        isNull);
    expect(find.text('บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่'),
        findsOneWidget);
  });

  testWidgets(
      'real range preview seeks to the selected part and pauses at its end',
      (tester) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = PreviewEnglishPlatform()
      ..duration = const Duration(seconds: 270);
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    await mount(tester, videoFile: File('selected-source.mp4'));
    await tap(tester, 'clip-split-tab-YOUTUBE_SHORTS');
    await tap(tester, 'clip-split-preview-1');
    expect(platform.seeks, [const Duration(seconds: 135)]);
    expect(platform.played, isEmpty);
    await tester.tap(find.text('เล่นตอนนี้'));
    await tester.pump();
    final pauses = platform.paused.length;
    platform.positions[1] = const Duration(seconds: 270);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(platform.played, [1]);
    expect(platform.paused.length, greaterThan(pauses));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {});
    await tester.pump();
    expect(platform.disposeCounts[1], 1);
  });

  testWidgets('account change removes the source frame from range preview',
      (tester) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = PreviewEnglishPlatform()
      ..duration = const Duration(seconds: 270);
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    await mount(tester, videoFile: File('owned-source.mp4'));
    await tap(tester, 'clip-split-preview-0');
    expect(
        find.byKey(const ValueKey('preview-english-player-1')), findsOneWidget);
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'different-owner', idToken: 'different-token'));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('preview-english-player-1')), findsNothing);
    expect(platform.paused, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {});
    await tester.pump();
  });

  testWidgets('a delayed native play is paused again after account change',
      (tester) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _DelayedPlayPlatform()
      ..duration = const Duration(seconds: 270);
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    await mount(tester, videoFile: File('owned-source.mp4'));
    await tap(tester, 'clip-split-preview-0');
    await tester.tap(find.text('เล่นตอนนี้'));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(
        AuthSession.authenticated(userId: 'new-owner', idToken: 'new-token'));
    await tester.pump();
    platform.playGate.complete();
    await tester.pumpAndSettle();
    expect(platform.commands.last, 'pause');
    expect(platform.commands, contains('play'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {});
    await tester.pump();
  });
}
