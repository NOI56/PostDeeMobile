import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_review_screen.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';

Widget reviewEnglishApp(Widget child,
    {Locale locale = const Locale('en'), bool dark = false, double scale = 1}) {
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return MaterialApp(
      locale: locale,
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: child!),
      home: Scaffold(body: child));
}

Future<void> loadReviewFonts() async {
  final fonts = FontLoader('Anuphan');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    fonts.addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
  }
  await fonts.load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const rect = Rect.fromLTWH(0, 0, 180, 320);
  canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
                colors: [Color(0xFF197A70), Color(0xFF163743)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            .createShader(rect));
  final painter = TextPainter(
      text: const TextSpan(
          text: 'SAMPLE\nVIDEO',
          style: TextStyle(
              fontFamily: 'Anuphan',
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr)
    ..layout(maxWidth: 160);
  painter.paint(canvas, Offset((180 - painter.width) / 2, 100));
  painter.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 320);
  try {
    reviewFixtureCoverBytes =
        (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

late Uint8List reviewFixtureCoverBytes;

void readableReviewText(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  expect(paragraph.didExceedMaxLines, isFalse,
      reason: paragraph.text.toPlainText());
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - .1),
      reason: paragraph.text.toPlainText());
}

Widget simulatedReviewFrame(GlobalKey key, Widget child) => Builder(
    builder: (context) => RepaintBoundary(
        key: key,
        child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Stack(children: [
              Positioned.fill(top: 32, child: child),
              Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                      key: ValueKey(key),
                      height: 32,
                      color: const Color(0xFF123E36),
                      alignment: Alignment.center,
                      child: const Text('SIMULATED DATA · NO POSTS SENT',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontFamily: 'Anuphan'),
                          textAlign: TextAlign.center))),
            ]))));

