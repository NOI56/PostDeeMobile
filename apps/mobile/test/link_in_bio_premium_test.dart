import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_premium_scenes.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_template_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_theme_picker.dart';

// The premium release: twenty original pictures on five page layouts.
const _designs = {
  'premium-gold-leaf': 'crest',
  'premium-white-marble': 'portal',
  'premium-thai-gold': 'crest',
  'premium-art-deco': 'cameo',
  'premium-emerald-facet': 'vitrine',
  'premium-pearl-strand': 'portal',
  'premium-velvet-wine': 'atelier',
  'premium-champagne': 'cameo',
  'premium-guilloche': 'cameo',
  'premium-rose-gold': 'vitrine',
  'premium-midnight-stars': 'cameo',
  'premium-black-onyx': 'atelier',
  'premium-silk-ribbon': 'portal',
  'premium-crystal': 'vitrine',
  'premium-damask': 'crest',
  'premium-golden-palms': 'atelier',
  'premium-spotlight': 'cameo',
  'premium-colonnade': 'portal',
  'premium-leather-stitch': 'atelier',
  'premium-sapphire-wave': 'vitrine',
};
const _english = {
  'premium-gold-leaf': 'Gold leaf',
  'premium-white-marble': 'White marble',
  'premium-thai-gold': 'Thai gold pattern',
  'premium-art-deco': 'Art Deco',
  'premium-emerald-facet': 'Cut emerald',
  'premium-pearl-strand': 'Pearl strands',
  'premium-velvet-wine': 'Wine velvet',
  'premium-champagne': 'Champagne bubbles',
  'premium-guilloche': 'Guilloche engraving',
  'premium-rose-gold': 'Rose gold',
  'premium-midnight-stars': 'Midnight stars',
  'premium-black-onyx': 'Gold-veined onyx',
  'premium-silk-ribbon': 'Silk ribbon',
  'premium-crystal': 'Crystal',
  'premium-damask': 'Damask',
  'premium-golden-palms': 'Golden palms',
  'premium-spotlight': 'Spotlight',
  'premium-colonnade': 'Colonnade',
  'premium-leather-stitch': 'Hand-stitched leather',
  'premium-sapphire-wave': 'Sapphire waves',
};
const _longName =
    'ร้านเครื่องประดับเงินแท้งานฝีมือช่างไทยส่งตรงจากเชียงใหม่ทั่วประเทศ';

LinkInBioCustomLink _link(String id) => LinkInBioCustomLink(
    id: id, title: 'ช่องทาง $id', url: 'https://example.com/$id');

