import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/profile/edit_profile_screen.dart';
import 'package:postdee_mobile/features/profile/profile_draft_store.dart';

const _draft = ProfileDraft(
  displayName: 'Mina',
  storeName: 'Mina Shop',
  accountEmail: 'owner@example.com',
  accountUserId: 'editor-owner',
);

class _Fixture {
  _Fixture({
    Locale initialLocale = const Locale('en'),
    this.draft = _draft,
    this.email = 'owner@example.com',
    this.verified = true,
    this.dark = false,
    this.scale = 1,
  }) : locale = ValueNotifier(initialLocale);

  final ValueNotifier<Locale> locale;
  final ProfileDraft draft;
  final String email;
  final bool verified;
  final bool dark;
  final double scale;
  final results = <ProfileDraft?>[];

  Widget app() => ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) {
          AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
          return MaterialApp(
            locale: value,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const ValueKey('open-editor'),
                    onPressed: () async {
                      results.add(await Navigator.of(context)
                          .push<ProfileDraft>(MaterialPageRoute(
                        builder: (_) => EditProfileScreen(
                          initialDraft: draft,
                          email: email,
                          emailVerified: verified,
                        ),
                      )));
                    },
                    child: const Text('Open editor'),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _field(String value) =>
    find.descendant(of: _key(value), matching: find.byType(TextField));

Future<void> _open(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await tester.tap(_key('open-editor'));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 180,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void _readable(WidgetTester tester, Finder text) {
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(
        paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5),
  );
}

void _editableFits(WidgetTester tester, Finder field) {
  final editable = tester
      .state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)))
      .renderEditable;
  expect(editable.size.height,
      greaterThanOrEqualTo(editable.preferredLineHeight - 0.5));
  final controller = tester.widget<TextField>(field).controller!;
  final caret = editable.getLocalRectForCaret(
      TextPosition(offset: controller.selection.extentOffset));
  expect(caret.top, greaterThanOrEqualTo(-0.5));
  expect(caret.bottom, lessThanOrEqualTo(editable.size.height + 0.5));
}

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

