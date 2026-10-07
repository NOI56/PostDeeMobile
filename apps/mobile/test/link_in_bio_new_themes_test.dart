import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_appearance_editor.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';

void main() {
  for (final theme in ['minimal', 'pink']) {
    testWidgets('$theme image background moves and freezes when paused',
        (tester) async {
      const key =
          'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-background.png';
      final appearance = LinkInBioAppearance.forTheme(theme).copyWith(
          background: const LinkInBioBackground(mode: 'image', imageKey: key),
          effects: const LinkInBioEffects(background: true));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: LinkInBioPreview(
                      storeName: 'ร้าน',
                      slug: 'sample',
                      links: const [],
                      appearance: appearance,
                      images: {
                        key: base64Decode(
                            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==')
                      })))));
      final picture =
          find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage);
      final transform =
          find.ancestor(of: picture, matching: find.byType(Transform)).first;
      List<double> matrix() =>
          tester.widget<Transform>(transform).transform.storage.toList();
      await tester.pump(const Duration(milliseconds: 600));
      final first = matrix();
      await tester.pump(const Duration(milliseconds: 600));
      expect(matrix(), isNot(first));
      final pause = find.byKey(const ValueKey('link-in-bio-preview-pause'));
      await tester.ensureVisible(pause);
      await tester.tap(pause);
      await tester.pumpAndSettle();
      final stopped = matrix();
      await tester.pump(const Duration(seconds: 1));
      expect(matrix(), stopped);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
  for (final theme in ['pink', 'garden', 'cards']) {
    testWidgets('$theme bounded preview starts at readable store content',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                  body: BioPreviewViewport(
                      height: 120,
                      appearance: LinkInBioAppearance.forTheme(theme),
                      child: LinkInBioPreview(
                          storeName: 'ร้านของคุณ',
                          slug: 'sample',
                          links: const [],
                          appearance: LinkInBioAppearance.forTheme(theme)))))));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(BioPreviewViewport));
      final title = tester.getRect(find.text('ร้านของคุณ'));
      expect(title.top, greaterThanOrEqualTo(viewport.top));
      expect(title.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('$theme round trips and preserves content when applied', () {
      final themed = bioApplyTheme(
          const LinkInBioAppearance(
              description: 'ร้านเดิม',
              logoKey:
                  'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-logo.png',
              featuredLinkId: 'shop',
              featuredLabel: 'โปรร้าน'),
          theme);
      expect(LinkInBioAppearance.fromJson(themed.toJson()).themeId, theme);
      expect(themed.description, 'ร้านเดิม');
      expect(themed.logoKey,
          'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-logo.png');
      expect(themed.featuredLinkId, 'shop');
      expect(themed.featuredLabel, 'โปรร้าน');
    });

    testWidgets(
        '$theme preview is readable with reduced motion on a narrow screen',
        (tester) async {
      tester.view.physicalSize = const Size(320, 852);
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
          storeName: 'ร้านของคุณ',
          slug: 'sample',
          appearance: LinkInBioAppearance.forTheme(theme),
          links: const [
            LinkInBioCustomLink(
                id: 'shop',
                title: 'ซื้อสินค้าที่ Shopee',
                url: 'https://shopee.co.th/shop',
                category: 'ช่องทางร้าน')
          ],
        ))),
      )));
      await tester.pumpAndSettle();
      expect(find.text('ร้านของคุณ'), findsOneWidget);
      expect(find.text('ซื้อสินค้าที่ Shopee'), findsOneWidget);
      if (theme == 'cards') expect(find.text('เปิดลิงก์'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in ['minimal', 'pink', 'garden', 'cards']) {
    testWidgets('$theme motion can pause and resume without changing the draft',
        (tester) async {
      final appearance = LinkInBioAppearance.forTheme(theme).copyWith(
          effects: const LinkInBioEffects(
              background: true,
              entrance: true,
              featured: true,
              stickers: 'hearts'));
      final before = appearance.toJson();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: LinkInBioPreview(
                      storeName: 'ร้านทดสอบ',
                      slug: 'shop',
                      appearance: appearance,
                      links: const [
            LinkInBioCustomLink(
                id: 'a', title: 'ร้าน', url: 'https://example.com')
          ])))));
      await tester.pump(const Duration(seconds: 1));
      final pause = find.byKey(const ValueKey('link-in-bio-preview-pause'));
      await tester.ensureVisible(pause);
      await tester.tap(pause);
      await tester.pumpAndSettle();
      expect(find.text('เล่นการเคลื่อนไหว'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.tap(pause);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('หยุดการเคลื่อนไหว'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(appearance.toJson(), before);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  test('legacy profiles are still and invalid effects are rejected', () {
    final legacy = const LinkInBioAppearance().toJson()..remove('effects');
    expect(LinkInBioAppearance.fromJson(legacy).effects.enabled, isFalse);
    for (final invalid in [
      null,
      [],
      'yes',
      {'background': 'true'},
      {'stickers': null},
      {'stickers': 'script'}
    ]) {
      expect(
          () => LinkInBioAppearance.fromJson({...legacy, 'effects': invalid}),
          throwsFormatException);
    }
  });
}
