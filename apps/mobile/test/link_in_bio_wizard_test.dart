import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
const _link = LinkInBioCustomLink(
    id: 'shop', title: 'ร้าน Shopee', url: 'https://shopee.co.th/mina');
const _draft = LinkInBioDraft(
    storeName: 'ร้านมินา',
    slug: 'mina-shop',
    autoUpdateFromScheduledPosts: false,
    enabledLinkIds: {'shop'},
    customLinks: [_link]);
LinkInBioProfileResult _profile() => LinkInBioProfileResult(
    storeName: 'ร้านที่เผยแพร่',
    slug: 'mina-shop',
    links: const [
      LinkInBioLinkResult(
          id: 'shop', title: 'ร้าน Shopee', url: 'https://shopee.co.th/mina')
    ],
    isPublished: true,
    updatedAt: DateTime.utc(2026, 10, 5),
    publishedAt: DateTime.utc(2026, 10, 5),
    publicPath: '/p/mina-shop',
    publicUrl: Uri.parse('https://api.example.com/p/mina-shop'));

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _mount(WidgetTester tester, LinkInBioScreen screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets('first setup shows one task and next validates before advancing',
      (tester) async {
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
    expect(find.text('เริ่มจากข้อมูลร้าน'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-add')), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-theme-dark')), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-publish')), findsNothing);
    await _tap(tester, 'link-in-bio-next');
    expect(find.text('เริ่มจากข้อมูลร้าน'), findsOneWidget);
    expect(find.textContaining('ชื่อ URL ต้องเป็น'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-slug')), 'mina-shop');
    await _tap(tester, 'link-in-bio-next');
    expect(find.text('เพิ่มช่องทางของร้าน'), findsOneWidget);
    await _tap(tester, 'link-in-bio-next');
    expect(find.textContaining('อย่างน้อย 1 ลิงก์'), findsOneWidget);
    expect(find.text('เพิ่มช่องทางของร้าน'), findsOneWidget);
  });

  testWidgets(
      'valid saved URL is collapsed after loading without losing its value',
      (tester) async {
    await _store.saveDraft(_draft);
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
    final slug = find.byKey(const ValueKey('link-in-bio-slug'));
    expect(slug, findsNothing);
    await _tap(tester, 'link-in-bio-url-settings');
    expect(tester.widget<TextField>(slug).controller!.text, 'mina-shop');
  });

  testWidgets('setup moves back without resetting text or independent styles',
      (tester) async {
    await _store.saveDraft(_draft);
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-description')),
        'ขายของใช้ในบ้าน');
    await _tap(tester, 'link-in-bio-next');
    await _tap(tester, 'link-in-bio-next');
    await _tap(tester, 'link-in-bio-theme-pastel');
    await _tap(tester, 'link-in-bio-previous');
    await _tap(tester, 'link-in-bio-previous');
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('link-in-bio-description')))
            .controller!
            .text,
        'ขายของใช้ในบ้าน');
    await _tap(tester, 'link-in-bio-more');
    await _tap(tester, 'link-in-bio-save-draft');
    final saved = (await _store.loadDraft())!;
    expect(saved.appearance.description, 'ขายของใช้ในบ้าน');
    expect(saved.appearance.themeId, 'pastel');
    expect(saved.customLinks.single.id, 'shop');
  });

  testWidgets(
      'published overview previews confirmed snapshot and preserves local draft',
      (tester) async {
    await _store.saveDraft(_draft);
    String? copied;
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => _profile(),
            copyLink: (value) async => copied = value));
    expect(find.byKey(const ValueKey('link-in-bio-store-name')), findsNothing);
    expect(find.byType(LinkInBioPreview), findsOneWidget);
    expect(
        tester
            .widget<LinkInBioPreview>(find.byType(LinkInBioPreview))
            .storeName,
        'ร้านที่เผยแพร่');
    await _tap(tester, 'link-in-bio-edit-page');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('link-in-bio-store-name')))
            .controller!
            .text,
        'ร้านมินา');
    await _tap(tester, 'link-in-bio-close-editor');
    await _tap(tester, 'link-in-bio-copy');
    expect(copied, 'https://api.example.com/p/mina-shop');
    expect((await _store.loadDraft())!.storeName, 'ร้านมินา');
  });

  testWidgets(
      'adding link starts with two fields and hidden invalid options stay invalid',
      (tester) async {
    await _store.saveDraft(_draft);
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
    await _tap(tester, 'link-in-bio-step-links');
    await _tap(tester, 'link-in-bio-add');
    expect(
        tester
            .getSize(find.byKey(const ValueKey('link-in-bio-link-sheet')))
            .height,
        lessThanOrEqualTo(430));
    expect(
        find.byKey(const ValueKey('link-in-bio-link-category')), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-link-title')), 'ติดต่อ');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-url')),
        'https://line.me/mina');
    await _tap(tester, 'link-in-bio-link-advanced');
    final category = find.byKey(const ValueKey('link-in-bio-link-category'));
    await tester.enterText(category, '😀' * 31);
    await _tap(tester, 'link-in-bio-link-advanced');
    await _tap(tester, 'link-in-bio-link-save');
    expect(find.text('หมวดหมู่ยาวเกิน 60 ตัวอักษร'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('link-in-bio-link-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review publishes once and returns to concise overview',
      (tester) async {
    await _store.saveDraft(_draft);
    final pending = Completer<LinkInBioProfileResult>();
    var calls = 0;
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => null,
            publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) {
              calls++;
              return pending.future;
            }));
    await _tap(tester, 'link-in-bio-step-review');
    await tester.tap(find.byKey(const ValueKey('link-in-bio-publish')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('link-in-bio-publish')));
    await tester.pump();
    expect(calls, 1);
    pending.complete(_profile());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-in-bio-edit-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-next')), findsNothing);
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
  });

  testWidgets('theme options stay above fixed footer in embedded phone layout',
      (tester) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await _store.saveDraft(_draft);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            extendBody: true,
            body: SafeArea(
                bottom: false,
                child: LinkInBioScreen(
                    embeddedInTab: true, loadProfile: () async => null)),
            bottomNavigationBar: const SizedBox(height: AppTheme.navOverlap))));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-step-theme');
    final advanced = find.byKey(const ValueKey('link-in-bio-decorate'));
    final next = find.byKey(const ValueKey('link-in-bio-next'));
    expect(tester.getBottomRight(advanced).dy,
        lessThanOrEqualTo(tester.getTopLeft(next).dy - 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('next stays visible above keyboard on narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(viewInsets: const EdgeInsets.only(bottom: 260)),
            child: child!),
        home: LinkInBioScreen(loadProfile: () async => null)));
    await tester.pumpAndSettle();
    final next = find.byKey(const ValueKey('link-in-bio-next'));
    expect(tester.getBottomRight(next).dy, lessThanOrEqualTo(380));
    expect(tester.takeException(), isNull);
  });
}
