import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_preview.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

const _owner = 'theme-member-owner';
const _premium = 'dimensional-clay-mint';

class _Drafts implements LinkInBioDraftStore {
  _Drafts({LinkInBioAppearance appearance = const LinkInBioAppearance()})
      : value = LinkInBioDraft(
            storeName: 'ร้านของฉัน',
            slug: 'theme-shop',
            autoUpdateFromScheduledPosts: false,
            customLinks: const [
              LinkInBioCustomLink(
                  id: 'shop', title: 'สินค้า', url: 'https://example.com/shop')
            ],
            enabledLinkIds: {'shop'},
            appearance: appearance);
  LinkInBioDraft value;
  int writes = 0;
  @override
  Future<LinkInBioDraft?> loadDraft() async => value;
  @override
  Future<void> saveDraft(LinkInBioDraft draft) async {
    value = draft;
    writes++;
  }
}

class _Fixture {
  _Fixture({LinkInBioAppearance appearance = const LinkInBioAppearance()})
      : drafts = _Drafts(appearance: appearance);
  final _Drafts drafts;
  final sessions = PostDeeAuthSessionStore(
      initialSession: const AuthSession(userId: _owner, idToken: 'fixture'));
  String plan = 'BASIC';
  String? purchasedPlan;
  String status = 'ACTIVE';
  bool allowed = false;
  bool fail = false;
  Future<SubscriptionStatusResult>? gate;
  int reads = 0;
  int publications = 0;
  LinkInBioAppearance? published;
  LinkInBioProfileResult? profile;
  int planVisits = 0;
  SubscriptionStatusResult subscription() => SubscriptionStatusResult(
      userId: _owner,
      plan: plan,
      purchasedPlan: purchasedPlan,
      status: status,
      canUsePremiumProfileThemes: allowed,
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false);
  LinkInBioProfileResult result(LinkInBioAppearance appearance) =>
      LinkInBioProfileResult(
          storeName: drafts.value.storeName,
          slug: 'theme-shop',
          links: const [
            LinkInBioLinkResult(
                id: 'shop', title: 'สินค้า', url: 'https://example.com/shop')
          ],
          appearance: appearance,
          isPublished: true,
          updatedAt: DateTime.utc(2026, 11, 3),
          publicPath: '/p/theme-shop',
          publicUrl: Uri.parse('https://example.com/p/theme-shop'));
  Widget app({String language = 'th', bool dark = false, double scale = 1}) {
    AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    return MaterialApp(
        locale: Locale(language),
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: true, textScaler: TextScaler.linear(scale)),
            child: child!),
        home: LinkInBioScreen(
            sessionStore: sessions,
            draftStore: drafts,
            loadProfile: () async => profile,
            loadImage: (_) async => base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
            loadSubscription: () async {
              reads++;
              if (fail) throw StateError('offline');
              return gate == null ? subscription() : await gate!;
            },
            openMembershipPlans: () async {
              planVisits++;
              allowed = true;
              plan = 'STARTER';
            },
            protectDraftImages: (
                {required draftId, required keys, required mode}) async {},
            publishProfile: (
                {required storeName,
                required slug,
                required links,
                appearance}) async {
              publications++;
              published = appearance;
              return result(appearance!);
            }));
  }

  void dispose() => sessions.dispose();
}

Finder _key(String name) => find.byKey(ValueKey(name));
Future<void> _theme(WidgetTester tester) async => showBioStep(tester, 'theme');
Future<void> _openPremium(WidgetTester tester) async {
  await _theme(tester);
  await tapBioControl(tester, 'link-in-bio-category-dimensional');
  final card = _key('link-in-bio-template-$_premium');
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  final scrollable =
      find.ancestor(of: card, matching: find.byType(Scrollable)).first;
  final visible = tester.getRect(card).intersect(tester.getRect(scrollable));
  expect(visible.isEmpty, isFalse);
  await tester.tapAt(visible.center);
  await tester.pumpAndSettle();
}

LinkInBioAppearance _preview(WidgetTester tester) => tester
    .widget<LinkInBioPreview>(find.byType(LinkInBioPreview).first)
    .appearance;

