import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:postdee_mobile/features/shared/postdee_press_feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _section(int step) => _key('link-in-bio-section-motion-$step');

const _links = [
  LinkInBioCustomLink(
      id: 'shop', title: 'ร้าน Shopee', url: 'https://shopee.co.th/mina'),
  LinkInBioCustomLink(
      id: 'chat', title: 'ติดต่อ LINE', url: 'https://line.me/mina'),
  LinkInBioCustomLink(
      id: 'off', title: 'โปรโมชั่น', url: 'https://example.com/promo'),
];
const _draft = LinkInBioDraft(
    storeName: 'ร้านมินา',
    slug: 'mina-shop',
    autoUpdateFromScheduledPosts: false,
    enabledLinkIds: {'shop', 'chat'},
    customLinks: _links);

class _DraftStore implements LinkInBioDraftStore {
  LinkInBioDraft saved = _draft;
  final List<LinkInBioDraft> requests = [];
  Completer<void>? gate;
  int get saves => requests.length;

  @override
  Future<LinkInBioDraft?> loadDraft() async => saved;

  @override
  Future<void> saveDraft(LinkInBioDraft value) async {
    requests.add(value);
    await gate?.future;
    saved = value;
  }
}

class _Fixture {
  final store = _DraftStore();
  var publications = 0;
  var unpublications = 0;
  var copies = 0;
  var opens = 0;
  var images = 0;
  var backs = 0;

  Widget app({
    bool reduced = false,
    bool active = true,
    bool ticker = true,
    double textScale = 1,
  }) =>
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: TickerMode(
          enabled: ticker,
          child: LinkInBioScreen(
            draftStore: store,
            embeddedInTab: true,
            isActive: active,
            onBack: () => backs++,
            loadProfile: () async => null,
            publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async {
              publications++;
              throw StateError('UI feedback must not publish');
            },
            unpublishProfile: () async {
              unpublications++;
              throw StateError('UI feedback must not unpublish');
            },
            copyLink: (_) async => copies++,
            openLink: (_) async {
              opens++;
              return true;
            },
            pickImage: () async {
              images++;
              return null;
            },
          ),
        ),
      );

  void expectNoRemoteActions() {
    expect(publications, 0);
    expect(unpublications, 0);
    expect(copies, 0);
    expect(opens, 0);
    expect(images, 0);
  }
}

Future<void> _mount(WidgetTester tester, _Fixture fixture,
    {double width = 393, bool reduced = false, double textScale = 1}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(fixture.app(reduced: reduced, textScale: textScale));
  await tester.pumpAndSettle();
}

Finder _feedback(Finder control) => find
    .ancestor(of: control, matching: find.byType(PostDeePressFeedback))
    .first;

double _scale(WidgetTester tester, Finder control) => tester
    .widget<Transform>(find
        .descendant(
            of: _feedback(control), matching: _key('postdee-press-transform'))
        .first)
    .transform
    .storage[0];

double _opacity(WidgetTester tester, int step) => tester
    .widget<Opacity>(find
        .descendant(of: _section(step), matching: find.byType(Opacity))
        .first)
    .opacity;

