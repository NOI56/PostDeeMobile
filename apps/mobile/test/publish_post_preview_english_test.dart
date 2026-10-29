import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/publish_post_preview.dart';

import 'publish_review_english_test.dart'
    show
        reviewEnglishApp,
        loadReviewFonts,
        readableReviewText,
        simulatedReviewFrame,
        captureReviewFixture,
        reviewFixtureCoverBytes;

class _VideoFixture extends StatefulWidget {
  const _VideoFixture({required this.onCreated});
  final VoidCallback onCreated;
  @override
  State<_VideoFixture> createState() => _VideoFixtureState();
}

class _VideoFixtureState extends State<_VideoFixture> {
  @override
  void initState() {
    super.initState();
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) => const DecoratedBox(
      key: ValueKey('local-video-fixture'),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF197A70), Color(0xFF163743)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.play_circle_outline, size: 64, color: Colors.white),
        Text('LOCAL VIDEO FIXTURE',
            style: TextStyle(color: Colors.white, fontSize: 11))
      ])));
}

Future<void> _tapPreview(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadReviewFonts);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));
  testWidgets(
      'English preview explains simulated presentation and preserves raw channel data',
      (tester) async {
    await tester.pumpWidget(reviewEnglishApp(PublishPostPreviewPane(
        data: PublishPostPreviewData(channels: const [
          PublishPostPreviewChannel(
              platform: SocialPlatform.youtubeShorts,
              caption: 'เสียงจากคลิป',
              displayName: 'ข้อมูลพรีวิว',
              title: 'ดูปก')
        ], caption: 'Raw main caption', watermarkEnabled: true),
        video: const ColoredBox(color: Colors.blue))));
    await tester.pumpAndSettle();
    expect(
        find.text('Preview before sending · Appearance may vary by platform.'),
        findsOneWidget);
    expect(find.text('The watermark will be added when the post is sent.'),
        findsOneWidget);
    expect(find.text('เสียงจากคลิป'), findsOneWidget);
    expect(find.text('ข้อมูลพรีวิว'), findsOneWidget);
    expect(find.text('ดูปก'), findsOneWidget);
  });

  testWidgets(
      'live locale preserves selected channel, expanded caption and video state',
      (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    var created = 0;
    final raw = List.filled(15, 'ข้อมูลพรีวิว ดูปก เสียงจากคลิป').join(' ');
    final data = PublishPostPreviewData(channels: [
      const PublishPostPreviewChannel(
          platform: SocialPlatform.tiktok,
          caption: 'TikTok raw',
          displayName: 'Raw store'),
      PublishPostPreviewChannel(
          platform: SocialPlatform.youtubeShorts,
          caption: raw,
          displayName: 'ดูปก',
          title: 'เสียงจากคลิป'),
    ], caption: 'Raw default');
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) => reviewEnglishApp(
            PublishPostPreviewPane(
                data: data, video: _VideoFixture(onCreated: () => created++)),
            locale: value)));
    await tester.pumpAndSettle();
    await _tapPreview(
        tester, find.byKey(const ValueKey('preview-platform-YOUTUBE_SHORTS')));
    await _tapPreview(
        tester, find.byKey(const ValueKey('preview-caption-expand')));
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('preview-caption')))
            .maxLines,
        isNull);
    for (final language in ['th', 'en']) {
      locale.value = Locale(language);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ChoiceChip>(
                  find.byKey(const ValueKey('preview-platform-YOUTUBE_SHORTS')))
              .selected,
          isTrue);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('preview-caption')))
              .data,
          raw);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('preview-title'))).data,
          'เสียงจากคลิป');
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('preview-identity')))
              .data,
          'ดูปก');
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('preview-caption')))
              .maxLines,
          isNull);
      expect(created, 1);
    }
    expect(find.text('Collapse caption'), findsOneWidget);
  });

  testWidgets('cover and playback state stay independent of localized labels',
      (tester) async {
    var covers = 0;
    final started = ValueNotifier(false);
    addTearDown(started.dispose);
    final data = PublishPostPreviewData(channels: const [
      PublishPostPreviewChannel(
          platform: SocialPlatform.tiktok,
          caption: 'Raw caption',
          displayName: 'Raw account')
    ], caption: 'Raw caption', coverImageBytes: reviewFixtureCoverBytes);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
        valueListenable: started,
        builder: (_, value, __) => reviewEnglishApp(PublishPostPreviewPane(
            data: data,
            hasStartedPlayback: value,
            onShowCover: () => covers++,
            video: const ColoredBox(color: Colors.black)))));
    await tester.pumpAndSettle();
    await _tapPreview(
        tester, find.byKey(const ValueKey('preview-cover-toggle')));
    expect(covers, 1);
    expect(find.text('Cover selected in PostDee'), findsOneWidget);
    expect(
        find.text(
            'TikTok uses a video frame as the cover, not this edited cover image.'),
        findsOneWidget);
    expect(find.text('Watch video'), findsOneWidget);
    started.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-cover-image')), findsNothing);
    expect(find.text('View cover'), findsOneWidget);
    expect(covers, 1);
  });

  testWidgets(
      'information panel keeps unknown notes raw and does not recreate the video',
      (tester) async {
    var created = 0;
    var information = 0;
    const note = 'Provider supplied note: ดูปก';
    await tester.pumpWidget(reviewEnglishApp(PublishPostPreviewPane(
        data: PublishPostPreviewData(channels: const [
          PublishPostPreviewChannel(
              platform: SocialPlatform.facebookReels,
              caption: 'แคปชั่น',
              displayName: 'ข้อมูลพรีวิว',
              publishingNote: note)
        ], caption: 'raw', watermarkEnabled: true),
        immersive: true,
        onShowInformation: () => information++,
        video: _VideoFixture(onCreated: () => created++))));
    await tester.pumpAndSettle();
    await _tapPreview(
        tester, find.byKey(const ValueKey('preview-info-toggle')));
    expect(find.text('Preview information'), findsOneWidget);
    expect(find.text(note), findsOneWidget);
    expect(find.text('Hearts and comments are part of the preview.'),
        findsOneWidget);
    expect(information, 1);
    await _tapPreview(tester, find.byKey(const ValueKey('preview-info-close')));
    expect(find.byKey(const ValueKey('preview-info-panel')), findsNothing);
    expect(created, 1);
  });

  testWidgets(
      'failed local cover displays English fallback while path stays unchanged',
      (tester) async {
    const path = '/nonexistent/ข้อมูลพรีวิว.png';
    final data = PublishPostPreviewData(
        channels: const [], caption: 'raw', coverImagePath: path);
    await tester.pumpWidget(reviewEnglishApp(PublishPostPreviewPane(
        data: data, video: const ColoredBox(color: Colors.black))));
    await tester.pumpAndSettle();
    await _tapPreview(
        tester, find.byKey(const ValueKey('preview-cover-toggle')));
    // FileImage completes on the real I/O loop. Pump between bounded waits so
    // its existing image stream can deliver the error to the mounted builder.
    for (var attempt = 0;
        attempt < 40 &&
            find.text('Could not display the cover').evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Could not display the cover'), findsOneWidget);
    expect(data.coverImagePath, path);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final immersive in [false, true]) {
        testWidgets(
            'preview 320dp ${scale}x dark=$dark immersive=$immersive remains readable',
            (tester) async {
          tester.view.physicalSize = const Size(320, 852);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          final caption =
              List.filled(9, 'Sample product caption #shop').join(' ');
          final data = PublishPostPreviewData(channels: [
            for (final platform in [
              SocialPlatform.tiktok,
              SocialPlatform.youtubeShorts,
              SocialPlatform.instagramReels,
              SocialPlatform.facebookReels
            ])
              PublishPostPreviewChannel(
                  platform: platform,
                  caption: caption,
                  displayName: '@sample_store',
                  title: 'Sample video title'),
          ], caption: caption, watermarkEnabled: true);
          await tester.pumpWidget(reviewEnglishApp(
              simulatedReviewFrame(
                  key,
                  PublishPostPreviewPane(
                      data: data,
                      immersive: immersive,
                      video: _VideoFixture(onCreated: () {}))),
              dark: dark,
              scale: scale));
          await tester.pumpAndSettle();
          if (scale == 1 && immersive && !dark) {
            await captureReviewFixture(tester, key, 'preview-tiktok-light');
          }
          if (immersive) {
            await _tapPreview(
                tester, find.byKey(const ValueKey('preview-info-toggle')));
            for (final text in [
              'Preview information',
              'Preview before sending · Appearance may vary by platform.',
              'The watermark will be added when the post is sent.',
              'Hearts and comments are part of the preview.',
              'Close'
            ]) {
              final finder = find.text(text);
              await tester.ensureVisible(finder);
              await tester.pumpAndSettle();
              readableReviewText(tester, finder);
            }
            await _tapPreview(
                tester, find.byKey(const ValueKey('preview-info-close')));
          } else {
            readableReviewText(
                tester,
                find.text(
                    'Preview before sending · Appearance may vary by platform.'));
            readableReviewText(
                tester,
                find.text(
                    'The watermark will be added when the post is sent.'));
          }
          for (final platform in [
            SocialPlatform.tiktok,
            SocialPlatform.youtubeShorts,
            SocialPlatform.instagramReels,
            SocialPlatform.facebookReels
          ]) {
            await _tapPreview(tester,
                find.byKey(ValueKey('preview-platform-${platform.apiValue}')));
            await _tapPreview(
                tester, find.byKey(const ValueKey('preview-caption-expand')));
            expect(
                tester
                    .widget<Text>(find.byKey(const ValueKey('preview-caption')))
                    .data,
                caption);
            readableReviewText(
                tester, find.byKey(const ValueKey('preview-caption')));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
