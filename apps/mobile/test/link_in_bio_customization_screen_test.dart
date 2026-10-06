import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

const _links = [
  LinkInBioCustomLink(
      id: 'shop', title: 'ร้านค้า', url: 'https://example.com/shop'),
  LinkInBioCustomLink(id: 'chat', title: 'ติดต่อ', url: 'https://line.me/shop'),
];
const _draft = LinkInBioDraft(
    storeName: 'ร้านมินา',
    slug: 'mina-shop',
    autoUpdateFromScheduledPosts: false,
    enabledLinkIds: {'shop', 'chat'},
    customLinks: _links);
const _imageKey =
    'uploads/seller-a/12345678-1234-1234-1234-123456789abc/profile-logo.png';
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
Widget _app(LinkInBioScreen screen) =>
    MaterialApp(theme: AppTheme.light, home: screen);
Future<void> _tap(WidgetTester tester, String key) =>
    tapBioControl(tester, key);

Future<void> _select(WidgetTester tester, String key, String label) async {
  await _tap(tester, key);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token'));
    await store.saveDraft(_draft);
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets(
      'decoration apply stays above an open keyboard on a narrow screen',
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
        home: LinkInBioScreen(loadProfile: () => Future.value(null))));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-decorate');
    final button = find.byKey(const ValueKey('link-in-bio-decoration-done'));
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(380));
    await _tap(tester, 'link-in-bio-decoration-done');
    expect(find.text('ใช้แบบนี้กับแบบร่าง'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Unicode description beyond server length stays editable without invalid appearance crash',
      (tester) async {
    await tester.pumpWidget(
        _app(LinkInBioScreen(loadProfile: () => Future.value(null))));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-decorate');
    await _tap(tester, 'link-in-bio-disclosure-images');
    final description = find.byKey(const ValueKey('link-in-bio-description'));
    await tester.ensureVisible(description);
    await tester.pumpAndSettle();
    await tester.enterText(description, '😀' * 150);
    await _tap(tester, 'link-in-bio-decoration-done');
    expect(find.text('คำแนะนำร้านยาวเกิน 280 ตัวอักษร'), findsOneWidget);
    expect(find.text('ใช้แบบนี้กับแบบร่าง'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(description, 'ข้อความที่ใช้ได้');
    await _tap(tester, 'link-in-bio-decoration-done');
    await _tap(tester, 'link-in-bio-save-draft');
    expect(
        (await store.loadDraft())!.appearance.description, 'ข้อความที่ใช้ได้');
  });

  testWidgets(
      'pending draft image appears in an already open editor without another edit',
      (tester) async {
    await store.saveDraft(LinkInBioDraft(
        storeName: _draft.storeName,
        slug: _draft.slug,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: _draft.enabledLinkIds,
        customLinks: _links,
        appearance: const LinkInBioAppearance(logoKey: _imageKey)));
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () => Future.value(null),
        loadImage: (_) => pending.future)));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-decorate');
    await _tap(tester, 'link-in-bio-disclosure-images');
    final storeImages = find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage);
    expect(storeImages, findsNothing);
    pending.complete(_png);
    await tester.pumpAndSettle();
    expect(storeImages, findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'decoration waits for pending initial profile and preserves loaded appearance',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final pending = Completer<LinkInBioProfileResult?>();
    await tester
        .pumpWidget(_app(LinkInBioScreen(loadProfile: () => pending.future)));
    await tester.pump();
    final button = find.byKey(const ValueKey('link-in-bio-step-theme'));
    expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
    final appearance = LinkInBioAppearance.forTheme('dark')
        .copyWith(description: 'ร้านจากเว็บไซต์');
    pending.complete(LinkInBioProfileResult(
        storeName: 'ร้านมินา',
        slug: 'mina-shop',
        links: const [
          LinkInBioLinkResult(
              id: 'shop', title: 'ร้านค้า', url: 'https://example.com/shop')
        ],
        appearance: appearance,
        isPublished: true,
        updatedAt: DateTime.utc(2026, 10, 5),
        publishedAt: DateTime.utc(2026, 10, 5),
        publicPath: '/p/mina-shop',
        publicUrl: Uri.parse('https://api.example.com/p/mina-shop')));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'theme');
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('link-in-bio-theme-dark')))
            .selected,
        isTrue);
    await _tap(tester, 'link-in-bio-decorate');
    await _tap(tester, 'link-in-bio-decoration-done');
    await _tap(tester, 'link-in-bio-save-draft');
    final saved = (await store.loadDraft())!;
    expect(saved.appearance.themeId, 'dark');
    expect(saved.appearance.description, 'ร้านจากเว็บไซต์');
    expect(find.textContaining('มีการแก้ไขที่ยังไม่ได้เผยแพร่'), findsNothing);
  });

  testWidgets('visual picker sets a section color without entering a hex code',
      (tester) async {
    await tester
        .pumpWidget(_app(LinkInBioScreen(loadProfile: () async => null)));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-decorate');
    await _tap(tester, 'link-in-bio-disclosure-styles');
    await _tap(tester, 'link-in-bio-disclosure-style-name');
    await _tap(tester, 'link-in-bio-name-color-picker');
    await _tap(tester, 'link-in-bio-color-swatch-e85d24');
    await _tap(tester, 'link-in-bio-color-confirm');
    await _tap(tester, 'link-in-bio-decoration-done');
    await _tap(tester, 'link-in-bio-save-draft');
    expect((await store.loadDraft())!.appearance.nameStyle.color, '#e85d24');
  });

  testWidgets(
      'theme and individual section font and color persist in owner draft at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(_app(LinkInBioScreen(loadProfile: () async => null)));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-theme-pastel');
    await _tap(tester, 'link-in-bio-decorate');
    await _tap(tester, 'link-in-bio-disclosure-styles');
    await _tap(tester, 'link-in-bio-disclosure-style-name');
    await _select(tester, 'link-in-bio-name-font', 'Prompt • ตัวอย่างภาษาไทย');
    final color = find.byKey(const ValueKey('link-in-bio-name-color'));
    await tester.ensureVisible(color);
    await tester.enterText(color, '#123456');
    await _tap(tester, 'link-in-bio-decoration-done');
    await _tap(tester, 'link-in-bio-save-draft');
    final saved = (await store.loadDraft())!;
    expect(saved.appearance.themeId, 'pastel');
    expect(saved.appearance.nameStyle.font, 'prompt');
    expect(saved.appearance.nameStyle.color, '#123456');
    expect(saved.appearance.buttonRadius, 'pill');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'publication includes appearance and keeps confirmed page separate from draft',
      (tester) async {
    LinkInBioAppearance? sent;
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        publishProfile: (
            {required storeName,
            required slug,
            required links,
            appearance}) async {
          sent = appearance;
          return LinkInBioProfileResult(
              storeName: storeName,
              slug: slug,
              links: links,
              appearance: appearance!,
              isPublished: true,
              updatedAt: DateTime.utc(2026, 10, 5),
              publishedAt: DateTime.utc(2026, 10, 5),
              publicPath: '/p/mina-shop',
              publicUrl: Uri.parse('https://api.example.com/p/mina-shop'));
        })));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-theme-dark');
    await _tap(tester, 'link-in-bio-publish');
    expect(sent?.themeId, 'dark');
    expect(find.textContaining('มีการแก้ไขที่ยังไม่ได้เผยแพร่'), findsNothing);
    await _tap(tester, 'link-in-bio-theme-shop');
    expect(
        find.textContaining('มีการแก้ไขที่ยังไม่ได้เผยแพร่'), findsOneWidget);
    expect(sent?.themeId, 'dark');
  });

  testWidgets(
      'image upload previews bytes and changing theme preserves media and description',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        pickImage: () async => _png,
        uploadImage: ({required slot, required bytes}) async {
          expect(slot, 'logo');
          expect(bytes, _png);
          return _imageKey;
        },
        loadImage: (key) async {
          reads++;
          return _png;
        })));
    await tester.pumpAndSettle();
    expect(reads, 0);
    await _tap(tester, 'link-in-bio-decorate');
    await _tap(tester, 'link-in-bio-disclosure-images');
    await _tap(tester, 'link-in-bio-image-logo');
    final description = find.byKey(const ValueKey('link-in-bio-description'));
    await tester.ensureVisible(description);
    await tester.enterText(description, 'ร้านน่ารัก ส่งไว');
    await _tap(tester, 'link-in-bio-decoration-done');
    await _tap(tester, 'link-in-bio-theme-shop');
    await _tap(tester, 'link-in-bio-save-draft');
    final saved = (await store.loadDraft())!;
    expect(saved.appearance.logoKey, _imageKey);
    expect(saved.appearance.description, 'ร้านน่ารัก ส่งไว');
    expect(find.byType(Image), findsWidgets);
    expect(reads, 0); // Freshly uploaded bytes already cached, no extra GET.
    expect(tester.takeException(), isNull);
  });

  testWidgets('image upload errors preserve existing draft media',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: SizedBox(key: ValueKey('warm-image-cache'))));
    await tester.runAsync(() => precacheImage(MemoryImage(_png),
        tester.element(find.byKey(const ValueKey('warm-image-cache')))));
    await store.saveDraft(LinkInBioDraft(
        storeName: _draft.storeName,
        slug: _draft.slug,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: _draft.enabledLinkIds,
        customLinks: _links,
        appearance: const LinkInBioAppearance(logoKey: _imageKey)));
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        pickImage: () async => _png,
        uploadImage: ({required slot, required bytes}) async =>
            throw StateError('offline'),
        loadImage: (_) async => _png)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _tap(tester, 'link-in-bio-decorate');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'link-in-bio-disclosure-images');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'link-in-bio-image-logo');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('อัปโหลดรูปไม่สำเร็จ'), findsOneWidget);
    await _tap(tester, 'link-in-bio-decoration-done');
    await _tap(tester, 'link-in-bio-save-draft');
    expect((await store.loadDraft())!.appearance.logoKey, _imageKey);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'category icon individual style feature and ordering persist, disabling clears featured',
      (tester) async {
    await tester
        .pumpWidget(_app(LinkInBioScreen(loadProfile: () async => null)));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-edit-shop');
    await _tap(tester, 'link-in-bio-link-advanced');
    final category = find.byKey(const ValueKey('link-in-bio-link-category'));
    await tester.ensureVisible(category);
    await tester.enterText(category, 'ช้อปสินค้า');
    await _select(tester, 'link-in-bio-link-icon', 'Shopee');
    await _select(tester, 'link-in-bio-link-font', 'Prompt • ตัวอย่างภาษาไทย');
    await _tap(tester, 'link-in-bio-link-save');
    await _tap(tester, 'link-in-bio-feature-shop');
    await _tap(tester, 'link-in-bio-move-up-chat');
    await _tap(tester, 'link-in-bio-save-draft');
    final saved = (await store.loadDraft())!;
    expect(saved.customLinks.map((e) => e.id), ['chat', 'shop']);
    expect(saved.customLinks.last.category, 'ช้อปสินค้า');
    expect(saved.customLinks.last.icon, 'shopee');
    expect(saved.customLinks.last.font, 'prompt');
    expect(saved.appearance.featuredLinkId, 'shop');
    await _tap(tester, 'link-in-bio-toggle-shop');
    await _tap(tester, 'link-in-bio-save-draft');
    expect((await store.loadDraft())!.appearance.featuredLinkId, isNull);
  });

  testWidgets(
      'late upload after account changes does not mutate previous owner draft',
      (tester) async {
    final pending = Completer<String>();
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        pickImage: () async => Uint8List.fromList(_png),
        uploadImage: ({required slot, required bytes}) => pending.future)));
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-decorate');
    await _tap(tester, 'link-in-bio-disclosure-images');
    final imageButton = find.byKey(const ValueKey('link-in-bio-image-logo'));
    await tester.scrollUntilVisible(imageButton, 200,
        scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(imageButton);
    await tester.pumpAndSettle();
    await tester.tap(imageButton);
    await tester.pump();
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-b', idToken: 'token-b'));
    pending.complete(_imageKey);
    await tester.pumpAndSettle();
    expect((await store.loadDraft())!.appearance.logoKey, isNull);
    expect(tester.takeException(), isNull);
  });
}
