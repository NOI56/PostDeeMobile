import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

const bioEnglishOwner = 'english-store-owner';
const bioEnglishEmptyDraft = LinkInBioDraft(
    storeName: '',
    slug: '',
    autoUpdateFromScheduledPosts: false,
    enabledLinkIds: {},
    customLinks: []);

class BioEnglishDrafts implements LinkInBioDraftStore {
  LinkInBioDraft? value = bioEnglishEmptyDraft;
  Object? error;
  Completer<void>? gate;
  int reads = 0;
  final saves = <LinkInBioDraft>[];

  @override
  Future<LinkInBioDraft?> loadDraft() async {
    reads++;
    return value;
  }

  @override
  Future<void> saveDraft(LinkInBioDraft draft) async {
    saves.add(draft);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    value = draft;
  }
}

class BioEnglishFixture {
  BioEnglishFixture(
      {Locale locale = const Locale('en'), this.dark = false, this.scale = 1})
      : language = ValueNotifier(locale);

  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final sessions = PostDeeAuthSessionStore(
      initialSession:
          const AuthSession(userId: bioEnglishOwner, idToken: 'fake-token'));
  final drafts = BioEnglishDrafts();
  SubscriptionStatusResult subscription = const SubscriptionStatusResult(
      userId: bioEnglishOwner,
      plan: 'PRO',
      status: 'ACTIVE',
      maxProfileLinks: 20,
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true);
  LinkInBioProfileResult? profile;
  Object? profileError;
  Object? subscriptionError;
  Future<LinkInBioProfileResult?>? profileGate;
  Future<SubscriptionStatusResult>? subscriptionGate;
  int profileReads = 0;
  int subscriptionReads = 0;
  final copied = <String>[];
  final opened = <Uri>[];
  bool openResult = true;
  Object? copyError;
  Object? openError;
  final publications = <({
    String name,
    String slug,
    List<LinkInBioLinkResult> links,
    LinkInBioAppearance? appearance
  })>[];
  int unpublications = 0;
  Object? publishError;
  Object? unpublishError;
  Future<LinkInBioProfileResult>? publishGate;
  Future<LinkInBioProfileResult>? unpublishGate;
  final images = <String, Uint8List>{};
  final imageGates = <String, Future<Uint8List>>{};
  final imageReads = <String>[];

  Future<LinkInBioProfileResult?> loadProfile() async {
    profileReads++;
    if (profileError != null) throw profileError!;
    return profileGate == null ? profile : await profileGate!;
  }

  Future<SubscriptionStatusResult> loadSubscription() async {
    subscriptionReads++;
    if (subscriptionError != null) throw subscriptionError!;
    return subscriptionGate == null ? subscription : await subscriptionGate!;
  }

  Future<LinkInBioProfileResult> publish(
      {required String storeName,
      required String slug,
      required List<LinkInBioLinkResult> links,
      LinkInBioAppearance? appearance}) async {
    publications.add((
      name: storeName,
      slug: slug,
      links: List.of(links),
      appearance: appearance
    ));
    if (publishError != null) throw publishError!;
    return publishGate == null
        ? profile = BioEnglishFixture.result(
            storeName: storeName,
            slug: slug,
            links: links,
            appearance: appearance ?? const LinkInBioAppearance())
        : await publishGate!;
  }

  Future<LinkInBioProfileResult> unpublish() async {
    unpublications++;
    if (unpublishError != null) throw unpublishError!;
    return unpublishGate == null
        ? profile = BioEnglishFixture.result(published: false)
        : await unpublishGate!;
  }

  static LinkInBioProfileResult result(
          {String storeName = 'ร้านมินา',
          String slug = 'mina-shop',
          bool published = true,
          List<LinkInBioLinkResult> links = const [],
          LinkInBioAppearance appearance = const LinkInBioAppearance()}) =>
      LinkInBioProfileResult(
          storeName: storeName,
          slug: slug,
          links: links,
          isPublished: published,
          updatedAt: DateTime.utc(2026, 10, 28),
          publishedAt: published ? DateTime.utc(2026, 10, 28) : null,
          publicPath: published ? '/p/$slug' : null,
          publicUrl:
              published ? Uri.parse('https://store.example.com/p/$slug') : null,
          appearance: appearance);

