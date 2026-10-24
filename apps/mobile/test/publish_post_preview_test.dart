import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/publish_post_preview.dart';

const _channels = [
  PublishPostPreviewChannel(
      platform: SocialPlatform.tiktok,
      caption: 'ข้อความ TikTok จริง',
      displayName: 'บัญชี TikTok',
      publishingNote: 'ส่งเป็นร่างเข้า TikTok'),
  PublishPostPreviewChannel(
      platform: SocialPlatform.youtubeShorts,
      caption: 'คำอธิบาย YouTube จริง',
      displayName: 'ช่อง YouTube',
      title: 'ชื่อ Shorts ที่ตั้งไว้'),
  PublishPostPreviewChannel(
      platform: SocialPlatform.instagramReels,
      caption: 'ข้อความ Instagram จริง',
      displayName: 'ร้าน Instagram'),
  PublishPostPreviewChannel(
      platform: SocialPlatform.facebookReels,
      caption: 'ข้อความ Facebook จริง',
      displayName: 'เพจ Facebook'),
];

class _Video extends StatefulWidget {
  const _Video({required this.onCreated});
  final VoidCallback onCreated;
  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  @override
  void initState() {
    super.initState();
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
      key: ValueKey('real-video-fixture'),
      color: Colors.black,
      child: Center(
          child: AspectRatio(
              aspectRatio: 9 / 16, child: ColoredBox(color: Colors.blue))));
}

