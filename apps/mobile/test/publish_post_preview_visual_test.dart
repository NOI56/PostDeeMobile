import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/publish_post_preview.dart';

const _captureDirectory =
    String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR', defaultValue: '');
const _captureKey = ValueKey('post-preview-visual-capture');
const _channels = [
  PublishPostPreviewChannel(
      platform: SocialPlatform.tiktok,
      displayName: 'PostDee Shop',
      caption: 'กระเป๋าใบโปรด จุของได้ครบ พกไปไหนก็คล่องตัว 👜\n'
          'ดูสีที่ชอบได้ที่ลิงก์หน้าโปรไฟล์ #กระเป๋าสะพาย #ของใช้ประจำวัน',
      publishingNote: 'ส่งเป็นร่างเข้า TikTok'),
  PublishPostPreviewChannel(
      platform: SocialPlatform.youtubeShorts,
      displayName: 'PostDee Shop',
      title: 'กระเป๋าใบเดียว จุของได้ครบ!',
      caption: 'ลองจัดของใช้ประจำวันลงกระเป๋าใบโปรด 👜\n'
          'ดูรายละเอียดเพิ่มเติมได้ที่ลิงก์หน้าโปรไฟล์ #Shorts #กระเป๋าสะพาย',
      publishingNote: 'การมองเห็น: ส่วนตัว'),
  PublishPostPreviewChannel(
      platform: SocialPlatform.instagramReels,
      displayName: 'PostDee Shop',
      caption: 'Everyday bag 👜 ใบโปรดสำหรับทุกวัน\n'
          'แมตช์ง่าย จุของได้ครบ ดูสีที่ลิงก์หน้าโปรไฟล์\n'
          '#EverydayBag #กระเป๋าสะพาย #ของใช้ประจำวัน'),
  PublishPostPreviewChannel(
      platform: SocialPlatform.facebookReels,
      displayName: 'PostDee Shop',
      caption: 'ใครกำลังมองหากระเป๋าใช้ทุกวัน ลองดูใบนี้ค่ะ 👜\n'
          'จุของได้ครบ แมตช์ง่าย มีหลายสีให้เลือก\n'
          'ดูรายละเอียดและสีที่ชอบได้ที่ลิงก์หน้าโปรไฟล์'),
];

Future<void> _loadAssets(WidgetTester tester) async {
  final context = tester.element(find.byType(PublishPostPreviewPane));
  await tester.runAsync(() async {
    final fonts = FontLoader('Anuphan');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts
          .addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
    }
    await fonts.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final name in [
      'tiktok',
      'youtube_shorts',
      'instagram_reels',
      'facebook_reels'
    ]) {
      await precacheImage(
          AssetImage('assets/images/platforms/$name.png'), context);
    }
  });
}

Widget _video({bool darkFrame = false}) => ColoredBox(
      key: ValueKey('visual-natural-video'),
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: darkFrame
                    ? const [Color(0xFF121A15), Color(0xFF24362B)]
                    : const [Colors.white, Color(0xFFE4EBE7)],
              ),
            ),
            child: const Center(
                child: Icon(Icons.shopping_bag_outlined,
                    color: Color(0xFF334D3F), size: 100)),
          ),
        ),
      ),
    );

Widget _controls() => SizedBox(
      key: const ValueKey('visual-player-controls'),
      height: 112,
      child: Column(children: [
        Slider(value: 0, onChanged: (_) {}),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              onPressed: () {},
              tooltip: 'เล่น',
              icon: const Icon(Icons.play_arrow)),
          IconButton(
              onPressed: () {},
              tooltip: 'เริ่มใหม่',
              icon: const Icon(Icons.replay)),
          IconButton(
              onPressed: () {},
              tooltip: 'เสียง',
              icon: const Icon(Icons.volume_up_outlined)),
        ]),
      ]),
    );

