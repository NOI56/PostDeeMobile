import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_composition_art.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_platform_logo.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_template_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_theme_picker.dart';

const _compositions = {
  'editorial',
  'bicolor',
  'portrait',
  'scallop',
  'collage',
  'window',
  'botanical',
  'glass',
  'torn',
  'seal',
  'tag',
  'gallery',
  'poster',
  'window-grid',
  'ticket',
  'rail',
  'ribbon',
  'notebook',
  'arch',
  'staircase',
};

final _links = List.generate(
    20,
    (index) => LinkInBioCustomLink(
        id: 'link-$index',
        title: 'ช่องทางร้านหมายเลข ${index + 1} สำหรับชื่อภาษาไทยที่ยาว',
        url: index.isEven
            ? 'https://youtube.com/@shop'
            : 'https://shopee.co.th/shop',
        category: index == 4
            ? 'สินค้าที่แนะนำ'
            : index == 12
                ? 'ติดต่อเรา'
                : '',
        buttonColor: index == 2 ? '#305d36' : null,
        textColor: index == 2 ? '#ffffff' : null,
        font: index == 2 ? 'prompt' : null));

final _wideLogo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAACCAYAAABllJ3tAAAAF0lEQVR4nGO4Y6P7HxnLud1BwQyEFAAAmookGcN/A0AAAAAASUVORK5CYII=');
final _tallLogo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAAICAYAAADTLS5CAAAAFElEQVR4nGO4Y6P7X87tzn8GyhgABfckGXD401AAAAAASUVORK5CYII=');

