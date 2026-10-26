import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

const _store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');
const _logoKey =
    'uploads/seller-a/12345678-1234-4234-8234-123456789abc/profile-logo.png';
const _link = LinkInBioCustomLink(
    id: 'shop', title: 'สินค้าของร้าน', url: 'https://example.com/shop');
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6dQAAAABJRU5ErkJggg==');

LinkInBioDraft _draft({bool logo = false}) => LinkInBioDraft(
      storeName: 'ร้านมินา',
      slug: 'mina-shop',
      autoUpdateFromScheduledPosts: false,
      enabledLinkIds: {'shop'},
      customLinks: [_link],
      appearance: LinkInBioAppearance(
          description: 'สินค้าดีของร้านเรา', logoKey: logo ? _logoKey : null),
    );
Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _mount(WidgetTester tester,
    {double scale = 1,
    bool dark = false,
    LinkInBioProfilePublisher? publish}) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  await tester.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: child!),
    home: LinkInBioScreen(
        loadProfile: () async => null,
        loadSubscription: loadBioProSubscription,
        protectDraftImages: (
            {required draftId, required keys, required mode}) async {},
        loadImage: (_) async => _png,
        pickImage: () async => null,
        publishProfile: publish ??
            (
                    {required storeName,
                    required slug,
                    required links,
                    appearance}) async =>
                throw StateError('Info editing must not publish')),
  ));
  await tester.pumpAndSettle();
  await showBioStep(tester, 'info');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'fixture-only'));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('airy shop info groups work at 320px text$scale dark=$dark',
          (tester) async {
        await _store.saveDraft(_draft());
        await _mount(tester, scale: scale, dark: dark);
        final logo = _key('link-in-bio-info-logo-panel');
        final fields = _key('link-in-bio-info-fields-panel');
        final url = _key('link-in-bio-info-url-panel');
        expect(logo, findsOneWidget);
        expect(fields, findsOneWidget);
        expect(url, findsOneWidget);
        expect(tester.getBottomLeft(logo).dy,
            lessThanOrEqualTo(tester.getTopLeft(fields).dy));
        expect(tester.getBottomLeft(fields).dy,
            lessThan(tester.getTopLeft(url).dy));
        expect(
            find.descendant(of: logo, matching: _key('link-in-bio-info-logo')),
            findsOneWidget);
        expect(find.descendant(of: logo, matching: find.byType(Image)),
            findsNothing);
        expect(tester.widget(_key('link-in-bio-image-logo')),
            isA<ButtonStyleButton>());
        expect(_key('link-in-bio-remove-logo'), findsNothing);
        for (final field in [
          'link-in-bio-store-name',
          'link-in-bio-description'
        ]) {
          expect(find.descendant(of: fields, matching: _key(field)),
              findsOneWidget);
        }
        expect(find.descendant(of: fields, matching: find.text('ชื่อร้าน')),
            findsOneWidget);
        expect(
            find.descendant(of: fields, matching: find.text('แนะนำร้านสั้น ๆ')),
            findsOneWidget);
        expect(find.descendant(of: fields, matching: find.text('ไม่บังคับ')),
            findsOneWidget);
        expect(
            tester
                .widget<TextField>(_key('link-in-bio-store-name'))
                .decoration!
                .labelText,
            isNull);
        expect(find.descendant(of: url, matching: find.text('ลิงก์ร้านของคุณ')),
            findsOneWidget);
        expect(find.descendant(of: url, matching: find.text('แก้ไข')),
            findsOneWidget);
        expect(_key('link-in-bio-slug').hitTestable(), findsNothing);
        await showBioControl(tester, url);
        final status = _key('link-in-bio-draft-status');
        await showBioControl(tester, status);
        expect(tester.getTopLeft(status).dy,
            greaterThan(tester.getBottomLeft(url).dy));
        expect(find.text('เผยแพร่อีกครั้งเพื่ออัปเดตหน้าเว็บจริง'),
            findsOneWidget);
        await tapBioControl(tester, 'link-in-bio-done');
        expect(_key('link-in-bio-add'), findsOneWidget);
        expect(status, findsOneWidget);
        expect(
            find.text('เผยแพร่อีกครั้งเพื่ออัปเดตหน้าเว็บจริง'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'field counters keep their space and appear only for the focused input',
      (tester) async {
    await _store.saveDraft(_draft());
    await _mount(tester);
    final name = _key('link-in-bio-info-name-counter');
    final description = _key('link-in-bio-info-description-counter');
    expect(name, findsOneWidget);
    expect(description, findsOneWidget);
    for (final finder in [name, description]) {
      final counter = tester.widget<Visibility>(finder);
      expect(counter.visible, isFalse);
      expect(counter.maintainSize, isTrue);
      expect(counter.maintainState, isTrue);
      expect(counter.maintainAnimation, isTrue);
    }
    final panelHeight =
        tester.getSize(_key('link-in-bio-info-fields-panel')).height;
    await showBioControl(tester, _key('link-in-bio-store-name'));
    await tester.tap(_key('link-in-bio-store-name'));
    await tester.pumpAndSettle();
    expect(tester.widget<Visibility>(name).visible, isTrue);
    expect(tester.widget<Visibility>(description).visible, isFalse);
    await showBioControl(tester, _key('link-in-bio-description'));
    await tester.tap(_key('link-in-bio-description'));
    await tester.pumpAndSettle();
    expect(tester.widget<Visibility>(name).visible, isFalse);
    expect(tester.widget<Visibility>(description).visible, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(tester.widget<Visibility>(description).visible, isFalse);
    expect(tester.getSize(_key('link-in-bio-info-fields-panel')).height,
        panelHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid Done expands the URL card and preserves the typed slug',
      (tester) async {
    await _store.saveDraft(_draft());
    await _mount(tester);
    await tapBioControl(tester, 'link-in-bio-url-settings');
    expect(find.text('ย่อ'), findsOneWidget);
    await showBioControl(tester, _key('link-in-bio-slug'));
    await tester.enterText(_key('link-in-bio-slug'), 'bad_slug');
    await tapBioControl(tester, 'link-in-bio-url-settings');
    expect(find.text('แก้ไข'), findsOneWidget);
    await tapBioControl(tester, 'link-in-bio-done');
    expect(find.text('ย่อ'), findsOneWidget);
    expect(tester.widget<TextField>(_key('link-in-bio-slug')).controller!.text,
        'bad_slug');
    expect(find.textContaining('ชื่อ URL ต้อง'), findsWidgets);
    expect(_key('link-in-bio-store-name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning to shop info reopens a collapsed invalid URL',
      (tester) async {
    await _store.saveDraft(_draft());
    await _mount(tester);
    await tapBioControl(tester, 'link-in-bio-url-settings');
    await showBioControl(tester, _key('link-in-bio-slug'));
    await tester.enterText(_key('link-in-bio-slug'), 'bad_slug');
    await tapBioControl(tester, 'link-in-bio-url-settings');
    expect(find.text('แก้ไข'), findsOneWidget);
    await tapBioControl(tester, 'link-in-bio-close-editor');
    expect(_key('link-in-bio-add'), findsOneWidget);
    await showBioStep(tester, 'info');
    expect(find.text('ย่อ'), findsOneWidget);
    expect(tester.widget<TextField>(_key('link-in-bio-slug')).controller!.text,
        'bad_slug');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'name and description auto-save without publishing or losing shop links',
      (tester) async {
    await _store.saveDraft(_draft());
    var publications = 0;
    await _mount(tester, publish: (
        {required storeName, required slug, required links, appearance}) async {
      publications++;
      throw StateError('Unexpected publication');
    });
    await showBioControl(tester, _key('link-in-bio-store-name'));
    await tester.enterText(_key('link-in-bio-store-name'), 'ร้านมินาใหม่');
    await showBioControl(tester, _key('link-in-bio-description'));
    await tester.enterText(
        _key('link-in-bio-description'), 'สินค้าใหม่พร้อมส่ง');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final saved = (await _store.loadDraft())!;
    expect(saved.storeName, 'ร้านมินาใหม่');
    expect(saved.appearance.description, 'สินค้าใหม่พร้อมส่ง');
    expect(saved.slug, 'mina-shop');
    expect(saved.enabledLinkIds, {'shop'});
    expect(saved.customLinks.single.url, _link.url);
    expect(publications, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'text delete-logo action removes only the image and keeps the rest of the draft',
      (tester) async {
    await _store.saveDraft(_draft(logo: true));
    await _mount(tester);
    final remove = _key('link-in-bio-remove-logo');
    expect(remove, findsOneWidget);
    expect(tester.widget(remove), isA<TextButton>());
    expect(find.byTooltip('ลบโลโก้'), findsOneWidget);
    await showBioControl(tester, remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    final saved = (await _store.loadDraft())!;
    expect(saved.appearance.logoKey, isNull);
    expect(saved.storeName, 'ร้านมินา');
    expect(saved.appearance.description, 'สินค้าดีของร้านเรา');
    expect(saved.slug, 'mina-shop');
    expect(saved.customLinks.single.toJson(), _link.toJson());
    expect(saved.enabledLinkIds, {'shop'});
    expect(remove, findsNothing);
    expect(_key('link-in-bio-info-logo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