  LinkInBioScreen screen() => LinkInBioScreen(
        key: const ValueKey('english-store-manager'),
        sessionStore: sessions,
        draftStore: drafts,
        loadProfile: loadProfile,
        loadSubscription: loadSubscription,
        publishProfile: publish,
        unpublishProfile: unpublish,
        copyLink: (value) async {
          copied.add(value);
          if (copyError != null) throw copyError!;
        },
        openLink: (value) async {
          opened.add(value);
          if (openError != null) throw openError!;
          return openResult;
        },
        pickImage: () async => null,
        uploadImage: ({required slot, required bytes}) async =>
            throw StateError('Unexpected image upload'),
        loadImage: (key) async {
          imageReads.add(key);
          if (imageGates.containsKey(key)) return imageGates[key]!;
          if (!images.containsKey(key)) throw StateError('Image unavailable');
          return images[key]!;
        },
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {},
      );

  Widget app() => ValueListenableBuilder<Locale>(
      valueListenable: language,
      builder: (_, locale, __) {
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        return MaterialApp(
            locale: locale,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const Scaffold(),
            initialRoute: '/store',
            routes: {'/store': (_) => screen()});
      });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  void dispose() {
    language.dispose();
    sessions.dispose();
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tapBioControl(tester, key);
}

void _readable(WidgetTester tester, Finder text) {
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first);
  final label = tester.widget<Text>(text).data;
  expect(paragraph.didExceedMaxLines, isFalse, reason: label);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5),
      reason: label);
}

