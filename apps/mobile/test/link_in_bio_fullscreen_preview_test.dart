import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

class _DraftStore implements LinkInBioDraftStore {
  _DraftStore({int count = 2})
      : draft = LinkInBioDraft(
            storeName: 'ร้านเดิมของเรา',
            slug: 'our-shop',
            autoUpdateFromScheduledPosts: false,
            appearance:
                LinkInBioAppearance.forTemplate('minimal-white-editorial')
                    .copyWith(effects: const LinkInBioEffects()),
            enabledLinkIds: {
              for (var i = 1; i <= count; i++) 'link-$i'
            },
            customLinks: [
              for (var i = 1; i <= count; i++)
                LinkInBioCustomLink(
                    id: 'link-$i',
                    title: 'ลิงก์ร้าน $i',
                    url: 'https://example.com/$i')
            ]);
  LinkInBioDraft draft;
  var saves = 0;
  @override
  Future<LinkInBioDraft?> loadDraft() async => draft;
  @override
  Future<void> saveDraft(LinkInBioDraft value) async {
    draft = value;
    saves++;
  }
}

Future<GlobalKey<NavigatorState>> _mount(WidgetTester tester, _DraftStore store,
    {double width = 393}) async {
  tester.view.physicalSize = Size(width, 852);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 28, bottom: 20);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final navigation = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
      navigatorKey: navigation,
      theme: AppTheme.light,
      home: Scaffold(
          body: LinkInBioScreen(
              embeddedInTab: true,
              draftStore: store,
              loadProfile: () async => null,
              protectDraftImages: (
                  {required draftId, required keys, required mode}) async {},
              publishProfile: (
                  {required storeName,
                  required slug,
                  required links,
                  appearance}) async {
                throw StateError('Viewing a preview must not publish.');
              }),
          bottomNavigationBar: const SizedBox(
              height: 64, child: Center(child: Text('เมนูแอป'))))));
  await tester.pumpAndSettle();
  await tapBioControl(tester, 'link-in-bio-preview');
  return navigation;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'preview-owner', idToken: 'test-token'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  for (final width in [320.0, 800.0]) {
    testWidgets('full-page preview fills the app viewport at $width px',
        (tester) async {
      final store = _DraftStore();
      final original = store.draft;
      await _mount(tester, store, width: width);
      final preview = find.byKey(const ValueKey('link-in-bio-full-preview'));
      expect(preview, findsOneWidget);
      expect(tester.getRect(preview), Rect.fromLTWH(0, 0, width, 852));
      final scroll =
          find.byKey(const ValueKey('link-in-bio-full-preview-scroll'));
      expect(tester.getRect(scroll), Rect.fromLTWH(0, 0, width, 852));
      final close =
          find.byKey(const ValueKey('link-in-bio-full-preview-close'));
      final closeBounds = tester.getRect(close);
      expect(closeBounds.width, greaterThanOrEqualTo(44));
      expect(closeBounds.height, greaterThanOrEqualTo(44));
      expect(closeBounds.top, greaterThanOrEqualTo(28));
      expect(closeBounds.bottom, lessThan(832));
      expect(closeBounds.right, lessThanOrEqualTo(width));
      final page =
          find.descendant(of: preview, matching: find.byType(LinkInBioPreview));
      expect(tester.getSize(page).height, greaterThanOrEqualTo(852));
      expect(tester.widget<LinkInBioPreview>(page).storeName, 'ร้านเดิมของเรา');
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(find.byKey(const ValueKey('link-in-bio-preview')), findsOneWidget);
      expect(store.draft, same(original));
      expect(store.saves, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long full-page preview scrolls while close stays reachable',
      (tester) async {
    final store = _DraftStore(count: 20);
    await _mount(tester, store);
    final close = find.byKey(const ValueKey('link-in-bio-full-preview-close'));
    final closeBounds = tester.getRect(close);
    final scroll =
        find.byKey(const ValueKey('link-in-bio-full-preview-scroll'));
    final last =
        find.descendant(of: scroll, matching: find.text('ลิงก์ร้าน 20'));
    await tester.scrollUntilVisible(last, 450,
        scrollable: find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(852));
    expect(tester.getRect(close), closeBounds);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('link-in-bio-full-preview')), findsNothing);
    expect(store.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account changes close only the owned full-page preview',
      (tester) async {
    final navigation = await _mount(tester, _DraftStore());
    expect(
        find.byKey(const ValueKey('link-in-bio-full-preview')), findsOneWidget);
    final unrelated = showDialog<void>(
        context: navigation.currentContext!,
        builder: (_) => const AlertDialog(title: Text('หน้าต่างอื่น')));
    await tester.pumpAndSettle();
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'another-owner', idToken: 'another-token'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('link-in-bio-full-preview')), findsNothing);
    expect(find.text('ร้านเดิมของเรา'), findsNothing);
    expect(find.text('หน้าต่างอื่น'), findsOneWidget);
    expect(tester.takeException(), isNull);
    navigation.currentState!.pop();
    await tester.pumpAndSettle();
    await unrelated;
  });
}
