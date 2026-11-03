import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_localizations.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_theme_picker.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  for (final language in ['th', 'en']) {
    for (final dark in [false, true]) {
      testWidgets(
          'premium gallery offers 20 choices with preview and apply ($language dark=$dark)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        const original = LinkInBioAppearance(
            description: 'ข้อมูลร้านของฉัน',
            featuredLinkId: 'shop',
            featuredLabel: 'โปรของร้าน');
        final results = <LinkInBioAppearance>[];
        await tester.pumpWidget(MaterialApp(
            locale: Locale(language),
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: const TextScaler.linear(2)),
                child: child!),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: BioThemePicker(
                        hasPremiumThemeAccess: true,
                        appearance: original,
                        storeName: 'ร้านของฉัน',
                        links: const [
                          LinkInBioCustomLink(
                              id: 'shop',
                              title: 'สินค้าของร้าน',
                              url: 'https://example.com/shop'),
                        ],
                        onChanged: results.add)))));
        await tester.pumpAndSettle();
        await _tap(tester, 'link-in-bio-category-premium');
        expect(
            find.text(language == 'th'
                ? 'หรูหรา / พรีเมียม · 20 แบบ'
                : 'Luxury / Premium · 20 templates'),
            findsOneWidget);
        final templates = profileTemplates
            .where((item) => item.category == 'premium')
            .toList();
        expect(templates, hasLength(20));
        expect(find.byType(BioTemplateSample), findsNWidgets(20));
        for (final template in templates) {
          final tile = _key('link-in-bio-template-${template.id}');
          expect(tile, findsOneWidget);
          final context = tester.element(tile);
          final label = localizeLinkInBioMessage(context, template.name);
          expect(find.descendant(of: tile, matching: find.text(label)),
              findsOneWidget);
          if (language == 'en') expect(label, isNot(template.name));
        }
        expect(results, isEmpty);
        await _tap(tester, 'link-in-bio-template-${templates.first.id}');
        expect(find.text('ร้านของฉัน'), findsOneWidget);
        expect(find.text(original.description), findsOneWidget);
        expect(results, isEmpty);
        await _tap(tester, 'link-in-bio-template-preview-close');
        expect(results, isEmpty);
        await _tap(tester, 'link-in-bio-template-${templates.last.id}');
        await _tap(tester, 'link-in-bio-template-use');
        expect(results, hasLength(1));
        expect(results.single.templateId, templates.last.id);
        expect(results.single.description, original.description);
        expect(results.single.featuredLinkId, original.featuredLinkId);
        expect(results.single.featuredLabel, original.featuredLabel);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('premium category stays previewable without membership',
      (tester) async {
    final results = <LinkInBioAppearance>[];
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioThemePicker(
                    appearance: const LinkInBioAppearance(),
                    onChanged: results.add)))));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-category-premium');
    final chip = tester.widget<ChoiceChip>(_key('link-in-bio-category-premium'));
    expect((chip.avatar as Icon).icon, Icons.lock_outline);
    expect(find.byType(BioTemplateSample), findsNWidgets(20));
    await _tap(tester, 'link-in-bio-template-premium-gold-leaf');
    expect(_key('link-in-bio-template-membership-required'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(_key('link-in-bio-template-use')).onPressed,
        isNull);
    await _tap(tester, 'link-in-bio-template-preview-close');
    expect(results, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a saved classic luxury design reopens on Simple; only the new set is listed',
      (tester) async {
    final results = <LinkInBioAppearance>[];
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioThemePicker(
                    hasPremiumThemeAccess: true,
                    appearance:
                        LinkInBioAppearance.forTemplate('luxury-gold-seal'),
                    onChanged: results.add)))));
    await tester.pumpAndSettle();
    expect(find.text('เรียบง่าย · 20 แบบ'), findsOneWidget);
    expect(_key('link-in-bio-category-luxury'), findsNothing);
    await _tap(tester, 'link-in-bio-category-premium');
    expect(_key('link-in-bio-template-luxury-gold-seal'), findsNothing);
    expect(_key('link-in-bio-template-premium-gold-leaf'), findsOneWidget);
    expect(results, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
