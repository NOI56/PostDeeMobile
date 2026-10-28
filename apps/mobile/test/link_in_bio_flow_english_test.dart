import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_english_test.dart' show BioEnglishFixture, bioEnglishOwner;
import 'link_in_bio_test_navigation.dart';

const _shop = LinkInBioCustomLink(
    id: 'shop',
    title: 'เพิ่มลิงก์',
    url: 'https://EXAMPLE.com/shop?coupon=%2F');
const _contact = LinkInBioCustomLink(
    id: 'contact',
    title: 'ส่งอีเมล',
    url: 'mailto:Seller+Deals@Example.com',
    category: 'ติดต่อร้าน');
const _ready = LinkInBioDraft(
    storeName: 'ร้านของคุณ',
    slug: 'mina-shop',
    autoUpdateFromScheduledPosts: false,
    enabledLinkIds: {'shop'},
    customLinks: [_shop, _contact],
    appearance: LinkInBioAppearance(description: 'สินค้าของคนไทย'));

Finder _key(String value) => find.byKey(ValueKey(value));
Future<void> _tap(WidgetTester tester, String key) async {
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tapBioControl(tester, key);
}

Future<void> _fillLink(WidgetTester tester, String title, String url) async {
  await tester.enterText(_key('link-in-bio-link-title'), title);
  await tester.enterText(_key('link-in-bio-link-url'), url);
  await _tap(tester, 'link-in-bio-link-save');
}

