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

const _owner = 'plan-races-owner';

SubscriptionStatusResult _subscription(
        {String owner = _owner, String plan = 'BASIC'}) =>
    SubscriptionStatusResult(
        userId: owner,
        plan: plan,
        status: 'ACTIVE',
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false);

class _DraftStore implements LinkInBioDraftStore {
  _DraftStore({int count = 1, int enabled = 1})
      : draft = LinkInBioDraft(
          storeName: 'ร้านทดสอบ',
          slug: 'race-shop',
          autoUpdateFromScheduledPosts: false,
          enabledLinkIds: {
            for (var index = 0; index < enabled; index++) 'link-$index'
          },
          customLinks: [
            for (var index = 0; index < count; index++)
              LinkInBioCustomLink(
                  id: 'link-$index',
                  title: 'ลิงก์เดิม $index',
                  url: 'https://example.com/$index')
          ],
        );
  LinkInBioDraft draft;
  int saves = 0;
  @override
  Future<LinkInBioDraft?> loadDraft() async => draft;
  @override
  Future<void> saveDraft(LinkInBioDraft value) async {
    draft = value;
    saves++;
  }
}

Future<void> _mount(WidgetTester tester, _DraftStore store,
    Future<SubscriptionStatusResult> Function() load,
    {LinkInBioProfilePublisher? publish}) async {
  tester.view.physicalSize = const Size(393, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!),
    home: LinkInBioScreen(
        draftStore: store,
        loadProfile: () async => null,
        loadSubscription: load,
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {},
        publishProfile: publish ??
            (
                    {required storeName,
                    required slug,
                    required links,
                    appearance}) async =>
                throw StateError('Unexpected publication')),
  ));
  await tester.pumpAndSettle();
}

Future<void> _fillNewLink(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const ValueKey('link-in-bio-link-title')), 'ลิงก์ใหม่');
  await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-url')),
      'https://example.com/new');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: _owner, idToken: 'fixture-token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets(
      'another owner entitlement cannot grant an addition or publication',
      (tester) async {
    final store = _DraftStore();
    var publications = 0;
    await _mount(tester, store,
        () async => _subscription(owner: 'different-owner', plan: 'PRO'),
        publish: (
            {required storeName,
            required slug,
            required links,
            appearance}) async {
      publications++;
      throw StateError('An unrelated entitlement cannot authorize publishing');
    });
    await tapBioControl(tester, 'link-in-bio-add');
    expect(find.byKey(const ValueKey('link-in-bio-link-sheet')), findsNothing);
    await showBioStep(tester, 'review');
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(publications, 0);
    expect(store.draft.customLinks.length, 1);
    expect(store.saves, 0);
    expect(find.textContaining('ยังตรวจสอบสิทธิ์ลิงก์ไม่ได้'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'synchronous entitlement failure can retry and open a new link sheet',
      (tester) async {
    final store = _DraftStore();
    var fails = true;
    var reads = 0;
    Future<SubscriptionStatusResult> load() {
      reads++;
      if (fails) throw StateError('Synchronous loader failure');
      return Future.value(_subscription());
    }

    await _mount(tester, store, load);
    expect(find.byKey(const ValueKey('link-in-bio-retry-subscription')),
        findsOneWidget);
    fails = false;
    await tapBioControl(tester, 'link-in-bio-retry-subscription');
    expect(find.byKey(const ValueKey('link-in-bio-retry-subscription')),
        findsNothing);
    expect(find.text('1/2'), findsOneWidget);
    await tapBioControl(tester, 'link-in-bio-add');
    expect(
        find.byKey(const ValueKey('link-in-bio-link-sheet')), findsOneWidget);
    expect(reads, greaterThanOrEqualTo(3));
    expect(store.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two pending enable actions cannot consume the same last slot',
      (tester) async {
    final store = _DraftStore(count: 3);
    Completer<SubscriptionStatusResult>? pending;
    await _mount(
        tester, store, () => pending?.future ?? Future.value(_subscription()));
    pending = Completer<SubscriptionStatusResult>();
    await tapBioControl(tester, 'link-in-bio-toggle-link-1');
    await tapBioControl(tester, 'link-in-bio-toggle-link-2');
    expect(store.draft.enabledLinkIds, {'link-0'});
    pending.complete(_subscription());
    await tester.pumpAndSettle();
    expect(store.draft.enabledLinkIds.length, 2);
    expect(store.draft.enabledLinkIds, contains('link-0'));
    expect(store.draft.enabledLinkIds.intersection({'link-1', 'link-2'}).length,
        1);
    expect(store.draft.customLinks.length, 3);
    expect(find.textContaining('เปิดใช้ได้สูงสุด 2 ลิงก์'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rapid add and save taps create only one link while validation waits',
      (tester) async {
    final store = _DraftStore();
    Completer<SubscriptionStatusResult>? pending;
    await _mount(
        tester, store, () => pending?.future ?? Future.value(_subscription()));
    pending = Completer<SubscriptionStatusResult>();
    final add = find.byKey(const ValueKey('link-in-bio-add'));
    await showBioControl(tester, add);
    await tester.tap(add);
    await tester.tap(add);
    await tester.pump();
    expect(find.byKey(const ValueKey('link-in-bio-link-sheet')), findsNothing);
    pending.complete(_subscription());
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('link-in-bio-link-sheet')), findsOneWidget);
    await _fillNewLink(tester);
    pending = Completer<SubscriptionStatusResult>();
    final save = find.byKey(const ValueKey('link-in-bio-link-save'));
    await showBioControl(tester, save);
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();
    expect(store.draft.customLinks.length, 1);
    pending.complete(_subscription());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-in-bio-link-sheet')), findsNothing);
    expect(store.draft.customLinks.length, 2);
    expect(
        store.draft.customLinks
            .where((link) => link.title == 'ลิงก์ใหม่')
            .length,
        1);
    expect(tester.takeException(), isNull);
  });
}
