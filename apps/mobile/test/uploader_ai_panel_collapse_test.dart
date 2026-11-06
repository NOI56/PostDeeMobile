import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/caption_language_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/uploader_wizard_test_navigation.dart';
import 'uploader_caption_english_test.dart';

const _toggle = 'uploader-ai-card-toggle';
Finder _key(String key, {bool offstage = false}) =>
    find.byKey(ValueKey(key), skipOffstage: !offstage);

Future<void> _mount(WidgetTester tester, CaptionEnglishFixture fixture) async {
  addTearDown(fixture.dispose);
  tester.view.physicalSize = const Size(430, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await fixture.mount(tester, expandAi: false);
  await revealCaptionEnglishControl(tester, _key(_toggle));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(AuthSession.authenticated(
        userId: captionEnglishOwner, idToken: 'ai-collapse-test'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
  });

  testWidgets('the whole AI card starts collapsed without side effects',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    expect(find.text('AI captions from your video'), findsOneWidget);
    expect(_key('uploader-ai-generate-button'), findsNothing);
    expect(_key('uploader-caption-language'), findsNothing);
    expect(_key('uploader-ai-style-summary'), findsNothing);
    expect(_key('uploader-ai-generate-button', offstage: true), findsOneWidget);
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapse preserves mounted language and guidance controls',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await tapCaptionEnglishControl(tester, _toggle);
    await tapCaptionEnglishControl(tester, 'uploader-ai-open-panel');
    await revealCaptionEnglishControl(
        tester, _key('uploader-ai-guidance-input'));
    await tester.enterText(
        _key('uploader-ai-guidance-input'), 'Keep this writing guidance');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, 'uploader-caption-language');
    await tester.enterText(_key('caption-language-search'), 'Thai');
    await tester.pumpAndSettle();
    await tester.tap(_key('caption-language-option-th'));
    await tester.pumpAndSettle();
    final languageElement = tester.element(_key('uploader-caption-language'));
    await tapCaptionEnglishControl(tester, _toggle);
    expect(_key('uploader-caption-language'), findsNothing);
    expect(tester.element(_key('uploader-caption-language', offstage: true)),
        same(languageElement));
    await tapCaptionEnglishControl(tester, _toggle);
    expect(
        tester
            .widget<CaptionLanguagePicker>(_key('uploader-caption-language'))
            .value,
        'th');
    expect(
        tester
            .widget<TextField>(_key('uploader-ai-guidance-field'))
            .controller!
            .text,
        'Keep this writing guidance');
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shortcut opens the card and expansion survives step Back',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await tapCaptionEnglishControl(tester, 'uploader-ai-open-shortcut');
    expect(_key('uploader-ai-generate-button'), findsOneWidget);
    await goToUploaderStep(tester, 0);
    await goToUploaderStep(tester, 1);
    await revealCaptionEnglishControl(
        tester, _key('uploader-ai-generate-button'));
    expect(_key('uploader-caption-language'), findsOneWidget);
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsing a busy card retains the one pending AI request',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = CaptionEnglishFixture()..aiGate = gate.future;
    await _mount(tester, fixture);
    await tapCaptionEnglishControl(tester, _toggle);
    await revealCaptionEnglishControl(
        tester, _key('uploader-ai-generate-button'));
    await tester.tap(_key('uploader-ai-generate-button'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(fixture.requests, hasLength(1));
    await tester.ensureVisible(_key(_toggle));
    await tester.tap(_key(_toggle));
    await tester.pumpAndSettle();
    expect(_key('uploader-ai-generate-button'), findsNothing);
    expect(find.text('Preparing captions from the selected video'),
        findsOneWidget);
    gate.complete(captionEnglishResult());
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, _toggle);
    expect(_key('uploader-ai-reopen-result'), findsOneWidget);
    expect(fixture.requests, hasLength(1));
    expect(fixture.uploadRequests, hasLength(1));
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Thai dark large text uses a settled reduced-motion header',
      (tester) async {
    final fixture = CaptionEnglishFixture(
        locale: const Locale('th'), dark: true, scale: 2);
    await _mount(tester, fixture);
    tester.view.physicalSize = const Size(320, 1100);
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, _toggle);
    final rotation = find.descendant(
        of: _key(_toggle), matching: find.byType(AnimatedRotation));
    expect(tester.widget<AnimatedRotation>(rotation).duration, Duration.zero);
    expect(find.text('กดพับเพื่อซ่อนตัวเลือก AI'), findsOneWidget);
    await tapCaptionEnglishControl(tester, _toggle);
    expect(_key('uploader-caption-language'), findsNothing);
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
