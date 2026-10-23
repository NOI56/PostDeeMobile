import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/platforms/social_platform_logo.dart';
import 'package:postdee_mobile/features/uploader/platform_caption_fields.dart';

void main() {
  testWidgets(
      'AI targets start empty and allow selecting and removing a target',
      (tester) async {
    var selected = <SocialPlatform>{};
    await tester.pumpWidget(_selector(
      selected: selected,
      onChanged: (value) => selected = value,
    ));

    expect(find.text('เลือกช่องทางให้ AI เขียน'), findsNothing);
    expect(find.text('เลือกอย่างน้อย 1 ช่องทาง'), findsNothing);
    expect(find.text('เลือกแล้ว 0 ช่องทาง · ใช้ 1 เครดิต AI ต่อครั้ง'),
        findsNothing);
    for (final platform in captionPlatforms) {
      expect(_chip(tester, platform).selected, isFalse);
    }
    expect(tester.getSemantics(_target(SocialPlatform.tiktok)),
        isSemantics(isSelected: false));

    await tester.tap(_target(SocialPlatform.tiktok));
    await tester.pump();
    expect(selected, {SocialPlatform.tiktok});
    expect(_chip(tester, SocialPlatform.tiktok).selected, isTrue);
    expect(tester.getSemantics(_target(SocialPlatform.tiktok)),
        isSemantics(isSelected: true));

    await tester.tap(_target(SocialPlatform.tiktok));
    await tester.pump();
    expect(selected, isEmpty);
    expect(_chip(tester, SocialPlatform.tiktok).selected, isFalse);
    expect(tester.getSemantics(_target(SocialPlatform.tiktok)),
        isSemantics(isSelected: false));
  });

  testWidgets('AI targets update independently without mutating the input set',
      (tester) async {
    const initial = {SocialPlatform.youtubeShorts};
    var selected = initial;
    await tester.pumpWidget(_selector(
      selected: selected,
      onChanged: (value) => selected = value,
    ));

    await tester.tap(_target(SocialPlatform.tiktok));
    await tester.pump();
    expect(selected, {SocialPlatform.tiktok, SocialPlatform.youtubeShorts});
    expect(initial, {SocialPlatform.youtubeShorts});
    await tester.tap(_target(SocialPlatform.youtubeShorts));
    await tester.pump();
    expect(selected, {SocialPlatform.tiktok});
    expect(initial, {SocialPlatform.youtubeShorts});
    expect(find.byKey(const ValueKey('ai-caption-select-all')), findsNothing);
    expect(
        find.byKey(const ValueKey('ai-caption-clear-selection')), findsNothing);
  });

  testWidgets('AI target controls do not change while disabled',
      (tester) async {
    var changes = 0;
    await tester.pumpWidget(_selector(
      selected: {SocialPlatform.tiktok},
      enabled: false,
      onChanged: (_) => changes++,
    ));

    for (final platform in captionPlatforms) {
      expect(_chip(tester, platform).onSelected, isNull);
      await tester.tap(_target(platform));
    }
    expect(changes, 0);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'compact AI targets use an equal two-column grid in '
        '${dark ? 'dark' : 'light'} mode', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_selector(
        selected: {SocialPlatform.tiktok, SocialPlatform.facebookReels},
        textScale: 1.7,
        dark: dark,
        onChanged: (_) {},
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final boxes = [
        for (final platform in captionPlatforms)
          tester.getRect(_target(platform)),
      ];
      for (final box in boxes) {
        expect(box.width, closeTo(boxes.first.width, .1));
        expect(box.height, greaterThanOrEqualTo(48));
        expect(box.left, greaterThanOrEqualTo(16));
        expect(box.right, lessThanOrEqualTo(304));
      }
      expect(boxes[0].top, boxes[1].top);
      expect(boxes[2].top, boxes[3].top);
      expect(boxes[0].left, boxes[2].left);
      expect(boxes[1].left, boxes[3].left);
      expect(boxes[1].left, greaterThan(boxes[0].right));
      expect(boxes[2].top, greaterThan(boxes[0].bottom));
      expect(find.text('TikTok'), findsOneWidget);
      expect(find.text('YouTube Shorts'), findsOneWidget);
      expect(find.text('Instagram Reels'), findsOneWidget);
      expect(find.text('Facebook Page Video'), findsOneWidget);
      expect(find.text('Facebook Reels'), findsNothing);
      for (final platform in captionPlatforms) {
        final chip = _chip(tester, platform);
        expect(chip.avatar, isA<SocialPlatformLogo>());
        final label = find.descendant(
          of: _target(platform),
          matching: find.byType(Text),
        );
        final textBox = tester.getRect(label);
        final chipBox = tester.getRect(_target(platform));
        expect(textBox.top, greaterThanOrEqualTo(chipBox.top));
        expect(textBox.bottom, lessThanOrEqualTo(chipBox.bottom));
      }
      for (final platform in captionPlatforms) {
        final chip = _chip(tester, platform);
        expect(chip.showCheckmark, isFalse);
        expect(chip.selectedColor, chip.backgroundColor);
      }
      final selectedSide = _chip(tester, SocialPlatform.tiktok).side!;
      final unselectedSide = _chip(tester, SocialPlatform.youtubeShorts).side!;
      expect(selectedSide.width, greaterThan(unselectedSide.width));
      expect(selectedSide.color, isNot(unselectedSide.color));
    });
  }

  for (final platforms in [
    [SocialPlatform.tiktok],
    [SocialPlatform.facebookReels, SocialPlatform.youtubeShorts],
    [
      SocialPlatform.instagramReels,
      SocialPlatform.tiktok,
      SocialPlatform.facebookReels,
    ],
    captionPlatforms,
  ]) {
    testWidgets('preview renders only ${platforms.length} requested captions',
        (tester) async {
      await tester.pumpWidget(_preview({
        for (final platform in platforms)
          platform: 'ข้อความ ${platform.apiValue}'
      }));

      final count = platforms.length;
      expect(
          find.text(count == 4
              ? 'แคปชั่นจาก AI ทั้ง 4 ช่องทาง'
              : 'แคปชั่นจาก AI $count ช่องทาง'),
          findsOneWidget);
      expect(find.text(count == 4 ? 'ใช้ทั้ง 4 แคปชั่น' : 'ใช้ $count แคปชั่น'),
          findsOneWidget);
      for (final platform in captionPlatforms) {
        expect(find.text('ข้อความ ${platform.apiValue}'),
            platforms.contains(platform) ? findsOneWidget : findsNothing);
      }
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where((text) => text.startsWith('ข้อความ '))
          .toList();
      expect(texts, [
        for (final platform in captionPlatforms.where(platforms.contains))
          'ข้อความ ${platform.apiValue}'
      ]);
    });
  }

  testWidgets('fallback preview explains the selected count and quota refund',
      (tester) async {
    await tester.pumpWidget(_preview(
      {SocialPlatform.tiktok: 'ตรวจข้อความ'},
      fallback: true,
      charged: false,
    ));
    expect(find.text('ตรวจข้อความสำรอง 1 ช่องทาง'), findsOneWidget);
    expect(find.textContaining('1 ช่องทาง'), findsNWidgets(2));
    expect(find.textContaining('ไม่หักโควตา AI'), findsOneWidget);
  });

  testWidgets('charged fallback does not promise a quota refund',
      (tester) async {
    await tester.pumpWidget(_preview(
      {
        SocialPlatform.tiktok: 'ตรวจข้อความ TikTok',
        SocialPlatform.youtubeShorts: 'ตรวจข้อความ YouTube',
      },
      fallback: true,
    ));
    expect(find.text('ตรวจข้อความสำรอง 2 ช่องทาง'), findsOneWidget);
    expect(find.textContaining('ไม่หักโควตา AI'), findsNothing);
  });

  testWidgets('empty preview cannot apply an empty caption set',
      (tester) async {
    await tester.pumpWidget(_preview({}));
    final apply = tester.widget<FilledButton>(
        find.byKey(const ValueKey('uploader-platform-ai-apply')));
    expect(apply.onPressed, isNull);
  });

  testWidgets('selector and preview fit a narrow screen with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_selector(
      selected: {SocialPlatform.tiktok},
      textScale: 1.7,
      onChanged: (_) {},
    ));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(_target(SocialPlatform.facebookReels));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_preview(
      {SocialPlatform.youtubeShorts: 'รายละเอียดคลิปที่ลูกค้าตรวจและแก้ไขได้'},
      textScale: 1.7,
    ));
    await tester.pumpAndSettle();
    expect(find.text('ใช้ 1 แคปชั่น'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _target(SocialPlatform platform) =>
    find.byKey(ValueKey('ai-caption-target-${platform.apiValue}'));

FilterChip _chip(WidgetTester tester, SocialPlatform platform) =>
    tester.widget<FilterChip>(_target(platform));

Widget _selector({
  required Set<SocialPlatform> selected,
  required ValueChanged<Set<SocialPlatform>> onChanged,
  bool enabled = true,
  double textScale = 1,
  bool dark = false,
}) =>
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(builder: (context, setState) {
              return PlatformCaptionAiTargets(
                selectedPlatforms: selected,
                enabled: enabled,
                onChanged: (value) {
                  setState(() => selected = value);
                  onChanged(value);
                },
              );
            }),
          ),
        ),
      ),
    );

Widget _preview(
  Map<SocialPlatform, String> captions, {
  bool fallback = false,
  bool charged = true,
  double textScale = 1,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(textScale)),
            child: PlatformCaptionPreviewSheet(
              captions: captions,
              isFallback: fallback,
              charged: charged,
            ),
          );
        }),
      ),
    );