bool _fontsLoaded = false;
Future<void> _pump(WidgetTester tester, PublishPostPreviewData data,
    {Widget? video,
    bool started = false,
    bool playing = false,
    VoidCallback? onShowCover,
    VoidCallback? onShowInformation,
    VoidCallback? onCanvasTap,
    double scale = 1,
    bool dark = false,
    bool immersive = false}) async {
  if (!_fontsLoaded) {
    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
    });
    _fontsLoaded = true;
  }
  await tester.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body: SafeArea(
            child: Column(children: [
      Expanded(
          child: GestureDetector(
              onTap: onCanvasTap,
              child: PublishPostPreviewPane(
                  data: data,
                  video: video ?? const ColoredBox(color: Colors.black),
                  hasStartedPlayback: started,
                  isPlaying: playing,
                  onShowCover: onShowCover,
                  onShowInformation: onShowInformation,
                  immersive: immersive))),
      if (!immersive)
        const SizedBox(
            height: 70, child: Center(child: Text('ตัวควบคุมคลิปจริง'))),
    ]))),
  ));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, SocialPlatform platform) async {
  final target = find.byKey(ValueKey('preview-platform-${platform.apiValue}'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'immersive preview fills the pane with transparent caption and inert social overlays',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var created = 0;
    var taps = 0;
    await _pump(tester,
        PublishPostPreviewData(channels: _channels, caption: 'ข้อความหลัก'),
        immersive: true,
        video: GestureDetector(
            onTap: () => taps++, child: _Video(onCreated: () => created++)));
    final pane =
        tester.getRect(find.byKey(const ValueKey('publish-post-preview')));
    expect(
        tester.getRect(find.byKey(const ValueKey('real-video-fixture'))), pane);
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('real-video-fixture')),
            matching: find.byType(ClipRRect)),
        findsNothing);
    expect(find.text('ตัวควบคุมคลิปจริง'), findsNothing);
    expect(find.textContaining('ภาพตัวอย่างก่อนส่ง'), findsNothing);
    expect(find.text('ส่งเป็นร่างเข้า TikTok'), findsNothing);
    final caption = find.byKey(const ValueKey('preview-caption'));
    final decoration = tester
        .widget<DecoratedBox>(find
            .ancestor(of: caption, matching: find.byType(DecoratedBox))
            .first)
        .decoration as BoxDecoration;
    expect(decoration.color, isNull);
    expect(find.byKey(const ValueKey('preview-tiktok-social-rail')),
        findsOneWidget);
    await tester.tapAt(pane.center);
    await tester.pump();
    expect(taps, 1);
    await _select(tester, SocialPlatform.youtubeShorts);
    expect(find.text('ชื่อ Shorts ที่ตั้งไว้'), findsOneWidget);
    expect(find.text('คำอธิบาย YouTube จริง'), findsOneWidget);
    expect(created, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'immersive generic preview shows shared caption without inventing account or destinations',
      (tester) async {
    await _pump(tester,
        PublishPostPreviewData(channels: const [], caption: 'แคปชั่นของฉัน'),
        immersive: true);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('preview-identity')), findsNothing);
    expect(find.text('แคปชั่นของฉัน'), findsOneWidget);
    final rail = find.byKey(const ValueKey('preview-tiktok-social-rail'));
    expect(tester.widget<IgnorePointer>(rail).ignoring, isTrue);
    expect(
        find.descendant(of: rail, matching: find.byType(Text)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'immersive information keeps cover, capability and watermark notes available without crowding the video',
      (tester) async {
    var pauses = 0;
    var informationPauses = 0;
    var canvasTaps = 0;
    final bytes =
        File('assets/images/brand/postdee_mark.png').readAsBytesSync();
    await _pump(
        tester,
        PublishPostPreviewData(
            channels: [_channels.first],
            caption: 'หลัก',
            coverImageBytes: bytes,
            watermarkEnabled: true),
        immersive: true,
        onShowCover: () => pauses++,
        onShowInformation: () => informationPauses++,
        onCanvasTap: () => canvasTaps++);
    expect(find.text('ลายน้ำจริงจะถูกใส่ตอนส่งโพสต์'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('preview-info-toggle')));
    await tester.pumpAndSettle();
    expect(informationPauses, 1);
    expect(find.byKey(const ValueKey('preview-info-panel')), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
    expect(find.text('ส่งเป็นร่างเข้า TikTok'), findsOneWidget);
    expect(find.textContaining('TikTok ใช้เฟรมจากคลิป'), findsOneWidget);
    expect(find.text('ลายน้ำจริงจะถูกใส่ตอนส่งโพสต์'), findsOneWidget);
    await tester.tap(find.text('ลายน้ำจริงจะถูกใส่ตอนส่งโพสต์'));
    await tester.pump();
    expect(canvasTaps, 0);
    await tester.tap(find.byKey(const ValueKey('preview-info-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preview-cover-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('preview-cover-image')), findsOneWidget);
    expect(pauses, 1);
    await tester.tap(find.byKey(const ValueKey('preview-info-toggle')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: Text('ออกจากพรีวิว')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-info-panel')), findsNothing);
    expect(find.text('ส่งเป็นร่างเข้า TikTok'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('immersive preview fits $size with doubled text',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
          tester, PublishPostPreviewData(channels: _channels, caption: 'หลัก'),
          immersive: true, scale: 2);
      for (final channel in _channels) {
        await _select(tester, channel.platform);
        expect(find.text(channel.caption), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  test('preview snapshots defensively copy channels and poster bytes', () {
    final channels = [_channels.first];
    final bytes = Uint8List.fromList([1, 2, 3]);
    final data = PublishPostPreviewData(
        channels: channels, caption: 'หลัก', coverImageBytes: bytes);
    channels.clear();
    bytes[0] = 99;
    expect(data.channels, hasLength(1));
    expect(data.coverImageBytes, [1, 2, 3]);
    expect(() => data.channels.clear(), throwsUnsupportedError);
    expect(() => data.coverImageBytes![0] = 9, throwsUnsupportedError);
    expect(() => data.coverImageBytes!.buffer.asUint8List()[0] = 9,
        throwsUnsupportedError);
  });

  testWidgets(
      'only selected supported destinations appear with their exact account and caption',
      (tester) async {
    final data = PublishPostPreviewData(channels: [
      _channels.first,
      _channels[1],
      const PublishPostPreviewChannel(
          platform: SocialPlatform.shopeeVideo,
          caption: 'อนาคต',
          displayName: 'ไม่ควรมี')
    ], caption: 'ข้อความหลักที่ซ่อน');
    await _pump(tester, data);
    expect(
        find.byKey(const ValueKey('preview-platform-TIKTOK')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-platform-YOUTUBE_SHORTS')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('preview-platform-INSTAGRAM_REELS')),
        findsNothing);
    expect(find.text('Shopee Video'), findsNothing);
    expect(find.text('บัญชี TikTok'), findsOneWidget);
    expect(find.text('ข้อความ TikTok จริง'), findsOneWidget);
    expect(find.text('ข้อความหลักที่ซ่อน'), findsNothing);
    expect(find.text('ส่งเป็นร่างเข้า TikTok'), findsOneWidget);
    await _select(tester, SocialPlatform.youtubeShorts);
    expect(find.text('ช่อง YouTube'), findsOneWidget);
    expect(find.text('คำอธิบาย YouTube จริง'), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-title')), findsOneWidget);
    expect(find.text('ชื่อ Shorts ที่ตั้งไว้'), findsOneWidget);
    expect(find.text('ข้อความ TikTok จริง'), findsNothing);
  });

  testWidgets(
      'no destination shows shared local preview without inventing an account',
      (tester) async {
    await _pump(tester,
        PublishPostPreviewData(channels: const [], caption: 'แคปชั่นหลัก'));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('preview-identity')), findsNothing);
    expect(find.text('แคปชั่นหลัก'), findsOneWidget);
    expect(find.text('เผยแพร่แล้ว'), findsNothing);
  });

  testWidgets('YouTube title-only never substitutes the hidden shared caption',
      (tester) async {
    await _pump(
        tester,
        PublishPostPreviewData(channels: const [
          PublishPostPreviewChannel(
              platform: SocialPlatform.youtubeShorts,
              caption: '',
              displayName: 'เจ้าของช่อง',
              title: 'เฉพาะชื่อวิดีโอ')
        ], caption: 'ห้ามนำข้อความนี้มาแสดง'));
    expect(find.text('เฉพาะชื่อวิดีโอ'), findsOneWidget);
    expect(find.text('ห้ามนำข้อความนี้มาแสดง'), findsNothing);
  });

  testWidgets(
      'switching all layouts keeps the actual video mounted once and never adds publish actions',
      (tester) async {
    var created = 0;
    await _pump(
        tester, PublishPostPreviewData(channels: _channels, caption: 'หลัก'),
        video: _Video(onCreated: () => created++));
    for (final channel in _channels) {
      await _select(tester, channel.platform);
      expect(find.text(channel.caption), findsOneWidget);
      expect(find.text(channel.displayName), findsOneWidget);
      expect(find.byKey(const ValueKey('real-video-fixture')), findsOneWidget);
      expect(find.text('Facebook Reels'), findsNothing);
      expect(find.text('โพสต์เลย'), findsNothing);
      expect(find.text('เผยแพร่'), findsNothing);
    }
    expect(find.text('Facebook'), findsWidgets);
    expect(find.text('Facebook Page Video'), findsNothing);
    expect(created, 1);
  });

  testWidgets(
      'TikTok watch preview uses a bottom gradient and four inert actions without a caption card',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var created = 0;
    await _pump(
        tester, PublishPostPreviewData(channels: _channels, caption: 'หลัก'),
        video: _Video(onCreated: () => created++));
    final gradient = find.byKey(const ValueKey('preview-tiktok-gradient'));
    expect(gradient, findsOneWidget);
    final decoration =
        tester.widget<DecoratedBox>(gradient).decoration as BoxDecoration;
    expect(decoration.gradient, isA<LinearGradient>());
    expect(decoration.color, isNull);
    final videoRect =
        tester.getRect(find.byKey(const ValueKey('real-video-fixture')));
    expect(tester.getRect(gradient), videoRect);
    final caption = find.byKey(const ValueKey('preview-caption'));
    final captionBackground = tester
        .widget<DecoratedBox>(find
            .ancestor(of: caption, matching: find.byType(DecoratedBox))
            .first)
        .decoration as BoxDecoration;
    expect(captionBackground.color, isNull);
    expect(captionBackground.borderRadius, isNull);
    final rail = find.byKey(const ValueKey('preview-tiktok-social-rail'));
    expect(tester.widget<IgnorePointer>(rail).ignoring, isTrue);
    for (final icon in [
      Icons.favorite,
      Icons.chat_bubble,
      Icons.bookmark,
      Icons.share
    ]) {
      expect(find.descendant(of: rail, matching: find.byIcon(icon)),
          findsOneWidget);
    }
    expect(
        find.descendant(of: rail, matching: find.byType(Text)), findsNothing);
    expect(find.descendant(of: rail, matching: find.byType(IconButton)),
        findsNothing);
    expect(find.descendant(of: rail, matching: find.byType(GestureDetector)),
        findsNothing);
    expect(find.byKey(const ValueKey('preview-clip-audio')), findsOneWidget);
    expect(find.text('เสียงจากคลิป'), findsOneWidget);
    expect(find.text(_channels.first.caption), findsOneWidget);
    expect(find.text(_channels.first.displayName), findsOneWidget);
    await _select(tester, SocialPlatform.youtubeShorts);
    expect(gradient, findsNothing);
    await _select(tester, SocialPlatform.tiktok);
    expect(gradient, findsOneWidget);
    expect(created, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'large type TikTok uses the readable fallback while preserving the video',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
        tester, PublishPostPreviewData(channels: _channels, caption: 'หลัก'),
        video: _Video(onCreated: () {}), scale: 1.7);
    expect(find.byKey(const ValueKey('preview-tiktok-gradient')), findsNothing);
    final video =
        tester.getRect(find.byKey(const ValueKey('real-video-fixture')));
    final caption =
        tester.getRect(find.byKey(const ValueKey('preview-caption')));
    expect(caption.top, greaterThanOrEqualTo(video.bottom));
    expect(find.text(_channels.first.caption), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a long caption expands in a bounded scroll area without covering player controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final caption = List.generate(45, (i) => 'บรรทัดจริง $i').join('\n');
    final data = PublishPostPreviewData(channels: [
      PublishPostPreviewChannel(
          platform: SocialPlatform.tiktok,
          caption: caption,
          displayName: 'ร้าน')
    ], caption: 'หลัก');
    await _pump(tester, data);
    final expand = find.byKey(const ValueKey('preview-caption-expand'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('preview-caption')))
            .maxLines,
        isNull);
    final control = tester.getRect(find.text('ตัวควบคุมคลิปจริง'));
    final pane =
        tester.getRect(find.byKey(const ValueKey('publish-post-preview')));
    expect(pane.bottom, lessThanOrEqualTo(control.top));
    // Playback ticks rebuild the pane while the implicit first channel remains
    // selected. Reading the full caption must survive those unrelated updates.
    await _pump(tester, data, started: true);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('preview-caption')))
            .maxLines,
        isNull);
    expect(
        find.byKey(const ValueKey('preview-tiktok-gradient')), findsOneWidget);
    await tester.ensureVisible(expand);
    expect(tester.getRect(expand).bottom, lessThanOrEqualTo(control.top));
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('preview-caption')))
            .maxLines,
        3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'poster toggle uses the chosen bytes and leaves the video mounted until playback reveals it',
      (tester) async {
    var created = 0;
    var pauses = 0;
    final video = _Video(onCreated: () => created++);
    final bytes =
        File('assets/images/brand/postdee_mark.png').readAsBytesSync();
    final data = PublishPostPreviewData(
        channels: _channels, caption: 'หลัก', coverImageBytes: bytes);
    await _pump(tester, data, video: video, onShowCover: () => pauses++);
    expect(find.byKey(const ValueKey('preview-cover-image')), findsNothing);
    final toggle = find.byKey(const ValueKey('preview-cover-toggle'));
    expect(toggle, findsOneWidget);
    await tester.tap(find.descendant(of: toggle, matching: find.text('ดูปก')));
    await tester.pumpAndSettle();
    final image =
        tester.widget<Image>(find.byKey(const ValueKey('preview-cover-image')));
    expect((image.image as MemoryImage).bytes, bytes);
    expect(find.text('ปกที่เลือกใน PostDee'), findsOneWidget);
    expect(find.byKey(const ValueKey('real-video-fixture')), findsOneWidget);
    expect(pauses, 1);
    await _pump(tester, data, video: video, started: true);
    expect(find.byKey(const ValueKey('preview-cover-image')), findsNothing);
    // A paused clip at a positive position has already started. Showing its
    // poster then resuming must reveal the same mounted video again.
    await _pump(tester, data,
        video: video, started: true, onShowCover: () => pauses++);
    await tester.tap(find.byKey(const ValueKey('preview-cover-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-cover-image')), findsOneWidget);
    expect(pauses, 2);
    await tester.tap(find.byKey(const ValueKey('preview-cover-toggle')));
    await tester.pumpAndSettle();
    expect(pauses, 2, reason: 'Hiding the poster does not need another pause.');
    await tester.tap(find.byKey(const ValueKey('preview-cover-toggle')));
    await tester.pumpAndSettle();
    await _pump(tester, data, video: video, started: true, playing: true);
    expect(find.byKey(const ValueKey('preview-cover-image')), findsNothing);
    expect(created, 1);
  });

  testWidgets(
      'watermark is explained honestly without drawing a fake export watermark',
      (tester) async {
    await _pump(
        tester,
        PublishPostPreviewData(
            channels: _channels, caption: 'หลัก', watermarkEnabled: true));
    expect(find.textContaining('ลายน้ำจริง'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('preview-watermark-overlay')), findsNothing);
  });

  testWidgets(
      'short landscape gives video and caption separate columns without restarting the video',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var created = 0;
    final video = _Video(onCreated: () => created++);
    final data = PublishPostPreviewData(channels: _channels, caption: 'หลัก');
    await _pump(tester, data, video: video, scale: 2);
    await tester.binding.setSurfaceSize(const Size(740, 360));
    await _pump(tester, data, video: video, scale: 2);
    final videoRect =
        tester.getRect(find.byKey(const ValueKey('real-video-fixture')));
    final captionRect =
        tester.getRect(find.byKey(const ValueKey('preview-caption')));
    expect(captionRect.left, greaterThanOrEqualTo(videoRect.right));
    expect(videoRect.height, greaterThan(100));
    expect(created, 1);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    for (final dark in [false, true]) {
      testWidgets(
          'preview fits $size ${dark ? 'dark' : 'light'} with large text and long details',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(
            tester,
            PublishPostPreviewData(
                channels: _channels, caption: 'หลัก', watermarkEnabled: true),
            scale: 1.7,
            dark: dark);
        for (final channel in _channels) {
          await _select(tester, channel.platform);
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('preview-caption')), findsOneWidget);
          expect(find.text('ตัวควบคุมคลิปจริง'), findsOneWidget);
        }
      });
    }
  }
}
