import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_appearance_editor.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_platform_logo.dart';

const _links = [
  LinkInBioCustomLink(
      id: 'shop',
      title: 'ซื้อสินค้าจากร้านของเราและโปรโมชั่นวันนี้',
      url: 'https://shopee.co.th/shop',
      category: 'เลือกซื้อสินค้า',
      buttonColor: '#305d36',
      textColor: '#ffffff',
      font: 'prompt'),
  LinkInBioCustomLink(
      id: 'chat', title: 'ติดต่อร้าน', url: 'https://line.me/shop'),
  LinkInBioCustomLink(
      id: 'mail',
      title: 'ส่งอีเมล',
      url: 'mailto:shop@example.com',
      category: 'ติดต่อ'),
];

void main() {
  testWidgets('raised tiles match the public border shadow and arrow position',
      (tester) async {
    final template = profileTemplates
        .firstWhere((item) => item.layout.composition == 'window-grid');
    final appearance = LinkInBioAppearance.forTemplate(template.id);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: LinkInBioPreview(
                        storeName: 'ร้าน',
                        slug: 'shop',
                        links: _links,
                        appearance: appearance))))));
    final finder = find.byKey(const ValueKey('link-in-bio-template-link-shop'));
    final decoration =
        tester.widget<Container>(finder).decoration as BoxDecoration;
    expect((decoration.border as Border?)?.top.width, 2);
    expect((decoration.border as Border?)?.top.color,
        bioColor(appearance.nameStyle.color));
    expect(decoration.boxShadow!.single.offset, const Offset(4, 4));
    expect(decoration.boxShadow!.single.color.a, 1);
    final logo = tester.getRect(
        find.descendant(of: finder, matching: find.byType(BioPlatformLogo)));
    final arrow = tester.getRect(
        find.descendant(of: finder, matching: find.byIcon(Icons.north_east)));
    expect(arrow.top, greaterThan(logo.bottom));
  });
  for (final width in [320.0, 800.0]) {
    testWidgets('template typography matches public sizes at $width px',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: LinkInBioPreview(
                      storeName: 'ร้าน',
                      slug: 'shop',
                      links: _links,
                      appearance: LinkInBioAppearance.forTemplate(
                              profileTemplates.first.id)
                          .copyWith(effects: const LinkInBioEffects()))))));
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('link-in-bio-template-store-name')))
              .style
              ?.fontSize,
          width <= 320 ? 48 : 56);
      expect(tester.widget<Text>(find.text(_links.first.title)).style?.fontSize,
          16);
    });
  }

  for (final header in ['centered', 'left', 'split', 'cover', 'badge']) {
    for (final withCover in [false, true]) {
      testWidgets(
          '$header bounded preview keeps store text readable cover=$withCover',
          (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final template =
            profileTemplates.firstWhere((item) => item.layout.header == header);
        final appearance = LinkInBioAppearance.forTemplate(template.id).copyWith(
            coverKey: withCover
                ? 'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-cover.png'
                : null);
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Scaffold(
                    body: BioPreviewViewport(
                        height: 120,
                        appearance: appearance,
                        child: LinkInBioPreview(
                            storeName: 'ร้านของคุณ',
                            slug: 'shop',
                            links: _links,
                            appearance: appearance))))));
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byType(BioPreviewViewport));
        final title = tester.getRect(
            find.byKey(const ValueKey('link-in-bio-template-store-name')));
        expect(title.top, greaterThanOrEqualTo(viewport.top));
        // Large editorial headings can be taller than this small scrollable
        // canvas. Reveal their first complete line rather than shrinking the
        // real page's typography to fit the editor.
        final text = tester.widget<Text>(
            find.byKey(const ValueKey('link-in-bio-template-store-name')));
        final firstLine =
            (text.style?.fontSize ?? 16) * (text.style?.height ?? 1);
        expect(
            title.top + (title.height < firstLine ? title.height : firstLine),
            lessThanOrEqualTo(viewport.bottom));
        expect(find.byType(Scrollbar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('grid pill keeps the owner selected full radius', (tester) async {
    final template =
        profileTemplates.firstWhere((item) => item.layout.links == 'grid');
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(
                disableAnimations: true, textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: LinkInBioPreview(
                        storeName: 'ร้าน',
                        slug: 'shop',
                        links: _links,
                        appearance: LinkInBioAppearance.forTemplate(template.id)
                            .copyWith(buttonRadius: 'pill')))))));
    final link = tester.widget<Container>(
        find.byKey(const ValueKey('link-in-bio-template-link-shop')));
    expect((link.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(999));
  });
  testWidgets('outline per-link fill and border use its custom button color',
      (tester) async {
    final template =
        profileTemplates.firstWhere((item) => item.layout.button == 'outline');
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: LinkInBioPreview(
                        storeName: 'ร้าน',
                        slug: 'shop',
                        links: _links,
                        appearance:
                            LinkInBioAppearance.forTemplate(template.id)))))));
    final link = tester.widget<Container>(
        find.byKey(const ValueKey('link-in-bio-template-link-shop')));
    final decoration = link.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xff305d36));
    expect((decoration.border as Border).top.color, const Color(0xff305d36));
  });

  test('applying any template retains owned media and existing promotion', () {
    const logo =
        'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-logo.png';
    const cover =
        'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-cover.png';
    const background =
        'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-background.png';
    const original = LinkInBioAppearance(
        description: 'ข้อมูลร้านเดิม',
        logoKey: logo,
        coverKey: cover,
        background: LinkInBioBackground(mode: 'image', imageKey: background),
        featuredLinkId: 'shop',
        featuredLabel: 'โปรของร้าน');
    for (final template in profileTemplates) {
      final selected = bioApplyTemplate(original, template.id);
      expect(selected.templateId, template.id);
      expect(selected.description, original.description);
      expect(selected.logoKey, logo);
      expect(selected.coverKey, cover);
      expect(selected.background.imageKey, background);
      expect(selected.featuredLinkId, 'shop');
      expect(selected.featuredLabel, 'โปรของร้าน');
      expect(bioApplyTheme(selected, 'minimal').templateId, isNull);
    }
  });

  testWidgets('browsing one category shows only its 20 templates',
      (tester) async {
    LinkInBioAppearance? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioThemePicker(
                    appearance: const LinkInBioAppearance(),
                    storeName: 'ร้านเดิม',
                    links: _links,
                    onChanged: (value) => selected = value)))));
    await tester.pumpAndSettle();
    for (final category in profileTemplateCategories.keys) {
      final chip = find.byKey(ValueKey('link-in-bio-category-$category'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-in-bio-template-grid')),
          findsOneWidget);
      for (final template in profileTemplates) {
        expect(find.byKey(ValueKey('link-in-bio-template-${template.id}')),
            template.category == category ? findsOneWidget : findsNothing);
      }
      final last =
          profileTemplates.where((item) => item.category == category).last;
      await tester.ensureVisible(
          find.byKey(ValueKey('link-in-bio-template-${last.id}')));
      expect(tester.takeException(), isNull);
      expect(selected, isNull);
    }
  });

  testWidgets('template preview needs confirmation and cancelling keeps draft',
      (tester) async {
    LinkInBioAppearance? selected;
    const original = LinkInBioAppearance(
        description: 'ข้อความของร้าน', featuredLinkId: 'shop');
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true), child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioThemePicker(
                    appearance: original,
                    storeName: 'ร้านเดิม',
                    links: _links,
                    onChanged: (value) => selected = value)))));
    final template = profileTemplates.first;
    final tile = find.byKey(ValueKey('link-in-bio-template-${template.id}'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-in-bio-template-preview')),
        findsOneWidget);
    expect(find.text('ร้านเดิม'), findsOneWidget);
    expect(find.text('ข้อความของร้าน'), findsOneWidget);
    expect(selected, isNull);
    await tester
        .tap(find.byKey(const ValueKey('link-in-bio-template-preview-close')));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link-in-bio-template-use')));
    await tester.pumpAndSettle();
    expect(selected?.templateId, template.id);
    expect(selected?.description, original.description);
    expect(selected?.featuredLinkId, original.featuredLinkId);
  });

  for (final template in profileTemplates) {
    testWidgets('${template.id} preserves content at 320px with large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(
                  disableAnimations: true, textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: LinkInBioPreview(
                          storeName: 'ชื่อร้านภาษาไทยที่ยาวสำหรับทดสอบ',
                          slug: 'test-shop',
                          links: _links,
                          appearance: LinkInBioAppearance.forTemplate(
                                  template.id)
                              .copyWith(
                                  description:
                                      'ข้อมูลร้านเดิมและช่องทางติดต่อ')))))));
      await tester.pumpAndSettle();
      expect(find.text('ชื่อร้านภาษาไทยที่ยาวสำหรับทดสอบ'), findsOneWidget);
      for (final link in _links) {
        expect(find.text(link.title), findsOneWidget);
      }
      expect(find.text('เลือกซื้อสินค้า'), findsOneWidget);
      expect(find.text('ติดต่อ'), findsOneWidget);
      expect(find.text('หยุดการเคลื่อนไหว'), findsNothing);
      expect(
          find.byKey(ValueKey(
              'link-in-bio-template-layout-${template.layout.header}-${template.layout.links}')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
