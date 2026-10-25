import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/post_quota_strip.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _captureDirectory =
    String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR', defaultValue: '');
const _captureKey = ValueKey('uploader-post-quota-visual-capture');
const _subscription = SubscriptionStatusResult(
  userId: 'post-quota-visual-owner',
  plan: 'STARTER',
  status: 'ACTIVE',
  monthlyPostLimit: 120,
  usedPostsThisMonth: 13,
  remainingPostsThisMonth: 107,
  canSchedule: true,
  canUseAiCaptions: true,
  canUseAnalytics: false,
);

class _Fixture {
  _Fixture() {
    file = File('${Directory.systemTemp.path}/post-quota-visual-'
        '${DateTime.now().microsecondsSinceEpoch}.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
  }

  late final File file;
  final store = TestPublishDraftStore(ownerUserId: 'post-quota-visual-owner');
  var uploadCalls = 0;
  var aiCalls = 0;
  var postCalls = 0;

  Widget app({required bool dark, required double textScale}) =>
      RepaintBoundary(
        key: _captureKey,
        child: _appTheme(
          dark: dark,
          textScale: textScale,
          body: UploaderScreen(
            fullScreen: true,
            draftStore: store,
            initialVideoPath: file.path,
            initialVideoName: 'รีวิวสินค้า.mp4',
            initialVideoSizeBytes: 512,
            initialVideoWidth: 1080,
            initialVideoHeight: 1920,
            enableRevenueCatBilling: false,
            probePublishMedia: probeValidPublishMedia,
            loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
            loadSocialConnections: () async => const [],
            loadSubscription: () async => _subscription,
            loadPostQuota: () async => _subscription,
            loadCaptionQuota: () async => const CaptionQuotaResult(
              plan: 'STARTER',
              quota: RealClipCaptionQuota(
                  limit: 50, usedThisMonth: 12, remainingThisMonth: 38),
            ),
            createUpload: (_) async {
              uploadCalls++;
              throw StateError('The visual test must not upload media');
            },
            generateRealClipCaption: (_) async {
              aiCalls++;
              throw StateError('The visual test must not spend AI credit');
            },
            createPost: (_) async {
              postCalls++;
              throw StateError('The visual test must not publish');
            },
          ),
        ),
      );
}

Widget _appTheme({
  required bool dark,
  required double textScale,
  required Widget body,
}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: body),
    );

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
        userId: 'post-quota-visual-owner', idToken: 'local-visual-token'));
  });

  for (final dark in [false, true]) {
    testWidgets(
        'real-font post quota in actual '
        '${dark ? 'dark narrow large-text' : 'light'} clip step',
        (tester) async {
      final size = dark ? const Size(320, 900) : const Size(430, 1000);
      final textScale = dark ? 1.7 : 1.0;
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
      await tester.pumpWidget(fixture.app(dark: dark, textScale: textScale));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('uploader-step-video')), findsOneWidget);
      expect(find.byKey(const ValueKey('uploader-step-caption')), findsNothing);
      final strip = find.byType(PostQuotaStrip);
      await tester.scrollUntilVisible(strip, 100,
          scrollable: uploaderMainScroll);
      await Scrollable.ensureVisible(tester.element(strip), alignment: .72);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('uploader-close')), findsOneWidget);
      expect(fixture.uploadCalls, 0);
      expect(fixture.aiCalls, 0);
      expect(fixture.postCalls, 0);
      final stripBounds = tester.getRect(strip);
      expect(stripBounds.left, greaterThanOrEqualTo(0));
      expect(stripBounds.right, lessThanOrEqualTo(size.width));
      expect(stripBounds.top, greaterThanOrEqualTo(0));
      expect(stripBounds.bottom, lessThanOrEqualTo(size.height));
      final cover = find.byKey(const ValueKey('uploader-cover-edit-button'));
      final change =
          find.byKey(const ValueKey('uploader-video-preview-picker'));
      expect(tester.getBottomLeft(cover).dy + 8,
          lessThanOrEqualTo(stripBounds.top));
      expect(tester.getBottomLeft(change).dy + 8,
          lessThanOrEqualTo(stripBounds.top));
      for (final label in [
        'โพสต์คงเหลือ',
        'Starter',
        '107 / 120 หน่วย',
        'ใช้ไป 13 หน่วย',
      ]) {
        final text = find.descendant(
            of: strip, matching: find.text(label, findRichText: true));
        expect(text, findsOneWidget);
        final bounds = tester.getRect(text);
        expect(bounds.left, greaterThanOrEqualTo(stripBounds.left));
        expect(bounds.right, lessThanOrEqualTo(stripBounds.right));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
            paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length)),
            isNotEmpty);
      }
      final capturedCard = tester.widget<PostQuotaStrip>(strip);
      final capturedCardSize = tester.getSize(strip);
      final name =
          dark ? 'post-quota-dark-320-large-text' : 'post-quota-light-430';
      await _capture(tester, '$name-page');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      if (_captureDirectory.isNotEmpty) {
        // Rebuild the actual card at its measured production size, without
        // cropping or editing pixels from the whole-page capture.
        await tester.pumpWidget(_appTheme(
          dark: dark,
          textScale: textScale,
          body: Center(
            child: RepaintBoundary(
              key: _captureKey,
              child: SizedBox(
                  width: capturedCardSize.width,
                  height: capturedCardSize.height,
                  child: capturedCard),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await _capture(tester, '$name-card');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}
