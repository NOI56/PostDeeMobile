import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';
import 'package:postdee_mobile/features/shell/postdee_shell.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Email implements EmailAuthGateway, EmailAccountRecoveryGateway {
  final signIns = <({String email, String password, bool create})>[];
  final resets = <String>[];

  @override
  Future<AuthSession> signIn(
      {required String email,
      required String password,
      required bool createAccount}) async {
    signIns.add((email: email, password: password, create: createAccount));
    throw const AuthUnavailableException('Fake sign-in was declined.');
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async => resets.add(email);
  @override
  Future<void> sendEmailVerification() async =>
      throw StateError('Unexpected verification request');
  @override
  Future<AuthSession> reloadSession() async =>
      throw StateError('Unexpected account reload');
}

class _Drafts implements PublishDraftStore {
  @override
  Future<List<PublishDraft>> listDrafts() async => [];
  @override
  Future<PublishDraft?> loadDraft(String draftId) async => null;
  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async =>
      throw StateError('Unexpected draft write');
  @override
  Future<void> deleteDraft(String draftId) async =>
      throw StateError('Unexpected draft delete');
  @override
  Future<void> deleteAllDrafts() async =>
      throw StateError('Unexpected drafts delete');
}

class _Fixture {
  _Fixture(
      {Locale locale = const Locale('en'), this.dark = false, this.scale = 1})
      : language = PostDeeLanguageController(initialLocale: locale);

  final PostDeeLanguageController language;
  final bool dark;
  final double scale;
  final email = _Email();
  final drafts = _Drafts();

  Widget app() => AnimatedBuilder(
        animation: language,
        builder: (_, __) {
          AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
          return MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            locale: language.locale,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: PostDeeLocalizations.supportedLocales,
            home: PostDeeShell(
              languageController: language,
              emailAuthGateway: email,
              uploaderDraftStore: drafts,
            ),
          );
        },
      );
}

Finder _key(String key) => find.byKey(ValueKey(key));
Finder get _dialog => _key('email-sign-in-form');
Finder get _dialogState => find
    .ancestor(
        of: _dialog,
        matching: find.byWidgetPredicate((widget) => widget is StatefulWidget))
    .first;
Finder _dialogText(String text) =>
    find.descendant(of: _dialog, matching: find.text(text));
Finder get _emailField =>
    find.descendant(of: _dialog, matching: find.byType(TextField)).first;
Finder get _passwordField =>
    find.descendant(of: _dialog, matching: find.byType(TextField)).last;
Finder get _submit =>
    find.descendant(of: _dialog, matching: find.byType(FilledButton));

Future<void> _mount(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
}

