import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _captureDirectory =
    String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR', defaultValue: '');
const _captureKey = ValueKey('compact-ai-panel-visual-capture');
const _platforms = [
  'TIKTOK',
  'YOUTUBE_SHORTS',
  'INSTAGRAM_REELS',
  'FACEBOOK_REELS',
];

class _Fixture {
  _Fixture() {
    file = File('${Directory.systemTemp.path}/compact-ai-panel-'
        '${DateTime.now().microsecondsSinceEpoch}.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
  }

  late final File file;
  final store = TestPublishDraftStore(ownerUserId: 'visual-owner');
  var uploadCalls = 0;
  var aiCalls = 0;

  Widget app({required bool dark, required double textScale}) =>
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: UploaderScreen(
              draftStore: store,
              initialVideoPath: file.path,
              initialVideoName: 'รีวิวสินค้า.mp4',
              initialVideoSizeBytes: 512,
              initialVideoWidth: 1080,
              initialVideoHeight: 1920,
              probePublishMedia: probeValidPublishMedia,
              loadSocialPublishingReadiness:
                  connectedPublishingReadinessForTests,
              loadSocialConnections: () async => const [],
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'visual-owner',
                plan: 'STARTER',
                status: 'ACTIVE',
                canSchedule: true,
                canUseAiCaptions: true,
                canUseAnalytics: false,
              ),
              createUpload: (_) async {
                uploadCalls++;
                throw StateError('The visual test must not upload media');
              },
              generateRealClipCaption: (_) async {
                aiCalls++;
                throw StateError('The visual test must not spend AI credit');
              },
            ),
          ),
        ),
      );
}

Future<void> _show(WidgetTester tester, Finder finder,
    {double alignment = .1}) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: uploaderMainScroll);
  await Scrollable.ensureVisible(tester.element(finder), alignment: alignment);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String fileName) async {
  expect(tester.takeException(), isNull);
  if (_captureDirectory.isEmpty) return;
  await tester.pump();
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final directory = Directory(_captureDirectory);
      await directory.create(recursive: true);
      await File('${directory.path}/$fileName.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final previousTheme =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    addTearDown(() => AppTheme.applyThemeMode(previousTheme));
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    sessions.signIn(AuthSession.authenticated(
        userId: 'visual-owner', idToken: 'local-visual-token'));
  });

  for (final dark in [false, true]) {
    testWidgets(
        'real-font compact AI panel in '
        '${dark ? 'dark narrow large-text' : 'light'} mode', (tester) async {
      final size = dark ? const Size(320, 900) : const Size(430, 930);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
      await tester.runAsync(() async {
        final fonts = FontLoader('Anuphan');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          fonts.addFont(
              rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
        }
        await fonts.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
      final fixture = _Fixture();
      await tester
          .pumpWidget(fixture.app(dark: dark, textScale: dark ? 1.7 : 1));
      await tester.pumpAndSettle();
      await goToUploaderStep(tester, 1);
      final mode =
          find.byKey(const ValueKey('uploader-platform-captions-toggle'));
      await _show(tester, mode);
      await tester.tap(mode);
      await tester.pumpAndSettle();

      for (final platform in _platforms.take(2)) {
        final target = find.byKey(ValueKey('ai-caption-target-$platform'));
        await _show(tester, target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      final panel = find.byKey(const ValueKey('uploader-ai-caption-panel'));
      await _show(tester, panel, alignment: .05);
      await tester.runAsync(() async {
        for (final asset in [
          'tiktok',
          'youtube_shorts',
          'instagram_reels',
          'facebook_reels',
        ]) {
          await precacheImage(AssetImage('assets/images/platforms/$asset.png'),
              tester.element(panel));
        }
      });
      await tester.pumpAndSettle();
      Finder inside(Finder target) =>
          find.descendant(of: panel, matching: target);
      for (final label in [
        'ให้ AI ช่วยเขียน',
        'เลือกช่องทางที่ต้องการ',
        'TikTok',
        'YouTube Shorts',
        'Instagram Reels',
        'Facebook Reels',
        'สร้างแคปชั่น · 1 เครดิต',
      ]) {
        final text = inside(find.text(label));
        expect(text, findsOneWidget);
        final bounds = tester.getRect(text);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(size.width));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(size.height));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(
            paragraph.getBoxesForSelection(TextSelection(
                baseOffset: label.lastIndexOf(' ') + 1,
                extentOffset: label.length)),
            isNotEmpty,
            reason: 'The final word must be painted: $label');
        for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length))) {
          expect(box.left, greaterThanOrEqualTo(0),
              reason:
                  'The full label must remain inside its paragraph: $label');
          expect(box.right, lessThanOrEqualTo(paragraph.size.width + 2),
              reason: 'The full label must wrap instead of fading: $label');
          expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 2),
              reason: 'All wrapped lines must remain visible: $label');
        }
      }
      for (final platform in _platforms) {
        final target = find.byKey(ValueKey('ai-caption-target-$platform'));
        expect(tester.widget<FilterChip>(target).selected,
            _platforms.take(2).contains(platform));
        final chipBounds = tester.getRect(target);
        final labelBounds = tester
            .getRect(find.descendant(of: target, matching: find.byType(Text)));
        expect(labelBounds.top, greaterThanOrEqualTo(chipBounds.top));
        expect(labelBounds.bottom, lessThanOrEqualTo(chipBounds.bottom));
        expect(
            find.byKey(ValueKey('uploader-caption-$platform')), findsOneWidget);
      }
      final button =
          inside(find.byKey(const ValueKey('uploader-ai-generate-button')));
      expect(tester.widget<PostDeeGradientButton>(button).onPressed, isNotNull);
      expect(fixture.uploadCalls, 0);
      expect(fixture.aiCalls, 0);
      final capturedPanel =
          _captureDirectory.isEmpty ? null : tester.widget<DecoratedBox>(panel);
      final capturedPanelSize =
          _captureDirectory.isEmpty ? null : tester.getSize(panel);
      await _capture(
          tester,
          dark
              ? 'compact-ai-panel-dark-320-large-text'
              : 'compact-ai-panel-light-430');

      if (!dark) {
        final style = find.byKey(const ValueKey('uploader-ai-style-button'));
        await tester.tap(style);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('uploader-ai-style-sheet')),
            findsOneWidget);
        final guidance =
            find.byKey(const ValueKey('uploader-ai-guidance-field'));
        await tester.enterText(guidance, 'ขอข้อความสั้น อ่านง่าย เป็นกันเอง');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(guidance).controller!.text,
            'ขอข้อความสั้น อ่านง่าย เป็นกันเอง');
        expect(fixture.uploadCalls, 0);
        expect(fixture.aiCalls, 0);
        await _capture(tester, 'compact-ai-panel-style-guidance');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      if (capturedPanel != null && capturedPanelSize != null) {
        // Reuse the actual panel and its exact size after interaction checks.
        // No callbacks are invoked after disposing the original composer.
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(dark ? 1.7 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: _captureKey,
                child: SizedBox(
                  width: capturedPanelSize.width,
                  height: capturedPanelSize.height,
                  child: capturedPanel,
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await _capture(
            tester,
            dark
                ? 'compact-ai-panel-dark-card'
                : 'compact-ai-panel-light-card');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}
