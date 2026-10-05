import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MaterialApp(
    theme: AppTheme.dark, home: LinkInBioScreen(loadProfile: () async => null));
Future<void> _show(WidgetTester tester, Finder finder,
    {double delta = 250}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, delta,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _show(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _add(WidgetTester tester,
    {String title = 'คูปอง Shopee',
    String url = 'https://shopee.co.th/shop'}) async {
  await _tap(tester, 'link-in-bio-add');
  await tester.enterText(
      find.byKey(const ValueKey('link-in-bio-link-title')), title);
  await tester.enterText(
      find.byKey(const ValueKey('link-in-bio-link-url')), url);
  await tester.tap(find.text('บันทึกลิงก์'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);
  const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');

  testWidgets('saves and reloads a local draft without claiming it is public',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-store-name')), 'ร้านมินา');
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-slug')), 'mina-shop');
    await _tap(tester, 'link-in-bio-save-draft');
    expect((await store.loadDraft())!.slug, 'mina-shop');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('link-in-bio-store-name')))
            .controller!
            .text,
        'ร้านมินา');
    expect(find.byKey(const ValueKey('link-in-bio-public-url')), findsNothing);
  });

  testWidgets('adds a real link, previews it and reloads it from owner draft',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _add(tester);
    await _tap(tester, 'link-in-bio-save-draft');
    expect((await store.loadDraft())!.customLinks.single.url,
        'https://shopee.co.th/shop');
    await _tap(tester, 'link-in-bio-preview');
    expect(find.text('ตัวอย่างก่อนเผยแพร่'), findsOneWidget);
    await tester.tap(find.text('ปิดตัวอย่าง'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _show(tester, find.byTooltip('แก้ไขลิงก์'));
    expect(find.text('https://shopee.co.th/shop'), findsOneWidget);
  });

  testWidgets(
      'editing a custom link preserves its identity and saved replacement',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _add(tester);
    await _tap(tester, 'link-in-bio-save-draft');
    final id = (await store.loadDraft())!.customLinks.single.id;
    await _show(tester, find.byTooltip('แก้ไขลิงก์'), delta: -200);
    await tester.tap(find.byTooltip('แก้ไขลิงก์'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-link-title')), 'คูปอง Lazada');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-url')),
        'https://lazada.co.th/shop');
    await tester.tap(find.text('บันทึกลิงก์'));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-save-draft');
    final link = (await store.loadDraft())!.customLinks.single;
    expect(link.id, id);
    expect(link.title, 'คูปอง Lazada');
    expect(link.url, 'https://lazada.co.th/shop');
  });

  testWidgets('deletes only the selected custom link from the saved draft',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _add(tester);
    await _show(tester, find.byTooltip('ลบลิงก์'));
    await tester.tap(find.byTooltip('ลบลิงก์'));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-save-draft');
    expect((await store.loadDraft())!.customLinks, isEmpty);
  });

  for (final url in [
    'javascript:alert(1)',
    'example.com',
    'https://user:pass@example.com',
    'https://example.com/a b'
  ]) {
    testWidgets('rejects unsafe link $url before adding', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _add(tester, url: url);
      expect(find.textContaining('https:// หรือ http://'), findsOneWidget);
      expect(find.text('บันทึกลิงก์'), findsOneWidget);
    });
  }

  testWidgets('initial offline load does not invent unpublished status',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: LinkInBioScreen(
            loadProfile: () async => throw const SocketException('offline'))));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่ได้เผยแพร่'), findsNothing);
    expect(find.text('ยังตรวจสถานะเว็บไซต์ไม่ได้'), findsOneWidget);
    expect(find.textContaining('ตรวจสอบอินเทอร์เน็ต'), findsOneWidget);
  });
}
