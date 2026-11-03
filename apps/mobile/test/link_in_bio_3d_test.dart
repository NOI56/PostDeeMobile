import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_theme_picker.dart';

const _links = [
  LinkInBioCustomLink(
      id: 'youtube', title: 'YouTube', url: 'https://youtube.com'),
  LinkInBioCustomLink(id: 'shop', title: 'Shopee', url: 'https://shopee.co.th'),
];
const _ids = [
  'dimensional-clay-mint',
  'dimensional-clay-peach',
  'dimensional-clay-cloud',
  'dimensional-clay-sand',
  'dimensional-paper-fold',
  'dimensional-paper-stage',
  'dimensional-paper-ribbon',
  'dimensional-glass-lavender',
  'dimensional-glass-mist',
  'dimensional-glass-sage',
  'dimensional-chrome-night',
  'dimensional-lowpoly-dawn',
  'dimensional-zen-garden',
  'dimensional-wood-blocks',
  'dimensional-parcel-stack',
  'dimensional-ceramic-tiles',
  'dimensional-pop-shapes',
  'dimensional-neon-sign',
  'dimensional-concrete-slab',
  'dimensional-terrazzo-steps',
];

Widget _page(Widget child,
        {ThemeMode mode = ThemeMode.light, String language = 'th'}) =>
    MaterialApp(
        locale: Locale(language),
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
            data: const MediaQueryData(disableAnimations: true), child: child!),
        home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('English picker labels 3D and translates its template names',
      (tester) async {
    await tester.pumpWidget(_page(
        BioThemePicker(
            appearance: LinkInBioAppearance.forTemplate(_ids.first),
            onChanged: (_) {}),
        language: 'en'));
    await tester.pumpAndSettle();
    expect(find.text('3D · 20 templates'), findsOneWidget);
    expect(find.text('Mint clay'), findsOneWidget);
    for (final name in const [
      'Night chrome',
      'Low-poly dawn',
      'Zen garden',
      'Wooden toy blocks',
      'Parcel stack',
      'Glazed tiles',
      'Pop shapes',
      'Neon night',
      'Raw concrete',
      'Terrazzo steps',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('โครมยามค่ำ'), findsNothing);
    expect(find.text('Minimal'), findsOneWidget);
    expect(find.text('ดินปั้นมิ้นต์'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '3D is a separate twenty-template category and browsing keeps the draft',
      (tester) async {
    LinkInBioAppearance? selected;
    final original = LinkInBioAppearance.forTemplate('minimal-white-editorial')
        .copyWith(description: 'ข้อความเดิมของร้าน');
    await tester.pumpWidget(_page(BioThemePicker(
        appearance: original,
        storeName: 'ร้านของฉัน',
        links: _links,
        onChanged: (value) => selected = value)));
    await tester.pumpAndSettle();
    expect(find.text('เรียบง่าย · 20 แบบ'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('link-in-bio-category-dimensional')));
    await tester.pumpAndSettle();
    expect(find.text('3D · 20 แบบ'), findsOneWidget);
    expect(find.byType(BioTemplateSample), findsNWidgets(20));
    expect(selected, isNull);
    expect(
        find.byKey(
            const ValueKey('link-in-bio-template-minimal-white-editorial')),
        findsNothing);
    await tester
        .tap(find.byKey(ValueKey('link-in-bio-template-${_ids.first}')));
    await tester.pumpAndSettle();
    expect(find.text('ร้านของฉัน'), findsOneWidget);
    expect(find.text('ข้อความเดิมของร้าน'), findsOneWidget);
    expect(selected, isNull);
    await tester
        .ensureVisible(find.byKey(const ValueKey('link-in-bio-template-use')));
    await tester.tap(find.byKey(const ValueKey('link-in-bio-template-use')));
    await tester.pumpAndSettle();
    expect(selected?.templateId, _ids.first);
    expect(selected?.description, original.description);
  });

  testWidgets('a saved 3D design opens its category without changing the draft',
      (tester) async {
    var changes = 0;
    await tester.pumpWidget(_page(BioThemePicker(
        appearance: LinkInBioAppearance.forTemplate(_ids.last),
        onChanged: (_) => changes++)));
    await tester.pumpAndSettle();
    expect(find.text('3D · 20 แบบ'), findsOneWidget);
    expect(find.byType(BioTemplateSample), findsNWidgets(20));
    expect(changes, 0);
    await tester
        .tap(find.byKey(const ValueKey('link-in-bio-category-minimal')));
    await tester.pumpAndSettle();
    expect(find.byType(BioTemplateSample), findsNWidgets(20));
    expect(changes, 0);
  });

  for (final id in _ids) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('$id has readable native content and depth in $mode',
          (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final appearance = LinkInBioAppearance.forTemplate(id);
        await tester.pumpWidget(_page(
            LinkInBioPreview(
                storeName: 'ร้านของเราที่มีชื่อภาษาไทยยาวและต้องอ่านได้ครบ',
                slug: 'shop',
                links: _links,
                appearance: appearance),
            mode: mode));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('link-in-bio-3d-hero-$id')), findsOneWidget);
        expect(find.byKey(ValueKey('link-in-bio-3d-art-$id')), findsOneWidget);
        final avatar = tester.widget<Container>(find.byKey(
            const ValueKey('link-in-bio-composition-avatar')));
        expect((avatar.decoration as BoxDecoration).color,
            bioColor(appearance.surfaceColor));
        final title = tester.widget<Text>(
            find.byKey(const ValueKey('link-in-bio-template-store-name')));
        expect(title.data, 'ร้านของเราที่มีชื่อภาษาไทยยาวและต้องอ่านได้ครบ');
        final button = tester.widget<Container>(
            find.byKey(const ValueKey('link-in-bio-template-link-shop')));
        expect((button.decoration as BoxDecoration).boxShadow, isNotEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('3D preserves custom colors, own logo and uploaded cover',
      (tester) async {
    final bytes = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='));
    const logo =
        'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-logo.png';
    const cover =
        'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-cover.png';
    final appearance = LinkInBioAppearance.forTemplate(_ids.last).copyWith(
        logoKey: logo,
        coverKey: cover,
        buttonColor: '#163923',
        buttonStyle: const LinkInBioTextStyle(color: '#ffffff'),
        buttonRadius: 'square');
    await tester.pumpWidget(_page(LinkInBioPreview(
        storeName: 'ร้านจริง',
        slug: 'shop',
        links: _links,
        appearance: appearance,
        images: {logo: bytes, cover: bytes})));
    await tester.pumpAndSettle();
    expect(
        find.byKey(ValueKey('link-in-bio-3d-art-${_ids.last}')), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-3d-custom-cover')),
        findsOneWidget);
    final button = tester.widget<Container>(
        find.byKey(const ValueKey('link-in-bio-template-link-shop')));
    final decoration = button.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xff163923));
    expect(decoration.gradient, isNull);
    expect(decoration.borderRadius, BorderRadius.circular(4));
    expect(tester.takeException(), isNull);
  });
}