void main() {
  final previewDirectory =
      Platform.environment['POSTDEE_THEME_ACCESS_PREVIEW_DIR'];
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));
  testWidgets(
      'expired premium can remove a hidden background image without changing its style',
      (tester) async {
    final original = LinkInBioAppearance.forTemplate(_premium).copyWith(
        background: const LinkInBioBackground(
            mode: 'gradient',
            imageKey:
                'uploads/theme-member-owner/12345678-1234-1234-1234-123456789abc/profile-background.png'));
    final fixture = _Fixture(appearance: original);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tapBioControl(tester, 'link-in-bio-decorate');
    await showBioControl(tester, _key('link-in-bio-disclosure-images'));
    await tester.tap(_key('link-in-bio-disclosure-images'));
    await tester.pumpAndSettle();
    final remove = find.widgetWithText(TextButton, 'ลบภาพพื้นหลัง');
    await showBioControl(tester, remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(_key('link-in-bio-decoration-done'));
    await tester.pumpAndSettle();
    expect(
        fixture.drafts.value.appearance.toJson(),
        original
            .copyWith(background: original.background.copyWith(imageKey: null))
            .toJson());
  });
  testWidgets(
      'full preview repaints on membership revoke and restore while open',
      (tester) async {
    final original = LinkInBioAppearance.forTemplate(_premium);
    final fixture = _Fixture(appearance: original)
      ..plan = 'PRO'
      ..allowed = true;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tapBioControl(tester, 'link-in-bio-preview');
    final page = find.descendant(
        of: _key('link-in-bio-full-preview'),
        matching: find.byType(LinkInBioPreview));
    expect(
        tester.widget<LinkInBioPreview>(page).appearance.templateId, _premium);
    fixture.allowed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.widget<LinkInBioPreview>(page).appearance.templateId, isNull);
    expect(
        tester.widget<Dialog>(_key('link-in-bio-full-preview')).backgroundColor,
        bioColor(const LinkInBioAppearance().background.color));
    fixture.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
        tester.widget<LinkInBioPreview>(page).appearance.templateId, _premium);
    expect(fixture.drafts.value.appearance.toJson(), original.toJson());
    expect(fixture.drafts.writes, 0);
  });
  test('legacy API has no premium membership grant', () {
    final dto = SubscriptionStatusResult.fromJson({
      'userId': _owner,
      'plan': 'PRO',
      'status': 'ACTIVE',
      'canSchedule': true,
      'canUseAiCaptions': true,
      'canUseAnalytics': false
    });
    expect(dto.canUsePremiumProfileThemes, isFalse);
  });

  for (final language in ['th', 'en']) {
    testWidgets(
        'expired saved theme is described separately from the temporary preview ($language)',
        (tester) async {
      final fixture =
          _Fixture(appearance: LinkInBioAppearance.forTemplate(_premium));
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app(language: language));
      await tester.pumpAndSettle();
      await _theme(tester);
      final label =
          tester.widget<Text>(_key('link-in-bio-saved-theme-membership')).data!;
      expect(
          label,
          contains(language == 'th'
              ? 'ขณะนี้ใช้ธีมเรียบง่ายชั่วคราว'
            : 'Using Minimal temporarily.'));
      expect(_preview(tester).templateId, isNull);
      expect(fixture.drafts.value.appearance.templateId, _premium);
      expect(fixture.drafts.writes, 0);
    });
    testWidgets('Basic can preview premium but cannot apply ($language)',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app(language: language));
      await tester.pumpAndSettle();
      await _openPremium(tester);
      expect(_key('link-in-bio-template-membership-required'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(_key('link-in-bio-template-use'))
              .onPressed,
          isNull);
      expect(find.text(language == 'th' ? 'ธีมสำหรับสมาชิก' : 'Member theme'),
          findsWidgets);
      expect(fixture.drafts.value.appearance.templateId, isNull);
      expect(fixture.drafts.writes, 0);
      expect(fixture.publications, 0);
    });
  }

  for (final plan in ['STARTER', 'PRO', 'BUSINESS']) {
    testWidgets('$plan applies premium only after a fresh authoritative read',
        (tester) async {
      final fixture = _Fixture()
        ..plan = plan
        ..allowed = true;
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _openPremium(tester);
      final initialReads = fixture.reads;
      await tester.tap(_key('link-in-bio-template-use'));
      await tester.pumpAndSettle();
      expect(fixture.reads, greaterThan(initialReads));
      expect(fixture.drafts.value.appearance.templateId, _premium);
      expect(fixture.drafts.value.customLinks.single.title, 'สินค้า');
    });
  }

  testWidgets(
      'membership expiring while preview is open prevents premium apply',
      (tester) async {
    final fixture = _Fixture()
      ..plan = 'PRO'
      ..allowed = true;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _openPremium(tester);
    fixture.allowed = false;
    fixture.plan = 'BASIC';
    await tester.tap(_key('link-in-bio-template-use'));
    await tester.pumpAndSettle();
    expect(fixture.drafts.value.appearance.templateId, isNull);
    expect(_key('link-in-bio-template-membership-required'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(_key('link-in-bio-template-use')).onPressed,
        isNull);
    expect(fixture.publications, 0);
  });

  testWidgets(
      'saved premium survives expiry and returns after membership resumes',
      (tester) async {
    final saved = LinkInBioAppearance.forTemplate(_premium)
        .copyWith(description: 'ข้อความเดิม');
    final fixture = _Fixture(appearance: saved);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _theme(tester);
    expect(_preview(tester).templateId, isNull);
    expect(_preview(tester).themeId, 'minimal');
    expect(_preview(tester).description, saved.description);
    expect(fixture.drafts.value.appearance.toJson(), saved.toJson());
    expect(fixture.drafts.writes, 0);
    fixture.plan = 'BUSINESS';
    fixture.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(_preview(tester).templateId, _premium);
    expect(fixture.drafts.value.appearance.toJson(), saved.toJson());
    expect(fixture.drafts.writes, 0);
  });

  testWidgets(
      'expired unchanged premium can publish content without saving fallback',
      (tester) async {
    final saved = LinkInBioAppearance.forTemplate(_premium)
        .copyWith(description: 'ข้อความใหม่');
    final fixture = _Fixture(appearance: saved);
    fixture.profile =
        fixture.result(saved.copyWith(description: 'ข้อความเดิม'));
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await showBioStep(tester, 'review');
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(fixture.publications, 1);
    expect(fixture.published!.toJson(), saved.toJson());
    expect(fixture.drafts.value.appearance.toJson(), saved.toJson());
  });

  testWidgets('expired changed premium palette cannot publish and is retained',
      (tester) async {
    final original = LinkInBioAppearance.forTemplate(_premium);
    final changed = original.copyWith(buttonColor: '#123456');
    final fixture = _Fixture(appearance: changed)..profile = null;
    fixture.profile = fixture.result(original);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await showBioStep(tester, 'review');
    await tapBioControl(tester, 'link-in-bio-publish');
    expect(fixture.publications, 0);
    expect(fixture.drafts.value.appearance.toJson(), changed.toJson());
    expect(find.textContaining('ธีมสำหรับสมาชิก'), findsWidgets);
  });

  testWidgets('return from plans refreshes the locked premium preview',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _openPremium(tester);
    await tester.tap(_key('link-in-bio-template-membership-plans'));
    await tester.pumpAndSettle();
    expect(fixture.planVisits, 1);
    expect(
        tester.widget<FilledButton>(_key('link-in-bio-template-use')).onPressed,
        isNotNull);
    await tester.tap(_key('link-in-bio-template-use'));
    await tester.pumpAndSettle();
    expect(fixture.drafts.value.appearance.templateId, _premium);
  });

  testWidgets(
      'account change while checking premium application cannot save or grant access',
      (tester) async {
    final fixture = _Fixture()
      ..plan = 'PRO'
      ..allowed = true;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _openPremium(tester);
    final response = Completer<SubscriptionStatusResult>();
    fixture.gate = response.future;
    await tester.tap(_key('link-in-bio-template-use'));
    await tester.pump();
    expect(
        tester.widget<FilledButton>(_key('link-in-bio-template-use')).onPressed,
        isNull);
    fixture.sessions
        .signIn(const AuthSession(userId: 'next-owner', idToken: 'other'));
    response.complete(fixture.subscription());
    await tester.pumpAndSettle();
    expect(fixture.drafts.writes, 0);
    expect(fixture.drafts.value.appearance.templateId, isNull);
    expect(_key('link-in-bio-template-use'), findsNothing);
    expect(fixture.publications, 0);
  });

  testWidgets(
      'an older paid response cannot override a newer membership denial on resume',
      (tester) async {
    final original = LinkInBioAppearance.forTemplate(_premium);
    final fixture = _Fixture(appearance: original)
      ..plan = 'PRO'
      ..allowed = true;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _theme(tester);
    final old = Completer<SubscriptionStatusResult>();
    final paid = fixture.subscription();
    fixture.gate = old.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_preview(tester).templateId, isNull);
    fixture.gate = null;
    fixture.allowed = false;
    fixture.plan = 'BASIC';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    old.complete(paid);
    await tester.pumpAndSettle();
    expect(_preview(tester).templateId, isNull);
    expect(fixture.drafts.value.appearance.toJson(), original.toJson());
    expect(fixture.drafts.writes, 0);
  });

  testWidgets(
      'failed membership lookup locks premium and a successful retry restores it',
      (tester) async {
    final fixture = _Fixture()
      ..plan = 'PRO'
      ..allowed = true
      ..fail = true;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _openPremium(tester);
    expect(
        tester.widget<FilledButton>(_key('link-in-bio-template-use')).onPressed,
        isNull);
    fixture.fail = false;
    await tester.tap(_key('link-in-bio-template-membership-retry'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<FilledButton>(_key('link-in-bio-template-use')).onPressed,
        isNotNull);
    expect(fixture.drafts.writes, 0);
  });

  testWidgets(
      'an explicit free theme choice survives later membership restoration',
      (tester) async {
    final fixture =
        _Fixture(appearance: LinkInBioAppearance.forTemplate(_premium));
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _theme(tester);
    await tapBioControl(tester, 'link-in-bio-category-minimal');
    await tapBioControl(tester, 'link-in-bio-template-minimal-white-editorial');
    await tester.tap(_key('link-in-bio-template-use'));
    await tester.pumpAndSettle();
    fixture.plan = 'PRO';
    fixture.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(_preview(tester).templateId, 'minimal-white-editorial');
    expect(
        fixture.drafts.value.appearance.templateId, 'minimal-white-editorial');
  });

  testWidgets(
      'expired premium locks styling but keeps description editable in the draft',
      (tester) async {
    final original = LinkInBioAppearance.forTemplate(_premium)
        .copyWith(description: 'ข้อความเดิม');
    final fixture = _Fixture(appearance: original);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tapBioControl(tester, 'link-in-bio-decorate');
    expect(_key('link-in-bio-premium-style-locked'), findsOneWidget);
    expect(
        tester
            .widget<ExpansionTile>(_key('link-in-bio-disclosure-buttons'))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<ExpansionTile>(_key('link-in-bio-disclosure-styles'))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<ExpansionTile>(_key('link-in-bio-disclosure-effects'))
            .enabled,
        isFalse);
    await showBioControl(tester, _key('link-in-bio-disclosure-images'));
    await tester.tap(_key('link-in-bio-disclosure-images'));
    await tester.pumpAndSettle();
    await showBioControl(tester, _key('link-in-bio-description'));
    await tester.enterText(_key('link-in-bio-description'), 'ข้อความใหม่');
    await tester.tap(_key('link-in-bio-decoration-done'));
    await tester.pumpAndSettle();
    expect(fixture.drafts.value.appearance.toJson(),
        original.copyWith(description: 'ข้อความใหม่').toJson());
  });

  for (final language in ['th', 'en']) {
    for (final dark in [false, true]) {
      testWidgets('locked member preview fits 320dp 2x ($language dark=$dark)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        await tester
            .pumpWidget(fixture.app(language: language, dark: dark, scale: 2));
        await tester.pumpAndSettle();
        await _openPremium(tester);
        expect(
            _key('link-in-bio-template-membership-required'), findsOneWidget);
        expect(
            tester
                .widget<FilledButton>(_key('link-in-bio-template-use'))
                .onPressed,
            isNull);
        expect(tester.takeException(), isNull);
        expect(fixture.drafts.writes, 0);
      });
    }
  }

  testWidgets('offline Thai locked theme preview fixture', (tester) async {
    tester.view.physicalSize = const Size(376, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    // Offline fixture only; no store account, checkout or public site is used.
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final boundaryKey = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: boundaryKey, child: fixture.app()));
    await tester.pumpAndSettle();
    await _openPremium(tester);
    expect(
        tester.widget<FilledButton>(_key('link-in-bio-template-use')).onPressed,
        isNull);
    expect(fixture.drafts.writes, 0);
    expect(tester.takeException(), isNull);
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(previewDirectory!);
        await directory.create(recursive: true);
        await File('${directory.path}/member-theme-locked-th.png')
            .writeAsBytes(png!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }, skip: previewDirectory == null);
}
