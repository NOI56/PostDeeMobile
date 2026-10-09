import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

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
  if (key == 'link-in-bio-link-icon') {
    await tester.enterText(
        find.byKey(const ValueKey('bio-platform-search')), label);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _ProtectedImageDraftStore implements LinkInBioDraftStore {
  _ProtectedImageDraftStore(this.saved, this.protected);
  LinkInBioDraft saved;
  final Set<String> protected;
  @override
  Future<LinkInBioDraft?> loadDraft() async => saved;
  @override
  Future<void> saveDraft(LinkInBioDraft draft) async {
    if (draft.appearance.logoKey != null &&
        !protected.contains(draft.appearance.logoKey)) {
      throw StateError('Local save attempted before image protection');
    }
    saved = draft;
  }
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

  for (final (label, error, message) in <(String, Object, String)>[
    (
      '404',
      const ApiException('Request failed', statusCode: 404),
      'ระบบคุ้มครองรูปแบบร่างยังไม่พร้อมใช้งาน กรุณาลองใหม่ภายหลัง'
    ),
    (
      '405',
      const ApiException('Request failed', statusCode: 405),
      'ระบบคุ้มครองรูปแบบร่างยังไม่พร้อมใช้งาน กรุณาลองใหม่ภายหลัง'
    ),
    (
      'network',
      const SocketException('offline'),
      'เชื่อมต่อ PostDee ไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่'
    ),
  ]) {
    testWidgets(
        'draft protection $label reports its cause and preserves the saved draft',
        (tester) async {
      await store.saveDraft(LinkInBioDraft(
          storeName: _draft.storeName,
          slug: _draft.slug,
          autoUpdateFromScheduledPosts: false,
          enabledLinkIds: _draft.enabledLinkIds,
          customLinks: _links,
          appearance: const LinkInBioAppearance(logoKey: _imageKey)));
      await tester.pumpWidget(_app(LinkInBioScreen(
          loadProfile: () async => null,
          loadImage: (_) async => _png,
          protectDraftImages: (
              {required draftId, required keys, required mode}) async {
            throw error;
          })));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      await showBioStep(tester, 'info');
      await tester.enterText(
          find.byKey(const ValueKey('link-in-bio-store-name')),
          'ชื่อที่ยังไม่บันทึก');
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect((await store.loadDraft())!.storeName, _draft.storeName);
      expect((await store.loadDraft())!.appearance.logoKey, _imageKey);
      expect(find.text('มีการแก้ไขที่ยังไม่ได้บันทึก'), findsOneWidget);
    });
  }

  testWidgets(
      'two managers refresh image protection before replacing a shared owner draft',
      (tester) async {
    const nextImage =
        'uploads/seller-a/42345678-1234-1234-1234-123456789abc/profile-logo.png';
    final protected = {_imageKey};
    final sentRevisions = <(String, int?)>[];
    final shared = _ProtectedImageDraftStore(
        LinkInBioDraft(
            storeName: _draft.storeName,
            slug: _draft.slug,
            autoUpdateFromScheduledPosts: false,
            enabledLinkIds: _draft.enabledLinkIds,
            customLinks: _links,
            appearance: const LinkInBioAppearance(logoKey: _imageKey)),
        protected);
    await linkInBioDraftReferenceIdForUser('seller-a');
    await saveLinkInBioProtectedImageKeysForUser('seller-a', protected);
    LinkInBioScreen screen(String id) => LinkInBioScreen(
        key: ValueKey(id),
        draftStore: shared,
        loadProfile: () async => null,
        loadImage: (_) async => _png,
        pickImage: () async => _png,
        uploadImage: ({required slot, required bytes}) async => nextImage,
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {
          final preferences = await SharedPreferences.getInstance();
          sentRevisions.add((
            draftId,
            preferences
                .getInt('postdee_link_in_bio.user.seller-a.image_revision')
          ));
          if (mode == 'replace') protected.clear();
          protected.addAll(keys);
        });
    await tester.pumpWidget(_app(screen('first-manager')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const ValueKey('first-manager'))))
        .push(
            MaterialPageRoute<void>(builder: (_) => screen('second-manager')));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'info');
    await _tap(tester, 'link-in-bio-image-logo');
    expect(shared.saved.appearance.logoKey, nextImage);
    expect(protected, {nextImage});
    await _tap(tester, 'link-in-bio-close-editor');
    await _tap(tester, 'link-in-bio-back');
    await showBioStep(tester, 'info');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-store-name')),
        'ชื่อจากตัวจัดการแรก');
    await tester.pumpAndSettle();
    expect(shared.saved.storeName, 'ชื่อจากตัวจัดการแรก');
    expect(shared.saved.appearance.logoKey, _imageKey);
    expect(protected, {_imageKey});
    for (final (token, persistedRevision) in sentRevisions) {
      expect(token, matches(RegExp(r'^[a-f0-9]{32}_[1-9][0-9]*$')));
      expect(persistedRevision,
          greaterThanOrEqualTo(int.parse(token.split('_').last)));
    }
  });

  testWidgets(
      'confirmed protected image allows offline local edits after restart and retries stale pin cleanup',
      (tester) async {
    await store.saveDraft(LinkInBioDraft(
        storeName: _draft.storeName,
        slug: _draft.slug,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: _draft.enabledLinkIds,
        customLinks: _links,
        appearance: const LinkInBioAppearance(logoKey: _imageKey)));
    await linkInBioDraftReferenceIdForUser('seller-a');
    await saveLinkInBioProtectedImageKeysForUser('seller-a', {_imageKey});
    final calls = <String>[];
    var offline = true;
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        loadImage: (_) async => _png,
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {
          calls.add(mode);
          if (offline) throw StateError('offline');
        })));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await showBioStep(tester, 'info');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-store-name')),
        'ชื่อใหม่แบบออฟไลน์');
    await tester.pumpAndSettle();
    expect((await store.loadDraft())!.storeName, 'ชื่อใหม่แบบออฟไลน์');
    expect(find.text('บันทึกแบบร่างในเครื่องแล้ว'), findsOneWidget);
    expect(calls, ['replace']);
    offline = false;
    await _tap(tester, 'link-in-bio-save-draft');
    expect(calls, ['replace', 'replace']);
    expect(
        await loadLinkInBioProtectedImageKeysForUser('seller-a'), {_imageKey});
  });

  testWidgets('canceling a replacement keeps the saved draft image protected',
      (tester) async {
    const replacement =
        'uploads/seller-a/22345678-1234-1234-1234-123456789abc/profile-logo.png';
    await store.saveDraft(LinkInBioDraft(
        storeName: _draft.storeName,
        slug: _draft.slug,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: _draft.enabledLinkIds,
        customLinks: _links,
        appearance: const LinkInBioAppearance(logoKey: _imageKey)));
    final calls = <Set<String>>[];
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        pickImage: () async => _png,
        uploadImage: ({required slot, required bytes}) async => replacement,
        loadImage: (_) async => _png,
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {
          calls.add({...keys});
        })));
    await tester.pumpAndSettle();
    expect(calls, [
      {_imageKey}
    ]);
    await _tap(tester, 'link-in-bio-decorate');
    await _tap(tester, 'link-in-bio-disclosure-images');
    await _tap(tester, 'link-in-bio-image-logo');
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect((await store.loadDraft())!.appearance.logoKey, _imageKey);
    expect(calls, [
      {_imageKey}
    ]);
  });

  testWidgets(
      'new draft image must be protected before local save and a failed protection remains retryable',
      (tester) async {
    const replacement =
        'uploads/seller-a/32345678-1234-1234-1234-123456789abc/profile-logo.png';
    await store.saveDraft(LinkInBioDraft(
        storeName: _draft.storeName,
        slug: _draft.slug,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: _draft.enabledLinkIds,
        customLinks: _links,
        appearance: const LinkInBioAppearance(logoKey: _imageKey)));
    var fail = true;
    final calls = <String>[];
    await tester.pumpWidget(_app(LinkInBioScreen(
        loadProfile: () async => null,
        pickImage: () async => _png,
        uploadImage: ({required slot, required bytes}) async => replacement,
        loadImage: (_) async => _png,
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {
          calls.add('$mode:${keys.single}');
          if (keys.contains(replacement) && mode == 'add') {
            expect((await store.loadDraft())!.appearance.logoKey, _imageKey);
            if (fail) throw StateError('offline');
          }
          if (mode == 'replace') {
            expect((await store.loadDraft())!.appearance.logoKey, replacement);
          }
        })));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'info');
    await _tap(tester, 'link-in-bio-image-logo');
    expect((await store.loadDraft())!.appearance.logoKey, _imageKey);
    expect(find.text('มีการแก้ไขที่ยังไม่ได้บันทึก'), findsOneWidget);
    fail = false;
    await _tap(tester, 'link-in-bio-save-draft');
    expect((await store.loadDraft())!.appearance.logoKey, replacement);
    expect(calls.last, 'replace:$replacement');
    expect(find.text('บันทึกแบบร่างในเครื่องแล้ว'), findsOneWidget);
  });

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
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {},
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
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {},
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
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {},
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
