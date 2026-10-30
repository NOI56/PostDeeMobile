import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';
import 'package:postdee_mobile/features/auth/phone_verification_screen.dart';
import 'package:postdee_mobile/features/auth/phone_verification_service.dart';

const _owner = AuthSession(userId: 'phone-flow-owner', idToken: 'original');
const _verified = AuthSession(userId: 'phone-flow-owner', idToken: 'verified');
const _other = AuthSession(userId: 'other-owner', idToken: 'other');

class _NoNativePhoneAuth implements FirebasePhoneAuthAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Native phone authentication must not be reached');
}

class _CancellationProbe extends FirebasePhoneVerificationGateway {
  _CancellationProbe(PostDeeAuthSessionStore sessions)
      : super(phoneAuthAdapter: _NoNativePhoneAuth(), sessionStore: sessions);

  int cancellations = 0;

  @override
  void cancelVerification() => cancellations++;
}

class _Fixture {
  _Fixture({String language = 'en'}) : locale = ValueNotifier(Locale(language));

  final ValueNotifier<Locale> locale;
  final sessions = PostDeeAuthSessionStore(initialSession: _owner);
  final sentTo = <String>[];
  final confirmed = <({String id, String code})>[];
  final callbacks = <AuthSession>[];
  final results = <AuthSession?>[];
  late final gateway = _CancellationProbe(sessions);
  PhoneVerificationCodeSender? onSend;
  PhoneVerificationCodeConfirmer? onConfirm;

  Future<PhoneVerificationStartResult> send(String phone) async {
    sentTo.add(phone);
    return onSend != null
        ? onSend!(phone)
        : PhoneVerificationStartResult.codeSent(
            verificationId: 'request-${sentTo.length}');
  }

  Future<AuthSession> confirm({
    required String verificationId,
    required String smsCode,
  }) async {
    confirmed.add((id: verificationId, code: smsCode));
    return onConfirm != null
        ? onConfirm!(verificationId: verificationId, smsCode: smsCode)
        : _verified;
  }

