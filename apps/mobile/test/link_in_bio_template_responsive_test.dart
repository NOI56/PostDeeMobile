import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';

const _links = [
  LinkInBioCustomLink(
      id: 'shop',
      title: 'เลือกซื้อสินค้าของร้าน',
      url: 'https://example.com/shop'),
  LinkInBioCustomLink(
      id: 'contact',
      title: 'สอบถามรายละเอียดสินค้า',
      url: 'https://example.com/contact'),
];

Future<void> _show(WidgetTester tester, LinkInBioAppearance appearance,
    {double scale = 1, String name = 'ร้านมินา'}) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: child!,
    ),
    home: Scaffold(
        body: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LinkInBioPreview(
          storeName: name,
          slug: 'mina-shop',
          links: _links,
          appearance: appearance),
    )),
  ));
  await tester.pumpAndSettle();
}

int _lineCount(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  return paragraph
      .getBoxesForSelection(TextSelection(
        baseOffset: 0,
        extentOffset: paragraph.text.toPlainText().length,
      ))
      .map((box) => box.top)
      .toSet()
      .length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Anuphan', 'Prompt']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle
            .load('assets/fonts/${family.toLowerCase()}/$family-$weight.ttf'));
      }
      await loader.load();
    }
  });
  setUp(() {
    AppTheme.applyThemeMode(ThemeMode.light);
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  for (final scale in [1.5, 2.0]) {
    for (final font in ['anuphan', 'prompt']) {
      for (final composition in ['editorial', 'ticket', 'rail', 'notebook']) {
        testWidgets(
            '$composition keeps 01 and 02 on one line at text$scale $font',
            (tester) async {
          final template = profileTemplates.firstWhere((item) =>
              item.category == 'minimal' &&
              item.layout.composition == composition);
          final appearance = LinkInBioAppearance.forTemplate(template.id);
          await _show(
              tester,
              appearance.copyWith(
                  buttonStyle: appearance.buttonStyle.copyWith(font: font)),
              scale: scale);
          for (final (index, link) in _links.indexed) {
            final number =
                find.byKey(ValueKey('link-in-bio-link-number-${link.id}'));
            expect(tester.widget<Text>(number).data,
                '${index + 1}'.padLeft(2, '0'));
            expect(_lineCount(tester, number), 1);
            final label = find.text(link.title);
            expect(label, findsOneWidget);
            expect(MediaQuery.textScalerOf(tester.element(label)).scale(16),
                16 * scale);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final font in ['anuphan', 'prompt']) {
    testWidgets('ร้านมินา fits one heading line at 320px text1.5 with $font',
        (tester) async {
      final appearance =
          LinkInBioAppearance.forTemplate('minimal-white-editorial');
      await _show(
          tester,
          appearance.copyWith(
              nameStyle: appearance.nameStyle.copyWith(font: font)),
          scale: 1.5);
      final name =
          find.byKey(const ValueKey('link-in-bio-template-store-name'));
      expect(_lineCount(tester, name), 1);
      final text = tester.widget<Text>(name);
      expect(text.data, 'ร้านมินา');
      expect(
          MediaQuery.textScalerOf(tester.element(name))
              .scale(text.style!.fontSize!),
          greaterThan(48));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'long names and links remain complete at text2 without truncation',
      (tester) async {
    const longName = 'ร้านมินาสินค้าดีสำหรับทุกคนและครอบครัว';
    await _show(
        tester, LinkInBioAppearance.forTemplate('minimal-white-editorial'),
        scale: 2, name: longName);
    final name = find.byKey(const ValueKey('link-in-bio-template-store-name'));
    expect(tester.widget<Text>(name).data, longName);
    expect(tester.widget<Text>(name).maxLines, isNull);
    expect(
        tester.renderObject<RenderParagraph>(name).didExceedMaxLines, isFalse);
    for (final link in _links) {
      expect(tester.widget<Text>(find.text(link.title)).maxLines, isNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsive long headings still grow with increased text size',
      (tester) async {
    for (final scale in [1.1, 1.3, 1.5, 2.0]) {
      await _show(
          tester, LinkInBioAppearance.forTemplate('minimal-white-editorial'),
          scale: scale, name: 'ร้านมินาสินค้าดีสำหรับทุกคนและครอบครัว');
      final name =
          find.byKey(const ValueKey('link-in-bio-template-store-name'));
      final text = tester.widget<Text>(name);
      expect(
          MediaQuery.textScalerOf(tester.element(name))
              .scale(text.style!.fontSize!),
          greaterThan(48),
          reason: 'Text scale $scale must still enlarge the heading');
    }
  });

  testWidgets('normal minimal typography and legacy content keep their sizes',
      (tester) async {
    for (final template
        in profileTemplates.where((item) => item.category == 'minimal')) {
      await _show(tester, LinkInBioAppearance.forTemplate(template.id));
      final label = find.text(_links.first.title);
      expect(tester.widget<Text>(label).style!.fontSize, 16);
      if (template.layout.composition == 'editorial') {
        expect(
            tester
                .widget<Text>(find
                    .byKey(const ValueKey('link-in-bio-template-store-name')))
                .style!
                .fontSize,
            48);
      }
      expect(tester.takeException(), isNull);
    }
    await _show(tester, LinkInBioAppearance.forTheme('minimal'), scale: 1.5);
    expect(find.text('ร้านมินา'), findsOneWidget);
    for (final link in _links) {
      expect(find.text(link.title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
