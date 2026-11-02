import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview_styles.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_template_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_theme_picker.dart';

// The cartoon release: ten original drawings on five cartoon page layouts.
const _designs = {
  'cartoon-doodle-shop': 'banner',
  'cartoon-comic-panels': 'panels',
  'cartoon-tag-buddy': 'beside',
  'cartoon-sticker-sheet': 'banner',
  'cartoon-chalkboard': 'banner',
  'cartoon-street-front': 'signboard',
  'cartoon-chat-bubbles': 'chat',
  'cartoon-signposts': 'beside',
  'cartoon-crayon-sky': 'banner',
  'cartoon-rocket-night': 'banner',
};
const _english = {
  'cartoon-doodle-shop': 'Doodle shop',
  'cartoon-comic-panels': 'Comic panels',
  'cartoon-tag-buddy': 'Little tag buddy',
  'cartoon-sticker-sheet': 'Sticker sheet',
  'cartoon-chalkboard': 'Chalkboard',
  'cartoon-street-front': 'Street shopfront',
  'cartoon-chat-bubbles': 'Chat bubbles',
  'cartoon-signposts': 'Signposts',
  'cartoon-crayon-sky': 'Crayon sky',
  'cartoon-rocket-night': 'Cartoon rocket',
};
const _longName = 'ร้านเสื้อผ้ามือสองคุณภาพดีราคาเป็นกันเองส่งทั่วประเทศไทย';

LinkInBioCustomLink _link(String id) => LinkInBioCustomLink(
    id: id, title: 'ช่องทาง $id', url: 'https://example.com/$id');

