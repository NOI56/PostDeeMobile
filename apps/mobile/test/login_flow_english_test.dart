import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';
import 'package:postdee_mobile/features/auth/auth_message_localization.dart';
import 'package:postdee_mobile/features/shell/postdee_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _resetSuccess =
    'If an account exists for this email, you will receive a password reset link. Check your inbox and spam folder.';
const _fakeSession =
    AuthSession(userId: 'fake-login-owner', idToken: 'fake-token');
const _otherSession =
    AuthSession(userId: 'other-owner', idToken: 'other-token');
const _googleCredentialError =
    'Google could not access a sign-in credential on this device. Please try again, check your Google account in Android Settings, or sign in with email.';
const _googleCredentialErrorThai =
    'Google ยังอ่านข้อมูลเข้าสู่ระบบบนอุปกรณ์นี้ไม่ได้ กรุณาลองใหม่ ตรวจสอบบัญชี Google ในการตั้งค่า Android หรือเข้าสู่ระบบด้วยอีเมล';

class _FakeEmailGateway
    implements EmailAuthGateway, EmailAccountRecoveryGateway {
  final signIns = <({String email, String password, bool createAccount})>[];
  final resets = <String>[];
  Future<AuthSession> Function()? onSignIn;
  Future<void> Function()? onReset;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
    required bool createAccount,
  }) async {
    signIns
        .add((email: email, password: password, createAccount: createAccount));
    return onSignIn != null ? onSignIn!() : _fakeSession;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    resets.add(email);
    await onReset?.call();
  }

  @override
  Future<AuthSession> reloadSession() async =>
      throw StateError('Email reload must not be called by login tests');

  @override
  Future<void> sendEmailVerification() async =>
      throw StateError('Verification email must not be sent by login tests');
}

class _Fixture {
  _Fixture({String language = 'en'})
      : language = PostDeeLanguageController(initialLocale: Locale(language));

  final PostDeeLanguageController language;
  final gateway = _FakeEmailGateway();
  late final shell = PostDeeShell(
    languageController: language,
    emailAuthGateway: gateway,
    loadScheduledPosts: () async => const [],
    loadRecentPosts: () async => const [],
    loadSocialConnections: () async => const [],
    loadSubscription: () async => const SubscriptionStatusResult(
      userId: 'fake-login-owner',
      plan: 'BASIC',
      status: 'INACTIVE',
      remainingPostsThisMonth: 3,
      monthlyPostLimit: 3,
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    ),
  );

  Widget app() => ListenableBuilder(
        listenable: language,
        builder: (_, __) => MaterialApp(
          locale: language.locale,
          supportedLocales: PostDeeLocalizations.supportedLocales,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light,
          home: shell,
        ),
      );
}

final _dialog = find.byKey(const ValueKey('email-sign-in-form'));
Finder get _email =>
    find.descendant(of: _dialog, matching: find.byType(TextField)).first;
Finder get _password =>
    find.descendant(of: _dialog, matching: find.byType(TextField)).last;
Finder get _submit =>
    find.descendant(of: _dialog, matching: find.byType(FilledButton));
final _forgot = find.byKey(const ValueKey('email-forgot-password'));
Finder get _cancel =>
    find.descendant(of: _dialog, matching: find.byType(TextButton)).last;
Finder get _toggle => find.descendant(
    of: _dialog, matching: find.text('New to PostDee? Create an account'));

Future<void> _open(WidgetTester tester, _Fixture fixture) async {
  SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
  PostDeeAuthSessionStore.instance.clear();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    PostDeeAuthSessionStore.instance.clear();
    fixture.language.dispose();
    AppTheme.applyThemeMode(ThemeMode.light);
  });
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('login-email-sign-in')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _fill(
  WidgetTester tester, {
  String email = ' seller@example.com ',
  String password = '  keep-password  ',
}) async {
  await tester.enterText(_email, email);
  await tester.enterText(_password, password);
}

void _expectInputs(WidgetTester tester) {
  expect(tester.widget<TextField>(_email).controller!.text,
      ' seller@example.com ');
  expect(tester.widget<TextField>(_password).controller!.text,
      '  keep-password  ');
}