BioEnglishFixture _fixture() => BioEnglishFixture()..drafts.value = _ready;
LinkInBioProfileResult _published() => BioEnglishFixture.result(
    storeName: _ready.storeName,
    links: [
      LinkInBioLinkResult(id: 'shop', title: _shop.title, url: _shop.url)
    ],
    appearance: _ready.appearance);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  testWidgets(
      'English add and edit keep Thai customer text and raw URLs unchanged',
      (tester) async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-add');
    await _fillLink(
        tester, 'คูปองของฉัน', 'https://EXAMPLE.com/new?coupon=%2F');
    expect(fixture.drafts.value!.customLinks, hasLength(3),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? text.textSpan?.toPlainText())
            .join('\n'));
    final added = fixture.drafts.value!.customLinks.last;
    expect(added.title, 'คูปองของฉัน');
    expect(added.url, 'https://EXAMPLE.com/new?coupon=%2F');
    final reads = fixture.subscriptionReads;
    await _tap(tester, 'link-in-bio-edit-${added.id}');
    expect(find.text('Edit link'), findsOneWidget);
    await _fillLink(tester, 'ลิงก์ร้าน', 'https://EXAMPLE.com/edit?x=%2f');
    final saved = fixture.drafts.value!.customLinks.last;
    expect(saved.id, added.id);
    expect(saved.title, 'ลิงก์ร้าน');
    expect(saved.url, 'https://EXAMPLE.com/edit?x=%2f');
    expect(fixture.drafts.value!.storeName, 'ร้านของคุณ');
    expect(fixture.drafts.value!.customLinks.first.title, 'เพิ่มลิงก์');
    expect(fixture.subscriptionReads, reads);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing an existing Thai automatic-looking title never translates data',
      (tester) async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-edit-contact');
    expect(
        tester
            .widget<TextField>(_key('link-in-bio-link-title'))
            .controller!
            .text,
        'ส่งอีเมล');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await _tap(tester, 'link-in-bio-link-save');
    expect(fixture.drafts.value!.customLinks.last.title, 'ส่งอีเมล');
    expect(fixture.drafts.value!.customLinks.last.url, _contact.url);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English delete and Undo restore order enabled state and featured link',
      (tester) async {
    final fixture = _fixture();
    fixture.drafts.value = LinkInBioDraft(
        storeName: _ready.storeName,
        slug: _ready.slug,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: const {'shop', 'contact'},
        customLinks: _ready.customLinks,
        appearance: _ready.appearance.copyWith(featuredLinkId: 'contact'));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-delete-contact');
    expect(fixture.drafts.value!.customLinks.map((link) => link.id), ['shop']);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final restored = fixture.drafts.value!;
    expect(restored.customLinks.map((link) => link.id), ['shop', 'contact']);
    expect(restored.enabledLinkIds, {'shop', 'contact'});
    expect(restored.appearance.featuredLinkId, 'contact');
    expect(restored.customLinks.last.title, 'ส่งอีเมล');
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('link menus move and feature only the selected saved link',
      (tester) async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-move-up-contact');
    expect(fixture.drafts.value!.customLinks.map((link) => link.id),
        ['contact', 'shop']);
    await _tap(tester, 'link-in-bio-feature-shop');
    expect(fixture.drafts.value!.appearance.featuredLinkId, 'shop');
    await _tap(tester, 'link-in-bio-link-menu-shop');
    expect(find.text('Remove featured promotion'), findsOneWidget);
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Move down'), findsOneWidget);
    expect(find.text('Delete link'), findsWidgets);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('publishing sends active links and original customer values once',
      (tester) async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Not published'), findsOneWidget);
    await _tap(tester, 'link-in-bio-publish');
    expect(fixture.publications, hasLength(1),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? text.textSpan?.toPlainText())
            .join('\n'));
    final request = fixture.publications.single;
    expect(request.name, 'ร้านของคุณ');
    expect(request.slug, 'mina-shop');
    expect(request.links.map((link) => link.id), ['shop']);
    expect(request.links.single.title, 'เพิ่มลิงก์');
    expect(request.links.single.url, _shop.url);
    expect(request.appearance!.description, 'สินค้าของคนไทย');
    expect(find.text('Published'), findsOneWidget);
    expect(_key('link-in-bio-copy'), findsOneWidget);
    expect(fixture.drafts.value!.customLinks, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unknown publish outcome reconciles through one read without republishing',
      (tester) async {
    final fixture = _fixture()
      ..publishError = const SocketException('lost response');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-publish');
    expect(
        find.text(
            'The publishing result is unknown. Check website status before trying again.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(_key('link-in-bio-publish')).onPressed,
        isNull);
    expect(_key('link-in-bio-copy'), findsNothing);
    fixture.profile = _published();
    await _tap(tester, 'link-in-bio-retry');
    expect(find.text('Published'), findsOneWidget);
    expect(fixture.profileReads, 2);
    expect(fixture.publications, hasLength(1));
    expect(_key('link-in-bio-copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('taken URL errors translate live without another publish or read',
      (tester) async {
    final fixture = _fixture()
      ..publishError = const ApiException('slug conflict',
          statusCode: 409, code: 'LINK_IN_BIO_SLUG_TAKEN');
    addTearDown(fixture.dispose);
    fixture.language.value = const Locale('th');
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-publish');
    expect(find.text('ชื่อ URL นี้มีคนใช้แล้ว กรุณาเลือกชื่อใหม่'),
        findsOneWidget);
    final reads = fixture.profileReads;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('This URL name is already taken. Please choose another.'),
        findsOneWidget);
    expect(fixture.publications, hasLength(1));
    expect(fixture.profileReads, reads);
    expect(find.text('Published'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unpublish dialog can decline then unpublish once and preserve the draft',
      (tester) async {
    final fixture = _fixture()..profile = _published();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-unpublish');
    expect(find.text('Unpublish this website?'), findsOneWidget);
    expect(
        find.text(
            'Customers will not be able to open this website until you publish it again. Your draft will be kept.'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.unpublications, 0);
    expect(find.text('Published'), findsOneWidget);
    await _tap(tester, 'link-in-bio-unpublish');
    await _tap(tester, 'link-in-bio-confirm-unpublish');
    expect(fixture.unpublications, 1);
    expect(find.text('Not published'), findsOneWidget);
    expect(_key('link-in-bio-copy'), findsNothing);
    expect(fixture.drafts.value!.customLinks, hasLength(2));
    expect(fixture.drafts.value!.storeName, 'ร้านของคุณ');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'copy and open use the confirmed URL rather than an unpublished slug',
      (tester) async {
    final fixture = _fixture()
      ..profile = BioEnglishFixture.result(slug: 'live-shop');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-copy');
    expect(find.text('Link copied. You can paste it in a chat or profile.'),
        findsOneWidget);
    await _tap(tester, 'link-in-bio-open');
    expect(fixture.copied, ['https://store.example.com/p/live-shop']);
    expect(
        fixture.opened, [Uri.parse('https://store.example.com/p/live-shop')]);
    expect(fixture.publications, isEmpty);
    expect(fixture.drafts.value!.slug, 'mina-shop');
    expect(tester.takeException(), isNull);
  });

  for (final operation in ['copy', 'open']) {
    testWidgets(
        '$operation failure shows English feedback without losing publication',
        (tester) async {
      final fixture = _fixture()..profile = _published();
      fixture.copyError =
          operation == 'copy' ? StateError('clipboard failed') : null;
      fixture.openResult = false;
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      await _tap(tester, 'link-in-bio-$operation');
      expect(
          find.text(operation == 'copy'
              ? 'Could not copy the link. Please try again.'
              : 'Could not open the website. Copy the link and open it in your browser.'),
          findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
      expect(fixture.publications, isEmpty);
      expect(fixture.unpublications, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('full preview keeps customer text and closes without publishing',
      (tester) async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-preview');
    expect(_key('link-in-bio-full-preview'), findsOneWidget);
    expect(find.text('ร้านของคุณ'), findsWidgets);
    expect(find.text('เพิ่มลิงก์'), findsWidgets);
    expect(find.byTooltip('Close preview'), findsOneWidget);
    await _tap(tester, 'link-in-bio-full-preview-close');
    expect(_key('link-in-bio-full-preview'), findsNothing);
    expect(fixture.publications, isEmpty);
    expect(fixture.opened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden links still count against the add allowance in English',
      (tester) async {
    final fixture = _fixture()
      ..subscription = const SubscriptionStatusResult(
          userId: bioEnglishOwner,
          plan: 'BASIC',
          status: 'INACTIVE',
          maxProfileLinks: 2,
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-add');
    expect(_key('link-in-bio-link-sheet'), findsNothing);
    expect(
        find.text(
            'Your plan allows up to 2 links, including hidden links. Delete an existing link or upgrade your plan to add another.'),
        findsOneWidget);
    expect(fixture.drafts.value!.customLinks.map((link) => link.id),
        ['shop', 'contact']);
    expect(fixture.drafts.value!.enabledLinkIds, {'shop'});
    expect(fixture.subscriptionReads, 2);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unavailable allowance blocks adding but keeps existing links editable',
      (tester) async {
    final fixture = _fixture()..subscriptionError = StateError('offline');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-add');
    expect(_key('link-in-bio-link-sheet'), findsNothing);
    expect(
        find.text(
            'Could not check your link allowance. Please try again. You can still edit your existing draft.'),
        findsWidgets);
    final reads = fixture.subscriptionReads;
    await _tap(tester, 'link-in-bio-edit-shop');
    await _fillLink(tester, 'ชื่อใหม่', 'https://EXAMPLE.com/edit?code=%2F');
    expect(fixture.drafts.value!.customLinks.first.title, 'ชื่อใหม่');
    expect(fixture.subscriptionReads, reads);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('excess active links cannot publish and are never discarded',
      (tester) async {
    final fixture = _fixture()
      ..subscription = const SubscriptionStatusResult(
          userId: bioEnglishOwner,
          plan: 'BASIC',
          status: 'INACTIVE',
          maxProfileLinks: 2,
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false);
    fixture.drafts.value = LinkInBioDraft(
        storeName: _ready.storeName,
        slug: _ready.slug,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: const {'shop', 'contact', 'third'},
        customLinks: const [
          _shop,
          _contact,
          LinkInBioCustomLink(
              id: 'third', title: 'Third', url: 'https://example.com/third')
        ],
        appearance: _ready.appearance);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-publish');
    expect(
        find.text(
            'Your plan allows up to 2 active links. Disable extra links before publishing. Your existing data has been kept.'),
        findsOneWidget);
    expect(fixture.publications, isEmpty);
    expect(fixture.drafts.value!.customLinks, hasLength(3));
    expect(fixture.drafts.value!.enabledLinkIds, {'shop', 'contact', 'third'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending publish changes language without a second mutation',
      (tester) async {
    final fixture = _fixture();
    final result = Completer<LinkInBioProfileResult>();
    fixture.publishGate = result.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-publish');
    expect(find.text('Please wait...'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('link-in-bio-publish')).onPressed,
        isNull);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กำลังดำเนินการ...'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Please wait...'), findsOneWidget);
    expect(fixture.publications, hasLength(1));
    result.complete(_published());
    await tester.pumpAndSettle();
    expect(find.text('Published'), findsOneWidget);
    expect(fixture.publications, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an old owner publish cannot display a late result or write a second draft',
      (tester) async {
    final fixture = _fixture();
    final result = Completer<LinkInBioProfileResult>();
    fixture.publishGate = result.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-publish');
    final saves = fixture.drafts.saves.length;
    fixture.sessions.signIn(
        const AuthSession(userId: 'another-store-owner', idToken: 'new-token'));
    await tester.pumpAndSettle();
    result.complete(_published());
    await tester.pumpAndSettle();
    expect(find.text('Your account has changed. Please reopen Store link.'),
        findsOneWidget);
    expect(find.text('Published'), findsNothing);
    expect(_key('link-in-bio-public-url'), findsNothing);
    expect(fixture.drafts.saves, hasLength(saves));
    expect(fixture.publications, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'owner replacement closes an editor containing private typed data',
      (tester) async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-edit-shop');
    await tester.enterText(
        _key('link-in-bio-link-title'), 'private unsaved title');
    fixture.sessions.signIn(
        const AuthSession(userId: 'another-store-owner', idToken: 'new-token'));
    await tester.pumpAndSettle();
    expect(_key('link-in-bio-link-sheet'), findsNothing);
    expect(find.text('private unsaved title'), findsNothing);
    expect(find.text('Your account has changed. Please reopen Store link.'),
        findsOneWidget);
    expect(fixture.drafts.saves, isEmpty);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'preview image failure translates without clearing the saved image key',
      (tester) async {
    final fixture = _fixture();
    fixture.language.value = const Locale('th');
    const imageKey =
        'uploads/$bioEnglishOwner/12345678-1234-4234-8234-123456789abc/profile-logo.png';
    final image = Completer<Uint8List>();
    fixture.imageGates[imageKey] = image.future;
    fixture.drafts.value = LinkInBioDraft(
        storeName: _ready.storeName,
        slug: _ready.slug,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: _ready.enabledLinkIds,
        customLinks: _ready.customLinks,
        appearance: _ready.appearance.copyWith(logoKey: imageKey));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(fixture.imageReads, [imageKey]);
    image.completeError(StateError('Image unavailable'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'โหลดรูปตัวอย่างไม่สำเร็จ กรุณาตรวจสถานะเว็บไซต์เพื่อลองใหม่'),
        findsOneWidget);
    final reads = fixture.imageReads.length;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not load the preview image. Check website status to try again.'),
        findsOneWidget);
    expect(fixture.imageReads, hasLength(reads));
    expect(fixture.drafts.value!.appearance.logoKey, imageKey);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed local saving stays unsaved across locale changes and can recover',
      (tester) async {
    final fixture = _fixture();
    fixture.drafts.error = StateError('disk full');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    await tester.enterText(_key('link-in-bio-store-name'), 'ร้านที่แก้ไข');
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    final saves = fixture.drafts.saves.length;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('มีการแก้ไขที่ยังไม่ได้บันทึก'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(fixture.drafts.saves, hasLength(saves));
    fixture.drafts.error = null;
    await _tap(tester, 'link-in-bio-save-draft');
    expect(fixture.drafts.value!.storeName, 'ร้านที่แก้ไข');
    expect(find.text('Draft saved on this device'), findsOneWidget);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