Future<void> _pump(WidgetTester tester, String id,
    {int links = 4,
    double width = 390,
    double textScale = 1,
    LinkInBioAppearance? appearance,
    Map<String, Uint8List> images = const {}}) async {
  tester.view.physicalSize = Size(width, 1800);
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

BoxDecoration _linkDecoration(WidgetTester tester, String id) => tester
    .widget<Container>(find.byKey(ValueKey('link-in-bio-template-link-$id')))
    .decoration as BoxDecoration;

void main() {
  test('the catalog and the app carry the same twenty premium designs', () {
    expect(
        profileTemplates
            .where((template) => template.category == 'premium')
            .map((template) => template.id),
        _designs.keys);
    expect(bioPremiumDesigns.keys, _designs.keys);
    for (final entry in _designs.entries) {
      expect(getProfileTemplate(entry.key)?.layout.composition, entry.value,
          reason: entry.key);
    }
  });

  for (final entry in _designs.entries) {
    testWidgets(
        '${entry.key} keeps the owner content in its ${entry.value} layout',
        (tester) async {
      await _pump(tester, entry.key);
      expect(find.byKey(ValueKey('link-in-bio-premium-layout-${entry.value}')),
          findsOneWidget);
      expect(find.text(_longName), findsOneWidget);
      expect(find.text('ร้านจริงของเจ้าของ'), findsOneWidget);
      expect(find.text('ช่องทาง l3'), findsOneWidget);
      final art = tester.widget<Image>(
          find.byKey(ValueKey('link-in-bio-premium-art-${entry.key}')));
      expect((art.image as AssetImage).assetName,
          'assets/images/profile_decorations/${entry.key}.png');
      expect(art.fit, BoxFit.cover);
      final title = _rect(tester, 'link-in-bio-template-store-name');
      final hero = _rect(tester, 'link-in-bio-premium-art-${entry.key}');
      expect(hero.bottom, lessThanOrEqualTo(title.top + 1));
      // A diamond ornament under centred names, a short rule under left ones.
      final centered = const {'crest', 'cameo', 'portal'}.contains(entry.value);
      expect(find.byKey(const ValueKey('link-in-bio-premium-ornament')),
          centered ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('link-in-bio-premium-rule-short')),
          entry.value == 'atelier' ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('link-in-bio-premium-frame')),
          bioPremiumDesigns[entry.key]!.frame ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} fits a small phone with large Thai text',
        (tester) async {
      await _pump(tester, entry.key, width: 320, textScale: 1.6, links: 3);
      final title = _rect(tester, 'link-in-bio-template-store-name');
      expect(title.right, lessThanOrEqualTo(320));
      expect(_rect(tester, 'link-in-bio-template-link-l2').right,
          lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the avatar sits on the edge, in the middle, on the sill or '
      'beside the name', (tester) async {
    Rect avatar() => tester.getRect(
        find.byKey(const ValueKey('link-in-bio-composition-avatar')));
    await _pump(tester, 'premium-gold-leaf');
    var art = _rect(tester, 'link-in-bio-premium-art-premium-gold-leaf');
    expect(avatar().center.dy, closeTo(art.bottom, 1));
    expect(avatar().center.dx, closeTo(art.center.dx, 1));
    await _pump(tester, 'premium-art-deco');
    art = _rect(tester, 'link-in-bio-premium-art-premium-art-deco');
    expect(avatar().center.dy, closeTo(art.center.dy, 1));
    await _pump(tester, 'premium-velvet-wine');
    art = _rect(tester, 'link-in-bio-premium-art-premium-velvet-wine');
    expect(avatar().center.dy, closeTo(art.bottom, 1));
    expect(avatar().left, lessThan(art.center.dx));
    await _pump(tester, 'premium-pearl-strand');
    final arch = _rect(tester, 'link-in-bio-premium-arch');
    expect(avatar().center.dy, closeTo(arch.bottom, 1));
    expect(arch.width, lessThan(390 * .75));
    await _pump(tester, 'premium-crystal');
    final title = _rect(tester, 'link-in-bio-template-store-name');
    expect(avatar().right, lessThan(title.left));
    expect(avatar().top,
        greaterThan(_rect(tester, 'link-in-bio-premium-vitrine').bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('each link is finished in its design material', (tester) async {
    for (final id in _designs.keys) {
      await _pump(tester, id, links: 2);
      final material = bioPremiumDesigns[id]!.material;
      expect(find.byKey(const ValueKey('link-in-bio-premium-gilded-l0')),
          material == BioPremiumMaterial.gilded ? findsOneWidget : findsNothing,
          reason: id);
      expect(
          find.byKey(const ValueKey('link-in-bio-premium-stitch-l0')),
          material == BioPremiumMaterial.stitched
              ? findsOneWidget
              : findsNothing,
          reason: id);
      expect(find.byKey(const ValueKey('link-in-bio-premium-notch-l0')),
          material == BioPremiumMaterial.notched ? findsOneWidget : findsNothing,
          reason: id);
      expect(find.byKey(const ValueKey('link-in-bio-premium-rule')),
          material == BioPremiumMaterial.hairline ? findsOneWidget : findsNothing,
          reason: id);
      final decoration = _linkDecoration(tester, 'l0');
      if (material == BioPremiumMaterial.plate ||
          material == BioPremiumMaterial.notched) {
        expect(decoration.gradient, isA<LinearGradient>(), reason: id);
      }
      if (material == BioPremiumMaterial.hairline) {
        expect(decoration.color, Colors.transparent, reason: id);
        expect((decoration.border as Border).bottom.width, 1, reason: id);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an uploaded cover replaces the picture and owner colors win',
      (tester) async {
    final bytes = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='));
    const cover =
        'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-cover.png';
    for (final id in _designs.keys) {
      final appearance = LinkInBioAppearance.forTemplate(id).copyWith(
          coverKey: cover,
          buttonColor: '#163923',
          buttonStyle: const LinkInBioTextStyle(color: '#ffffff'));
      await _pump(tester, id, appearance: appearance, images: {cover: bytes});
      expect(find.byKey(ValueKey('link-in-bio-premium-art-$id')), findsNothing,
          reason: id);
      expect(find.byKey(const ValueKey('link-in-bio-premium-custom-cover')),
          findsOneWidget,
          reason: id);
      final decoration = _linkDecoration(tester, 'l0');
      // Open rows stay open only while the owner's text reads on the panel,
      // as on the public page.
      final surface = Color(int.parse(
              'ff${getProfileTemplate(id)!.palette.surface.substring(1)}',
              radix: 16))
          .computeLuminance();
      final open = getProfileTemplate(id)!.layout.button == 'outline' &&
          1.05 / (surface + .05) >= 4.5;
      final fill = decoration.gradient is LinearGradient
          ? (decoration.gradient! as LinearGradient).colors[1]
          : decoration.color;
      expect(fill, open ? Colors.transparent : const Color(0xff163923),
          reason: id);
      expect(tester.takeException(), isNull);
    }
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('English picker names the premium designs ($mode)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('th'), Locale('en')],
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          themeMode: mode,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          builder: (_, child) => MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: BioThemePicker(
                      hasPremiumThemeAccess: true,
                      appearance:
                          LinkInBioAppearance.forTemplate('premium-art-deco'),
                      onChanged: (_) {})))));
      await tester.pumpAndSettle();
      expect(find.text('Luxury / Premium · 20 templates'), findsOneWidget);
      for (final name in _english.values) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      for (final id in _designs.keys) {
        expect(find.text(getProfileTemplate(id)!.name), findsNothing);
      }
      // Thumbnails never invent a store name.
      expect(find.text('noikub'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
