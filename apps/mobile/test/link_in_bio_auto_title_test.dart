import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_link_defaults.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

const _store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
final _title = find.byKey(const ValueKey('link-in-bio-link-title'));
final _url = find.byKey(const ValueKey('link-in-bio-link-url'));

String _titleText(WidgetTester tester) =>
    tester.widget<TextField>(_title).controller!.text;

Future<void> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 873);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: LinkInBioScreen(loadProfile: () async => null)));
  await tester.pumpAndSettle();
}

Future<void> _addSheet(WidgetTester tester) async {
  await _mount(tester);
  await tapBioControl(tester, 'link-in-bio-add');
}

Future<void> _enterUrl(WidgetTester tester, String value) async {
  await tester.enterText(_url, value);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  test('platform defaults use real domains and their short links', () {
    const cases = {
      'https://shopee.co.th/shop': 'Shopee',
      'https://s.shopee.co.th/shop': 'Shopee',
      'https://shope.ee/code': 'Shopee',
      'https://s.lazada.co.th/shop': 'Lazada',
      'https://lin.ee/contact': 'LINE',
      'https://line.me/contact': 'LINE',
      'https://vm.tiktok.com/code': 'TikTok',
      'HTTPS://WWW.YOUTUBE.COM/watch?v=1': 'YouTube',
      'https://youtu.be/video': 'YouTube',
      'https://instagram.com/seller': 'Instagram',
      'https://m.facebook.com/seller': 'Facebook',
      'https://fb.me/code': 'Facebook',
      '  https://www.example.com/path  ': 'example.com',
      'https://shopee.co.th.evil.example/shop': 'shopee.co.th.evil.example',
      'https://notshopee.co.th/shop': 'notshopee.co.th',
    };
    for (final entry in cases.entries) {
      expect(suggestedBioLinkTitle(entry.key), entry.value, reason: entry.key);
    }
  });

  test('unsafe or incomplete URLs do not receive a suggested title', () {
    for (final url in [
      '',
      'https://',
      'www.example.com',
      'javascript:alert(1)',
      'ftp://example.com/file',
      'https://user:password@shopee.co.th/shop',
      'https://example.com/a b',
      'https://example.com/${'a' * 2048}',
    ]) {
      expect(suggestedBioLinkTitle(url), isNull, reason: url);
    }
  });

  test('a long domain stays within the button title limit', () {
    final title = suggestedBioLinkTitle('https://${'a' * 60}.${'b' * 30}.com');
    expect(title, isNotNull);
    expect(title!.length, 80);
  });

  testWidgets('URL-only link fills its title and saves in the owner draft',
      (tester) async {
    await _addSheet(tester);
    await _enterUrl(tester, 'https://shopee.co.th/shop');
    expect(_titleText(tester), 'Shopee');
    await tapBioControl(tester, 'link-in-bio-link-save');
    await tapBioControl(tester, 'link-in-bio-save');
    final link = (await _store.loadDraft())!.customLinks.single;
    expect(link.title, 'Shopee');
    expect(link.url, 'https://shopee.co.th/shop');
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester);
    expect(find.text('Shopee'), findsOneWidget);
  });

  testWidgets('generated title follows URL changes and clears for invalid URL',
      (tester) async {
    await _addSheet(tester);
    await _enterUrl(tester, 'https://shopee.co.th/shop');
    expect(_titleText(tester), 'Shopee');
    await _enterUrl(tester, 'https://youtu.be/video');
    expect(_titleText(tester), 'YouTube');
    await _enterUrl(tester, 'https://');
    expect(_titleText(tester), isEmpty);
    await _enterUrl(tester, 'https://www.example.com/items');
    expect(_titleText(tester), 'example.com');
  });

  testWidgets('typing a title before the URL keeps the users title',
      (tester) async {
    await _addSheet(tester);
    await tester.enterText(_title, 'สินค้าราคาพิเศษ');
    await _enterUrl(tester, 'https://shopee.co.th/shop');
    expect(_titleText(tester), 'สินค้าราคาพิเศษ');
    await _enterUrl(tester, 'https://lazada.co.th/shop');
    expect(_titleText(tester), 'สินค้าราคาพิเศษ');
  });

  testWidgets('manually edited generated title survives later URL changes',
      (tester) async {
    await _addSheet(tester);
    await _enterUrl(tester, 'https://shopee.co.th/shop');
    await tester.enterText(_title, 'คูปองร้านของฉัน');
    await _enterUrl(tester, 'https://lazada.co.th/shop');
    expect(_titleText(tester), 'คูปองร้านของฉัน');
    await _enterUrl(tester, '');
    expect(_titleText(tester), 'คูปองร้านของฉัน');
  });

  testWidgets('manually typing the same generated name makes it a custom title',
      (tester) async {
    await _addSheet(tester);
    await _enterUrl(tester, 'https://shopee.co.th/shop');
    await tester.enterText(_title, 'Shop');
    await tester.enterText(_title, 'Shopee');
    await _enterUrl(tester, 'https://youtube.com/video');
    expect(_titleText(tester), 'Shopee');
  });

  testWidgets('clearing a custom name resumes the URL-based default',
      (tester) async {
    await _addSheet(tester);
    await _enterUrl(tester, 'https://lin.ee/contact');
    await tester.enterText(_title, 'ติดต่อฉัน');
    await tester.enterText(_title, '   ');
    await tester.pump();
    expect(_titleText(tester).trim(), isEmpty);
    await _enterUrl(tester, 'https://line.me/contact');
    expect(_titleText(tester), 'LINE');
    await _enterUrl(tester, 'https://tiktok.com/@seller');
    expect(_titleText(tester), 'TikTok');
  });

  testWidgets('saving a valid URL with a cleared name fills the default',
      (tester) async {
    await _addSheet(tester);
    await _enterUrl(tester, 'https://tiktok.com/@seller');
    await tester.enterText(_title, '');
    await tapBioControl(tester, 'link-in-bio-link-save');
    await tapBioControl(tester, 'link-in-bio-save');
    expect((await _store.loadDraft())!.customLinks.single.title, 'TikTok');
  });

  testWidgets('editing a saved link keeps its name and identity',
      (tester) async {
    const existing = LinkInBioCustomLink(
        id: 'shop',
        title: 'Shopee',
        url: 'https://shopee.co.th/shop',
        category: 'สินค้า',
        icon: 'link');
    await _store.saveDraft(const LinkInBioDraft(
        storeName: 'ร้านมินา',
        slug: 'mina-shop',
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: {'shop'},
        customLinks: [existing]));
    await _mount(tester);
    await tapBioControl(tester, 'link-in-bio-edit-shop');
    await _enterUrl(tester, 'https://lazada.co.th/shop');
    expect(_titleText(tester), 'Shopee');
    await tapBioControl(tester, 'link-in-bio-link-save');
    await tapBioControl(tester, 'link-in-bio-save');
    final saved = (await _store.loadDraft())!.customLinks.single;
    expect(saved.id, existing.id);
    expect(saved.title, existing.title);
    expect(saved.url, 'https://lazada.co.th/shop');
    expect(saved.category, existing.category);
    expect(saved.icon, existing.icon);
  });

  testWidgets('an invalid URL cannot acquire a default name or be saved',
      (tester) async {
    await _addSheet(tester);
    await _enterUrl(tester, 'javascript:alert(1)');
    expect(_titleText(tester), isEmpty);
    await tapBioControl(tester, 'link-in-bio-link-save');
    expect(
        find.byKey(const ValueKey('link-in-bio-link-sheet')), findsOneWidget);
    expect(await _store.loadDraft(), isNull);
  });
}