void _expectControlsDisabled(WidgetTester tester) {
  for (final field in tester.widgetList<TextField>(
      find.descendant(of: _dialog, matching: find.byType(TextField)))) {
    expect(field.enabled, isFalse);
  }
  for (final button in tester.widgetList<ButtonStyleButton>(find.descendant(
      of: _dialog,
      matching:
          find.byWidgetPredicate((widget) => widget is ButtonStyleButton)))) {
    expect(button.onPressed, isNull);
  }
  expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
  expect(tester.widget<TextButton>(_cancel).onPressed, isNull);
}

void main() {
  testWidgets('English recovery success preserves non-enumerating feedback',
      (tester) async {
    final fixture = _Fixture();
    await _open(tester, fixture);
    await _fill(tester);
    await _tap(tester, _forgot);
    await tester.pumpAndSettle();
    expect(find.text(_resetSuccess), findsOneWidget);
    expect(fixture.gateway.resets, ['seller@example.com']);
    expect(fixture.gateway.signIns, isEmpty);
    expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
  });

  testWidgets('English known reset failure preserves input and permits retry',
      (tester) async {
    final fixture = _Fixture();
    fixture.gateway.onReset = () async => throw const AuthUnavailableException(
        'ส่งอีเมลตั้งรหัสผ่านไม่สำเร็จ กรุณาลองใหม่');
    await _open(tester, fixture);
    await _fill(tester);
    await _tap(tester, _forgot);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: _dialog,
            matching: find.text(
                'Could not send the password reset email. Please try again.')),
        findsOneWidget);
    expect(tester.widget<TextField>(_email).controller!.text,
        ' seller@example.com ');
    expect(tester.widget<TextField>(_password).controller!.text,
        '  keep-password  ');
    expect(tester.widget<TextButton>(_forgot).onPressed, isNotNull);
    expect(fixture.gateway.resets, ['seller@example.com']);
  });

  for (final createAccount in [false, true]) {
    testWidgets(
        'pending ${createAccount ? 'signup' : 'login'} preserves exact credentials and completes once',
        (tester) async {
      final pending = Completer<AuthSession>();
      final fixture = _Fixture();
      fixture.gateway.onSignIn = () => pending.future;
      await _open(tester, fixture);
      await _fill(tester);
      if (createAccount) {
        await _tap(tester, _toggle);
      }
      await _tap(tester, _submit);
      expect(find.text('Please wait...'), findsOneWidget);
      _expectControlsDisabled(tester);
      _expectInputs(tester);
      expect(fixture.gateway.signIns, [
        (
          email: 'seller@example.com',
          password: '  keep-password  ',
          createAccount: createAccount
        )
      ]);
      await _tap(tester, _submit);
      expect(fixture.gateway.signIns, hasLength(1));
      fixture.language.setLocale(const Locale('th'));
      await tester.pumpAndSettle();
      expect(find.text('กำลังดำเนินการ...'), findsOneWidget);
      _expectInputs(tester);
      _expectControlsDisabled(tester);
      pending.complete(_fakeSession);
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);
      expect(PostDeeAuthSessionStore.instance.session, same(_fakeSession));
      expect(fixture.gateway.signIns, hasLength(1));
      expect(fixture.gateway.resets, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'generic ${createAccount ? 'signup' : 'login'} failure follows live locale and keeps credentials',
        (tester) async {
      final pending = Completer<AuthSession>();
      final fixture = _Fixture();
      fixture.gateway.onSignIn = () => pending.future;
      await _open(tester, fixture);
      await _fill(tester);
      if (createAccount) await _tap(tester, _toggle);
      await _tap(tester, _submit);
      pending.completeError(StateError('fake sign-in failure'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: _dialog,
              matching: find.text('Could not sign in. Please try again.')),
          findsOneWidget);
      _expectInputs(tester);
      fixture.language.setLocale(const Locale('th'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: _dialog,
              matching: find.text('เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')),
          findsOneWidget);
      _expectInputs(tester);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
      expect(fixture.gateway.signIns, hasLength(1));
      expect(fixture.gateway.signIns.single.createAccount, createAccount);
      expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
    });
  }

  testWidgets(
      'pending recovery uses completion locale without disclosing account existence',
      (tester) async {
    final pending = Completer<void>();
    final fixture = _Fixture(language: 'th');
    fixture.gateway.onReset = () => pending.future;
    await _open(tester, fixture);
    await _fill(tester);
    await _tap(tester, _forgot);
    _expectControlsDisabled(tester);
    expect(fixture.gateway.resets, ['seller@example.com']);
    fixture.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('Please wait...'), findsOneWidget);
    _expectInputs(tester);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text(_resetSuccess), findsOneWidget);
    expect(fixture.gateway.signIns, isEmpty);
    expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
    fixture.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    expect(find.textContaining('หากอีเมลนี้มีบัญชี'), findsOneWidget);
    _expectInputs(tester);
    expect(fixture.gateway.resets, hasLength(1));
  });

  testWidgets('reset failure switches live then retries without a login call',
      (tester) async {
    final fixture = _Fixture();
    fixture.gateway.onReset = () async => throw const AuthUnavailableException(
        'ส่งอีเมลตั้งรหัสผ่านไม่สำเร็จ กรุณาลองใหม่');
    await _open(tester, fixture);
    await _fill(tester);
    await _tap(tester, _forgot);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: _dialog,
            matching: find.text(
                'Could not send the password reset email. Please try again.')),
        findsOneWidget);
    fixture.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: _dialog,
            matching: find.text('ส่งอีเมลตั้งรหัสผ่านไม่สำเร็จ กรุณาลองใหม่')),
        findsOneWidget);
    _expectInputs(tester);
    fixture.gateway.onReset = null;
    fixture.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    await _tap(tester, _forgot);
    await tester.pumpAndSettle();
    expect(find.text(_resetSuccess), findsOneWidget);
    expect(
        find.descendant(
            of: _dialog,
            matching: find.text(
                'Could not send the password reset email. Please try again.')),
        findsNothing);
    expect(
        fixture.gateway.resets, ['seller@example.com', 'seller@example.com']);
    expect(fixture.gateway.signIns, isEmpty);
  });

  for (final isRecovery in [false, true]) {
    testWidgets(
        'unknown ${isRecovery ? 'reset' : 'login'} error is unchanged across languages',
        (tester) async {
      const raw = 'provider-code-81: ข้อความเฉพาะจากผู้ให้บริการ';
      final fixture = _Fixture();
      if (isRecovery) {
        fixture.gateway.onReset =
            () async => throw const AuthUnavailableException(raw);
      } else {
        fixture.gateway.onSignIn =
            () async => throw const AuthUnavailableException(raw);
      }
      await _open(tester, fixture);
      await _fill(tester);
      await _tap(tester, isRecovery ? _forgot : _submit);
      await tester.pumpAndSettle();
      expect(find.descendant(of: _dialog, matching: find.text(raw)),
          findsOneWidget);
      fixture.language.setLocale(const Locale('th'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: _dialog, matching: find.text(raw)),
          findsOneWidget);
      fixture.language.setLocale(const Locale('en'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: _dialog, matching: find.text(raw)),
          findsOneWidget);
      _expectInputs(tester);
      expect(
          isRecovery
              ? fixture.gateway.resets.length
              : fixture.gateway.signIns.length,
          1);
      expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
    });
  }

  testWidgets(
      'Cancel discards email signup input without making auth or recovery calls',
      (tester) async {
    final fixture = _Fixture();
    await _open(tester, fixture);
    await _fill(tester);
    await _tap(tester, _toggle);
    await _tap(tester, _cancel);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(fixture.gateway.signIns, isEmpty);
    expect(fixture.gateway.resets, isEmpty);
    await _tap(tester, find.byKey(const ValueKey('login-email-sign-in')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_email).controller!.text, isEmpty);
    expect(tester.widget<TextField>(_password).controller!.text, isEmpty);
    expect(find.descendant(of: _dialog, matching: find.text('Sign in')),
        findsOneWidget);
  });

  for (final isRecovery in [false, true]) {
    testWidgets(
        'disposed login screen ignores late ${isRecovery ? 'reset' : 'sign-in'} completion',
        (tester) async {
      final signIn = Completer<AuthSession>();
      final reset = Completer<void>();
      final fixture = _Fixture();
      fixture.gateway.onSignIn = () => signIn.future;
      fixture.gateway.onReset = () => reset.future;
      await _open(tester, fixture);
      await _fill(tester);
      await _tap(tester, isRecovery ? _forgot : _submit);
      await tester.pumpWidget(const SizedBox());
      if (isRecovery) {
        reset.complete();
      } else {
        signIn.complete(_fakeSession);
      }
      await tester.pumpAndSettle();
      expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'replacement session survives late ${isRecovery ? 'reset' : 'login'} completion',
        (tester) async {
      final signIn = Completer<AuthSession>();
      final reset = Completer<void>();
      final fixture = _Fixture();
      fixture.gateway.onSignIn = () => signIn.future;
      fixture.gateway.onReset = () => reset.future;
      await _open(tester, fixture);
      await _fill(tester);
      await _tap(tester, isRecovery ? _forgot : _submit);
      PostDeeAuthSessionStore.instance.signIn(_otherSession);
      if (isRecovery) {
        reset.complete();
      } else {
        signIn.complete(_fakeSession);
      }
      // A replacement owner mounts the whole Shell, whose unrelated loaders may
      // animate. Settle the auth completion without waiting on those screens.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(PostDeeAuthSessionStore.instance.session, same(_otherSession));
      expect(find.text(_resetSuccess), findsNothing);
      expect(fixture.gateway.signIns, hasLength(isRecovery ? 0 : 1));
      expect(fixture.gateway.resets, hasLength(isRecovery ? 1 : 0));
      expect(tester.takeException(), isNull);
    });
  }

  const googleMessages = <String, String>{
    _googleCredentialError: _googleCredentialErrorThai,
    'Google sign-in was canceled. Please try again.':
        'ยกเลิกการเข้าสู่ระบบด้วย Google แล้ว กรุณาลองอีกครั้ง',
    'Google sign-in is not configured correctly. Please contact support.':
        'การตั้งค่าเข้าสู่ระบบด้วย Google ยังไม่ถูกต้อง กรุณาติดต่อทีมงาน',
  };
  for (final message in googleMessages.entries) {
    testWidgets(
        'known Google error renders with current locale: ${message.key}',
        (tester) async {
      final fixture = _Fixture();
      fixture.gateway.onSignIn =
          () async => throw AuthUnavailableException(message.key);
      await _open(tester, fixture);
      await _fill(tester);
      await _tap(tester, _submit);
      await tester.pumpAndSettle();
      expect(find.descendant(of: _dialog, matching: find.text(message.key)),
          findsOneWidget);
      fixture.language.setLocale(const Locale('th'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: _dialog, matching: find.text(message.value)),
          findsOneWidget);
      _expectInputs(tester);
      fixture.language.setLocale(const Locale('en'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: _dialog, matching: find.text(message.key)),
          findsOneWidget);
      expect(fixture.gateway.signIns, hasLength(1));
      expect(fixture.gateway.resets, isEmpty);
      expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
    });
  }

  testWidgets(
      'auth message helper uses Thai fallback and preserves unknown text',
      (tester) async {
    const raw = 'custom untranslated provider message';
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Column(
                  children: [
                    Text(localizeAuthMessage(context, _googleCredentialError)),
                    Text(localizeAuthMessage(context, raw))
                  ],
                ))));
    expect(find.text(_googleCredentialErrorThai), findsOneWidget);
    expect(find.text(raw), findsOneWidget);
    expect(find.textContaining('ยังไม่พบบัญชี'), findsNothing);
  });

  for (final isRecovery in [false, true]) {
    testWidgets(
        '${isRecovery ? 'reset' : 'login'} timeout is localized and ignores late completion',
        (tester) async {
      final signIn = Completer<AuthSession>();
      final reset = Completer<void>();
      final fixture = _Fixture();
      fixture.gateway.onSignIn = () => signIn.future;
      fixture.gateway.onReset = () => reset.future;
      await _open(tester, fixture);
      await _fill(tester);
      await _tap(tester, isRecovery ? _forgot : _submit);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      final english = isRecovery
          ? 'This is taking too long. Please try again.'
          : 'Sign-in is taking too long. Check your internet connection and try again.';
      expect(find.descendant(of: _dialog, matching: find.text(english)),
          findsOneWidget);
      _expectInputs(tester);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
      if (isRecovery) {
        reset.complete();
      } else {
        signIn.complete(_fakeSession);
      }
      await tester.pumpAndSettle();
      expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
      expect(find.text(_resetSuccess), findsNothing);
      expect(
          isRecovery
              ? fixture.gateway.resets.length
              : fixture.gateway.signIns.length,
          1);
    });
  }
}