  Widget app() => ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) => MaterialApp(
          locale: value,
          supportedLocales: PostDeeLocalizations.supportedLocales,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-phone-flow'),
                onPressed: () async {
                  results.add(await Navigator.of(context).push<AuthSession>(
                    MaterialPageRoute(
                      builder: (_) => PhoneVerificationScreen(
                        sessionStore: sessions,
                        enableFirebaseAuth: false,
                        allowLocalMockVerification: false,
                        firebasePhoneVerificationGateway: gateway,
                        sendCode: send,
                        confirmCode: confirm,
                        onVerified: callbacks.add,
                      ),
                    ),
                  ));
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
}

Finder _key(String name) => find.byKey(ValueKey(name));
final _phone = _key('phone-verification-phone-field');
final _code = _key('phone-verification-code-field');
final _send = _key('phone-verification-send-code');
final _confirm = _key('phone-verification-confirm-code');
final _resend = _key('phone-verification-resend-code');
final _change = _key('phone-verification-change-phone');

Future<void> _open(WidgetTester tester, _Fixture fixture) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    fixture.sessions.dispose();
    fixture.locale.dispose();
  });
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await tester.tap(_key('open-phone-flow'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _request(WidgetTester tester,
    [String number = '081-234 5678']) async {
  await tester.enterText(_phone, number);
  await _tap(tester, _send);
}

Future<void> _verify(WidgetTester tester, [String code = '654321']) async {
  await tester.enterText(_code, code);
  await _tap(tester, _confirm);
}

void main() {
  testWidgets('English pending send is single flight and normalizes its number',
      (tester) async {
    final pending = Completer<PhoneVerificationStartResult>();
    final fixture = _Fixture()..onSend = (_) => pending.future;
    await _open(tester, fixture);
    await _request(tester);
    expect(find.text('Sending code...'), findsOneWidget);
    await _tap(tester, _send);
    expect(fixture.sentTo, ['+66812345678']);
    pending.complete(const PhoneVerificationStartResult.codeSent(
        verificationId: 'first-request'));
    await tester.pumpAndSettle();
    expect(
        find.text('A 6-digit code was sent to +66812345678'), findsOneWidget);
    expect(fixture.sessions.session, same(_owner));
    expect(fixture.callbacks, isEmpty);
  });

  testWidgets(
      'English generic send failure is recoverable without verification',
      (tester) async {
    final fixture = _Fixture()..onSend = (_) async => throw StateError('fake');
    await _open(tester, fixture);
    await _request(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not send OTP.'), findsOneWidget);
    expect(fixture.sentTo, ['+66812345678']);
    expect(fixture.callbacks, isEmpty);
    expect(fixture.results, isEmpty);
    expect(fixture.sessions.session, same(_owner));
  });

  testWidgets('manual OTP confirmation and route result each complete once',
      (tester) async {
    final pending = Completer<AuthSession>();
    final fixture = _Fixture()
      ..onConfirm =
          ({required verificationId, required smsCode}) => pending.future;
    await _open(tester, fixture);
    await _request(tester, '  +1 415-555-2671  ');
    await tester.pumpAndSettle();
    await _verify(tester, '987654');
    expect(find.text('Verifying...'), findsOneWidget);
    expect(tester.widget<TextButton>(_change).onPressed, isNull);
    await _tap(tester, _confirm);
    expect(fixture.confirmed, [(id: 'request-1', code: '987654')]);
    pending.complete(_verified);
    await tester.pumpAndSettle();
    expect(find.text('Phone number verified'), findsOneWidget);
    expect(fixture.callbacks, [_verified]);
    expect(fixture.results, isEmpty);
    expect(fixture.sessions.session, same(_owner));
    await _tap(tester, find.text('Done'));
    await tester.pumpAndSettle();
    expect(fixture.results, [_verified]);
    expect(fixture.callbacks, [_verified]);
    expect(fixture.sentTo, ['+14155552671']);
  });

  testWidgets(
      'automatic verification skips manual confirmation and returns once',
      (tester) async {
    final fixture = _Fixture()
      ..onSend = (_) async =>
          const PhoneVerificationStartResult.autoVerified(session: _verified);
    await _open(tester, fixture);
    await _request(tester);
    await tester.pumpAndSettle();
    expect(find.text('Phone number verified'), findsOneWidget);
    expect(_code, findsNothing);
    expect(fixture.confirmed, isEmpty);
    expect(fixture.callbacks, [_verified]);
    expect(fixture.sessions.session, same(_owner));
    await _tap(tester, find.text('Done'));
    await tester.pumpAndSettle();
    expect(fixture.results, [_verified]);
  });

  testWidgets(
      'resend waits 30 seconds and verifies only the replacement request',
      (tester) async {
    final pending = Completer<PhoneVerificationStartResult>();
    final fixture = _Fixture();
    fixture.onSend = (_) async => fixture.sentTo.length == 1
        ? const PhoneVerificationStartResult.codeSent(verificationId: 'old-id')
        : pending.future;
    await _open(tester, fixture);
    await _request(tester);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(_resend).onPressed, isNull);
    await _tap(tester, _resend);
    expect(fixture.sentTo, hasLength(1));
    await tester.pump(const Duration(seconds: 29));
    await tester.pump();
    expect(find.text('Resend code (wait 1 second)'), findsOneWidget);
    expect(tester.widget<TextButton>(_resend).onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.enterText(_code, '111111');
    await _tap(tester, _resend);
    expect(fixture.sentTo, ['+66812345678', '+66812345678']);
    expect(tester.widget<TextButton>(_resend).onPressed, isNull);
    expect(tester.widget<TextButton>(_change).onPressed, isNull);
    expect(tester.widget<TextField>(_code).controller!.text, isEmpty);
    pending.complete(const PhoneVerificationStartResult.codeSent(
        verificationId: 'replacement-id'));
    await tester.pumpAndSettle();
    expect(find.text('Resend code (wait 30 seconds)'), findsOneWidget);
    await _verify(tester);
    await tester.pumpAndSettle();
    expect(fixture.confirmed, [(id: 'replacement-id', code: '654321')]);
    expect(fixture.callbacks, [_verified]);
  });

  testWidgets('changing number cancels its request without bypassing cooldown',
      (tester) async {
    final fixture = _Fixture();
    await _open(tester, fixture);
    await _request(tester);
    await tester.pumpAndSettle();
    await tester.enterText(_code, '111111');
    final cancellations = fixture.gateway.cancellations;
    await _tap(tester, _change);
    await tester.pumpAndSettle();
    expect(fixture.gateway.cancellations, cancellations + 1);
    expect(_code, findsNothing);
    expect(find.textContaining('Send OTP (wait '), findsOneWidget);
    await tester.enterText(_phone, '0891234567');
    await _tap(tester, _send);
    expect(fixture.sentTo, ['+66812345678']);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    await _tap(tester, _send);
    await tester.pumpAndSettle();
    expect(fixture.sentTo, ['+66812345678', '+66891234567']);
    expect(tester.widget<TextField>(_code).controller!.text, isEmpty);
    await _verify(tester, '222222');
    await tester.pumpAndSettle();
    expect(fixture.confirmed, [(id: 'request-2', code: '222222')]);
  });

  testWidgets('pending send error uses current locale and can switch back live',
      (tester) async {
    final pending = Completer<PhoneVerificationStartResult>();
    final fixture = _Fixture(language: 'th')..onSend = (_) => pending.future;
    await _open(tester, fixture);
    await _request(tester);
    expect(find.text('กำลังส่งรหัส...'), findsOneWidget);
    fixture.locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Sending code...'), findsOneWidget);
    pending.completeError(StateError('fake sender failure'));
    await tester.pumpAndSettle();
    expect(find.text('Could not send OTP.'), findsOneWidget);
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ส่งรหัส OTP ไม่สำเร็จ'), findsOneWidget);
    expect(fixture.sentTo, ['+66812345678']);
    expect(fixture.callbacks, isEmpty);
    expect(tester.widget<TextField>(_phone).controller!.text, '+66812345678');
  });

  const providerMessages = <String, String>{
    'ตรวจสอบเบอร์โทรมือถือและรหัสประเทศ เช่น 0812345678 หรือ +66812345678':
        'Check your mobile number and country code, e.g. 0812345678 or +66812345678.',
    'รหัส OTP ไม่ถูกต้อง กรุณากรอกรหัสล่าสุดจาก SMS อีกครั้ง':
        'Invalid OTP. Enter the latest code from your SMS.',
    'รหัส OTP หมดอายุแล้ว กรุณากดส่งรหัสอีกครั้ง':
        'Your OTP has expired. Please request a new code.',
    'ส่งคำขอบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่':
        'Too many requests. Please wait a moment and try again.',
    'ระบบส่ง SMS ไม่พร้อมชั่วคราว กรุณาลองใหม่ภายหลัง':
        'SMS delivery is temporarily unavailable. Please try again later.',
    'เชื่อมต่อไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่':
        'Could not connect. Check your internet connection and try again.',
    'เบอร์นี้ใช้กับบัญชีอื่นแล้ว กรุณาใช้เบอร์อื่นหรือเข้าสู่บัญชีเดิม':
        'This number is linked to another account. Use another number or sign in to the original account.',
    'ยืนยันเบอร์โทรไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
        'Could not verify your phone number. Please try again.',
    'รหัส OTP ไม่ถูกต้อง (โหมดทดสอบใช้ 123456)':
        'Invalid OTP (test mode uses 123456).',
  };

  for (final message in providerMessages.entries) {
    testWidgets('known error follows locale: ${message.value}', (tester) async {
      final fixture = _Fixture()
        ..onConfirm = ({required verificationId, required smsCode}) async =>
            throw AuthUnavailableException(message.key);
      await _open(tester, fixture);
      await _request(tester);
      await tester.pumpAndSettle();
      await _verify(tester);
      await tester.pumpAndSettle();
      expect(find.text(message.value), findsOneWidget);
      expect(find.text(message.key), findsNothing);
      fixture.locale.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(find.text(message.key), findsOneWidget);
      expect(fixture.confirmed, [(id: 'request-1', code: '654321')]);
      expect(fixture.callbacks, isEmpty);
      expect(fixture.sessions.session, same(_owner));
    });
  }

  for (final isConfirm in [false, true]) {
    testWidgets(
        'unknown ${isConfirm ? 'confirmation' : 'sender'} error stays raw',
        (tester) async {
      const raw = 'ข้อความเฉพาะผู้ให้บริการ provider-code-42';
      final fixture = _Fixture();
      if (isConfirm) {
        fixture.onConfirm = (
                {required verificationId, required smsCode}) async =>
            throw const AuthUnavailableException(raw);
      } else {
        fixture.onSend = (_) async => throw const AuthUnavailableException(raw);
      }
      await _open(tester, fixture);
      await _request(tester);
      await tester.pumpAndSettle();
      if (isConfirm) {
        await _verify(tester);
        await tester.pumpAndSettle();
      }
      expect(find.text(raw), findsOneWidget);
      fixture.locale.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(find.text(raw), findsOneWidget);
      fixture.locale.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text(raw), findsOneWidget);
      expect(fixture.callbacks, isEmpty);
    });
  }

  testWidgets('pending generic confirmation error uses completion locale',
      (tester) async {
    final pending = Completer<AuthSession>();
    final fixture = _Fixture(language: 'th')
      ..onConfirm =
          ({required verificationId, required smsCode}) => pending.future;
    await _open(tester, fixture);
    await _request(tester);
    await tester.pumpAndSettle();
    await _verify(tester);
    fixture.locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Verifying...'), findsOneWidget);
    pending.completeError(StateError('fake confirmation failure'));
    await tester.pumpAndSettle();
    expect(find.text('Could not verify the code.'), findsOneWidget);
    expect(fixture.callbacks, isEmpty);
    expect(tester.widget<TextField>(_code).controller!.text, '654321');
  });

  for (final isConfirm in [false, true]) {
    testWidgets(
        'expired ${isConfirm ? 'confirmation' : 'send'} remains unverified',
        (tester) async {
      final fixture = _Fixture();
      if (isConfirm) {
        fixture.onConfirm = (
                {required verificationId, required smsCode}) async =>
            throw const AuthSessionChangedException();
      } else {
        fixture.onSend = (_) async => throw const AuthSessionChangedException();
      }
      await _open(tester, fixture);
      await _request(tester);
      await tester.pumpAndSettle();
      if (isConfirm) {
        await _verify(tester);
        await tester.pumpAndSettle();
      }
      expect(
          find.text(
              'The verification request has expired. Please send a new code.'),
          findsOneWidget);
      expect(fixture.callbacks, isEmpty);
      expect(fixture.results, isEmpty);
      expect(fixture.sessions.session, same(_owner));
    });
  }

  for (final phase in ['send', 'confirm', 'resend']) {
    testWidgets('owner replacement ignores late $phase completion',
        (tester) async {
      final sent = Completer<PhoneVerificationStartResult>();
      final confirmed = Completer<AuthSession>();
      final fixture = _Fixture();
      fixture.onSend = (_) async =>
          phase == 'send' || fixture.sentTo.length == 2
              ? sent.future
              : const PhoneVerificationStartResult.codeSent(
                  verificationId: 'first');
      fixture.onConfirm =
          ({required verificationId, required smsCode}) => confirmed.future;
      await _open(tester, fixture);
      await _request(tester);
      if (phase == 'confirm') {
        await tester.pumpAndSettle();
        await _verify(tester);
      } else if (phase == 'resend') {
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 30));
        await tester.pump();
        await _tap(tester, _resend);
      }
      fixture.sessions.signIn(_other);
      if (phase == 'confirm') {
        confirmed.complete(_verified);
      } else {
        sent.complete(const PhoneVerificationStartResult.autoVerified(
            session: _verified));
      }
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Your account has changed. Please reopen phone verification.'),
          findsOneWidget);
      expect(find.text('Phone number verified'), findsNothing);
      expect(_code, findsNothing);
      expect(tester.widget<TextField>(_phone).controller!.text, isEmpty);
      expect(fixture.callbacks, isEmpty);
      expect(fixture.results, isEmpty);
      expect(fixture.sessions.session, same(_other));
      final calls = fixture.sentTo.length;
      await tester.enterText(_phone, '0891234567');
      await _tap(tester, _send);
      expect(fixture.sentTo, hasLength(calls));
      expect(tester.takeException(), isNull);
    });
  }

  for (final isConfirm in [false, true]) {
    testWidgets(
        'mismatched ${isConfirm ? 'manual' : 'automatic'} owner is rejected',
        (tester) async {
      final fixture = _Fixture();
      if (isConfirm) {
        fixture.onConfirm =
            ({required verificationId, required smsCode}) async => _other;
      } else {
        fixture.onSend = (_) async =>
            const PhoneVerificationStartResult.autoVerified(session: _other);
      }
      await _open(tester, fixture);
      await _request(tester);
      await tester.pumpAndSettle();
      if (isConfirm) {
        await _verify(tester);
        await tester.pumpAndSettle();
      }
      expect(
          find.text(
              'The verification request has expired. Please send a new code.'),
          findsOneWidget);
      expect(fixture.callbacks, isEmpty);
      expect(fixture.sessions.session, same(_owner));
      expect(find.text('Phone number verified'), findsNothing);
    });
  }

  for (final isConfirm in [false, true]) {
    testWidgets(
        'Back ignores late ${isConfirm ? 'manual' : 'automatic'} completion',
        (tester) async {
      final sent = Completer<PhoneVerificationStartResult>();
      final confirmed = Completer<AuthSession>();
      final fixture = _Fixture();
      fixture.onSend = (_) async => isConfirm
          ? const PhoneVerificationStartResult.codeSent(verificationId: 'first')
          : sent.future;
      fixture.onConfirm =
          ({required verificationId, required smsCode}) => confirmed.future;
      await _open(tester, fixture);
      await _request(tester);
      if (isConfirm) {
        await tester.pumpAndSettle();
        await _verify(tester);
      }
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(fixture.results, [null]);
      if (isConfirm) {
        confirmed.complete(_verified);
      } else {
        sent.complete(const PhoneVerificationStartResult.autoVerified(
            session: _verified));
      }
      await tester.pumpAndSettle();
      expect(fixture.callbacks, isEmpty);
      expect(fixture.results, [null]);
      expect(find.byType(PhoneVerificationScreen), findsNothing);
      expect(fixture.sessions.session, same(_owner));
      expect(tester.takeException(), isNull);
    });
  }
}
