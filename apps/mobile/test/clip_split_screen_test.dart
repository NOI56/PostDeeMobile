import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
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
      bool direct = false,
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
                                sourceDurationSeconds: 270,
                                videoName: 'คลิปสินค้าของฉัน.mp4',
                                initialPlatforms: _platforms,
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
