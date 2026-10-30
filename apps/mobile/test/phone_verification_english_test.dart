import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/auth/phone_verification_screen.dart';
import 'package:postdee_mobile/features/auth/phone_verification_service.dart';

const _owner = 'english-phone-owner';
const _verifiedSession = AuthSession(userId: _owner, idToken: 'verified-token');

class _Fixture {
  _Fixture(
      {Locale locale = const Locale('en'),
      this.dark = false,
      this.scale = 1,
      this.firebase = false,
      this.mock = false})
      : language = ValueNotifier(locale);

  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final bool firebase;
  final bool mock;
  final sessions = PostDeeAuthSessionStore(
      initialSession: const AuthSession(userId: _owner, idToken: 'fake-token'));
  final sentTo = <String>[];
  final confirmed = <({String id, String code})>[];
  final verified = <AuthSession>[];
  final results = <AuthSession?>[];

  Future<PhoneVerificationStartResult> send(String phone) async {
    sentTo.add(phone);
    return const PhoneVerificationStartResult.codeSent(
        verificationId: 'english-phone-request');
  }

  Future<AuthSession> confirm({
    required String verificationId,
    required String smsCode,
  }) async {
    confirmed.add((id: verificationId, code: smsCode));
    return _verifiedSession;
  }

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
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
                builder: (context) => Scaffold(
                      body: Center(
                          child: ElevatedButton(
                        key: const ValueKey('open-phone-verification'),
                        onPressed: () async {
                          results.add(
                              await Navigator.of(context).push<AuthSession>(
                            MaterialPageRoute(
                                builder: (_) => PhoneVerificationScreen(
                                      sessionStore: sessions,
                                      enableFirebaseAuth: firebase,
                                      allowLocalMockVerification: mock,
                                      sendCode: send,
                                      confirmCode: confirm,
                                      onVerified: verified.add,
                                    )),
                          ));
                        },
                        child: const Text('Open phone verification'),
                      )),
                    )),
          );
        },
      );

  void dispose() {
    language.dispose();
    sessions.dispose();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _open(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await tester.tap(_key('open-phone-verification'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _request(WidgetTester tester,
    [String phone = '0812345678']) async {
  await tester.enterText(_key('phone-verification-phone-field'), phone);
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _tap(tester, _key('phone-verification-send-code'));
}

const _phoneHelper =
    'Enter a 10-digit Thai mobile number, or an international number with +country code';
const _phoneValidation =
    'Enter a 10-digit Thai mobile number, e.g. 0812345678, or an international number with its country code.';

void _readable(WidgetTester tester, Finder text) {
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first);
  final fullText = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler)
    ..layout(maxWidth: paragraph.size.width);
  final details = '${tester.widget<Text>(text).data}: size=${paragraph.size}, '
      'intrinsicHeight=${paragraph.getMinIntrinsicHeight(paragraph.size.width)}, '
      'maxLines=${paragraph.maxLines}, softWrap=${paragraph.softWrap}, '
      'overflow=${paragraph.overflow}, fullHeight=${fullText.height}, '
      'fullLines=${fullText.computeLineMetrics().length}';
  fullText.dispose();
  expect(paragraph.didExceedMaxLines, isFalse, reason: details);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5),
      reason: details);
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _typeWithKeyboard(
    WidgetTester tester, Finder field, String value) async {
  await _reveal(tester, field);
  await tester.showKeyboard(field);
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.enterText(field, value);
  final editableFinder =
      find.descendant(of: field, matching: find.byType(EditableText));
  await tester.ensureVisible(editableFinder);
  await tester.pumpAndSettle();
  final editable =
      tester.state<EditableTextState>(editableFinder).renderEditable;
  expect(editable.size.height,
      greaterThanOrEqualTo(editable.preferredLineHeight - 0.5));
  final controller = tester.widget<TextField>(field).controller!;
  final caret = editable.getLocalRectForCaret(
      TextPosition(offset: controller.selection.extentOffset));
  expect(caret.top, greaterThanOrEqualTo(-0.5));
  expect(caret.bottom, lessThanOrEqualTo(editable.size.height + 0.5));
  final globalCaret = caret.shift(editable.localToGlobal(Offset.zero));
  expect(globalCaret.top,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar)).dy - 0.5));
  expect(globalCaret.bottom, lessThanOrEqualTo(440));
  expect(tester.testTextInput.isVisible, isTrue);
  tester.testTextInput.hide();
  tester.view.resetViewInsets();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  testWidgets('English phone entry names its title and phone input',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    expect(find.text('Verify phone number'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);
    expect(fixture.sentTo, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English OTP step retains its destination and initial cooldown',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    await _request(tester);
    expect(find.text('Enter OTP'), findsOneWidget);
    expect(
        find.text('A 6-digit code was sent to +66812345678'), findsOneWidget);
    expect(find.text('Resend code (wait 30 seconds)'), findsOneWidget);
    expect(fixture.sentTo, ['+66812345678']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored phone validation switches to English without losing input',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    final state = tester.state(find.byType(PhoneVerificationScreen));
    await _request(tester, '081234');
    expect(find.textContaining('กรอกเบอร์โทรมือถือไทย'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PhoneVerificationScreen)), same(state));
    expect(find.textContaining('กรอกเบอร์โทรมือถือไทย'), findsNothing);
    expect(find.text(_phoneValidation), findsOneWidget);
    expect(
        tester
            .widget<TextField>(_key('phone-verification-phone-field'))
            .controller!
            .text,
        '081234');
    expect(fixture.sentTo, isEmpty);
    expect(fixture.confirmed, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('last cooldown second uses singular wording on both entry steps',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    await _request(tester);
    await tester.pump(const Duration(seconds: 29));
    await tester.pump();
    expect(find.text('Resend code (wait 1 second)'), findsOneWidget);
    await _tap(tester, _key('phone-verification-change-phone'));
    expect(find.text('Send OTP (wait 1 second)'), findsOneWidget);
    expect(fixture.sentTo, ['+66812345678']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English phone instructions retain the Basic verification requirement',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    expect(
        find.text('Verify your phone to unlock free posting'), findsOneWidget);
    expect(
        find.text(
            'The Basic plan requires phone verification before you can use its 3 free post units per month.'),
        findsOneWidget);
    final phone =
        tester.widget<TextField>(_key('phone-verification-phone-field'));
    expect(phone.keyboardType, TextInputType.phone);
    expect(phone.decoration!.hintText, '0812345678 or +66812345678');
    expect(find.text(_phoneHelper), findsOneWidget);
    expect(fixture.sentTo, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'international input retains its country code in English instructions',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    await _request(tester, '  +44 7700-900123  ');
    expect(fixture.sentTo, ['+447700900123']);
    expect(
        find.text('A 6-digit code was sent to +447700900123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English OTP input keeps six-digit numeric formatting',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    await _request(tester);
    final code = _key('phone-verification-code-field');
    await tester.enterText(code, 'ab12.34x567890');
    final input = tester.widget<TextField>(code);
    expect(find.text('OTP code'), findsOneWidget);
    expect(input.decoration!.hintText, '123456');
    expect(input.keyboardType, TextInputType.number);
    expect(input.maxLength, 6);
    expect(input.controller!.text, '123456');
    expect(fixture.confirmed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'live OTP locale changes retain typed code selection and cooldown',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    await _request(tester);
    final state = tester.state(find.byType(PhoneVerificationScreen));
    final code = _key('phone-verification-code-field');
    await tester.enterText(code, '456789');
    final controller = tester.widget<TextField>(code).controller!;
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Resend code (wait 25 seconds)'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กรอกรหัส OTP'), findsOneWidget);
    expect(find.text('ส่งรหัส 6 หลักไปที่ +66812345678'), findsOneWidget);
    expect(find.text('ส่งรหัสอีกครั้ง (รอ 25 วินาที)'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PhoneVerificationScreen)), same(state));
    expect(tester.widget<TextField>(code).controller, same(controller));
    expect(controller.text, '456789');
    expect(controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3));
    expect(
        find.text('A 6-digit code was sent to +66812345678'), findsOneWidget);
    expect(find.text('Resend code (wait 25 seconds)'), findsOneWidget);
    expect(fixture.sentTo, ['+66812345678']);
    expect(fixture.confirmed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'verified success copy switches locale before Done returns its session',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    await _request(tester);
    await tester.enterText(_key('phone-verification-code-field'), '123456');
    await _tap(tester, _key('phone-verification-confirm-code'));
    expect(find.text('ยืนยันเบอร์เรียบร้อย'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Phone number verified'), findsOneWidget);
    expect(
        find.text('You can now use your Basic plan\'s free posting allowance.'),
        findsOneWidget);
    expect(fixture.results, isEmpty);
    expect(fixture.verified, [_verifiedSession]);
    await _tap(tester, find.text('Done'));
    expect(fixture.results, [_verifiedSession]);
    expect(fixture.confirmed, hasLength(1));
    expect(fixture.verified, [_verifiedSession]);
    expect(tester.takeException(), isNull);
  });

  for (final flags in [
    (false, false),
    (false, true),
    (true, false),
    (true, true)
  ]) {
    testWidgets(
        'demo OTP notice follows the existing Firebase/mock gate $flags',
        (tester) async {
      final fixture = _Fixture(firebase: flags.$1, mock: flags.$2);
      addTearDown(fixture.dispose);
      await _open(tester, fixture);
      await _request(tester);
      final demo = find.byWidgetPredicate((widget) =>
          widget is Text &&
          widget.textSpan?.toPlainText() == 'Test mode: use code 123456');
      expect(demo, !flags.$1 && flags.$2 ? findsOneWidget : findsNothing);
      expect(
          tester
              .widget<TextField>(_key('phone-verification-code-field'))
              .decoration!
              .hintText,
          '123456');
      expect(fixture.sentTo, ['+66812345678']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'visible demo notice follows locale without starting a new request',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'), mock: true);
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    await _request(tester);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText() == 'โหมดทดสอบ: ใช้รหัส 123456'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText() == 'Test mode: use code 123456'),
        findsOneWidget);
    expect(fixture.sentTo, hasLength(1));
    expect(fixture.confirmed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Back returns no verified session and does not dispatch typed input',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _open(tester, fixture);
    await tester.enterText(
        _key('phone-verification-phone-field'), '0812345678');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(fixture.results, [null]);
    expect(fixture.sentTo, isEmpty);
    expect(fixture.confirmed, isEmpty);
    expect(fixture.verified, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain MaterialApp retains the existing Thai phone entry',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    AppTheme.applyThemeMode(ThemeMode.light);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: PhoneVerificationScreen(
        sessionStore: fixture.sessions,
        sendCode: fixture.send,
        confirmCode: fixture.confirm,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันเบอร์โทร'), findsOneWidget);
    expect(find.text('ยืนยันเบอร์เพื่อปลดล็อกโพสต์ฟรี'), findsOneWidget);
    expect(find.text('ส่งรหัส OTP'), findsOneWidget);
    await _request(tester, '081234');
    expect(find.textContaining('กรอกเบอร์โทรมือถือไทย'), findsOneWidget);
    expect(fixture.sentTo, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'phone validation and gated demo notice fit 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _Fixture(dark: dark, scale: 2, mock: true);
      addTearDown(fixture.dispose);
      await _open(tester, fixture);
      await _request(tester, '081234');
      await _reveal(tester, find.text(_phoneValidation));
      _readable(tester, find.text(_phoneValidation));
      expect(fixture.sentTo, isEmpty);
      await _request(tester);
      final demo = find.byWidgetPredicate((widget) =>
          widget is Text &&
          widget.textSpan?.toPlainText() == 'Test mode: use code 123456');
      await _reveal(tester, demo);
      _readable(tester, demo);
      expect(fixture.sentTo, ['+66812345678']);
      expect(fixture.confirmed, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'all English phone steps and keyboard fit 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final fixture = _Fixture(dark: dark, scale: 2);
      addTearDown(fixture.dispose);
      await _open(tester, fixture);
      expect(find.byType(BackButton), findsOneWidget);
      _readable(tester, find.text('Verify phone number'));
      for (final label in [
        'Verify your phone to unlock free posting',
        'The Basic plan requires phone verification before you can use its 3 free post units per month.',
        'Phone number',
        'Send OTP',
        _phoneHelper,
      ]) {
        await _reveal(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      await _typeWithKeyboard(
          tester, _key('phone-verification-phone-field'), '0812345678');
      await _tap(tester, _key('phone-verification-send-code'));
      for (final label in [
        'Enter OTP',
        'A 6-digit code was sent to +66812345678',
        'OTP code',
        'Verify',
        'Change number',
      ]) {
        await _reveal(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      final resend = find.descendant(
          of: _key('phone-verification-resend-code'),
          matching: find.byType(Text));
      await _reveal(tester, resend);
      _readable(tester, resend);
      await _typeWithKeyboard(
          tester, _key('phone-verification-code-field'), '123456');
      await _tap(tester, _key('phone-verification-confirm-code'));
      for (final label in [
        'Phone number verified',
        'You can now use your Basic plan\'s free posting allowance.',
        'Done',
      ]) {
        await _reveal(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      await _tap(tester, find.text('Done'));
      expect(fixture.results, [_verifiedSession]);
      expect(fixture.sentTo, ['+66812345678']);
      expect(
          fixture.confirmed, [(id: 'english-phone-request', code: '123456')]);
      expect(fixture.verified, [_verifiedSession]);
      expect(tester.takeException(), isNull);
    });
  }
}
