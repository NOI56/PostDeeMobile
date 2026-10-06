import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _links = [
  LinkInBioCustomLink(
      id: 'youtube', title: 'ดูวิดีโอ', url: 'https://youtu.be/v'),
  LinkInBioCustomLink(
      id: 'shopee', title: 'ซื้อสินค้า', url: 'https://shopee.co.th/shop'),
  LinkInBioCustomLink(
      id: 'lazada', title: 'ร้านค้า', url: 'https://lazada.co.th/shop'),
  LinkInBioCustomLink(
      id: 'line', title: 'ติดต่อร้าน', url: 'https://lin.ee/shop'),
  LinkInBioCustomLink(
      id: 'tiktok', title: 'คลิปสั้น', url: 'https://tiktok.com/@shop'),
  LinkInBioCustomLink(
      id: 'instagram', title: 'รูปสินค้า', url: 'https://instagram.com/shop'),
  LinkInBioCustomLink(
      id: 'facebook', title: 'เพจร้าน', url: 'https://fb.me/shop'),
];

Finder _asset(String id) => find.byWidgetPredicate((widget) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage).assetName ==
        'assets/images/platforms/$id.png');

Future<void> _preview(WidgetTester tester, List<LinkInBioCustomLink> links,
    {ThemeData? theme}) async {
  await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
          body: SingleChildScrollView(
              child: LinkInBioPreview(
                  storeName: 'ร้านมินา',
                  slug: 'mina-shop',
                  links: links,
                  appearance: const LinkInBioAppearance(
                      buttonColor: '#2c5734',
                      buttonStyle: LinkInBioTextStyle(color: '#ffffff')))))));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets(
      'preview uses platform logos instead of letter and emoji placeholders',
      (tester) async {
    await _preview(tester, _links);
    for (final link in _links) {
      expect(_asset(link.id), findsOneWidget, reason: link.id);
      final image = tester.widget<Image>(_asset(link.id));
      expect(image.fit, BoxFit.contain);
      expect(image.color, isNull, reason: 'Brand colors must not be tinted');
      expect(tester.getSize(_asset(link.id)), const Size(40, 40));
    }
    expect(find.text('S'), findsNothing);
    expect(find.text('L'), findsNothing);
    expect(find.text('LINE'), findsNothing);
    expect(find.text('▶'), findsNothing);
    expect(find.text('♪'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('every brand image is bundled and decodes as a real image', () async {
    for (final link in _links) {
      final data =
          await rootBundle.load('assets/images/platforms/${link.id}.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThanOrEqualTo(40), reason: link.id);
      expect(frame.image.height, greaterThanOrEqualTo(40), reason: link.id);
      frame.image.dispose();
      codec.dispose();
    }
  });

  testWidgets('manual brand and generic icon choices override URL detection',
      (tester) async {
    await _preview(tester, const [
      LinkInBioCustomLink(
          id: 'brand',
          title: 'ร้านอื่น',
          url: 'https://example.com',
          icon: 'shopee'),
      LinkInBioCustomLink(
          id: 'generic',
          title: 'ลิงก์ธรรมดา',
          url: 'https://youtube.com',
          icon: 'link'),
    ]);
    expect(_asset('shopee'), findsOneWidget);
    expect(_asset('youtube'), findsNothing);
    expect(find.text('ร้านอื่น'), findsOneWidget);
    expect(find.text('ลิงก์ธรรมดา'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown and misleading domains do not display platform branding',
      (tester) async {
    await _preview(tester, const [
      LinkInBioCustomLink(
          id: 'unknown', title: 'เว็บไซต์', url: 'https://example.com'),
      LinkInBioCustomLink(
          id: 'spoof',
          title: 'อีกเว็บไซต์',
          url: 'https://shopee.co.th.evil.example'),
    ]);
    for (final link in _links) {
      expect(_asset(link.id), findsNothing);
    }
    expect(find.text('เว็บไซต์'), findsOneWidget);
    expect(find.text('อีกเว็บไซต์'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dark preview keeps original image colors and accessible link titles',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _preview(tester, _links.take(2).toList(), theme: AppTheme.dark);
    expect(tester.widget<Image>(_asset('youtube')).color, isNull);
    expect(tester.widget<Image>(_asset('shopee')).color, isNull);
    expect(find.bySemanticsLabel('ดูวิดีโอ'), findsOneWidget);
    expect(find.bySemanticsLabel('ซื้อสินค้า'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('manager cards use the same platform images as the preview',
      (tester) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await const SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a')
        .saveDraft(LinkInBioDraft(
            storeName: 'ร้านมินา',
            slug: 'mina-shop',
            autoUpdateFromScheduledPosts: false,
            enabledLinkIds: {'youtube', 'shopee'},
            customLinks: [_links[0], _links[1]]));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: LinkInBioScreen(loadProfile: () async => null)));
    await tester.pumpAndSettle();
    expect(_asset('youtube'), findsOneWidget);
    expect(_asset('shopee'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('link-in-bio-edit-youtube')), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-toggle-shopee')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
