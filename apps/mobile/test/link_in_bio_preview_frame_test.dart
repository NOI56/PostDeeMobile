import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';

const _pageKey = ValueKey('preview-frame-page');

Widget _host(Widget body) => MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!),
    home: Scaffold(body: body));

LinkInBioPreview _preview(LinkInBioAppearance appearance,
        {bool fullPage = false}) =>
    fullPage
        ? LinkInBioPreview(
            key: _pageKey,
            storeName: 'ร้านทดสอบ',
            slug: 'test-shop',
            links: const [],
            appearance: appearance,
            cornerRadius: 0)
        : LinkInBioPreview(
            key: _pageKey,
            storeName: 'ร้านทดสอบ',
            slug: 'test-shop',
            links: const [],
            appearance: appearance);

ClipRRect _outerClip(WidgetTester tester) => tester.widget<ClipRRect>(
    find.descendant(of: find.byKey(_pageKey), matching: find.byType(ClipRRect)).first);

void main() {
  final appearances = {
    'legacy': const LinkInBioAppearance(),
    'template': LinkInBioAppearance.forTemplate('minimal-white-editorial'),
    'decorated': LinkInBioAppearance.forTheme('pink'),
  };

  for (final entry in appearances.entries) {
    testWidgets('${entry.key} keeps the default rounded frame and only removes outer corners for full page',
        (tester) async {
      await tester.pumpWidget(_host(SingleChildScrollView(
          child: _preview(entry.value))));
      await tester.pumpAndSettle();
      final normalSize = tester.getSize(find.byKey(_pageKey));
      final normalNameStyle = tester.widget<Text>(find.text('ร้านทดสอบ')).style;
      expect(_outerClip(tester).borderRadius, BorderRadius.circular(20));

      await tester.pumpWidget(_host(SingleChildScrollView(
          child: _preview(entry.value, fullPage: true))));
      await tester.pumpAndSettle();
      expect(_outerClip(tester).borderRadius, BorderRadius.zero);
      expect(tester.getSize(find.byKey(_pageKey)), normalSize);
      expect(tester.widget<Text>(find.text('ร้านทดสอบ')).style, normalNameStyle);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} short page fills incoming viewport minimum height',
        (tester) async {
      tester.view.physicalSize = const Size(393, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(SingleChildScrollView(
          child: _preview(entry.value, fullPage: true))));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)).height, lessThan(1200));

      await tester.pumpWidget(_host(LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
              child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: _preview(entry.value, fullPage: true))))));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)), const Size(393, 1200));
      expect(_outerClip(tester).borderRadius, BorderRadius.zero);
      expect(find.text('ร้านทดสอบ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
