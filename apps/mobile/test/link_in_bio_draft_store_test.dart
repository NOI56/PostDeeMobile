import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
}