void main() {
  final cases = [
    for (final channel in _channels)
      (
        name: channel.platform.apiValue.toLowerCase(),
        platform: channel.platform,
        size: const Size(430, 900),
        scale: 1.0,
        dark: false
      ),
    (
      name: 'dark-large',
      platform: SocialPlatform.youtubeShorts,
      size: const Size(320, 740),
      scale: 1.7,
      dark: true
    ),
    (
      name: 'landscape-large',
      platform: SocialPlatform.facebookReels,
      size: const Size(740, 360),
      scale: 2.0,
      dark: false
    ),
    (
      name: 'tiktok-dark-frame',
      platform: SocialPlatform.tiktok,
      size: const Size(430, 900),
      scale: 1.0,
      dark: true
    ),
    (
      name: 'tiktok-narrow',
      platform: SocialPlatform.tiktok,
      size: const Size(320, 740),
      scale: 1.0,
      dark: false
    ),
    (
      name: 'tiktok-large-fallback',
      platform: SocialPlatform.tiktok,
      size: const Size(320, 740),
      scale: 1.7,
      dark: true
    ),
    (
      name: 'tiktok-landscape-fallback',
      platform: SocialPlatform.tiktok,
      size: const Size(740, 360),
      scale: 2.0,
      dark: false
    ),
  ];
  for (final sample in cases) {
    testWidgets('real-font post preview ${sample.name}', (tester) async {
      tester.view.physicalSize = sample.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final oldTheme = AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
      addTearDown(() => AppTheme.applyThemeMode(oldTheme));
      AppTheme.applyThemeMode(sample.dark ? ThemeMode.dark : ThemeMode.light);
      await tester.pumpWidget(RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: sample.dark ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(sample.scale)),
                  child: child!),
              home: Scaffold(
                  appBar: AppBar(title: const Text('ตัวอย่างโพสต์')),
                  body: SafeArea(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Column(children: [
                            Expanded(
                                child: PublishPostPreviewPane(
                                    data: PublishPostPreviewData(
                                        channels: _channels,
                                        caption: 'ข้อความหลัก'),
                                    video: _video(darkFrame: sample.dark))),
                            _controls(),
                          ])))))));
      await _loadAssets(tester);
      await tester.pumpAndSettle();
      final chip =
          find.byKey(ValueKey('preview-platform-${sample.platform.apiValue}'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final channel =
          _channels.firstWhere((c) => c.platform == sample.platform);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(find.text(channel.caption), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-identity')), findsOneWidget);
      expect(find.text('Facebook Reels'), findsNothing);
      expect(find.text('Facebook Page Video'), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('preview-platform-FACEBOOK_REELS')),
              matching: find.text('Facebook')),
          findsOneWidget);
      final pane =
          tester.getRect(find.byKey(const ValueKey('publish-post-preview')));
      final controls =
          tester.getRect(find.byKey(const ValueKey('visual-player-controls')));
      expect(pane.bottom, lessThanOrEqualTo(controls.top));
      expect(controls.bottom, lessThanOrEqualTo(sample.size.height));
      expect(tester.takeException(), isNull);
      if (_captureDirectory.isNotEmpty) {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final directory = Directory(_captureDirectory)
              ..createSync(recursive: true);
            await File('${directory.path}/post-preview-${sample.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    });
  }

  final immersiveCases = [
    (name: 'portrait', size: const Size(390, 844), scale: 1.0, generic: false),
    (name: 'narrow', size: const Size(320, 640), scale: 1.0, generic: false),
    (
      name: 'large-text',
      size: const Size(320, 640),
      scale: 2.0,
      generic: false
    ),
    (name: 'landscape', size: const Size(844, 390), scale: 2.0, generic: false),
    (name: 'generic', size: const Size(390, 844), scale: 1.0, generic: true),
  ];
  for (final sample in immersiveCases) {
    testWidgets('real-font immersive post preview ${sample.name}',
        (tester) async {
      tester.view.physicalSize = sample.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(sample.scale)),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(fit: StackFit.expand, children: [
              PublishPostPreviewPane(
                immersive: true,
                data: PublishPostPreviewData(
                    channels: sample.generic ? const [] : _channels,
                    caption: _channels.first.caption),
                video: _video(darkFrame: true),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 56,
                    child: Row(children: [
                      IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.arrow_back_ios_new,
                              color: Colors.white)),
                      Expanded(
                        child: Text('พรีวิว',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.volume_up_outlined,
                              color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ));
      await _loadAssets(tester);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('visual-player-controls')), findsNothing);
      expect(find.byKey(const ValueKey('preview-tiktok-social-rail')),
          findsOneWidget);
      final pane =
          tester.getRect(find.byKey(const ValueKey('publish-post-preview')));
      expect(pane.size, sample.size);
      expect(tester.getRect(find.byKey(const ValueKey('visual-natural-video'))),
          pane);
      expect(find.text(_channels.first.caption), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-identity')),
          sample.generic ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
      if (_captureDirectory.isNotEmpty) {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final directory = Directory(_captureDirectory)
              ..createSync(recursive: true);
            await File(
                    '${directory.path}/post-preview-immersive-${sample.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    });
  }
}
