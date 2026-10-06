import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

const _link = LinkInBioCustomLink(
    id: 'shop', title: 'ร้านค้า', url: 'https://example.com/shop');
const _draft = LinkInBioDraft(
    storeName: 'ร้านมินา',
    slug: 'mina-shop',
    autoUpdateFromScheduledPosts: false,
    enabledLinkIds: {'shop'},
    customLinks: [_link]);
LinkInBioProfileResult _profile({bool published = true}) =>
    LinkInBioProfileResult(
      storeName: 'ร้านมินา',
      slug: 'mina-shop',
      links: const [
        LinkInBioLinkResult(
            id: 'shop', title: 'ร้านค้า', url: 'https://example.com/shop')
      ],
      isPublished: published,
      publishedAt: published ? DateTime.utc(2026, 10, 5) : null,
      updatedAt: DateTime.utc(2026, 10, 5),
      publicPath: published ? '/p/mina-shop' : null,
      publicUrl:
          published ? Uri.parse('https://api.example.com/p/mina-shop') : null,
    );

class _FailSecondSaveDraftStore implements LinkInBioDraftStore {
  _FailSecondSaveDraftStore(this.draft);
  LinkInBioDraft draft;
  int saves = 0;
  @override
  Future<LinkInBioDraft?> loadDraft() async => draft;
  @override
  Future<void> saveDraft(LinkInBioDraft value) async {
    if (++saves == 2) throw StateError('disk full');
    draft = value;
  }
}

LinkInBioProfileResult _normalizedProfile() => LinkInBioProfileResult(
    storeName: 'ร้านมินา',
    slug: 'mina-shop',
    links: const [
      LinkInBioLinkResult(
          id: 'shop', title: 'ร้านค้า', url: 'https://example.com/')
    ],
    isPublished: true,
    publishedAt: DateTime.utc(2026, 10, 5),
    updatedAt: DateTime.utc(2026, 10, 5),
    publicPath: '/p/mina-shop',
    publicUrl: Uri.parse('https://api.example.com/p/mina-shop'));

const _nonCanonicalDraft = LinkInBioDraft(
    storeName: 'ร้านมินา',
    slug: 'mina-shop',
    autoUpdateFromScheduledPosts: false,
    enabledLinkIds: {
      'shop'
    },
    customLinks: [
      LinkInBioCustomLink(
          id: 'shop', title: 'ร้านค้า', url: 'https://EXAMPLE.com'),
      LinkInBioCustomLink(
          id: 'off', title: 'ปิดไว้', url: 'https://EXAMPLE.com/off'),
    ]);
Widget _app(LinkInBioScreen screen) =>
    MaterialApp(theme: AppTheme.light, home: screen);
