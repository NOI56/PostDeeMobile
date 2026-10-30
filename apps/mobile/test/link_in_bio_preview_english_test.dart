import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';

Widget _app(Widget child,
        {Locale locale = const Locale('en'),
        bool dark = false,
        double scale = 1,
        bool localized = true}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: localized
          ? const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ]
          : null,
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true, textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Widget _preview(LinkInBioAppearance appearance,
        {String name = '', List<LinkInBioCustomLink> links = const []}) =>
    LinkInBioPreview(
      storeName: name,
      slug: 'unchanged-store-slug',
      links: links,
      appearance: appearance,
    );

final _appearances = <String, LinkInBioAppearance>{
  'legacy': const LinkInBioAppearance(),
  'decorated': LinkInBioAppearance.forTheme('cards'),
  'template': LinkInBioAppearance.forTemplate('minimal-white-editorial'),
};

void main() {
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  for (final entry in _appearances.entries) {
    testWidgets('${entry.key} empty preview has English app-owned guidance',
        (tester) async {
      await tester.pumpWidget(_app(_preview(entry.value)));
      await tester.pumpAndSettle();
      expect(find.text('Your store'), findsOneWidget);
      expect(find.text('Choose a channel below'), findsOneWidget);
      expect(find.text('Add a link to see a preview'), findsOneWidget);
      if (entry.key != 'template') {
        expect(find.text('Create a store page with PostDee'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${entry.key} retains Thai preview fallback without localization',
        (tester) async {
      await tester.pumpWidget(_app(_preview(entry.value), localized: false));
      await tester.pumpAndSettle();
      expect(find.text('ร้านของคุณ'), findsOneWidget);
      expect(find.text('เลือกช่องทางที่ต้องการได้เลย'), findsOneWidget);
      expect(find.text('เพิ่มลิงก์เพื่อแสดงตัวอย่าง'), findsOneWidget);
      if (entry.key != 'template') {
        expect(find.text('สร้างหน้าเว็บร้านค้าด้วย PostDee'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${entry.key} locale changes preserve saved Thai customer content and values',
        (tester) async {
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      const rawLink = LinkInBioCustomLink(
          id: 'saved-link',
          title: 'เปิดลิงก์',
          url: 'https://example.com/unchanged?value=thai',
          category: 'เพิ่มลิงก์เพื่อแสดงตัวอย่าง',
          icon: 'link');
      final appearance = entry.value.copyWith(
          description: 'เลือกช่องทางที่ต้องการได้เลย',
          featuredLinkId: rawLink.id,
          featuredLabel: 'สร้างหน้าเว็บร้านค้าด้วย PostDee');
      final beforeAppearance = appearance.toJson();
      final beforeLink = rawLink.toJson();
      final page = _preview(appearance, name: 'ร้านของคุณ', links: [rawLink]);
      await tester.pumpWidget(ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (_, language, __) => _app(page, locale: language)));
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(LinkInBioPreview));
      for (final language in [
        const Locale('en'),
        const Locale('th'),
        const Locale('en')
      ]) {
        locale.value = language;
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(LinkInBioPreview)), same(element));
        expect(find.text('ร้านของคุณ'), findsOneWidget);
        expect(find.text('เลือกช่องทางที่ต้องการได้เลย'), findsOneWidget);
        expect(find.text('เพิ่มลิงก์เพื่อแสดงตัวอย่าง'), findsOneWidget);
        expect(
            find.text('เปิดลิงก์'),
            language.languageCode == 'th' && entry.key == 'decorated'
                ? findsNWidgets(2)
                : findsOneWidget);
        if (entry.key == 'decorated') {
          expect(find.text('Open link'),
              language.languageCode == 'en' ? findsOneWidget : findsNothing);
        }
        expect(
            find.text('สร้างหน้าเว็บร้านค้าด้วย PostDee'),
            language.languageCode == 'th' && entry.key != 'template'
                ? findsNWidgets(2)
                : findsOneWidget);
        expect(appearance.toJson(), beforeAppearance);
        expect(rawLink.toJson(), beforeLink);
        expect(tester.takeException(), isNull);
      }
    });

    for (final dark in [false, true]) {
      testWidgets('${entry.key} English guidance fits 320dp 2x (dark=$dark)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        await tester
            .pumpWidget(_app(_preview(entry.value), dark: dark, scale: 2));
        await tester.pumpAndSettle();
        for (final text in [
          'Your store',
          'Choose a channel below',
          'Add a link to see a preview',
          if (entry.key != 'template') 'Create a store page with PostDee'
        ]) {
          final finder = find.text(text);
          expect(finder, findsOneWidget);
          expect(tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
              isFalse);
          expect(tester.getRect(finder).width, lessThanOrEqualTo(320));
        }
        expect(tester.takeException(), isNull);
        const customerLabel = 'Browse our new collection';
        await tester.pumpWidget(_app(
            _preview(entry.value, name: 'ร้านของคุณ', links: const [
              LinkInBioCustomLink(
                  id: 'saved',
                  title: customerLabel,
                  url: 'https://example.com/saved')
            ]),
            dark: dark,
            scale: 2));
        await tester.pumpAndSettle();
        expect(find.text('ร้านของคุณ'), findsOneWidget);
        expect(find.text(customerLabel), findsOneWidget);
        expect(
            tester
                .renderObject<RenderParagraph>(find.text(customerLabel))
                .didExceedMaxLines,
            isFalse);
        if (entry.key == 'decorated') {
          expect(find.text('Open link'), findsOneWidget);
          expect(
              tester
                  .renderObject<RenderParagraph>(find.text('Open link'))
                  .didExceedMaxLines,
              isFalse);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'preview viewport accessibility follows locale without resetting scroll',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    try {
      const appearance = LinkInBioAppearance();
      final child = BioPreviewViewport(
          height: 320,
          appearance: appearance,
          child: _preview(appearance, links: [
            for (var i = 0; i < 8; i++)
              LinkInBioCustomLink(
                  id: '$i',
                  title: 'Saved link $i',
                  url: 'https://example.com/$i')
          ]));
      await tester.pumpWidget(ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (_, language, __) => _app(child, locale: language)));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Page preview. Scroll to see more.'),
          findsOneWidget);
      final state = tester.state(find.byType(BioPreviewViewport));
      final scrollable = tester.state<ScrollableState>(find
          .descendant(
              of: find.byType(BioPreviewViewport),
              matching: find.byType(Scrollable))
          .first);
      await tester.drag(find.byType(BioPreviewViewport), const Offset(0, -160));
      await tester.pumpAndSettle();
      final offset = scrollable.position.pixels;
      expect(offset, greaterThan(0));
      locale.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('ตัวอย่างหน้าเว็บ เลื่อนเพื่อดูส่วนอื่น'),
          findsOneWidget);
      expect(tester.state(find.byType(BioPreviewViewport)), same(state));
      expect(scrollable.position.pixels, offset);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