void main() {
  testWidgets(
      'category resumes after an uncategorized link with a new heading and rhythm',
      (tester) async {
    final template = getProfileTemplate('cute-sticker-layers')!;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioTemplatePreview(
                    template: template,
                    storeName: 'ร้าน',
                    links: const [
                      LinkInBioCustomLink(
                          id: 'first',
                          title: 'หนึ่ง',
                          url: 'https://example.com/1',
                          category: 'สินค้า'),
                      LinkInBioCustomLink(
                          id: 'empty',
                          title: 'สอง',
                          url: 'https://example.com/2'),
                      LinkInBioCustomLink(
                          id: 'again',
                          title: 'สาม',
                          url: 'https://example.com/3',
                          category: 'สินค้า'),
                    ],
                    appearance: LinkInBioAppearance.forTemplate(template.id),
                    images: const {},
                    staticPreview: true)))));
    await tester.pumpAndSettle();
    expect(find.text('สินค้า'), findsNWidgets(2));
    final first = tester
        .getSize(find.byKey(const ValueKey('link-in-bio-template-link-first')));
    final empty = tester
        .getSize(find.byKey(const ValueKey('link-in-bio-template-link-empty')));
    final again = tester
        .getSize(find.byKey(const ValueKey('link-in-bio-template-link-again')));
    expect(empty.width, lessThan(first.width));
    expect(again.width, first.width);
  });

  testWidgets(
      'outline on an opaque white panel stays transparent above a black page',
      (tester) async {
    final template = getProfileTemplate('minimal-mono-pair')!;
    final appearance = LinkInBioAppearance.forTemplate(template.id).copyWith(
        surfaceColor: '#ffffff',
        background: const LinkInBioBackground(color: '#000000'),
        buttonStyle: const LinkInBioTextStyle(color: '#000000'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioTemplatePreview(
                    template: template,
                    storeName: 'ร้าน',
                    links: _links.take(1).toList(),
                    appearance: appearance,
                    images: const {},
                    staticPreview: true)))));
    await tester.pumpAndSettle();
    final button = tester.widget<Container>(
        find.byKey(const ValueKey('link-in-bio-template-link-link-0')));
    expect((button.decoration as BoxDecoration).color, Colors.transparent);
  });

  for (final composition in ['collage', 'torn', 'tag', 'notebook']) {
    testWidgets('$composition paper preserves the owner panel color',
        (tester) async {
      final template = profileTemplates
          .firstWhere((template) => template.layout.composition == composition);
      final appearance = LinkInBioAppearance.forTemplate(template.id);
      Future<void> render(LinkInBioAppearance value) =>
          tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: BioTemplatePreview(
                          template: template,
                          storeName: 'ร้าน',
                          links: const [],
                          appearance: value,
                          images: const {},
                          staticPreview: true)))));
      final paper = find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/images/profile_decorations/paper.png');
      final panel = find.byKey(ValueKey(
          'link-in-bio-template-layout-${template.layout.header}-${template.layout.links}'));
      final panelPaper = find.descendant(of: panel, matching: paper);
      await render(appearance);
      expect(panelPaper, findsOneWidget);
      expect(paper, findsNWidgets(2));
      await render(appearance.copyWith(surfaceColor: '#153960'));
      expect(panelPaper, findsNothing);
      expect(paper, findsOneWidget);
      expect(
          (tester.widget<Container>(panel).decoration as BoxDecoration).color,
          bioColor('#153960'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('custom gradient and inactive owner image suppress stock forest',
      (tester) async {
    final template = getProfileTemplate('nature-greenhouse')!;
    final appearance = LinkInBioAppearance.forTemplate(template.id);
    Future<void> render(LinkInBioAppearance value) => tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: BioTemplatePreview(
                        template: template,
                        storeName: 'ร้าน',
                        links: const [],
                        appearance: value,
                        images: const {},
                        staticPreview: true)))));
    final forest = find.byWidgetPredicate((widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName ==
            'assets/images/profile_decorations/forest.png');
    await render(appearance);
    expect(forest, findsOneWidget);
    await render(appearance.copyWith(
        background: appearance.background.copyWith(mode: 'gradient')));
    expect(forest, findsNothing);
    await render(appearance.copyWith(
        background:
            appearance.background.copyWith(imageKey: 'owner-background')));
    expect(forest, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('inactive owner image suppresses stock window gingham',
      (tester) async {
    final template = getProfileTemplate('cute-candy-box')!;
    final appearance = LinkInBioAppearance.forTemplate(template.id);
    Future<void> render(LinkInBioAppearance value) => tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: BioTemplatePreview(
                        template: template,
                        storeName: 'ร้าน',
                        links: const [],
                        appearance: value,
                        images: const {},
                        staticPreview: true)))));
    final gingham = find.byWidgetPredicate((widget) =>
        widget is CustomPaint &&
        widget.painter is BioCompositionPattern &&
        (widget.painter as BioCompositionPattern).kind == 'window');
    await render(appearance);
    expect(gingham, findsOneWidget);
    await render(appearance.copyWith(
        background:
            appearance.background.copyWith(imageKey: 'owner-background')));
    expect(gingham, findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final id in [
    'minimal-mono-pair',
    'minimal-clean-cover',
    'luxury-gold-seal',
    'luxury-silver-signature'
  ]) {
    testWidgets('$id preserves its composition avatar and owner image',
        (tester) async {
      final template = getProfileTemplate(id)!;
      final appearance = LinkInBioAppearance.forTemplate(id);
      Future<void> render({bool owned = false}) =>
          tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: BioTemplatePreview(
                          template: template,
                          storeName: 'noikub',
                          links: const [],
                          appearance: owned
                              ? appearance.copyWith(logoKey: 'owner')
                              : appearance,
                          images: owned
                              ? {
                                  'owner': Uint8List.fromList([1, 2, 3])
                                }
                              : const {},
                          staticPreview: true)))));
      await render();
      final avatar =
          find.byKey(const ValueKey('link-in-bio-composition-avatar'));
      final box = tester.widget<Container>(avatar).decoration as BoxDecoration;
      if (template.layout.composition == 'bicolor' ||
          template.layout.composition == 'seal') {
        expect(
            box.borderRadius,
            BorderRadius.circular(
                template.layout.composition == 'bicolor' ? 88 : 52));
      }
      if (template.layout.composition == 'bicolor') {
        expect(box.border, isNotNull);
        expect(find.byKey(const ValueKey('link-in-bio-avatar-double-outline')),
            findsOneWidget);
      }
      if (template.layout.composition == 'seal' ||
          template.layout.composition == 'tag') {
        expect(box.color, Colors.transparent);
        expect(box.border, isNull);
        expect(tester.widget<Text>(find.text('n')).style?.color,
            bioColor(appearance.nameStyle.color));
      }
      if (template.layout.composition == 'portrait') {
        expect(box.color, bioColor(appearance.buttonColor));
        expect(tester.widget<Text>(find.text('n')).style?.color,
            bioColor(appearance.buttonStyle.color));
      }
      await render(owned: true);
      final image = find.descendant(of: avatar, matching: find.byType(Image));
      expect(image, findsOneWidget);
      expect(tester.widget<Image>(image).image, isA<MemoryImage>());
      expect(tester.takeException(), isNull);
    });
  }
  for (final wide in [true, false]) {
    testWidgets(
        '${wide ? 'wide' : 'tall'} owner logo stays centered and uncropped in all 100 templates',
        (tester) async {
      tester.view.physicalSize = const Size(393, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = wide ? _wideLogo : _tallLogo;
      final sourceSize = wide ? const Size(8, 2) : const Size(2, 8);
      for (final template in profileTemplates) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: BioTemplatePreview(
                        template: template,
                        storeName: 'ร้าน',
                        links: const [],
                        appearance: LinkInBioAppearance.forTemplate(template.id)
                            .copyWith(logoKey: 'owner-logo'),
                        images: {'owner-logo': bytes},
                        staticPreview: true)))));
        await tester.pumpAndSettle();
        final avatar =
            find.byKey(const ValueKey('link-in-bio-composition-avatar'));
        final imageFinder =
            find.descendant(of: avatar, matching: find.byType(Image));
        expect(imageFinder, findsOneWidget, reason: template.id);
        final image = tester.widget<Image>(imageFinder);
        expect(identical((image.image as MemoryImage).bytes, bytes), isTrue,
            reason: template.id);
        expect(image.alignment, Alignment.center, reason: template.id);
        final fitted =
            applyBoxFit(image.fit!, sourceSize, tester.getSize(imageFinder));
        expect(fitted.source, sourceSize, reason: template.id);
        expect(fitted.destination.aspectRatio,
            closeTo(sourceSize.aspectRatio, .000001),
            reason: template.id);
        if (template.layout.composition == 'gallery') {
          expect(tester.getSize(avatar), const Size(48, 104),
              reason: template.id);
        } else if (template.layout.composition == 'portrait') {
          expect(tester.getSize(avatar), const Size(78, 130),
              reason: template.id);
        }
        expect(tester.takeException(), isNull, reason: template.id);
      }
    });
  }
  testWidgets('owner cover and background photos still fill their frames',
      (tester) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final coverBytes = _tallLogo;
    final backgroundBytes = Uint8List.fromList(_tallLogo);
    Finder photo(Uint8List bytes) => find.byWidgetPredicate((widget) =>
        widget is Image &&
        widget.image is MemoryImage &&
        identical((widget.image as MemoryImage).bytes, bytes));
    for (final composition in _compositions) {
      final template = profileTemplates
          .firstWhere((template) => template.layout.composition == composition);
      final appearance = LinkInBioAppearance.forTemplate(template.id);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: BioTemplatePreview(
                      template: template,
                      storeName: 'ร้าน',
                      links: const [],
                      appearance: appearance.copyWith(
                          logoKey: 'owner-logo',
                          coverKey: 'owner-cover',
                          background: appearance.background.copyWith(
                              mode: 'image', imageKey: 'owner-background')),
                      images: {
                        'owner-logo': _wideLogo,
                        'owner-cover': coverBytes,
                        'owner-background': backgroundBytes
                      },
                      staticPreview: true)))));
      await tester.pumpAndSettle();
      for (final bytes in [coverBytes, backgroundBytes]) {
        final imageFinder = photo(bytes);
        expect(imageFinder, findsOneWidget, reason: composition);
        final image = tester.widget<Image>(imageFinder);
        expect(image.fit, BoxFit.cover, reason: composition);
        final fitted = applyBoxFit(
            image.fit!, const Size(2, 8), tester.getSize(imageFinder));
        expect(fitted.source.height, lessThan(8), reason: composition);
      }
      expect(tester.takeException(), isNull, reason: composition);
    }
  });
  testWidgets(
      'collage paper cards have their own border and hard shadow while preserving owner radius',
      (tester) async {
    final template = getProfileTemplate('cute-sticker-layers')!;
    final appearance = LinkInBioAppearance.forTemplate(template.id);
    final link =
        LinkInBioCustomLink(id: 'paper', title: 'ร้าน', url: 'https://line.me');
    Future<void> render(LinkInBioAppearance value) => tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: BioTemplatePreview(
                        template: template,
                        storeName: 'noikub',
                        links: [link],
                        appearance: value,
                        images: const {},
                        staticPreview: true)))));
    await render(appearance);
    BoxDecoration card() => tester
        .widget<Container>(
            find.byKey(const ValueKey('link-in-bio-template-link-paper')))
        .decoration as BoxDecoration;
    expect(card().borderRadius, BorderRadius.circular(4));
    expect((card().border as Border).top.width, 1);
    expect(card().boxShadow!.single.blurRadius, 0);
    expect(card().boxShadow!.single.offset, const Offset(3, 4));
    await render(appearance.copyWith(buttonRadius: 'pill'));
    expect(card().borderRadius, BorderRadius.circular(999));
    expect(tester.takeException(), isNull);
  });
  for (final id in ['cute-candy-box', 'creative-play-blocks']) {
    testWidgets('$id uses its own four-color rhythm and keeps custom colors',
        (tester) async {
      final template = getProfileTemplate(id)!;
      final appearance = LinkInBioAppearance.forTemplate(id);
      final expected = id == 'cute-candy-box'
          ? [appearance.buttonColor, '#fff9e6', '#d2bfff', '#bcf0bd']
          : [
              appearance.buttonColor,
              appearance.background.color,
              appearance.surfaceColor,
              '#f8d4e1'
            ];
      final links = List.generate(
          4,
          (i) => LinkInBioCustomLink(
              id: 'sample-$i', title: 'ร้าน $i', url: 'https://line.me'));
      Future<void> render(LinkInBioAppearance value) =>
          tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: BioTemplatePreview(
                          template: template,
                          storeName: 'ร้าน',
                          links: links,
                          appearance: value,
                          images: const {},
                          staticPreview: true)))));
      await render(appearance);
      for (var i = 0; i < 4; i++) {
        final tile = tester.widget<Container>(
            find.byKey(ValueKey('link-in-bio-template-link-sample-$i')));
        expect((tile.decoration as BoxDecoration).color, bioColor(expected[i]));
      }
      await render(appearance.copyWith(
          buttonColor: '#305d36',
          buttonStyle: appearance.buttonStyle.copyWith(color: '#ffffff')));
      for (var i = 0; i < 4; i++) {
        final tile = tester.widget<Container>(
            find.byKey(ValueKey('link-in-bio-template-link-sample-$i')));
        expect((tile.decoration as BoxDecoration).color, bioColor('#305d36'));
      }
      expect(tester.takeException(), isNull);
    });
  }
  test('each category offers twenty genuinely different compositions', () {
    for (final category in profileTemplateCategories.keys) {
      expect(
          profileTemplates
              .where((t) => t.category == category)
              .map((t) => t.layout.composition)
              .toSet(),
          _compositions);
    }
  });

  testWidgets('picker thumbnails use the same static renderer as the real page',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BioTemplateSample(template: profileTemplates.first))));
    await tester.pumpAndSettle();
    final preview =
        tester.widget<BioTemplatePreview>(find.byType(BioTemplatePreview));
    expect(preview.staticPreview, isTrue);
    expect(preview.links.length, 4);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('หยุดการเคลื่อนไหว'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored light label on a new outline keeps its readable fill',
      (tester) async {
    final template = profileTemplates.first;
    final appearance = LinkInBioAppearance.forTemplate(template.id).copyWith(
      buttonColor: '#285934',
      buttonStyle: const LinkInBioTextStyle(color: '#ffffff'),
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioTemplatePreview(
                    template: template,
                    storeName: 'ร้านเดิม',
                    links: _links.take(1).toList(),
                    appearance: appearance,
                    images: const {},
                    staticPreview: true)))));
    await tester.pumpAndSettle();
    final container = tester.widget<Container>(
        find.byKey(const ValueKey('link-in-bio-template-link-link-0')));
    expect(
        (container.decoration as BoxDecoration).color, const Color(0xff285934));
    expect(tester.widget<Text>(find.text(_links.first.title)).style?.color,
        Colors.white);
    expect(tester.takeException(), isNull);
  });

  for (final composition in _compositions) {
    testWidgets(
        '$composition inline preview reveals the heading and retains user scrolling',
        (tester) async {
      final template = profileTemplates
          .firstWhere((t) => t.layout.composition == composition);
      final appearance = LinkInBioAppearance.forTemplate(template.id);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: BioPreviewViewport(
                  height: 120,
                  appearance: appearance,
                  child: BioTemplatePreview(
                      template: template,
                      storeName: 'noikub',
                      links: _links,
                      appearance: appearance,
                      images: const {},
                      staticPreview: true)))));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(BioPreviewViewport));
      final title = tester.getRect(
          find.byKey(const ValueKey('link-in-bio-template-store-name')));
      expect(title.top, greaterThanOrEqualTo(viewport.top));
      expect(title.top + 48, lessThanOrEqualTo(viewport.bottom));
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(position.maxScrollExtent / 2);
      final offset = position.pixels;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(position.pixels, offset);
      expect(tester.takeException(), isNull);
    });
    for (final width in [320.0, 393.0]) {
      testWidgets('$composition retains twenty ordered links at $width px',
          (tester) async {
        final template = profileTemplates
            .firstWhere((t) => t.layout.composition == composition);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final appearance =
            LinkInBioAppearance.forTemplate(template.id).copyWith(
          description: 'ข้อมูลร้านของเจ้าของที่ต้องเก็บไว้และอ่านได้ทั้งหมด',
          logoKey: 'bad-logo',
          coverKey: 'bad-cover',
          background: const LinkInBioBackground(
              mode: 'image', imageKey: 'bad-background', color: '#fafafa'),
          featuredLinkId: 'link-15',
          featuredLabel: 'โปรโมชั่นของร้าน',
        );
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: const MediaQueryData(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(1.3)),
                child: Scaffold(
                    body: SingleChildScrollView(
                        child: BioTemplatePreview(
                  template: template,
                  storeName: 'ชื่อร้านภาษาไทยที่ยาวและต้องแสดงได้ครบ',
                  links: _links,
                  appearance: appearance,
                  images: {
                    'bad-logo': Uint8List.fromList([1, 2]),
                    'bad-cover': Uint8List.fromList([1, 2]),
                    'bad-background': Uint8List.fromList([1, 2])
                  },
                ))))));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('link-in-bio-composition-$composition')),
            findsOneWidget);
        expect(find.text('ชื่อร้านภาษาไทยที่ยาวและต้องแสดงได้ครบ'),
            findsOneWidget);
        var previousY = double.negativeInfinity;
        for (final link in _links) {
          final finder =
              find.byKey(ValueKey('link-in-bio-template-link-${link.id}'));
          expect(finder, findsOneWidget);
          final rect = tester.getRect(finder);
          expect(rect.top, greaterThanOrEqualTo(previousY));
          previousY = rect.top;
          expect(find.text(link.title), findsOneWidget);
          final logo = find.descendant(
              of: finder, matching: find.byType(BioPlatformLogo));
          expect(tester.getSize(logo), const Size(40, 40));
          if (rect.width < width * .6) {
            final arrow = find.descendant(
                of: finder, matching: find.byIcon(Icons.north_east));
            expect(
                tester.getRect(arrow).top,
                greaterThanOrEqualTo(
                    tester.getRect(find.text(link.title)).bottom));
          }
        }
        expect(find.text('สินค้าที่แนะนำ'), findsOneWidget);
        expect(find.text('ติดต่อเรา'), findsOneWidget);
        expect(find.text('โปรโมชั่นของร้าน'), findsOneWidget);
        expect(find.text('หยุดการเคลื่อนไหว'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
