import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview_styles.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_template_preview.dart';

// The second 3D release: ten scenes on five new page layouts.
const _scenes = {
  'dimensional-chrome-night': 'showcase',
  'dimensional-lowpoly-dawn': 'showcase',
  'dimensional-zen-garden': 'showcase',
  'dimensional-wood-blocks': 'split-art',
  'dimensional-parcel-stack': 'split-art',
  'dimensional-ceramic-tiles': 'tile-grid',
  'dimensional-pop-shapes': 'tile-grid',
  'dimensional-neon-sign': 'neon',
  'dimensional-concrete-slab': 'slab',
  'dimensional-terrazzo-steps': 'slab',
};
const _longName = 'ร้านเสื้อผ้ามือสองคุณภาพดีราคาเป็นกันเองส่งทั่วประเทศไทย';

LinkInBioCustomLink _link(String id) => LinkInBioCustomLink(
    id: id, title: 'ช่องทาง $id', url: 'https://example.com/$id');

Future<void> _pump(WidgetTester tester, String id,
    {int links = 2,
    double width = 320,
    double textScale = 1,
    LinkInBioAppearance? appearance,
    Map<String, Uint8List> images = const {}}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: Scaffold(
          body: SingleChildScrollView(
              child: BioTemplatePreview(
                  template: getProfileTemplate(id)!,
                  storeName: _longName,
                  links: [for (var i = 0; i < links; i++) _link('l$i')],
                  appearance: appearance ??
                      LinkInBioAppearance.forTemplate(id)
                          .copyWith(description: 'ร้านจริงของเจ้าของ'),
                  images: images,
                  staticPreview: true)))));
  await tester.pumpAndSettle();
}

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey(key)));

void main() {
  test('every new scene uses the layout the public page renders', () {
    for (final entry in _scenes.entries) {
      expect(getProfileTemplate(entry.key)?.layout.composition, entry.value,
          reason: entry.key);
    }
  });

  for (final entry in _scenes.entries) {
    testWidgets(
        '${entry.key} keeps the owner content in its ${entry.value} layout',
        (tester) async {
      await _pump(tester, entry.key);
      expect(find.byKey(ValueKey('link-in-bio-3d-scene-${entry.value}')),
          findsOneWidget);
      expect(find.text(_longName), findsOneWidget);
      expect(find.text('ร้านจริงของเจ้าของ'), findsOneWidget);
      final art = tester.widget<Image>(
          find.byKey(ValueKey('link-in-bio-3d-art-${entry.key}')));
      expect(
          art.fit,
          const {'showcase', 'neon'}.contains(entry.value)
              ? BoxFit.cover
              : BoxFit.contain);
      final title = _rect(tester, 'link-in-bio-template-store-name');
      final hero = _rect(tester, 'link-in-bio-3d-art-${entry.key}');
      if (entry.value == 'slab') {
        expect(hero.top, greaterThan(title.bottom));
      } else {
        expect(hero.bottom, lessThanOrEqualTo(title.top));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} fits a small phone with large Thai text',
        (tester) async {
      await _pump(tester, entry.key, width: 320, textScale: 1.6, links: 3);
      final title = _rect(tester, 'link-in-bio-template-store-name');
      expect(title.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('split-art places the art beside the avatar', (tester) async {
    await _pump(tester, 'dimensional-wood-blocks');
    final avatar = _rect(tester, 'link-in-bio-composition-avatar');
    final art = _rect(tester, 'link-in-bio-3d-art-dimensional-wood-blocks');
    expect(art.left, greaterThan(avatar.right));
  });

  testWidgets('tile-grid pairs links and a lone last tile takes the row',
      (tester) async {
    await _pump(tester, 'dimensional-ceramic-tiles', links: 3);
    final first = _rect(tester, 'link-in-bio-template-link-l0');
    final second = _rect(tester, 'link-in-bio-template-link-l1');
    final third = _rect(tester, 'link-in-bio-template-link-l2');
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    expect(third.width, greaterThan(first.width * 1.8));
  });

  testWidgets('outline scenes stay open while their text is readable',
      (tester) async {
    for (final id in ['dimensional-zen-garden', 'dimensional-neon-sign']) {
      await _pump(tester, id);
      final appearance = LinkInBioAppearance.forTemplate(id);
      final decoration = tester
          .widget<Container>(
              find.byKey(const ValueKey('link-in-bio-template-link-l0')))
          .decoration as BoxDecoration;
      // Open links show the solid panel, as on the public page.
      expect(decoration.color, bioColor(appearance.surfaceColor), reason: id);
      expect((decoration.border as Border).top.color,
          bioColor(appearance.buttonColor),
          reason: id);
      expect(decoration.boxShadow, isNotEmpty, reason: id);
    }
  });

  testWidgets('an uploaded cover replaces scene art and owner colors win',
      (tester) async {
    final bytes = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='));
    const cover =
        'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-cover.png';
    for (final id in _scenes.keys) {
      final appearance = LinkInBioAppearance.forTemplate(id).copyWith(
          coverKey: cover,
          buttonColor: '#163923',
          buttonStyle: const LinkInBioTextStyle(color: '#ffffff'));
      await _pump(tester, id, appearance: appearance, images: {cover: bytes});
      expect(find.byKey(ValueKey('link-in-bio-3d-art-$id')), findsNothing);
      expect(find.byKey(const ValueKey('link-in-bio-3d-custom-cover')),
          findsOneWidget);
      final decoration = tester
          .widget<Container>(
              find.byKey(const ValueKey('link-in-bio-template-link-l0')))
          .decoration as BoxDecoration;
      // Outline scenes keep an open fill while white text stays readable on
      // their dark panel, and draw the owner's color as the border instead.
      final open = getProfileTemplate(id)!.layout.button == 'outline' &&
          decoration.color == bioColor(appearance.surfaceColor);
      expect(open ? (decoration.border as Border).top.color : decoration.color,
          const Color(0xff163923),
          reason: id);
      expect(tester.takeException(), isNull);
    }
  });
}