void main() {
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  testWidgets('English editor names its fields and local-only save scope',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.locale.dispose);
    await _open(tester, fixture);

    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Change profile photo'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Store name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    await _reveal(tester, find.text('Saved on this device only'));
    expect(
      find.text(
          'Name changes are saved only on this device and are not synced with your account or other devices.'),
      findsOneWidget,
    );
    expect(fixture.results, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English editor has localized empty-field hints and email status',
      (tester) async {
    final fixture = _Fixture(
      draft: const ProfileDraft(displayName: '', storeName: ''),
      verified: false,
    );
    addTearDown(fixture.locale.dispose);
    await _open(tester, fixture);

    expect(find.text('e.g. Mina'), findsOneWidget);
    expect(find.text('e.g. Mina Shop'), findsOneWidget);
    expect(find.text('Email not verified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored required-name error changes language without losing edits',
      (tester) async {
    final fixture = _Fixture(initialLocale: const Locale('th'));
    addTearDown(fixture.locale.dispose);
    await _open(tester, fixture);
    final state = tester.state(find.byType(EditProfileScreen));
    await tester.enterText(_field('edit-profile-display-name'), '   ');
    await tester.enterText(_field('edit-profile-store-name'), 'ร้านมีนาขายดี');
    await tester.tap(_key('edit-profile-save'));
    await tester.pumpAndSettle();
    expect(find.text('กรอกชื่อที่ต้องการให้แสดง'), findsOneWidget);
    final name = tester
        .widget<TextField>(_field('edit-profile-display-name'))
        .controller!;
    final shop =
        tester.widget<TextField>(_field('edit-profile-store-name')).controller!;
    shop.selection = const TextSelection(baseOffset: 1, extentOffset: 4);

    fixture.locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditProfileScreen)), same(state));
    expect(find.text('Enter a display name'), findsOneWidget);
    expect(
        tester.widget<TextField>(_field('edit-profile-store-name')).controller,
        same(shop));
    expect(
        tester
            .widget<TextField>(_field('edit-profile-display-name'))
            .controller,
        same(name));
    expect(shop.text, 'ร้านมีนาขายดี');
    expect(shop.selection, const TextSelection(baseOffset: 1, extentOffset: 4));
    expect(name.text, '   ');

    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กรอกชื่อที่ต้องการให้แสดง'), findsOneWidget);
    expect(find.text('Enter a display name'), findsNothing);
    expect(shop.text, 'ร้านมีนาขายดี');
    expect(fixture.results, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving trims Thai names and retains the original draft owner',
      (tester) async {
    const original = ProfileDraft(
      displayName: 'Original',
      storeName: 'Original shop',
      accountEmail: 'Original.Owner@example.com',
      accountUserId: 'stable-owner-id',
    );
    final fixture = _Fixture(draft: original, email: 'visible@example.com');
    addTearDown(fixture.locale.dispose);
    await _open(tester, fixture);
    await tester.enterText(_field('edit-profile-display-name'), '  มีนา  ');
    await tester.enterText(
        _field('edit-profile-store-name'), '  ร้านมีนาขายดี  ');
    await tester.tap(_key('edit-profile-save'));
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsNothing);
    expect(fixture.results, hasLength(1));
    final saved = fixture.results.single!;
    expect(saved.displayName, 'มีนา');
    expect(saved.storeName, 'ร้านมีนาขายดี');
    expect(saved.accountEmail, original.accountEmail);
    expect(saved.accountUserId, original.accountUserId);
    expect(original.displayName, 'Original');
    expect(original.storeName, 'Original shop');
    expect(tester.takeException(), isNull);
  });

  testWidgets('store name stays optional and whitespace is saved as empty',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.locale.dispose);
    await _open(tester, fixture);
    await tester.enterText(_field('edit-profile-store-name'), ' \n\t ');
    await tester.tap(_key('edit-profile-save'));
    await tester.pumpAndSettle();
    expect(fixture.results, hasLength(1));
    expect(fixture.results.single!.displayName, 'Mina');
    expect(fixture.results.single!.storeName, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final blank in ['', '   ']) {
    testWidgets('blank display name cannot save (${blank.length} characters)',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.locale.dispose);
      await _open(tester, fixture);
      await tester.enterText(_field('edit-profile-display-name'), blank);
      await tester.tap(_key('edit-profile-save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a display name'), findsOneWidget);
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(fixture.results, isEmpty);
      await tester.enterText(
          _field('edit-profile-display-name'), 'Mina edited');
      await tester.pump();
      expect(find.text('Enter a display name'), findsNothing);
      await tester.tap(_key('edit-profile-save'));
      await tester.pumpAndSettle();
      expect(fixture.results, hasLength(1));
      expect(fixture.results.single!.displayName, 'Mina edited');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching languages retains Thai input until explicitly saved',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.locale.dispose);
    await _open(tester, fixture);
    await tester.enterText(_field('edit-profile-display-name'), 'มีนา ขายดี');
    await tester.enterText(_field('edit-profile-store-name'), 'ร้านของฉัน 🛍️');
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ชื่อที่แสดง'), findsOneWidget);
    expect(find.text('มีนา ขายดี'), findsOneWidget);
    expect(find.text('ร้านของฉัน 🛍️'), findsOneWidget);
    fixture.locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('มีนา ขายดี'), findsOneWidget);
    expect(find.text('ร้านของฉัน 🛍️'), findsOneWidget);
    expect(fixture.results, isEmpty);
    await tester.tap(_key('edit-profile-save'));
    await tester.pumpAndSettle();
    expect(fixture.results.single!.displayName, 'มีนา ขายดี');
    expect(fixture.results.single!.storeName, 'ร้านของฉัน 🛍️');
    expect(tester.takeException(), isNull);
  });

  for (final systemBack in [false, true]) {
    testWidgets(
        'back cancels edits without returning a draft (system=$systemBack)',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.locale.dispose);
      await _open(tester, fixture);
      await tester.enterText(
          _field('edit-profile-display-name'), 'Unsaved name');
      await tester.enterText(_field('edit-profile-store-name'), 'Unsaved shop');
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(fixture.results, [null]);
      expect(fixture.draft.displayName, 'Mina');
      expect(fixture.draft.storeName, 'Mina Shop');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('email is read-only and keeps its original characters',
      (tester) async {
    final fixture = _Fixture(email: 'Seller+Inbox@Example.com');
    addTearDown(fixture.locale.dispose);
    await _open(tester, fixture);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Seller+Inbox@Example.com'), findsOneWidget);
    await tester.tap(find.text('Seller+Inbox@Example.com'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(fixture.results, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final email in ['', 'ยังไม่ได้เชื่อมอีเมล', 'Email not connected']) {
    testWidgets('missing-email fallback follows live locale ($email)',
        (tester) async {
      final fixture = _Fixture(
          initialLocale: const Locale('th'), email: email, verified: false);
      addTearDown(fixture.locale.dispose);
      await _open(tester, fixture);
      expect(find.text('ยังไม่ได้เชื่อมอีเมล'), findsOneWidget);
      fixture.locale.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text('Email not connected'), findsOneWidget);
      expect(find.text('ยังไม่ได้เชื่อมอีเมล'), findsNothing);
      expect(find.text('Email not verified'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(_field('edit-profile-display-name'))
              .controller!
              .text,
          'Mina');
      expect(fixture.results, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final camera in [true, false]) {
    testWidgets(
        'photo ${camera ? 'camera' : 'text'} entry explains unavailable upload',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.locale.dispose);
      await _open(tester, fixture);
      await tester.enterText(
          _field('edit-profile-display-name'), 'Unsaved Mina');
      final state = tester.state(find.byType(EditProfileScreen));
      await tester.tap(camera
          ? _key('edit-profile-avatar')
          : find.widgetWithText(TextButton, 'Change profile photo'));
      await tester.pumpAndSettle();
      expect(find.text('Profile photo uploads are not available yet.'),
          findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.state(find.byType(EditProfileScreen)), same(state));
      expect(find.text('Unsaved Mina'), findsOneWidget);
      expect(fixture.results, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('photo camera has an English accessible action name',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.locale.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await _open(tester, fixture);
      final data =
          tester.getSemantics(_key('edit-profile-avatar')).getSemanticsData();
      expect(data.label, contains('Change profile photo'));
      expect(data.label, isNot(contains('เปลี่ยนรูปโปรไฟล์')));
      expect(data.flagsCollection.isButton, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('plain MaterialApp retains the existing Thai editor copy',
      (tester) async {
    AppTheme.applyThemeMode(ThemeMode.light);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const EditProfileScreen(
        initialDraft: ProfileDraft(displayName: '', storeName: ''),
        email: 'owner@example.com',
        emailVerified: false,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('แก้ไขโปรไฟล์'), findsOneWidget);
    expect(find.text('เช่น มีนา'), findsOneWidget);
    expect(find.text('เช่น ร้านมีนาขายดี'), findsOneWidget);
    expect(find.text('อีเมลยังไม่ยืนยัน'), findsOneWidget);
    await tester.tap(_key('edit-profile-save'));
    await tester.pumpAndSettle();
    expect(find.text('กรอกชื่อที่ต้องการให้แสดง'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final verified in [false, true]) {
      testWidgets(
          'English fields and email status fit 320dp 2x (dark=$dark verified=$verified)',
          (tester) async {
        _narrow(tester);
        final fixture = _Fixture(
            dark: dark,
            scale: 2,
            verified: verified,
            draft: const ProfileDraft(displayName: '', storeName: ''));
        addTearDown(fixture.locale.dispose);
        await _open(tester, fixture);

        expect(find.byType(BackButton), findsOneWidget);
        _readable(tester, find.text('Edit profile'));
        _readable(tester, find.text('Save'));
        _readable(tester, find.text('Change profile photo'));
        for (final label in ['Display name', 'Store name', 'Email']) {
          await _reveal(tester, find.text(label));
          _readable(tester, find.text(label));
        }
        final status = find.text(verified ? 'Verified' : 'Email not verified');
        await _reveal(tester, status);
        _readable(tester, status);
        _readable(tester, find.text('owner@example.com'));
        await _reveal(tester, find.text('Saved on this device only'));
        _readable(tester, find.text('Saved on this device only'));
        _readable(
            tester,
            find.text(
                'Name changes are saved only on this device and are not synced with your account or other devices.'));
        expect(fixture.results, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320dp 2x keyboard keeps input and caret usable (dark=$dark)',
        (tester) async {
      _narrow(tester);
      final fixture = _Fixture(dark: dark, scale: 2);
      addTearDown(fixture.locale.dispose);
      await _open(tester, fixture);

      for (final entry in [
        ('edit-profile-display-name', 'มีนา 🛍️'),
        ('edit-profile-store-name', 'ร้านขายดี'),
      ]) {
        final field = _field(entry.$1);
        await _reveal(tester, field);
        await tester.showKeyboard(field);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.enterText(field, entry.$2);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        _editableFits(tester, field);
        final fieldBounds = tester.getRect(field);
        expect(fieldBounds.top, greaterThanOrEqualTo(0));
        expect(fieldBounds.bottom, lessThanOrEqualTo(440));
        tester.testTextInput.hide();
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }
      await tester.tap(_key('edit-profile-save'));
      await tester.pumpAndSettle();
      expect(fixture.results, hasLength(1));
      expect(fixture.results.single!.displayName, 'มีนา 🛍️');
      expect(fixture.results.single!.storeName, 'ร้านขายดี');
      expect(tester.takeException(), isNull);
    });
  }
}