Future<void> _openEmail(WidgetTester tester) async {
  await tester.ensureVisible(_key('login-email-sign-in'));
  await tester.pumpAndSettle();
  await tester.tap(_key('login-email-sign-in'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
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
  await tester.ensureVisible(field);
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
  final controller = tester.widget<TextField>(field).controller!;
  expect(editable.size.height,
      greaterThanOrEqualTo(editable.preferredLineHeight - 0.5));
  final caret = editable.getLocalRectForCaret(
      TextPosition(offset: controller.selection.extentOffset));
  expect(caret.top, greaterThanOrEqualTo(-0.5));
  expect(caret.bottom, lessThanOrEqualTo(editable.size.height + 0.5));
  final globalCaret = caret.shift(editable.localToGlobal(Offset.zero));
  expect(globalCaret.top, greaterThanOrEqualTo(0));
  expect(globalCaret.bottom, lessThanOrEqualTo(440));
  expect(tester.testTextInput.isVisible, isTrue);
  tester.testTextInput.hide();
  tester.view.resetViewInsets();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    PostDeeAuthSessionStore.instance.clear();
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('English login gate explains the current posting benefit',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.language.dispose);
    await _mount(tester, fixture);
    expect(find.text('Post once. Sell everywhere.'), findsOneWidget);
    expect(
        find.text(
            'Post one video to TikTok, Shorts,\nReels and Facebook at once.'),
        findsOneWidget);
    expect(
        find.text(
            'Connect your account once. Sign in securely. PostDee does not store your password.'),
        findsOneWidget);
    expect(fixture.email.signIns, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English email dialog labels its fields and recovery actions',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.language.dispose);
    await _mount(tester, fixture);
    await _openEmail(tester);
    expect(_dialogText('Sign in with email'), findsOneWidget);
    expect(_dialogText('Email'), findsOneWidget);
    expect(_dialogText('Password'), findsOneWidget);
    expect(_dialogText('Forgot password?'), findsOneWidget);
    expect(_dialogText('New to PostDee? Create an account'), findsOneWidget);
    expect(_dialogText('Cancel'), findsOneWidget);
    expect(_dialogText('Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored email validation follows locale and retains typed credentials',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    addTearDown(fixture.language.dispose);
    await _mount(tester, fixture);
    await _openEmail(tester);
    await tester.enterText(_emailField, 'seller.example.com');
    await tester.enterText(_passwordField, ' รหัสผ่านเดิม ');
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(_dialogText('กรอกอีเมลให้ถูกต้อง'), findsOneWidget);
    final state = tester.state(_dialogState);
    fixture.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(tester.state(_dialogState), same(state));
    expect(_dialogText('Enter a valid email address.'), findsOneWidget);
    expect(tester.widget<TextField>(_emailField).controller!.text,
        'seller.example.com');
    expect(tester.widget<TextField>(_passwordField).controller!.text,
        ' รหัสผ่านเดิม ');
    expect(fixture.email.signIns, isEmpty);
    expect(fixture.email.resets, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Thai login gate keeps its existing hero and secure sign-in copy',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    addTearDown(fixture.language.dispose);
    await _mount(tester, fixture);
    expect(find.text('ลงครั้งเดียว ขายได้ทุกที่'), findsOneWidget);
    expect(
        find.text(
            'โพสต์วิดีโอเดียวไป TikTok, Shorts,\nReels และ Facebook พร้อมกัน'),
        findsOneWidget);
    expect(
        find.text(
            'เชื่อมต่อบัญชีเพียงครั้งเดียว ปลอดภัย ไม่เก็บรหัสผ่านของคุณ'),
        findsOneWidget);
    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบด้วยอีเมล'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'live login gate locale changes preserve the same signed-out shell',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    addTearDown(fixture.language.dispose);
    await _mount(tester, fixture);
    final shell = tester.state(find.byType(PostDeeShell));
    fixture.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('Post once. Sell everywhere.'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
    expect(tester.state(find.byType(PostDeeShell)), same(shell));
    expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
    expect(fixture.email.signIns, isEmpty);
    expect(fixture.email.resets, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English account mode toggles keep raw credentials without dispatch',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.language.dispose);
    await _mount(tester, fixture);
    await _openEmail(tester);
    await tester.enterText(_emailField, ' Seller+Test@Example.com ');
    await tester.enterText(_passwordField, ' รหัสผ่านเดิม ');
    await _tap(tester, _dialogText('New to PostDee? Create an account'));
    expect(_dialogText('Create an account with email'), findsOneWidget);
    expect(_dialogText('Create account'), findsOneWidget);
    expect(_dialogText('Already have an account? Sign in'), findsOneWidget);
    expect(_key('email-forgot-password'), findsNothing);
    expect(tester.widget<TextField>(_emailField).controller!.text,
        ' Seller+Test@Example.com ');
    expect(tester.widget<TextField>(_passwordField).controller!.text,
        ' รหัสผ่านเดิม ');
    await _tap(tester, _dialogText('Already have an account? Sign in'));
    expect(_dialogText('Sign in with email'), findsOneWidget);
    expect(_dialogText('Forgot password?'), findsOneWidget);
    expect(fixture.email.signIns, isEmpty);
    expect(fixture.email.resets, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final create in [false, true]) {
    testWidgets('short password is rejected in English (create=$create)',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.language.dispose);
      await _mount(tester, fixture);
      await _openEmail(tester);
      if (create) {
        await _tap(tester, _dialogText('New to PostDee? Create an account'));
      }
      await tester.enterText(_emailField, 'seller@example.com');
      await tester.enterText(_passwordField, '12345');
      await _tap(tester, _submit);
      expect(_dialogText('Your password must have at least 6 characters.'),
          findsOneWidget);
      expect(fixture.email.signIns, isEmpty);
      expect(fixture.email.resets, isEmpty);
      expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'stored password validation follows current locale with controller selection',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    addTearDown(fixture.language.dispose);
    await _mount(tester, fixture);
    await _openEmail(tester);
    await tester.enterText(_emailField, ' Seller@Example.com ');
    await tester.enterText(_passwordField, '12345');
    await _tap(tester, _submit);
    expect(_dialogText('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร'), findsOneWidget);
    final email = tester.widget<TextField>(_emailField).controller!;
    final password = tester.widget<TextField>(_passwordField).controller!;
    password.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    fixture.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(_dialogText('Your password must have at least 6 characters.'),
        findsOneWidget);
    expect(tester.widget<TextField>(_emailField).controller, same(email));
    expect(tester.widget<TextField>(_passwordField).controller, same(password));
    expect(email.text, ' Seller@Example.com ');
    expect(password.text, '12345');
    expect(password.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3));
    fixture.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    expect(_dialogText('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร'), findsOneWidget);
    expect(fixture.email.signIns, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Thai dialog keeps its existing sign-in and create-account wording',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    addTearDown(fixture.language.dispose);
    await _mount(tester, fixture);
    await _openEmail(tester);
    for (final text in [
      'เข้าสู่ระบบด้วยอีเมล',
      'อีเมล',
      'รหัสผ่าน',
      'ลืมรหัสผ่าน?',
      'ยังไม่มีบัญชี? สร้างบัญชีใหม่',
      'ยกเลิก',
      'เข้าสู่ระบบ'
    ]) {
      expect(_dialogText(text), findsOneWidget);
    }
    await _tap(tester, _dialogText('ยังไม่มีบัญชี? สร้างบัญชีใหม่'));
    expect(_dialogText('สร้างบัญชีด้วยอีเมล'), findsOneWidget);
    expect(_dialogText('สร้างบัญชี'), findsOneWidget);
    expect(_dialogText('มีบัญชีอยู่แล้ว? เข้าสู่ระบบ'), findsOneWidget);
    expect(fixture.email.signIns, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'English gate and email modes fit 320dp 2x with keyboard (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final fixture = _Fixture(dark: dark, scale: 2);
      addTearDown(fixture.language.dispose);
      await _mount(tester, fixture);
      for (final label in [
        'Post once. Sell everywhere.',
        'Post one video to TikTok, Shorts,\nReels and Facebook at once.',
        'Connect your account once. Sign in securely. PostDee does not store your password.',
        'Sign in with Google',
        'Sign in with email',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        _readable(tester, find.text(label));
      }
      await _openEmail(tester);
      for (final create in [false, true]) {
        if (create) {
          await _tap(tester, _dialogText('New to PostDee? Create an account'));
        }
        for (final label in [
          create ? 'Create an account with email' : 'Sign in with email',
          'Email',
          'Password',
          'Cancel',
          create ? 'Create account' : 'Sign in',
          create
              ? 'Already have an account? Sign in'
              : 'New to PostDee? Create an account',
        ]) {
          await tester.ensureVisible(_dialogText(label));
          await tester.pumpAndSettle();
          _readable(tester, _dialogText(label));
        }
        if (!create) {
          await tester.ensureVisible(_dialogText('Forgot password?'));
          await tester.pumpAndSettle();
          _readable(tester, _dialogText('Forgot password?'));
        }
        await _typeWithKeyboard(tester, _emailField, 'seller@example.com');
        await _typeWithKeyboard(tester, _passwordField, '12345');
        await _tap(tester, _submit);
        await tester.ensureVisible(
            _dialogText('Your password must have at least 6 characters.'));
        await tester.pumpAndSettle();
        _readable(tester,
            _dialogText('Your password must have at least 6 characters.'));
      }
      await _tap(tester, _dialogText('Cancel'));
      expect(_dialog, findsNothing);
      expect(fixture.email.signIns, isEmpty);
      expect(fixture.email.resets, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
