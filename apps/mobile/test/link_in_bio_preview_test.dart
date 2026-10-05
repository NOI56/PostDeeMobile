import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';

void main() {
  testWidgets(
      'preview follows published array order including repeated categories and featured item',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LinkInBioPreview(
                    storeName: 'ร้านมินา',
                    slug: 'mina-shop',
                    appearance: const LinkInBioAppearance(
                        featuredLinkId: 'c', featuredLabel: 'โปรพิเศษ'),
                    links: const [
          LinkInBioCustomLink(
              id: 'a',
              title: 'สินค้าแรก',
              url: 'https://example.com/a',
              category: 'สินค้า',
              icon: 'shopee'),
          LinkInBioCustomLink(
              id: 'b',
              title: 'คุยกับร้าน',
              url: 'https://line.me/shop',
              category: 'ติดต่อ'),
          LinkInBioCustomLink(
              id: 'c',
              title: 'สินค้าพิเศษ',
              url: 'https://example.com/c',
              category: 'สินค้า'),
        ])))));
    expect(tester.getTopLeft(find.text('สินค้าแรก')).dy,
        lessThan(tester.getTopLeft(find.text('คุยกับร้าน')).dy));
    expect(tester.getTopLeft(find.text('คุยกับร้าน')).dy,
        lessThan(tester.getTopLeft(find.text('สินค้าพิเศษ')).dy));
    expect(find.text('สินค้า'), findsNWidgets(2));
    expect(find.text('โปรพิเศษ'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('system typography does not inherit the app bundled Anuphan font',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: LinkInBioPreview(
                storeName: 'ฟอนต์ระบบ',
                slug: 'system-font',
                links: const [],
                appearance: const LinkInBioAppearance(
                    nameStyle: LinkInBioTextStyle(font: 'system'))))));
    final title = tester.widget<Text>(find.text('ฟอนต์ระบบ'));
    expect(title.style?.inherit, isFalse);
    expect(title.style?.fontFamily, isNull);
  });
}
