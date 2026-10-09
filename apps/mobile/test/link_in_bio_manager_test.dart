import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

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
  if (key.startsWith('link-in-bio-theme-') && finder.evaluate().isEmpty) {
    final legacy = find.byKey(const ValueKey('link-in-bio-legacy-themes'));
    await showBioControl(tester, legacy);
    await tester.tap(legacy);
    await tester.pumpAndSettle();
  }
  await showBioControl(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _mount(WidgetTester tester, LinkInBioScreen screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  await tester.pumpAndSettle();
}

Future<void> _reload(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
}

class _ControlledDraftStore implements LinkInBioDraftStore {
  _ControlledDraftStore({this.fail = false});
  bool fail;
  Completer<void>? gate;
  int saves = 0;
  LinkInBioDraft saved = _draft;
  @override
  Future<LinkInBioDraft?> loadDraft() async => saved;
  @override
  Future<void> saveDraft(LinkInBioDraft value) async {
    saves++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('disk unavailable');
    saved = value;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets(
      'automatic draft saves serialize edits and skip queued work after an owner change',
      (tester) async {
    final store = _ControlledDraftStore()..gate = Completer<void>();
    await _mount(tester,
        LinkInBioScreen(draftStore: store, loadProfile: () async => null));
    await tester.tap(find.byKey(const ValueKey('link-in-bio-toggle-shop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('link-in-bio-toggle-shop')));
    await tester.pump();
    expect(store.saves, 1);
    expect(find.text('กำลังบันทึกแบบร่างในเครื่อง...'), findsOneWidget);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(store.saves, 2);
    expect(store.saved.enabledLinkIds, {'shop'});
    store.gate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('link-in-bio-toggle-shop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('link-in-bio-toggle-shop')));
    await tester.pump();
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-b', idToken: 'token-b'));
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(store.saves, 3);
    expect(store.saved.enabledLinkIds, isEmpty);
  });

  testWidgets(
      'failed automatic save reports unsaved changes and back waits for a successful retry',
      (tester) async {
    final store = _ControlledDraftStore(fail: true);
    var backs = 0;
    await _mount(
        tester,
        LinkInBioScreen(
            draftStore: store,
            loadProfile: () async => null,
            onBack: () => backs++));
    await _tap(tester, 'link-in-bio-toggle-shop');
    expect(find.text('มีการแก้ไขที่ยังไม่ได้บันทึก'), findsOneWidget);
    expect(store.saved.enabledLinkIds, {'shop'});
    await _tap(tester, 'link-in-bio-back');
    expect(backs, 0);
    store.fail = false;
    await _tap(tester, 'link-in-bio-back');
    expect(backs, 1);
    expect(store.saved.enabledLinkIds, isEmpty);
  });

  testWidgets(
      'Save Link and Done persist without a second parent save or publication',
      (tester) async {
    var publications = 0;
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => null,
            publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async {
              publications++;
              return _profile();
            }));
    await _tap(tester, 'link-in-bio-add');
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-link-title')), 'ร้านใหม่');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-url')),
        'https://example.com/new');
    await _tap(tester, 'link-in-bio-link-save');
    expect((await _store.loadDraft())!.customLinks.single.title, 'ร้านใหม่');
    await showBioUrlSettings(tester);
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-slug')), 'new-shop');
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-store-name')), 'ร้านใหม่ของฉัน');
    await _tap(tester, 'link-in-bio-done');
    expect((await _store.loadDraft())!.storeName, 'ร้านใหม่ของฉัน');
    expect(find.text('บันทึกแบบร่างในเครื่องแล้ว'), findsOneWidget);
    await _reload(tester);
    expect(find.text('ร้านใหม่'), findsOneWidget);
    expect(publications, 0);
    expect(find.byKey(const ValueKey('link-in-bio-public-url')), findsNothing);
  });

  testWidgets('inactive embedded preview disables animation tickers',
      (tester) async {
    await _store.saveDraft(_draft);
    Widget screen(bool active) => MaterialApp(
        theme: AppTheme.light,
        home: LinkInBioScreen(
            isActive: active,
            embeddedInTab: true,
            loadProfile: () async => null));
    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-review');
    final preview = find.byType(LinkInBioPreview);
    expect(TickerMode.valuesOf(tester.element(preview)).enabled, isTrue);
    await tester.pumpWidget(screen(false));
    await tester.pump();
    expect(TickerMode.valuesOf(tester.element(preview)).enabled, isFalse);
  });

  testWidgets('empty manager opens directly with Add Link and no setup wizard',
      (tester) async {
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
    expect(find.text('ลิงก์ร้าน'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-add')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-save')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-review')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-store-name')), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-next')), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-previous')), findsNothing);
    expect(find.byType(LinkInBioPreview), findsNothing);
    await _tap(tester, 'link-in-bio-add');
    expect(
        find.byKey(const ValueKey('link-in-bio-link-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-link-url')), findsOneWidget);
  });

  testWidgets('publish still validates URL and enabled links without a wizard',
      (tester) async {
    var calls = 0;
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => null,
            publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async {
              calls++;
              return _profile();
            }));
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(find.textContaining('ชื่อ URL ต้องเป็น'), findsOneWidget);
    expect(calls, 0);
    await showBioUrlSettings(tester);
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-slug')), 'mina-shop');
    await _tap(tester, 'link-in-bio-done');
    expect(find.byKey(const ValueKey('link-in-bio-add')), findsOneWidget);
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(find.textContaining('อย่างน้อย 1 ลิงก์'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('saved URL stays collapsed in shop settings without losing value',
      (tester) async {
    await _store.saveDraft(_draft);
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
    await showBioStep(tester, 'info');
    final slug = find.byKey(const ValueKey('link-in-bio-slug'));
    expect(slug, findsNothing);
    await _tap(tester, 'link-in-bio-url-settings');
    expect(tester.widget<TextField>(slug).controller!.text, 'mina-shop');
  });

  testWidgets(
      'shop and theme changes return to links and retain independent styles',
      (tester) async {
    await _store.saveDraft(_draft);
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
    await showBioStep(tester, 'info');
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-description')),
        'ขายของใช้ในบ้าน');
    await _tap(tester, 'link-in-bio-done');
    expect(find.byKey(const ValueKey('link-in-bio-card-shop')), findsOneWidget);
    await showBioStep(tester, 'theme');
    await _tap(tester, 'link-in-bio-theme-pastel');
    await _tap(tester, 'link-in-bio-done');
    expect(find.byKey(const ValueKey('link-in-bio-card-shop')), findsOneWidget);
    await _tap(tester, 'link-in-bio-save');
    final saved = (await _store.loadDraft())!;
    expect(saved.appearance.description, 'ขายของใช้ในบ้าน');
    expect(saved.appearance.themeId, 'pastel');
    expect(saved.customLinks.single.id, 'shop');
    await showBioStep(tester, 'info');
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('link-in-bio-description')))
            .controller!
            .text,
        'ขายของใช้ในบ้าน');
  });

  testWidgets('published manager shows local links and shares confirmed URL',
      (tester) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const local = LinkInBioCustomLink(
        id: 'local', title: 'ลิงก์แบบร่าง', url: 'https://example.com/draft');
    await _store.saveDraft(const LinkInBioDraft(
        storeName: 'ร้านมินา',
        slug: 'new-draft-slug',
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: {'local'},
        customLinks: [local]));
    String? copied;
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => _profile(),
            copyLink: (value) async => copied = value));
    expect(
        find.byKey(const ValueKey('link-in-bio-card-local')), findsOneWidget);
    expect(find.text('ลิงก์แบบร่าง'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-card-shop')), findsNothing);
    expect(find.byType(LinkInBioPreview), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-add')).hitTestable(),
        findsOneWidget);
    await _tap(tester, 'link-in-bio-copy');
    expect(copied, 'https://api.example.com/p/mina-shop');
    expect((await _store.loadDraft())!.slug, 'new-draft-slug');
    expect((await _store.loadDraft())!.customLinks.single.id, 'local');
  });

  testWidgets(
      'direct toggles and drag reorder persist disabled links after reload',
      (tester) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const links = [
      _link,
      LinkInBioCustomLink(
          id: 'chat', title: 'ติดต่อ LINE', url: 'https://line.me/mina'),
      LinkInBioCustomLink(
          id: 'off', title: 'โปรโมชั่น', url: 'https://example.com/promo'),
    ];
    await _store.saveDraft(const LinkInBioDraft(
        storeName: 'ร้านมินา',
        slug: 'mina-shop',
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: {'shop', 'chat'},
        customLinks: links,
        appearance: LinkInBioAppearance(featuredLinkId: 'shop')));
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
    await _tap(tester, 'link-in-bio-toggle-shop');
    final first = find.byKey(const ValueKey('link-in-bio-card-shop'));
    final second = find.byKey(const ValueKey('link-in-bio-card-chat'));
    final handle = find.byKey(const ValueKey('link-in-bio-drag-shop'));
    await showBioControl(tester, second);
    expect(handle.hitTestable(), findsOneWidget);
    final distance = tester.getCenter(second).dy - tester.getCenter(first).dy;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, distance / 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-save');
    final saved = (await _store.loadDraft())!;
    expect(saved.customLinks.map((link) => link.id), ['chat', 'shop', 'off']);
    expect(saved.enabledLinkIds, {'chat'});
    expect(saved.appearance.featuredLinkId, isNull);
    await _reload(tester);
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(first).dy));
    expect(
        tester
            .widget<Switch>(
                find.byKey(const ValueKey('link-in-bio-toggle-shop')))
            .value,
        isFalse);
    expect(
        tester
            .widget<Switch>(
                find.byKey(const ValueKey('link-in-bio-toggle-chat')))
            .value,
        isTrue);
    expect(find.byKey(const ValueKey('link-in-bio-card-off')), findsOneWidget);
  });

  testWidgets(
      'adding link starts with two fields and hidden invalid options stay invalid',
      (tester) async {
    await _store.saveDraft(_draft);
    await _mount(tester, LinkInBioScreen(loadProfile: () async => null));
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
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-link-category')), '😀' * 31);
    await _tap(tester, 'link-in-bio-link-advanced');
    await _tap(tester, 'link-in-bio-link-save');
    expect(find.text('หมวดหมู่ยาวเกิน 60 ตัวอักษร'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('link-in-bio-link-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review publishes once and returns to editable link manager',
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
    await _tap(tester, 'link-in-bio-review');
    await tester.tap(find.byKey(const ValueKey('link-in-bio-publish')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('link-in-bio-publish')));
    await tester.pump();
    expect(calls, 1);
    pending.complete(_profile());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-in-bio-card-shop')), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-add')), findsOneWidget);
    expect(find.byType(LinkInBioPreview), findsNothing);
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-copy')), findsOneWidget);
  });

  for (final width in [320.0, 393.0]) {
    testWidgets(
        'manager controls remain reachable above navigation at ${width}px',
        (tester) async {
      tester.view.physicalSize = Size(width, 873);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await _store.saveDraft(_draft);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!),
          home: Scaffold(
              extendBody: true,
              body: SafeArea(
                  bottom: false,
                  child: LinkInBioScreen(
                      embeddedInTab: true, loadProfile: () async => null)),
              bottomNavigationBar: const SizedBox(
                  key: ValueKey('test-bottom-nav'),
                  height: AppTheme.navOverlap))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-in-bio-add')).hitTestable(),
          findsOneWidget);
      final save = find.byKey(const ValueKey('link-in-bio-save'));
      final review = find.byKey(const ValueKey('link-in-bio-review'));
      final nav = find.byKey(const ValueKey('test-bottom-nav'));
      expect(save.hitTestable(), findsOneWidget);
      expect(review.hitTestable(), findsOneWidget);
      expect(tester.getBottomRight(save).dy,
          lessThanOrEqualTo(tester.getTopLeft(nav).dy));
      expect(tester.getBottomRight(review).dy,
          lessThanOrEqualTo(tester.getTopLeft(nav).dy));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shop settings Done remains above keyboard on narrow screen',
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
    await showBioStep(tester, 'info');
    final done = find.byKey(const ValueKey('link-in-bio-done'));
    expect(tester.getBottomRight(done).dy, lessThanOrEqualTo(380));
    expect(tester.takeException(), isNull);
  });

  testWidgets('link sheet saves while keyboard is open on a narrow screen',
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
    await _tap(tester, 'link-in-bio-add');
    final title = find.byKey(const ValueKey('link-in-bio-link-title'));
    final url = find.byKey(const ValueKey('link-in-bio-link-url'));
    await showBioControl(tester, title);
    await tester.enterText(title, 'LINE ของร้าน');
    await showBioControl(tester, url);
    await tester.enterText(url, 'https://line.me/mina');
    final save = find.byKey(const ValueKey('link-in-bio-link-save'));
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(380));
    await _tap(tester, 'link-in-bio-link-save');
    expect(find.byKey(const ValueKey('link-in-bio-link-sheet')), findsNothing);
    await _tap(tester, 'link-in-bio-save');
    expect((await _store.loadDraft())!.customLinks.single.url,
        'https://line.me/mina');
    expect(tester.takeException(), isNull);
  });
}
