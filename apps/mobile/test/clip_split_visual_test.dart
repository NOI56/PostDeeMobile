import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_split_localizations.dart';
import 'package:postdee_mobile/features/uploader/clip_split_prompt.dart';
import 'package:postdee_mobile/features/uploader/clip_split_screen.dart';

const _directory = String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR');
const _captureKey = ValueKey('clip-split-visual-capture');
const _channels = {
  SocialPlatform.facebookReels,
  SocialPlatform.youtubeShorts,
  SocialPlatform.tiktok,
  SocialPlatform.instagramReels,
};

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final anuphan = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        anuphan.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await anuphan.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (_directory.isEmpty) return;
  await tester.pump();
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Directory(_directory);
      await output.create(recursive: true);
      await File('${output.path}/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Widget _app(
        {required bool dark, required bool english, required double scale}) =>
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
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
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
                title:
                    Text(clipSplitText(context, 'เลือกคลิป', 'Choose video'))),
            body: SingleChildScrollView(
              padding: AppTheme.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    clipSplitText(context, 'คลิปตัวอย่าง · 4:30 นาที',
                        'Video fixture · 4:30 min'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  ClipSplitPrompt(
                    exceededPlatforms: const [
                      SocialPlatform.facebookReels,
                      SocialPlatform.youtubeShorts,
                    ],
                    onOpen: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const ClipSplitScreen(
                          sourceDurationSeconds: 270,
                          videoName: 'คลิปตัวอย่าง-4นาที30วินาที.mp4',
                          initialPlatforms: _channels,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    final previousMode =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    sessions.signIn(AuthSession.authenticated(
        userId: 'split-visual-fixture', idToken: 'offline-visual-token'));
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
      AppTheme.applyThemeMode(previousMode);
    });
  });

  for (final mode in [
    (name: 'light-th', dark: false, english: false, width: 430.0, scale: 1.0),
    (
      name: 'dark-th-large',
      dark: true,
      english: false,
      width: 320.0,
      scale: 1.7
    ),
    (name: 'light-en', dark: false, english: true, width: 430.0, scale: 1.0),
    (
      name: 'dark-en-large',
      dark: true,
      english: true,
      width: 320.0,
      scale: 1.7
    ),
  ]) {
    testWidgets('actual prompt and split screens with real fonts ${mode.name}',
        (tester) async {
      tester.view.physicalSize = Size(mode.width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppTheme.applyThemeMode(mode.dark ? ThemeMode.dark : ThemeMode.light);
      await _fonts(tester);
      await tester.pumpWidget(
          _app(dark: mode.dark, english: mode.english, scale: mode.scale));
      await tester.pumpAndSettle();
      await _capture(tester, 'clip-split-${mode.name}-prompt');
      final open = find.byKey(const ValueKey('uploader-clip-split-open'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(ClipSplitScreen), findsOneWidget);
      expect(find.text(mode.english ? '7 post units' : '7 หน่วยโพสต์'),
          findsOneWidget);
      await _capture(tester, 'clip-split-${mode.name}-plan');

      final scroll = find.descendant(
          of: find.byKey(const ValueKey('clip-split-scroll')),
          matching: find.byType(Scrollable));
      final youtube =
          find.byKey(const ValueKey('clip-split-tab-YOUTUBE_SHORTS'));
      await tester.scrollUntilVisible(youtube, 150, scrollable: scroll);
      await tester.ensureVisible(youtube);
      await tester.pumpAndSettle();
      await tester.tap(youtube);
      await tester.pumpAndSettle();
      final cut = find.byKey(const ValueKey('clip-split-first-boundary'));
      await tester.scrollUntilVisible(cut, 150, scrollable: scroll);
      await tester.ensureVisible(cut);
      await tester.pumpAndSettle();
      await _capture(tester, 'clip-split-${mode.name}-ranges');

      await tester.tap(find.byKey(const ValueKey('clip-split-review')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('clip-split-confirm'));
      final bounds = tester.getRect(confirm);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(mode.width));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(1000));
      expect(find.text(mode.english ? 'Review split plan' : 'ตรวจแผนแบ่งคลิป'),
          findsOneWidget);
      await _capture(tester, 'clip-split-${mode.name}-review');
    });
  }
}
