import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_template_preview.dart';

LinkInBioCustomLink _link(String id, {String category = '', String? title}) =>
    LinkInBioCustomLink(
        id: id,
        title: title ?? id,
        url: 'https://example.com/$id',
        category: category);

Future<void> _template(WidgetTester tester, String composition,
    {String storeName = 'ร้าน', List<LinkInBioCustomLink> links = const []}) {
  final template =
      profileTemplates.firstWhere((t) => t.layout.composition == composition);
  return tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: BioTemplatePreview(
                  template: template,
                  storeName: storeName,
                  links: links,
                  appearance: LinkInBioAppearance.forTemplate(template.id),
                  images: const {},
                  staticPreview: true)))));
}

Size _linkSize(WidgetTester tester, String id) =>
    tester.getSize(find.byKey(ValueKey('link-in-bio-template-link-$id')));

void main() {
  group('avatar initial without an uploaded logo', () {
    for (final (name, expected) in [
      ('ร้านผ้าไหมบ้านนา', 'ผ'),
      ('ร้าน ป้าแดง', 'ป'),
      ('เจ๊ปูขายดี', 'จ'),
      ('ร้านไหมทอง', 'ห'),
      ('ร้าน', 'ร'),
      ('  @postdee shop', 'p'),
      ('บ้านนา', 'บ'),
      ('😀', '😀'),
      ('', 'ร'),
    ]) {
      test('uses a meaningful letter for "$name"', () {
        expect(bioAvatarInitial(name), expected);
      });
    }

    testWidgets('decorated themes show the letter after "ร้าน"',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: LinkInBioPreview(
                      storeName: 'ร้านผ้าไหมบ้านนา',
                      slug: 'shop',
                      links: const [],
                      appearance: LinkInBioAppearance.forTheme('pink'),
                      images: const {})))));
      expect(find.text('ผ'), findsOneWidget);
      expect(find.text('ร'), findsNothing);
    });

    testWidgets('templates skip a leading Thai vowel', (tester) async {
      await _template(tester, 'seal', storeName: 'เจ๊ปูขายดี');
      expect(find.text('จ'), findsOneWidget);
      expect(find.text('เ'), findsNothing);
    });
  });

  group('phone numbers stay on one line', () {
    test('joins the separators inside phone numbers only', () {
      expect(bioKeepNumbersTogether('โทร 081-234-5678 ด่วน'),
          'โทร 081-\u2060234-\u20605678 ด่วน');
      expect(bioKeepNumbersTogether('WhatsApp +66 81 234 5678'),
          'WhatsApp +66\u00a081\u00a0234\u00a05678');
      expect(bioKeepNumbersTogether('ลด 20% เหลือ 199 บาท'),
          'ลด 20% เหลือ 199 บาท');
    });

    testWidgets('template link titles keep the number together',
        (tester) async {
      await _template(tester, 'bicolor',
          links: [_link('tel', title: 'โทร 081-234-5678')]);
      expect(find.text('โทร 081-\u2060234-\u20605678'), findsOneWidget);
    });
  });

  testWidgets('the framed bicolor store name is not letter-spaced',
      (tester) async {
    await _template(tester, 'bicolor', storeName: 'ร้านผ้าไหม');
    final name = tester.widget<Text>(
        find.byKey(const ValueKey('link-in-bio-template-store-name')));
    expect(name.style?.letterSpacing, isNull);
  });

  group('grid layouts without a half-empty last row', () {
    for (final composition in ['bicolor', 'gallery', 'window-grid']) {
      testWidgets(
          '$composition fills the row with the last tile of an odd group',
          (tester) async {
        await _template(tester, composition, links: [
          for (final id in ['a', 'b', 'c']) _link(id, category: 'ซื้อ'),
          for (final id in ['d', 'e']) _link(id, category: 'ติดต่อ'),
        ]);
        await tester.pumpAndSettle();
        expect(_linkSize(tester, 'b').width, _linkSize(tester, 'a').width);
        expect(_linkSize(tester, 'c').width,
            greaterThan(_linkSize(tester, 'a').width * 1.5));
        expect(_linkSize(tester, 'e').width, _linkSize(tester, 'd').width);
        expect(tester.takeException(), isNull);
      });
    }

    for (final composition in ['collage', 'glass']) {
      testWidgets('$composition fills the row when a tile would be alone',
          (tester) async {
        await _template(tester, composition, links: [
          for (final id in ['a', 'b']) _link(id, category: 'หนึ่ง'),
          for (final id in ['c', 'd', 'e']) _link(id, category: 'สอง'),
        ]);
        await tester.pumpAndSettle();
        expect(_linkSize(tester, 'b').width, _linkSize(tester, 'a').width);
        expect(_linkSize(tester, 'd').width,
            lessThan(_linkSize(tester, 'c').width));
        expect(_linkSize(tester, 'e').width, _linkSize(tester, 'd').width);
        expect(tester.takeException(), isNull);
      });
    }
  });

  for (final template in profileTemplates
      .where((template) => template.category == 'dimensional')) {
    testWidgets('${template.id} keeps its artwork and readable native text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: BioTemplatePreview(
                      template: template,
                      storeName: 'ร้านเจ๊ปู',
                      links: [_link('tel', title: 'โทร 081-234-5678')],
                      appearance: LinkInBioAppearance.forTemplate(template.id)
                          .copyWith(description: 'สายด่วน 02 123 4567 ทุกวัน'),
                      images: const {},
                      staticPreview: true)))));
      await tester.pumpAndSettle();
      expect(find.text('จ'), findsOneWidget);
      expect(find.text('โทร 081-\u2060234-\u20605678'), findsOneWidget);
      expect(find.text('สายด่วน 02\u00a0123\u00a04567 ทุกวัน'), findsOneWidget);
      expect(find.byKey(ValueKey('link-in-bio-3d-hero-${template.id}')),
          findsOneWidget);
      expect(find.byKey(ValueKey('link-in-bio-3d-art-${template.id}')),
          findsOneWidget);
      final button = tester.widget<Container>(
          find.byKey(const ValueKey('link-in-bio-template-link-tel')));
      expect((button.decoration as BoxDecoration).boxShadow, isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