Future<void> _enterInfo(WidgetTester tester) async {
  await showBioControl(tester, _key('link-in-bio-step-info'));
  await tester.tap(_key('link-in-bio-step-info'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _resume(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
    });
    sessions.signIn(
        const AuthSession(userId: 'seller-a', idToken: 'motion-test-token'));
  });

  testWidgets(
      'manager press cancels safely and keeps button semantics and edge taps',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final semantics = tester.ensureSemantics();
    try {
      final info = _key('link-in-bio-step-info');
      final data = tester.getSemantics(info).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, contains('ข้อมูลร้าน'));
      final rect = tester.getRect(info);
      final gesture = await tester.startGesture(rect.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(_scale(tester, info), lessThan(1));
      expect(_section(1), findsOneWidget);
      expect(_key('link-in-bio-store-name'), findsNothing);
      expect(fixture.store.saves, 0);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_scale(tester, info), 1);
      expect(tester.getSize(info), rect.size);
      await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
      await tester.pumpAndSettle();
      expect(_section(0), findsOneWidget);
      expect(_key('link-in-bio-store-name'), findsOneWidget);
      expect(fixture.store.saves, 0);
      fixture.expectNoRemoteActions();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('section entrance keeps only the current form and finishes once',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final semantics = tester.ensureSemantics();
    try {
      await _enterInfo(tester);
      expect(_section(0), findsOneWidget);
      expect(_section(1), findsNothing);
      expect(_opacity(tester, 0), inExclusiveRange(0, 1));
      expect(_key('link-in-bio-add'), findsNothing);
      expect(_key('link-in-bio-store-name'), findsOneWidget);
      await tester.tap(_key('link-in-bio-close-editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_section(1), findsOneWidget);
      expect(_section(0), findsNothing);
      expect(_key('link-in-bio-store-name'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^ชื่อร้าน')), findsNothing);
      expect(_opacity(tester, 1), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(_opacity(tester, 1), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(fixture.store.saves, 0);
      fixture.expectNoRemoteActions();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('cancelled Add Link sheet never auto saves or publishes',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final add = _key('link-in-bio-add');
    final gesture = await tester.startGesture(tester.getCenter(add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_scale(tester, add), lessThan(1));
    expect(_key('link-in-bio-link-sheet'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.enterText(
        _key('link-in-bio-link-title'), 'ลิงก์ที่ยังไม่บันทึก');
    await tester.enterText(
        _key('link-in-bio-link-url'), 'https://example.com/cancelled');
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(_key('link-in-bio-link-sheet'), findsNothing);
    expect(_section(1), findsOneWidget);
    expect(fixture.store.saves, 0);
    expect(fixture.store.saved.customLinks.map((link) => link.id),
        ['shop', 'chat', 'off']);
    expect(find.text('ลิงก์ที่ยังไม่บันทึก'), findsNothing);
    fixture.expectNoRemoteActions();
  });

  testWidgets('Add Link save feedback keeps its one real persistence callback',
      (tester) async {
    final fixture = _Fixture();
    fixture.store.gate = Completer<void>();
    await _mount(tester, fixture);
    await tapBioControl(tester, 'link-in-bio-add');
    await tester.enterText(_key('link-in-bio-link-title'), 'ร้านใหม่');
    await tester.enterText(
        _key('link-in-bio-link-url'), 'https://example.com/new');
    final save = _key('link-in-bio-link-save');
    final gesture = await tester.startGesture(tester.getCenter(save));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(_scale(tester, save), lessThan(1));
    expect(fixture.store.saves, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.store.saves, 1);
    expect(fixture.store.saved.customLinks, hasLength(3));
    expect(fixture.store.requests.single.customLinks.last.title, 'ร้านใหม่');
    fixture.store.gate!.complete();
    await tester.pumpAndSettle();
    expect(fixture.store.saved.customLinks, hasLength(4));
    expect(fixture.store.saved.enabledLinkIds,
        contains(fixture.store.saved.customLinks.last.id));
    expect(fixture.store.saves, 1);
    fixture.expectNoRemoteActions();
  });

  testWidgets('footer save press preserves pending and confirmed local data',
      (tester) async {
    final fixture = _Fixture();
    fixture.store.gate = Completer<void>();
    await _mount(tester, fixture);
    final save = _key('link-in-bio-save');
    final gesture = await tester.startGesture(tester.getCenter(save));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_scale(tester, save), lessThan(1));
    expect(fixture.store.saves, 0);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fixture.store.saves, 1);
    expect(tester.widget<OutlinedButton>(save).onPressed, isNull);
    fixture.store.gate!.complete();
    await tester.pumpAndSettle();
    expect(fixture.store.saved.storeName, 'ร้านมินา');
    expect(fixture.store.saved.enabledLinkIds, {'shop', 'chat'});
    expect(fixture.store.saves, 1);
    expect(find.text('บันทึกแบบร่างในเครื่องแล้ว'), findsOneWidget);
    fixture.expectNoRemoteActions();
  });

  testWidgets(
      'mid press reduction ticker disable and inactive tab release motion',
      (tester) async {
    for (final mode in ['reduced', 'ticker', 'inactive']) {
      final fixture = _Fixture();
      await _mount(tester, fixture);
      final info = _key('link-in-bio-step-info');
      final gesture = await tester.startGesture(tester.getCenter(info));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(_scale(tester, info), lessThan(1));
      await tester.pumpWidget(fixture.app(
          reduced: mode == 'reduced',
          ticker: mode != 'ticker',
          active: mode != 'inactive'));
      await tester.pumpAndSettle();
      expect(_scale(tester, info), 1, reason: mode);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: mode);
      expect(_section(1), findsOneWidget);
      expect(fixture.store.saves, 0);
      fixture.expectNoRemoteActions();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'mid section reduction preserves the field and never replays on enable',
      (tester) async {
    for (final mode in ['reduced', 'ticker', 'inactive']) {
      final fixture = _Fixture();
      await _mount(tester, fixture);
      await _enterInfo(tester);
      expect(_opacity(tester, 0), inExclusiveRange(0, 1));
      final editable = find.descendant(
          of: _key('link-in-bio-store-name'),
          matching: find.byType(EditableText));
      final before = tester.state<EditableTextState>(editable);
      await tester.pumpWidget(fixture.app(
          reduced: mode == 'reduced',
          ticker: mode != 'ticker',
          active: mode != 'inactive'));
      await tester.pumpAndSettle();
      expect(_opacity(tester, 0), 1, reason: mode);
      expect(tester.state<EditableTextState>(editable), same(before));
      expect(
          tester
              .widget<TextField>(_key('link-in-bio-store-name'))
              .controller!
              .text,
          'ร้านมินา');
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      expect(_opacity(tester, 0), 1);
      expect(tester.state<EditableTextState>(editable), same(before));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(fixture.store.saves, 0);
      fixture.expectNoRemoteActions();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'inactive and background lifecycle stop motion without late navigation',
      (tester) async {
    addTearDown(() => _resume(tester));
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _enterInfo(tester);
    expect(_opacity(tester, 0), inExclusiveRange(0, 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(_opacity(tester, 0), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(_opacity(tester, 0), 1);
    expect(_key('link-in-bio-store-name'), findsOneWidget);
    expect(_section(1), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(fixture.store.saves, 0);
    fixture.expectNoRemoteActions();
  });

  testWidgets(
      'drag proxy respects reduced motion and retains real reorder data',
      (tester) async {
    for (final reduced in [false, true]) {
      final fixture = _Fixture();
      await _mount(tester, fixture, reduced: reduced);
      final first = _key('link-in-bio-card-shop');
      final second = _key('link-in-bio-card-chat');
      await showBioControl(tester, second);
      final handle = _key('link-in-bio-drag-shop');
      expect(handle.hitTestable(), findsOneWidget);
      final distance = tester.getCenter(second).dy - tester.getCenter(first).dy;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final proxy = _key('link-in-bio-drag-proxy');
      expect(proxy, findsOneWidget);
      final elevation = tester.widget<Material>(proxy).elevation;
      expect(elevation, reduced ? equals(0) : greaterThan(0));
      for (var frame = 0; frame < 10; frame++) {
        await gesture.moveBy(Offset(0, distance / 10));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fixture.store.saved.customLinks.map((link) => link.id),
          ['chat', 'shop', 'off']);
      expect(fixture.store.saved.enabledLinkIds, {'shop', 'chat'});
      expect(fixture.store.saves, 1);
      expect(proxy, findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      fixture.expectNoRemoteActions();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final mode in ['reduced', 'ticker', 'inactive', 'lifecycle']) {
    testWidgets('mid drag $mode stops proxy motion without saving',
        (tester) async {
      addTearDown(() => _resume(tester));
      final fixture = _Fixture();
      await _mount(tester, fixture);
      await showBioControl(tester, _key('link-in-bio-card-chat'));
      final handle = _key('link-in-bio-drag-shop');
      expect(handle.hitTestable(), findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      try {
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        final proxy = _key('link-in-bio-drag-proxy');
        expect(proxy, findsOneWidget);
        expect(tester.widget<Material>(proxy).elevation, greaterThan(0));
        expect(fixture.store.saves, 0);
        if (mode == 'lifecycle') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        } else {
          await tester.pumpWidget(fixture.app(
              reduced: mode == 'reduced',
              ticker: mode != 'ticker',
              active: mode != 'inactive'));
        }
        await tester.pumpAndSettle();
        expect(proxy, findsOneWidget);
        expect(tester.widget<Material>(proxy).elevation, 0, reason: mode);
        expect(tester.binding.hasScheduledFrame, isFalse, reason: mode);
        expect(fixture.store.saves, 0);
        if (mode == 'lifecycle') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pumpAndSettle();
          expect(tester.binding.hasScheduledFrame, isFalse);
        }
      } finally {
        _resume(tester);
        await tester.pumpWidget(fixture.app());
        await gesture.cancel();
        await tester.pumpAndSettle();
      }
      expect(_key('link-in-bio-drag-proxy'), findsNothing);
      expect(fixture.store.saved.customLinks.map((link) => link.id),
          ['shop', 'chat', 'off']);
      expect(fixture.store.saved.enabledLinkIds, {'shop', 'chat'});
      expect(fixture.store.saves, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      fixture.expectNoRemoteActions();
    });
  }

  testWidgets('320 width large text keeps toggle truth and finite motion',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, width: 320, textScale: 1.8);
    expect(_section(1), findsOneWidget);
    final toggle = _key('link-in-bio-toggle-shop');
    await showBioControl(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(fixture.store.saved.enabledLinkIds, {'chat'});
    expect(
        find.descendant(
            of: _key('link-in-bio-card-shop'), matching: find.text('ซ่อนอยู่')),
        findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(fixture.store.saved.enabledLinkIds, {'shop', 'chat'});
    expect(
        find.descendant(
            of: _key('link-in-bio-card-shop'), matching: find.text('ซ่อนอยู่')),
        findsNothing);
    expect(fixture.store.saves, 2);
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    fixture.expectNoRemoteActions();
  });
}