Future<void> _pump(WidgetTester tester, String id,
    {int links = 4,
    double width = 320,
    double textScale = 1,
    LinkInBioAppearance? appearance,
    Map<String, Uint8List> images = const {}}) async {
  tester.view.physicalSize = Size(width, 1600);
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

Widget _localized(Widget child, {String language = 'th'}) => MaterialApp(
    locale: Locale(language),
    supportedLocales: const [Locale('th'), Locale('en')],
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    builder: (_, child) => MediaQuery(
        data: const MediaQueryData(disableAnimations: true), child: child!),
    home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  test('the catalog carries exactly the ten approved cartoon designs', () {
    expect(
        profileTemplates
            .where((template) => template.category == 'cartoon')
            .map((template) => template.id),
        _designs.keys);
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
      expect(find.byKey(ValueKey('link-in-bio-cartoon-layout-${entry.value}')),
          findsOneWidget);
      expect(find.text(_longName), findsOneWidget);
      expect(find.text('ร้านจริงของเจ้าของ'), findsOneWidget);
      expect(find.text('ช่องทาง l3'), findsOneWidget);
      final art = tester.widget<Image>(
          find.byKey(ValueKey('link-in-bio-cartoon-art-${entry.key}')));
      expect((art.image as AssetImage).assetName,
          'assets/images/profile_decorations/${entry.key}.png');
      expect(
          art.fit,
          const {'beside', 'chat'}.contains(entry.value)
              ? BoxFit.contain
              : BoxFit.cover);
      final title = _rect(tester, 'link-in-bio-template-store-name');
      final hero = _rect(tester, 'link-in-bio-cartoon-art-${entry.key}');
      expect(hero.bottom, lessThanOrEqualTo(title.top + 1));
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

  testWidgets('beside layouts put the drawing next to the avatar',
      (tester) async {
    for (final id in ['cartoon-tag-buddy', 'cartoon-signposts']) {
      await _pump(tester, id);
      final avatar = _rect(tester, 'link-in-bio-composition-avatar');
      final art = _rect(tester, 'link-in-bio-cartoon-art-$id');
      expect(art.left, greaterThan(avatar.right), reason: id);
    }
  });

  testWidgets('the shopfront hangs the owner logo as its sign over the art',
      (tester) async {
    await _pump(tester, 'cartoon-street-front');
    final sign = _rect(tester, 'link-in-bio-cartoon-sign');
    final art = _rect(tester, 'link-in-bio-cartoon-art-cartoon-street-front');
    final avatar = _rect(tester, 'link-in-bio-composition-avatar');
    expect(sign.top, greaterThanOrEqualTo(art.top));
    expect(sign.bottom, lessThan(art.bottom));
    expect(sign.contains(avatar.center), isTrue);
    expect((sign.center.dx - art.center.dx).abs(), lessThan(1));
  });

  testWidgets('comic and chat captions sit on the readable wash color',
      (tester) async {
    for (final id in ['cartoon-comic-panels', 'cartoon-chat-bubbles']) {
      await _pump(tester, id);
      final template = getProfileTemplate(id)!;
      final caption = tester
          .widget<Container>(
              find.byKey(const ValueKey('link-in-bio-cartoon-caption')))
          .decoration as BoxDecoration;
      expect(caption.color, bioColor(template.palette.gradient), reason: id);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('link-in-bio-cartoon-caption')),
              matching: find.text(_longName)),
          findsOneWidget,
          reason: id);
    }
    // Small phones shrink the comic avatar so long names have room.
    await _pump(tester, 'cartoon-comic-panels', width: 320);
    expect(_rect(tester, 'link-in-bio-composition-avatar').width, 58);
    await _pump(tester, 'cartoon-comic-panels', width: 420);
    expect(_rect(tester, 'link-in-bio-composition-avatar').width, 82);
    await _pump(tester, 'cartoon-chat-bubbles');
    final caption = _rect(tester, 'link-in-bio-cartoon-caption');
    final avatar = _rect(tester, 'link-in-bio-composition-avatar');
    expect(caption.left, greaterThan(avatar.right));
  });

  testWidgets('chat links alternate sides as speech bubbles with tails',
      (tester) async {
    await _pump(tester, 'cartoon-chat-bubbles', width: 360);
    final first = _rect(tester, 'link-in-bio-template-link-l0');
    final second = _rect(tester, 'link-in-bio-template-link-l1');
    expect(second.right, greaterThan(first.right + 20));
    expect(first.left, lessThan(second.left - 20));
    expect(first.width, closeTo(second.width, 1));
    for (final id in ['l0', 'l1']) {
      expect(
          find.byKey(ValueKey('link-in-bio-cartoon-tail-$id')), findsOneWidget);
    }
    final tail = _rect(tester, 'link-in-bio-cartoon-tail-l1');
    expect(tail.center.dx, greaterThan(second.center.dx));
  });

  testWidgets('signpost links are cut into arrows', (tester) async {
    await _pump(tester, 'cartoon-signposts');
    expect(find.byKey(const ValueKey('link-in-bio-cartoon-arrow-l0')),
        findsOneWidget);
    final appearance = LinkInBioAppearance.forTemplate('cartoon-signposts');
    expect(
        _linkDecoration(tester, 'l0').color, bioColor(appearance.buttonColor));
  });

  testWidgets('chalk links are open dashed outlines', (tester) async {
    await _pump(tester, 'cartoon-chalkboard');
    expect(find.byKey(const ValueKey('link-in-bio-cartoon-dashed-l0')),
        findsOneWidget);
    expect(_linkDecoration(tester, 'l0').color, Colors.transparent);
  });

  testWidgets('stickers tilt alternately and crayon outlines rotate colors',
      (tester) async {
    await _pump(tester, 'cartoon-sticker-sheet');
    double angle(String id) {
      final matrix = tester
          .widget<Transform>(
              find.byKey(ValueKey('link-in-bio-cartoon-tilt-$id')))
          .transform;
      return math.atan2(matrix.entry(1, 0), matrix.entry(0, 0));
    }

    expect(angle('l0'), closeTo(-math.pi / 180, .001));
    expect(angle('l1'), closeTo(math.pi / 180, .001));
    await _pump(tester, 'cartoon-crayon-sky');
    final colors = [
      for (final id in ['l0', 'l1', 'l2', 'l3'])
        (_linkDecoration(tester, id).border as Border).top.color
    ];
    expect(colors.toSet(), hasLength(4));
  });

  testWidgets('comic, sticker and chat fills cycle only with default colors',
      (tester) async {
    for (final id in [
      'cartoon-comic-panels',
      'cartoon-sticker-sheet',
      'cartoon-chat-bubbles'
    ]) {
      await _pump(tester, id);
      final fills = [
        for (final link in ['l0', 'l1', 'l2', 'l3'])
          _linkDecoration(tester, link).color
      ];
      expect(fills.toSet().length, greaterThan(1), reason: id);
      expect(fills.first, bioColor(getProfileTemplate(id)!.palette.button),
          reason: id);
      final custom = LinkInBioAppearance.forTemplate(id).copyWith(
          buttonColor: '#204060',
          buttonStyle: const LinkInBioTextStyle(color: '#ffffff'));
      await _pump(tester, id, appearance: custom);
      expect({
        for (final link in ['l0', 'l1', 'l2', 'l3'])
          _linkDecoration(tester, link).color
      }, {
        const Color(0xff204060)
      }, reason: id);
    }
  });

  testWidgets('an uploaded cover replaces the drawing and owner colors win',
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
      expect(find.byKey(ValueKey('link-in-bio-cartoon-art-$id')), findsNothing,
          reason: id);
      expect(find.byKey(const ValueKey('link-in-bio-cartoon-custom-cover')),
          findsOneWidget,
          reason: id);
      final decoration = _linkDecoration(tester, 'l0');
      final open = getProfileTemplate(id)!.layout.button == 'outline';
      expect(open ? Colors.transparent : decoration.color,
          open ? decoration.color : const Color(0xff163923),
          reason: id);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the picker offers cartoon as its own ten-design category',
      (tester) async {
    LinkInBioAppearance? selected;
    final original = LinkInBioAppearance.forTemplate('minimal-white-editorial')
        .copyWith(description: 'ข้อความเดิมของร้าน');
    await tester.pumpWidget(_localized(BioThemePicker(
        appearance: original,
        storeName: 'ร้านของฉัน',
        links: const [
          LinkInBioCustomLink(
              id: 'shop', title: 'Shopee', url: 'https://shopee.co.th')
        ],
        onChanged: (value) => selected = value)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('link-in-bio-category-cartoon')));
    await tester.pumpAndSettle();
    expect(find.text('การ์ตูน · 10 แบบ'), findsOneWidget);
    expect(find.byType(BioTemplateSample), findsNWidgets(10));
    // Thumbnails never invent a store name.
    expect(find.text('noikub'), findsNothing);
    expect(selected, isNull);
    await tester.tap(
        find.byKey(const ValueKey('link-in-bio-template-cartoon-doodle-shop')));
    await tester.pumpAndSettle();
    expect(find.text('ร้านของฉัน'), findsOneWidget);
    expect(find.text('ข้อความเดิมของร้าน'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('link-in-bio-template-use')));
    await tester.tap(find.byKey(const ValueKey('link-in-bio-template-use')));
    await tester.pumpAndSettle();
    expect(selected?.templateId, 'cartoon-doodle-shop');
    expect(selected?.description, 'ข้อความเดิมของร้าน');
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('English picker names the cartoon designs ($mode)',
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
                      appearance: LinkInBioAppearance.forTemplate(
                          'cartoon-rocket-night'),
                      onChanged: (_) {})))));
      await tester.pumpAndSettle();
      expect(find.text('Cartoon · 10 templates'), findsOneWidget);
      expect(find.text('Cartoon'), findsOneWidget);
      for (final name in _english.values) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      for (final id in _designs.keys) {
        expect(find.text(getProfileTemplate(id)!.name), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