Future<void> _typeWithKeyboard(
    WidgetTester tester, Finder field, String value) async {
  await showBioControl(tester, field);
  await tester.showKeyboard(field);
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.enterText(field, value);
  final editableFinder =
      find.descendant(of: field, matching: find.byType(EditableText));
  await tester.pumpAndSettle();
  await tester.ensureVisible(editableFinder);
  await tester.pumpAndSettle();
  final editable =
      tester.state<EditableTextState>(editableFinder).renderEditable;
  expect(editable.size.height,
      greaterThanOrEqualTo(editable.preferredLineHeight - 0.5));
  final controller = tester.widget<EditableText>(editableFinder).controller;
  final caret = editable.getLocalRectForCaret(
      TextPosition(offset: controller.selection.extentOffset));
  expect(caret.top, greaterThanOrEqualTo(-0.5));
  expect(caret.bottom, lessThanOrEqualTo(editable.size.height + 0.5));
  final globalCaret = caret.shift(editable.localToGlobal(Offset.zero));
  expect(globalCaret.top, greaterThanOrEqualTo(0));
  expect(globalCaret.bottom, lessThanOrEqualTo(440));
  tester.testTextInput.hide();
  tester.view.resetViewInsets();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  testWidgets('website-generated titles retain the baseline domain spelling',
      (tester) async {
    const generatedTitle =
        '%e0%b9%80%e0%b8%a3%e0%b8%b5%e0%b8%a2%e0%b8%9a%e0%b8%87%e0%b9%88%e0%b8%b2%e0%b8%a';
    final fixture = BioEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapBioControl(tester, 'link-in-bio-add');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-url')),
        'https://เรียบง่าย');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('link-in-bio-link-title')))
            .controller!
            .text,
        generatedTitle);
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapBioControl(tester, 'link-in-bio-link-save');
    expect(fixture.drafts.value!.customLinks.single.title, generatedTitle);
    expect(fixture.drafts.value!.customLinks.single.url, 'https://เรียบง่าย');
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final entry in {
    'Seller+Deals@Example.com': (
      'Send email',
      'mailto:Seller+Deals@Example.com'
    ),
    '+66812345678': ('Call the store', 'tel:+66812345678'),
  }.entries) {
    testWidgets(
        'generated contact title is English and retained on locale change: ${entry.key}',
        (tester) async {
      final fixture = BioEnglishFixture();
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      await tapBioControl(tester, 'link-in-bio-add');
      await tester.enterText(
          find.byKey(const ValueKey('link-in-bio-link-url')), entry.key);
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('link-in-bio-link-title')))
              .controller!
              .text,
          entry.value.$1);
      fixture.language.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('link-in-bio-link-title')))
              .controller!
              .text,
          entry.value.$1);
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapBioControl(tester, 'link-in-bio-link-save');
      expect(fixture.drafts.value!.customLinks.single.title, entry.value.$1);
      expect(fixture.drafts.value!.customLinks.single.url, entry.value.$2);
      expect(fixture.publications, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('English store manager names its sections and publication state',
      (tester) async {
    final fixture = BioEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Store link'), findsOneWidget);
    expect(find.text('Store info'), findsOneWidget);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Add link'), findsOneWidget);
    expect(find.text('Not published'), findsOneWidget);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English store info labels its customer data and URL fields',
      (tester) async {
    final fixture = BioEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    expect(find.text('Store info'), findsOneWidget);
    expect(find.text('Store name'), findsOneWidget);
    expect(find.text('Short store description'), findsOneWidget);
    await showBioUrlSettings(tester);
    expect(find.text('URL name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English add-link editor names its heading and save action',
      (tester) async {
    final fixture = BioEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapBioControl(tester, 'link-in-bio-add');
    expect(find.text('Add link'), findsWidgets);
    final sheet = find.byKey(const ValueKey('link-in-bio-link-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('Add link')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Save link')),
        findsOneWidget);
    expect(fixture.drafts.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty manager explains its first link without claiming publication',
      (tester) async {
    final fixture = BioEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Your store'), findsOneWidget);
    expect(find.text('Add your store\'s first link'), findsOneWidget);
    expect(find.text('For example, a store, product or contact link.'),
        findsOneWidget);
    expect(find.text('Not published'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-public-url')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'checking publication cannot claim a published or unpublished state',
      (tester) async {
    final fixture = BioEnglishFixture();
    final profile = Completer<LinkInBioProfileResult?>();
    fixture.profileGate = profile.future;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Checking website status...'), findsOneWidget);
    expect(find.text('Published'), findsNothing);
    expect(find.text('Not published'), findsNothing);
    profile.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Not published'), findsOneWidget);
    expect(fixture.profileReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored profile error changes locale without refetching private data',
      (tester) async {
    final fixture = BioEnglishFixture(locale: const Locale('th'))
      ..profileError = StateError('offline');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('ยังตรวจสถานะเว็บไซต์ไม่ได้'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not check website status'), findsOneWidget);
    expect(find.text('Could not load website status. Please try again.'),
        findsOneWidget);
    expect(find.text('Not published'), findsNothing);
    expect(fixture.profileReads, 1);
    expect(fixture.subscriptionReads, 1);
    expect(fixture.drafts.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'store info locale changes preserve raw customer fields and controller selection',
      (tester) async {
    final fixture = BioEnglishFixture();
    fixture.drafts.value = const LinkInBioDraft(
        storeName: 'ร้านของคุณ',
        slug: 'mina-shop',
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: {},
        customLinks: [],
        appearance: LinkInBioAppearance(description: 'ข้อมูลร้านภาษาไทย'));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    final field = find.byKey(const ValueKey('link-in-bio-store-name'));
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, 'ร้านของคุณ');
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ชื่อร้าน'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Store name'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller, same(controller));
    expect(controller.text, 'ร้านของคุณ');
    expect(controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4));
    expect(find.text('ข้อมูลร้านภาษาไทย'), findsOneWidget);
    expect(fixture.drafts.saves, isEmpty);
    expect(fixture.profileReads, 1);
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored link validation translates live and retains the unsafe input',
      (tester) async {
    final fixture = BioEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await _tap(tester, 'link-in-bio-add');
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-link-title')), 'ปุ่มลูกค้า');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-link-url')),
        'javascript:alert(1)');
    await _tap(tester, 'link-in-bio-link-save');
    expect(find.textContaining('ใช้ URL เต็ม'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Use a full https:// or http:// URL without a username or password, or use mailto:email / tel:phone.'),
        findsOneWidget);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('link-in-bio-link-title')))
            .controller!
            .text,
        'ปุ่มลูกค้า');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('link-in-bio-link-url')))
            .controller!
            .text,
        'javascript:alert(1)');
    expect(fixture.drafts.saves, isEmpty);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'store info required-name validation is English and does not publish',
      (tester) async {
    final fixture = BioEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    await _tap(tester, 'link-in-bio-done');
    expect(
        find.text('Enter a store name with 1–80 characters.'), findsOneWidget);
    expect(fixture.publications, isEmpty);
    expect(fixture.drafts.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fresh unsaved draft is not presented as saved or published',
      (tester) async {
    final fixture = BioEnglishFixture()..drafts.value = null;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Draft not saved yet'), findsOneWidget);
    expect(find.text('Not published'), findsOneWidget);
    expect(fixture.drafts.saves, isEmpty);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh unsaved store name starts in English without saving',
      (tester) async {
    final fixture = BioEnglishFixture()..drafts.value = null;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    final field = find.byKey(const ValueKey('link-in-bio-store-name'));
    expect(tester.widget<TextField>(field).controller!.text, 'Your store');
    expect(fixture.drafts.saves, isEmpty);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh unsaved store name follows locale without writing data',
      (tester) async {
    final fixture = BioEnglishFixture()..drafts.value = null;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    final field = find.byKey(const ValueKey('link-in-bio-store-name'));
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, 'Your store');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(controller.text, 'ร้านของคุณ');
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller, same(controller));
    expect(controller.text, 'Your store');
    expect(fixture.drafts.saves, isEmpty);
    expect(fixture.publications, isEmpty);
    expect(fixture.profileReads, 1);
    expect(fixture.subscriptionReads, 1);
    expect(fixture.drafts.reads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final name in ['ร้านของคุณ', 'ร้านที่ลูกค้าตั้งเอง']) {
    testWidgets('edited fresh store name survives locale while saving: $name',
        (tester) async {
      final fixture = BioEnglishFixture()..drafts.value = null;
      final save = Completer<void>();
      fixture.drafts.gate = save;
      addTearDown(() {
        if (!save.isCompleted) save.complete();
        fixture.dispose();
      });
      await fixture.mount(tester);
      await showBioStep(tester, 'info');
      final field = find.byKey(const ValueKey('link-in-bio-store-name'));
      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.text, 'Your store');
      await tester.enterText(field, name);
      await tester.pumpAndSettle();
      expect(fixture.drafts.value, isNull);
      expect(fixture.drafts.saves, hasLength(1));
      fixture.language.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(controller.text, name);
      fixture.language.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(controller.text, name);
      expect(fixture.drafts.saves, hasLength(1));
      expect(fixture.drafts.saves.single.storeName, name);
      save.complete();
      await tester.pumpAndSettle();
      expect(fixture.drafts.value!.storeName, name);
      expect(fixture.publications, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saving the fresh default makes it data retained across locales',
      (tester) async {
    final fixture = BioEnglishFixture()..drafts.value = null;
    final save = Completer<void>();
    fixture.drafts.gate = save;
    addTearDown(() {
      if (!save.isCompleted) save.complete();
      fixture.dispose();
    });
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    final field = find.byKey(const ValueKey('link-in-bio-store-name'));
    final controller = tester.widget<TextField>(field).controller!;
    await _tap(tester, 'link-in-bio-save-draft');
    expect(fixture.drafts.saves, hasLength(1));
    expect(fixture.drafts.saves.single.storeName, 'Your store');
    expect(fixture.drafts.value, isNull);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(controller.text, 'Your store');
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(controller.text, 'Your store');
    expect(fixture.drafts.saves, hasLength(1));
    save.complete();
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(controller.text, 'Your store');
    expect(fixture.drafts.value!.storeName, 'Your store');
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a previously loaded profile name survives a later empty refresh',
      (tester) async {
    final fixture = BioEnglishFixture()
      ..drafts.value = null
      ..profile =
          BioEnglishFixture.result(storeName: 'ร้านของคุณ', published: false);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    final field = find.byKey(const ValueKey('link-in-bio-store-name'));
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, 'ร้านของคุณ');
    fixture.profile = null;
    await _tap(tester, 'link-in-bio-refresh');
    expect(controller.text, 'ร้านของคุณ');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(controller.text, 'ร้านของคุณ');
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(controller.text, 'ร้านของคุณ');
    expect(fixture.profileReads, 2);
    expect(fixture.drafts.reads, 1);
    expect(fixture.drafts.saves, isEmpty);
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending local draft save follows locale without another write',
      (tester) async {
    final fixture = BioEnglishFixture();
    final save = Completer<void>();
    fixture.drafts.gate = save;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await showBioStep(tester, 'info');
    await tester.enterText(find.byKey(const ValueKey('link-in-bio-store-name')),
        'ร้านที่กำลังบันทึก');
    await tester.pumpAndSettle();
    expect(find.text('Saving draft on this device...'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กำลังบันทึกแบบร่างในเครื่อง...'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Saving draft on this device...'), findsOneWidget);
    expect(fixture.drafts.saves, hasLength(1));
    save.complete();
    await tester.pumpAndSettle();
    expect(find.text('Draft saved on this device'), findsOneWidget);
    expect(fixture.drafts.value!.storeName, 'ร้านที่กำลังบันทึก');
    expect(fixture.publications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'main store sections and link editor fit 320dp 2x with keyboard (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final fixture = BioEnglishFixture(dark: dark, scale: 2);
      fixture.drafts.value = const LinkInBioDraft(
          storeName: 'Mina',
          slug: 'mina-shop',
          autoUpdateFromScheduledPosts: false,
          enabledLinkIds: {},
          customLinks: []);
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      for (final label in [
        'Store link',
        'Store info',
        'Customize',
        'Preview',
        'Add link',
        'Review and publish'
      ]) {
        await showBioControl(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      await showBioStep(tester, 'info');
      for (final label in [
        'Store info',
        'Store name',
        'Short store description',
        'Optional',
        'Done'
      ]) {
        await showBioControl(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      await _typeWithKeyboard(tester,
          find.byKey(const ValueKey('link-in-bio-store-name')), 'Mina Shop');
      await _typeWithKeyboard(
          tester,
          find.byKey(const ValueKey('link-in-bio-description')),
          'My store description');
      await showBioUrlSettings(tester);
      _readable(tester, find.text('URL name'));
      await showBioControl(
          tester, find.text('3–40 characters: a–z, 0–9 and hyphens'));
      _readable(tester, find.text('3–40 characters: a–z, 0–9 and hyphens'));
      await _tap(tester, 'link-in-bio-done');
      expect(tester.takeException(), isNull);
      await _tap(tester, 'link-in-bio-add');
      for (final label in [
        'Button label',
        'Link or contact',
        'Paste a website link, email address or phone number',
        'Save link'
      ]) {
        await showBioControl(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      await _typeWithKeyboard(tester,
          find.byKey(const ValueKey('link-in-bio-link-title')), 'My store');
      await _typeWithKeyboard(tester,
          find.byKey(const ValueKey('link-in-bio-link-url')), 'not-a-link');
      await _tap(tester, 'link-in-bio-link-save');
      expect(tester.takeException(), isNull);
      const invalidUrl =
          'Use a full https:// or http:// URL without a username or password, or use mailto:email / tel:phone.';
      await showBioControl(tester, find.text(invalidUrl));
      _readable(tester, find.text(invalidUrl));
      expect(fixture.drafts.value!.customLinks, isEmpty);
      expect(fixture.publications, isEmpty);
      await _typeWithKeyboard(
          tester,
          find.byKey(const ValueKey('link-in-bio-link-url')),
          'https://example.com/shop');
      await _tap(tester, 'link-in-bio-link-save');
      expect(fixture.drafts.value!.customLinks.single.title, 'My store');
      await showBioStep(tester, 'review');
      for (final label in [
        'Review and publish',
        'Publish website',
        'Back to links'
      ]) {
        await showBioControl(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      expect(fixture.publications, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
