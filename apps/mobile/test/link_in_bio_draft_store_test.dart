import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('draft revisions persist monotonically and remain owner scoped',
      () async {
    expect(await nextLinkInBioDraftRevisionForUser('first'), 1);
    expect(await nextLinkInBioDraftRevisionForUser('first'), 2);
    expect(await nextLinkInBioDraftRevisionForUser('second'), 1);
  });

  test('an invalid persisted revision cannot send an older draft token',
      () async {
    SharedPreferences.setMockInitialValues({
      'postdee_link_in_bio.user.first.image_revision': 9007199254740991,
    });
    await expectLater(
        nextLinkInBioDraftRevisionForUser('first'), throwsStateError);
  });

  test('shared owner draft mutations serialize while other owners continue',
      () async {
    final gate = Completer<void>();
    final steps = <String>[];
    final first = withLinkInBioDraftMutationForUser('first', () async {
      steps.add('first-start');
      await gate.future;
      steps.add('first-end');
    });
    final second = withLinkInBioDraftMutationForUser(
        'first', () async => steps.add('second'));
    await withLinkInBioDraftMutationForUser(
        'other', () async => steps.add('other'));
    expect(steps, ['first-start', 'other']);
    gate.complete();
    await Future.wait([first, second]);
    expect(steps, ['first-start', 'other', 'first-end', 'second']);
  });

  test('draft image reference IDs survive reload and stay owner scoped',
      () async {
    final first = await linkInBioDraftReferenceIdForUser('first');
    expect(first, matches(RegExp(r'^[a-zA-Z0-9_-]{8,80}$')));
    expect(await linkInBioDraftReferenceIdForUser('first'), first);
    expect(await linkInBioDraftReferenceIdForUser('second'), isNot(first));
  });

  test('image protection confirmations and account cleanup remain owner scoped',
      () async {
    await linkInBioDraftReferenceIdForUser('first');
    final second = await linkInBioDraftReferenceIdForUser('second');
    await saveLinkInBioProtectedImageKeysForUser('first', {'first-image'});
    await saveLinkInBioProtectedImageKeysForUser('second', {'second-image'});
    expect(
        await loadLinkInBioProtectedImageKeysForUser('first'), {'first-image'});
    await clearLinkInBioDraftForUser('first');
    expect(await existingLinkInBioDraftReferenceIdForUser('first'), isNull);
    expect(await loadLinkInBioProtectedImageKeysForUser('first'), isEmpty);
    expect(await existingLinkInBioDraftReferenceIdForUser('second'), second);
    expect(await loadLinkInBioProtectedImageKeysForUser('second'),
        {'second-image'});
  });

  test(
      'scopes saved links and deletion to their owner, ignoring legacy globals',
      () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesLinkInBioDraftStore.storeNameKey: 'ร้านบัญชีเก่า',
    });
    const first = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'first');
    const second = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'second');
    expect(await first.loadDraft(), isNull);
    expect(await second.loadDraft(), isNull);
    await first.saveDraft(const LinkInBioDraft(
      storeName: 'ร้านหนึ่ง',
      slug: 'first-shop',
      autoUpdateFromScheduledPosts: false,
      enabledLinkIds: {'a'},
      customLinks: [
        LinkInBioCustomLink(
            id: 'a', title: 'สินค้า', url: 'https://example.com')
      ],
    ));
    expect((await first.loadDraft())!.customLinks.single.url,
        'https://example.com');
    expect(await second.loadDraft(), isNull);
    await second.saveDraft(const LinkInBioDraft(
      storeName: 'ร้านสอง',
      slug: 'second-shop',
      autoUpdateFromScheduledPosts: false,
      enabledLinkIds: {},
      customLinks: [],
    ));
    await first.clearDraft();
    expect(await first.loadDraft(), isNull);
    expect((await second.loadDraft())!.storeName, 'ร้านสอง');
    final preferences = await SharedPreferences.getInstance();
    expect(
        preferences
            .getString(SharedPreferencesLinkInBioDraftStore.storeNameKey),
        'ร้านบัญชีเก่า');
  });

  test('cannot persist an unowned draft', () async {
    const store = SharedPreferencesLinkInBioDraftStore();
    expect(await store.loadDraft(), isNull);
    await expectLater(
        store.saveDraft(LinkInBioDraft.defaults()), throwsStateError);
  });

  test('appearance and link options survive an owner-scoped save and reload',
      () async {
    const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller');
    final appearance = LinkInBioAppearance.forTheme('dark')
        .copyWith(description: 'ร้านออนไลน์ของเรา');
    await store.saveDraft(LinkInBioDraft(
      storeName: 'ร้านเรา',
      slug: 'our-shop',
      autoUpdateFromScheduledPosts: false,
      enabledLinkIds: const {'shop'},
      appearance: appearance,
      customLinks: const [
        LinkInBioCustomLink(
            id: 'shop',
            title: 'สินค้า',
            url: 'https://example.com',
            category: 'ของใช้',
            icon: 'shopee',
            font: 'prompt',
            textColor: '#ffffff',
            buttonColor: '#e85d24')
      ],
    ));
    final loaded = (await store.loadDraft())!;
    expect(loaded.appearance.toJson(), appearance.toJson());
    expect(loaded.customLinks.single.toJson(), {
      'id': 'shop',
      'title': 'สินค้า',
      'url': 'https://example.com',
      'category': 'ของใช้',
      'icon': 'shopee',
      'font': 'prompt',
      'textColor': '#ffffff',
      'buttonColor': '#e85d24',
    });
  });

  test('older owned drafts without appearance still load with legacy defaults',
      () async {
    SharedPreferences.setMockInitialValues({
      'postdee_link_in_bio.user.seller': jsonEncode({
        'storeName': 'ร้านเดิม',
        'slug': 'old-shop',
        'enabledLinkIds': ['shop'],
        'customLinks': [
          jsonEncode(
              {'id': 'shop', 'title': 'ร้าน', 'url': 'https://example.com'})
        ],
      }),
    });
    final draft =
        await const SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller')
            .loadDraft();
    expect(draft!.appearance.toJson(), const LinkInBioAppearance().toJson());
    expect(draft.customLinks.single.toJson(),
        {'id': 'shop', 'title': 'ร้าน', 'url': 'https://example.com'});
  });

  test('new manual contact icons survive an owner-scoped draft round trip',
      () async {
    const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller');
    const other = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'other');
    const contacts = {
      'messenger': 'https://m.me/shop',
      'whatsapp': 'https://wa.me/66812345678',
      'google_maps': 'https://maps.app.goo.gl/shop',
      'website': 'https://example.com/shop',
      'email': 'mailto:shop@example.com',
      'phone': 'tel:+66812345678',
    };
    final links = contacts.entries
        .map((entry) => LinkInBioCustomLink(
            id: entry.key,
            title: 'ติดต่อร้าน',
            url: entry.value,
            category: 'ติดต่อ',
            icon: entry.key))
        .toList();
    await store.saveDraft(LinkInBioDraft(
        storeName: 'ร้านของเรา',
        slug: 'our-shop',
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: contacts.keys.toSet(),
        customLinks: links));
    final loaded = (await store.loadDraft())!;
    expect(loaded.enabledLinkIds, contacts.keys.toSet());
    expect(loaded.customLinks.map((link) => link.toJson()).toList(),
        links.map((link) => link.toJson()).toList());
    expect(await other.loadDraft(), isNull);
  });

  test('a malformed appearance never becomes a silently reset saved design',
      () async {
    SharedPreferences.setMockInitialValues({
      'postdee_link_in_bio.user.seller': jsonEncode({
        'storeName': 'ร้านเดิม',
        'slug': 'old-shop',
        'enabledLinkIds': [],
        'customLinks': [],
        'appearance': {'version': 999},
      }),
    });
    expect(
        await const SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller')
            .loadDraft(),
        isNull);
  });
}
