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

const _store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
SubscriptionStatusResult _subscription(String plan) => SubscriptionStatusResult(
    userId: 'seller-a',
    plan: plan,
    status: 'ACTIVE',
    canSchedule: false,
    canUseAiCaptions: false,
    canUseAnalytics: false);
LinkInBioDraft _draft(int count, {int? enabled}) => LinkInBioDraft(
        storeName: 'ร้านทดสอบ',
        slug: 'quota-shop',
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: {
          for (var i = 0; i < (enabled ?? count); i++) 'link-$i'
        },
        customLinks: [
          for (var i = 0; i < count; i++)
            LinkInBioCustomLink(
                id: 'link-$i', title: 'ลิงก์ $i', url: 'https://example.com/$i')
        ]);
LinkInBioProfileResult _profile(List<LinkInBioLinkResult> links) =>
    LinkInBioProfileResult(
        storeName: 'ร้านทดสอบ',
        slug: 'quota-shop',
        links: links,
        isPublished: true,
        updatedAt: DateTime.utc(2026, 10, 26),
        publishedAt: DateTime.utc(2026, 10, 26),
        publicPath: '/p/quota-shop',
        publicUrl: Uri.parse('https://example.com/p/quota-shop'));
Future<void> _mount(WidgetTester tester, LinkInBioScreen screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  await tester.pumpAndSettle();
}

Future<void> _enterLink(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const ValueKey('link-in-bio-link-title')), 'ลิงก์ใหม่');
  await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-url')),
      'https://example.com/new');
}