Future<void> _tap(WidgetTester tester, String key) =>
    tapBioControl(tester, key);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets(
      'confirmed publication normalizes draft URLs and retains disabled links after reload',
      (tester) async {
    const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
    await store.saveDraft(_nonCanonicalDraft);
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async =>
            _normalizedProfile())));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-publish');
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
    expect(find.textContaining('มีการแก้ไขที่ยังไม่ได้เผยแพร่'), findsNothing);
    final saved = (await store.loadDraft())!;
    expect(saved.customLinks.first.url, 'https://example.com/');
    expect(saved.customLinks.last.url, 'https://EXAMPLE.com/off');
    expect(saved.enabledLinkIds, {'shop'});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
        _app(LinkInBioScreen(loadProfile: () async => _normalizedProfile())));
    await tester.pumpAndSettle();
    expect(find.textContaining('มีการแก้ไขที่ยังไม่ได้เผยแพร่'), findsNothing);
  });

  testWidgets(
      'post-confirmation local save failure never turns publication into an unknown outcome',
      (tester) async {
    final store = _FailSecondSaveDraftStore(_nonCanonicalDraft);
    await tester.pumpWidget(_app(LinkInBioScreen(
        draftStore: store,
        loadProfile: () async => null,
        publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async =>
            _normalizedProfile())));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-publish');
    expect(store.saves, 2);
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-copy')), findsOneWidget);
    expect(find.textContaining('ยังไม่ทราบผล'), findsNothing);
    expect(find.textContaining('มีการแก้ไขที่ยังไม่ได้เผยแพร่'), findsNothing);
    expect(
        find.textContaining('บันทึกแบบร่างในเครื่องไม่สำเร็จ'), findsOneWidget);
  });

  testWidgets(
      'pending refresh blocks unpublish and cannot overwrite a later confirmed removal',
      (tester) async {
    final pending = Completer<LinkInBioProfileResult?>();
    var loads = 0;
    var deletes = 0;
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => ++loads == 1 ? _profile() : pending.future,
        unpublishProfile: () async {
          deletes++;
          return _profile(published: false);
        })));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-refresh');
    await _tap(tester, 'link-in-bio-more');
    final button = find.byKey(const ValueKey('link-in-bio-unpublish'));
    expect(tester.widget<PopupMenuItem<String>>(button).enabled, isFalse);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(find.byKey(const ValueKey('link-in-bio-confirm-unpublish')),
        findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    pending.complete(_profile());
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-unpublish');
    await _tap(tester, 'link-in-bio-confirm-unpublish');
    expect(deletes, 1);
    expect(find.byKey(const ValueKey('link-in-bio-public-url')), findsNothing);
    expect(find.text('ยังไม่ได้เผยแพร่'), findsOneWidget);
  });
  testWidgets('empty page has no invented links or fabricated public URL',
      (tester) async {
    await tester
        .pumpWidget(_app(LinkInBioScreen(loadProfile: () async => null)));
    await tester.pumpAndSettle();
    expect(find.text('ลิงก์ร้าน'), findsOneWidget);
    expect(find.textContaining('postdee.link'), findsNothing);
    expect(find.text('สินค้าแนะนำ'), findsNothing);
    expect(find.text('อัปเดตจากโพสต์ที่ตั้งเวลา'), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-public-url')), findsNothing);
    expect(find.text('ยังไม่ได้เผยแพร่'), findsOneWidget);
  });
  testWidgets('inactive tab is lazy and embedded back uses callback',
      (tester) async {
    var loads = 0;
    var backs = 0;
    Widget screen(bool active) => _app(LinkInBioScreen(
        isActive: active,
        embeddedInTab: true,
        onBack: () => backs++,
        loadProfile: () async {
          loads++;
          return null;
        }));
    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    expect(loads, 0);
    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.tap(find.byKey(const ValueKey('link-in-bio-back')));
    expect(backs, 1);
  });
  testWidgets(
      'publishes real enabled links and shares confirmed URL despite unsaved slug edits',
      (tester) async {
    const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
    await store.saveDraft(const LinkInBioDraft(
        storeName: 'ร้านมินา',
        slug: 'mina-shop',
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: {
          'shop'
        },
        customLinks: [
          _link,
          LinkInBioCustomLink(
              id: 'off', title: 'ปิดไว้', url: 'https://example.com/off')
        ]));
    String? copied;
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        publishProfile: (
            {required storeName,
            required slug,
            required links,
            appearance}) async {
          expect(storeName, 'ร้านมินา');
          expect(slug, 'mina-shop');
          expect(links.map((link) => link.id), ['shop']);
          return _profile();
        },
        copyLink: (url) async {
          copied = url;
        })));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-publish');
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
    await showBioUrlSettings(tester);
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-slug')), 'new-shop');
    await _tap(tester, 'link-in-bio-copy');
    expect(copied, 'https://api.example.com/p/mina-shop');
    expect(
        find.textContaining('มีการแก้ไขที่ยังไม่ได้เผยแพร่'), findsOneWidget);
  });
  testWidgets('late cloud load preserves a locally edited draft',
      (tester) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<LinkInBioProfileResult?>();
    await tester
        .pumpWidget(_app(LinkInBioScreen(loadProfile: () => pending.future)));
    await tester.pump();
    await _tap(tester, 'link-in-bio-add');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-title')),
        'ลิงก์ใหม่ยังไม่เผยแพร่');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-url')),
        'https://example.com/local');
    await _tap(tester, 'link-in-bio-link-save');
    pending.complete(_profile());
    await tester.pumpAndSettle();
    expect(find.text('ลิงก์ใหม่ยังไม่เผยแพร่'), findsOneWidget);
    expect(find.text('https://example.com/local'), findsOneWidget);
    expect(find.text('https://example.com/shop'), findsNothing);
    expect(find.text('https://api.example.com/p/mina-shop'), findsOneWidget);
  });
  testWidgets(
      'unknown publish result is not shown as success and reload recovers it',
      (tester) async {
    const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
    await store.saveDraft(_draft);
    var loads = 0;
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => ++loads == 1 ? null : _profile(),
        publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async =>
            throw TimeoutException('slow'))));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-publish');
    expect(find.text('เผยแพร่แล้ว'), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-copy')), findsNothing);
    expect(find.textContaining('ยังไม่ทราบผล'), findsWidgets);
    await _tap(tester, 'link-in-bio-refresh');
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
  });
  testWidgets('slug conflict preserves inputs and reports a Thai error',
      (tester) async {
    const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
    await store.saveDraft(_draft);
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async =>
            throw const ApiException('taken',
                statusCode: 409, code: 'LINK_IN_BIO_SLUG_TAKEN'))));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-publish');
    expect(find.textContaining('ชื่อ URL นี้มีคนใช้แล้ว'), findsOneWidget);
    await showBioUrlSettings(tester);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('link-in-bio-slug')))
            .controller!
            .text,
        'mina-shop');
  });
  testWidgets('unpublish needs confirmation and keeps draft contents',
      (tester) async {
    var deletes = 0;
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => _profile(),
        unpublishProfile: () async {
          deletes++;
          return _profile(published: false);
        })));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-unpublish');
    expect(deletes, 0);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await _tap(tester, 'link-in-bio-unpublish');
    await _tap(tester, 'link-in-bio-confirm-unpublish');
    expect(deletes, 1);
    expect(find.byKey(const ValueKey('link-in-bio-public-url')), findsNothing);
    await showBioStep(tester, 'info');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('link-in-bio-store-name')))
            .controller!
            .text,
        'ร้านมินา');
  });
}