Future<void> captureReviewFixture(
    WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['POSTDEE_REVIEW_ENGLISH_PREVIEW_DIR'];
  if (directory == null || directory.isEmpty) return;
  await tester.pumpAndSettle();
  for (var attempt = 0; attempt < 20; attempt++) {
    final images = tester.widgetList<RawImage>(
        find.descendant(of: find.byKey(key), matching: find.byType(RawImage)));
    if (images.every((image) => image.image != null)) break;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  expect(find.descendant(of: find.byKey(key), matching: find.text('SIMULATED DATA · NO POSTS SENT')).hitTestable(), findsOneWidget);
  InlineSpan captureFont(InlineSpan span) {
    if (span is! TextSpan) return span;
    final style = span.style ?? const TextStyle();
    return TextSpan(
        text: span.text,
        style: style.copyWith(
            fontFamily: style.fontFamily == null || style.fontFamily == 'Ahem'
                ? 'Anuphan'
                : style.fontFamily),
        children: span.children?.map(captureFont).toList(),
        recognizer: span.recognizer,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale);
  }

  // Flutter's built-in test fallback paints square glyphs for inline button
  // styles with no family. Use the bundled app font only for the screenshot,
  // then restore every paragraph before running the functional assertions.
  final originals = <(RenderParagraph, InlineSpan)>[];
  for (final element in find
      .descendant(of: find.byKey(key), matching: find.byType(RichText))
      .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    originals.add((paragraph, paragraph.text));
    paragraph.text = captureFont(paragraph.text);
  }
  boundary.markNeedsPaint();
  await tester.pump();
  try {
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/simulated-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  } finally {
    for (final (paragraph, span) in originals) {
      if (paragraph.attached) paragraph.text = span;
    }
    boundary.markNeedsPaint();
    await tester.pump();
  }
}

void main() {
  setUpAll(loadReviewFonts);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));
  testWidgets(
      'English summary translates app labels and keeps merchant text raw',
      (tester) async {
    await tester.pumpWidget(reviewEnglishApp(SingleChildScrollView(
        child: PublishReviewSummary(
            videoName: 'กำหนดเวลา.mp4',
            caption: 'โพสต์ทันที',
            platforms: const [SocialPlatform.tiktok],
            connectionDisplayNames: const {SocialPlatform.tiktok: 'แคปชั่น'},
            scheduledAt: null,
            watermarkEnabled: false,
            onPreview: () {},
            onEditPlatforms: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('Caption'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Post to 1 channel'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('โพสต์ทันที'), findsOneWidget);
    expect(find.text('แคปชั่น'), findsOneWidget);
    expect(find.text('กำหนดเวลา.mp4'), findsOneWidget);
    expect(find.text('Post now'), findsOneWidget);
  });

  testWidgets(
      'English rendering keeps pure draft outcome and confirm guard unchanged',
      (tester) async {
    const settings = PlatformPublishSettings();
    final outcome =
        publishReviewOutcomeFor(SocialPlatform.tiktok, settings: settings);
    expect(outcome, 'ส่งเป็นร่างเข้า TikTok · ส่งออกจริงและใช้โควตาโพสต์');
    await tester.pumpWidget(reviewEnglishApp(const SingleChildScrollView(
        child: PublishReviewSummary(
            videoName: 'sample.mp4',
            caption: 'Raw caption',
            platforms: [SocialPlatform.tiktok],
            connectionDisplayNames: {SocialPlatform.tiktok: '@fake-store'},
            scheduledAt: null,
            watermarkEnabled: false))));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Send as draft to TikTok · Sends the video and uses your post quota.'),
        findsOneWidget);
    expect(publishReviewOutcomeFor(SocialPlatform.tiktok, settings: settings),
        outcome);
    expect(
        publishReviewCanConfirm(
            platforms: [SocialPlatform.tiktok],
            platformSettings: settings,
            connectionDisplayNames: {SocialPlatform.tiktok: '@fake-store'}),
        isTrue);
  });

  testWidgets(
      'locale changes preserve local schedule, raw titles, and edit callbacks',
      (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    final at = DateTime(2026, 10, 30, 9, 5);
    final wire = at.toUtc().toIso8601String();
    var previews = 0;
    var edits = 0;
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) => reviewEnglishApp(
            SingleChildScrollView(
                child: PublishReviewSummary(
                    videoName: 'พรีวิว.mp4',
                    caption: 'กำหนดเวลา',
                    platforms: const [SocialPlatform.tiktok],
                    connectionDisplayNames: const {
                      SocialPlatform.tiktok: 'โพสต์ทันที'
                    },
                    scheduledAt: at,
                    watermarkEnabled: false,
                    onPreview: () => previews++,
                    onEditPlatforms: () => edits++)),
            locale: value)));
    await tester.pumpAndSettle();
    expect(find.text('30 Oct 2026 · 09:05'), findsOneWidget);
    expect(
        find.text(
            'Send to drafts on 30 Oct at 09:05 · TikTok · Sends the video and uses your post quota.'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('publish-review-preview')));
    await tester
        .tap(find.byKey(const ValueKey('publish-review-edit-platforms')));
    expect(previews, 1);
    expect(edits, 1);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('30 ต.ค. 2026 · 09:05 น.'), findsOneWidget);
    expect(find.text('กำหนดเวลา'), findsNWidgets(2));
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('กำหนดเวลา'), findsOneWidget);
    expect(find.text('โพสต์ทันที'), findsOneWidget);
    expect(at.toUtc().toIso8601String(), wire);
    expect(previews, 1);
    expect(edits, 1);
  });

  testWidgets(
      'separate captions and YouTube title remain raw even when equal to labels',
      (tester) async {
    const settings = PlatformPublishSettings(
        usePlatformCaptions: true,
        platformCaptions: {
          SocialPlatform.tiktok: 'พรีวิว',
          SocialPlatform.youtubeShorts: 'โพสต์ทันที'
        },
        youtubeTitle: 'กำหนดเวลา',
        youtubeMadeForKids: false,
        youtubeContainsSyntheticMedia: true,
        youtubeCommunityGuidelinesCertified: true);
    final before = settings.toDraftJson();
    await tester.pumpWidget(reviewEnglishApp(const SingleChildScrollView(
        child: PublishReviewSummary(
            videoName: 'sample.mp4',
            caption: 'unused base',
            platforms: [SocialPlatform.tiktok, SocialPlatform.youtubeShorts],
            connectionDisplayNames: {
              SocialPlatform.tiktok: 'แคปชั่น',
              SocialPlatform.youtubeShorts: 'พรีวิว'
            },
            platformSettings: settings,
            scheduledAt: null,
            watermarkEnabled: false))));
    await tester.pumpAndSettle();
    expect(find.text('Video title: กำหนดเวลา'), findsOneWidget);
    expect(find.text('Made for kids: No'), findsOneWidget);
    expect(find.text('Realistic synthetic media: Yes'), findsOneWidget);
    expect(
        find.text('YouTube Community Guidelines: Confirmed'), findsOneWidget);
    expect(find.text('โพสต์ทันที'), findsOneWidget);
    expect(find.text('พรีวิว'), findsNWidgets(2));
    expect(settings.toDraftJson(), before);
  });

  testWidgets('missing and unknown destinations keep confirmation blocked',
      (tester) async {
    await tester.pumpWidget(reviewEnglishApp(const SingleChildScrollView(
        child: PublishReviewSummary(
            videoName: 'sample.mp4',
            caption: '',
            platforms: [SocialPlatform.shopeeVideo],
            scheduledAt: null,
            watermarkEnabled: false))));
    await tester.pumpAndSettle();
    expect(find.text('(No caption)'), findsOneWidget);
    expect(find.text('Destination account not confirmed'), findsOneWidget);
    expect(find.text('Publishing method not confirmed'), findsOneWidget);
    expect(
        find.text(
            'Some destination accounts or Pages are not confirmed. Refresh channels or reconnect them.'),
        findsOneWidget);
    expect(
        publishReviewCanConfirm(
            platforms: [SocialPlatform.shopeeVideo],
            platformSettings: const PlatformPublishSettings(),
            connectionDisplayNames: const {}),
        isFalse);
  });

  for (final throws in [false, true]) {
    testWidgets(
        'YouTube terms recovery throws=$throws keeps public URL and follows current locale',
        (tester) async {
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      final urls = <String>[];
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher,
          (call) async {
        final arguments = call.arguments;
        if (arguments is Map && arguments['url'] is String) {
          urls.add(arguments['url'] as String);
        }
        if (throws) throw PlatformException(code: 'fake-unavailable');
        return false;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, null));
      await tester.pumpWidget(ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (_, value, __) =>
              reviewEnglishApp(const YouTubeUploadNotice(), locale: value)));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('publish-review-youtube-terms')));
      await tester.pumpAndSettle();
      expect(urls, ['https://m.youtube.com/terms']);
      expect(
          find.text(
              'Could not open YouTube terms. Try again or open m.youtube.com/terms in your browser.'),
          findsOneWidget);
      locale.value = const Locale('th');
      await tester.pump();
      expect(
          find.text(
              'เปิดข้อกำหนด YouTube ไม่สำเร็จ ลองใหม่หรือเปิด m.youtube.com/terms ในเบราว์เซอร์'),
          findsOneWidget);
      expect(urls.length, 1);
    });
  }

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'summary and cover notice are readable at320dp ${scale}x dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(320, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(reviewEnglishApp(
            simulatedReviewFrame(
                key,
                SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: PublishReviewSummary(
                            videoName: 'sample-store-video.mp4',
                            caption:
                                'Handmade products from our sample store. This is local fixture data.',
                            platforms: const [
                              SocialPlatform.tiktok,
                              SocialPlatform.facebookReels
                            ],
                            platformSettings: const PlatformPublishSettings(
                                facebookPublishMode:
                                    FacebookPublishMode.pageDraft),
                            connectionDisplayNames: const {
                              SocialPlatform.tiktok: '@sample_store',
                              SocialPlatform.facebookReels: 'Sample store Page'
                            },
                            coverResult: CoverEditorResult(
                                localImagePath: 'unread-local-fixture.png',
                                sizeBytes: 1,
                                design:
                                    const CoverDesign(coverFrameTimeMs: 1250),
                                imageBytes: reviewFixtureCoverBytes),
                            scheduledAt: DateTime(2026, 10, 30, 9, 5),
                            watermarkEnabled: false,
                            onPreview: () {},
                            onEditPlatforms: () {})))),
            dark: dark,
            scale: scale));
        await tester.pumpAndSettle();
        if (scale == 1) {
          await captureReviewFixture(
              tester, key, 'review-summary-${dark ? 'dark' : 'light'}');
        }
        for (final text in [
          'Caption',
          'Preview',
          'Cover selected at 1.3 seconds',
          'Cover support',
          'Post to 2 channels',
          'Edit',
          'Schedule',
          '30 Oct 2026 · 09:05'
        ]) {
          final finder = find.text(text);
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          readableReviewText(tester, finder);
        }
        final noticeFinder =
            find.byKey(const ValueKey('cover-platform-capability-notice'));
        final background = (tester.widget<Container>(noticeFinder).decoration!
                as BoxDecoration)
            .color!;
        for (final text in tester.widgetList<Text>(
            find.descendant(of: noticeFinder, matching: find.byType(Text)))) {
          final foreground = text.style!.color!;
          final a = background.computeLuminance();
          final b = foreground.computeLuminance();
          final ratio = ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'Cover notice must remain readable: ${text.data}');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