Future<void> _toggle(WidgetTester tester, String id) async {
  await showBioStep(tester, 'links');
  final toggle = find.byKey(ValueKey('link-in-bio-toggle-$id'));
  await tester.scrollUntilVisible(toggle, 200,
      scrollable: find
          .descendant(
              of: find.byKey(const ValueKey('link-in-bio-content')),
              matching: find.byType(Scrollable))
          .first);
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  await tester.drag(
      find.byKey(const ValueKey('link-in-bio-content')), const Offset(0, 1000));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  for (final (plan, limit) in [('BASIC', 2), ('STARTER', 7), ('PRO', 20)]) {
    testWidgets('$plan allows its final slot and blocks the next addition',
        (tester) async {
      await _store.saveDraft(_draft(limit - 1));
      await _mount(
          tester,
          LinkInBioScreen(
              loadProfile: () async => null,
              loadSubscription: () async => _subscription(plan)));
      expect(find.text('${limit - 1}/$limit'), findsOneWidget);
      await tapBioControl(tester, 'link-in-bio-add');
      await _enterLink(tester);
      await tapBioControl(tester, 'link-in-bio-link-save');
      expect((await _store.loadDraft())!.customLinks.length, limit);
      await tapBioControl(tester, 'link-in-bio-add');
      expect(
          find.byKey(const ValueKey('link-in-bio-link-sheet')), findsNothing);
      expect((await _store.loadDraft())!.customLinks.length, limit);
      expect(find.textContaining('สูงสุด $limit ลิงก์'), findsWidgets);
    });
  }

  testWidgets('disabled stored links still consume addition slots',
      (tester) async {
    await _store.saveDraft(_draft(2, enabled: 1));
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => null,
            loadSubscription: () async => _subscription('BASIC')));
    await tapBioControl(tester, 'link-in-bio-add');
    expect(find.byKey(const ValueKey('link-in-bio-link-sheet')), findsNothing);
    expect((await _store.loadDraft())!.customLinks.length, 2);
  });

  testWidgets(
      'downgrade during add keeps typed data in the sheet and can retry after upgrade',
      (tester) async {
    var plan = 'PRO';
    await _store.saveDraft(_draft(2));
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => null,
            loadSubscription: () async => _subscription(plan)));
    await tapBioControl(tester, 'link-in-bio-add');
    await _enterLink(tester);
    plan = 'BASIC';
    await tapBioControl(tester, 'link-in-bio-link-save');
    expect(
        find.byKey(const ValueKey('link-in-bio-link-sheet')), findsOneWidget);
    expect(find.text('ลิงก์ใหม่'), findsOneWidget);
    expect((await _store.loadDraft())!.customLinks.length, 2);
    plan = 'STARTER';
    await tapBioControl(tester, 'link-in-bio-link-save');
    expect(find.byKey(const ValueKey('link-in-bio-link-sheet')), findsNothing);
    expect((await _store.loadDraft())!.customLinks.length, 3);
  });

  testWidgets(
      'failed entitlement blocks add and publish but keeps local editing and retry',
      (tester) async {
    var fail = true;
    var publications = 0;
    await _store.saveDraft(_draft(1));
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => null,
            loadSubscription: () async {
              if (fail) throw StateError('offline');
              return _subscription('BASIC');
            },
            publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async {
              publications++;
              return _profile(links);
            }));
    await tapBioControl(tester, 'link-in-bio-add');
    expect(find.byKey(const ValueKey('link-in-bio-link-sheet')), findsNothing);
    await tapBioControl(tester, 'link-in-bio-edit-link-0');
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-link-title')), 'แก้ไขออฟไลน์');
    await tapBioControl(tester, 'link-in-bio-link-save');
    expect(
        (await _store.loadDraft())!.customLinks.single.title, 'แก้ไขออฟไลน์');
    await showBioStep(tester, 'review');
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(publications, 0);
    expect(find.textContaining('ยังตรวจสอบสิทธิ์ลิงก์ไม่ได้'), findsWidgets);
    fail = false;
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(publications, 1);
  });

  testWidgets(
      'downgrade blocks publication then publishes selected subset without deleting legacy links',
      (tester) async {
    var plan = 'PRO';
    var publications = 0;
    await _store.saveDraft(_draft(3));
    await _mount(
        tester,
        LinkInBioScreen(
            loadProfile: () async => _profile([
                  for (final link in _draft(3).customLinks)
                    LinkInBioLinkResult(
                        id: link.id, title: link.title, url: link.url)
                ]),
            loadSubscription: () async => _subscription(plan),
            publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async {
              publications++;
              expect(links.length, 2);
              return _profile(links);
            }));
    plan = 'BASIC';
    await showBioStep(tester, 'review');
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(publications, 0);
    expect(find.textContaining('เปิดใช้ได้สูงสุด 2 ลิงก์'), findsWidgets);
    await showBioStep(tester, 'links');
    await _toggle(tester, 'link-2');
    await showBioStep(tester, 'review');
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(publications, 1);
    final saved = (await _store.loadDraft())!;
    expect(saved.customLinks.length, 3);
    expect(saved.enabledLinkIds.length, 2);
    await _toggle(tester, 'link-2');
    expect((await _store.loadDraft())!.enabledLinkIds.length, 2);
  });

  for (final (status, code) in [
    (403, 'LINK_IN_BIO_LINK_LIMIT_EXCEEDED'),
    (503, 'LINK_IN_BIO_ENTITLEMENTS_UNAVAILABLE')
  ]) {
    testWidgets(
        'authoritative API $code rejection stays definite and allows retry',
        (tester) async {
      var publications = 0;
      await _store.saveDraft(_draft(2));
      await _mount(
          tester,
          LinkInBioScreen(
              loadProfile: () async => null,
              loadSubscription: () async => _subscription('BASIC'),
              publishProfile: (
                  {required storeName,
                  required slug,
                  required links,
                  appearance}) async {
                if (++publications == 1) {
                  throw ApiException(
                      'ตรวจสอบสิทธิ์ลิงก์ร้านไม่ได้ กรุณาลองใหม่',
                      statusCode: status,
                      code: code);
                }
                return _profile(links);
              }));
      await showBioStep(tester, 'review');
      await tapBioControl(tester, 'link-in-bio-publish');
      expect(find.textContaining('ยังไม่ทราบผลการเผยแพร่'), findsNothing);
      await tapBioControl(tester, 'link-in-bio-publish');
      expect(publications, 2);
    });
  }

  testWidgets(
      'late paid entitlement after account change cannot add or restore private draft',
      (tester) async {
    final pending = Completer<SubscriptionStatusResult>();
    await _store.saveDraft(_draft(2));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: LinkInBioScreen(
            loadProfile: () async => null,
            loadSubscription: () => pending.future)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-b', idToken: 'other'));
    pending.complete(_subscription('PRO'));
    await tester.pumpAndSettle();
    expect(find.text('บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าลิงก์ร้านอีกครั้ง'),
        findsOneWidget);
    expect(find.text('2/20'), findsNothing);
    final add = tester
        .widget<FilledButton>(find.byKey(const ValueKey('link-in-bio-add')));
    expect(add.onPressed, isNull);
    expect((await _store.loadDraft())!.customLinks.length, 2);
  });
}
