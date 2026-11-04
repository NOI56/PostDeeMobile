import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'uploader_caption_english_test.dart';

Future<void> _mount(WidgetTester tester, CaptionEnglishFixture fixture) async {
  addTearDown(fixture.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await fixture.mount(tester);
}

Future<void> _type(WidgetTester tester, String text,
    {String key = 'uploader-caption-field'}) async {
  final field = find.byKey(ValueKey(key));
  await revealCaptionEnglishControl(tester, field);
  await tester.enterText(field, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(AuthSession.authenticated(
        userId: captionEnglishOwner, idToken: 'caption-result-reuse'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
  });

  testWidgets('shared AI quotes one credit and its shortcut does not generate',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await tapCaptionEnglishControl(tester, 'uploader-ai-open-shortcut');
    expect(fixture.requests, isEmpty);
    expect(find.text('Generate captions · 1 credit'), findsOneWidget);
    expect(
        find.text(
            'Credits are used when results are generated. Viewing or applying them does not use more credits.'),
        findsOneWidget);
  });

  testWidgets(
      'dismissed shared result reopens free and Undo keeps later manual text',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await _type(tester, 'Original manual caption');
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(find.byKey(const ValueKey('uploader-shared-ai-preview')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('uploader-shared-ai-close')));
    await tester.pumpAndSettle();
    await _type(tester, 'Later manual caption');
    await tapCaptionEnglishControl(tester, 'uploader-ai-reopen-result');
    expect(fixture.requests, hasLength(1));
    expect(fixture.uploadRequests, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('uploader-shared-ai-apply')));
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, 'uploader-shared-ai-undo');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-caption-field')))
            .controller!
            .text,
        'Later manual caption');
    expect(fixture.requests, hasLength(1));
  });

  testWidgets('manual edits during generation keep a recoverable paid result',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = CaptionEnglishFixture()..aiGate = gate.future;
    await _mount(tester, fixture);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    await _type(tester, 'Keep this manual caption');
    final toggle =
        find.byKey(const ValueKey('uploader-platform-captions-toggle'));
    await revealCaptionEnglishControl(tester, toggle);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    gate.complete(captionEnglishResult());
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, 'uploader-ai-reopen-result');
    expect(fixture.requests, hasLength(1));
    expect(find.byKey(const ValueKey('uploader-shared-ai-preview')),
        findsOneWidget);
  });

  testWidgets(
      'advanced results reopen at zero credits and preserve unrelated edits',
      (tester) async {
    final base = captionEnglishResult();
    final fixture = CaptionEnglishFixture()
      ..result = RealClipCaptionResult(
          caption: base.caption,
          captionOptions: const [],
          hooks: const [],
          hashtags: const [],
          seoKeywords: const [],
          searchTitle: '',
          source: base.source,
          platformCaptions: const {
            'TIKTOK':
                CaptionResult(caption: 'Generated TikTok caption', hashtags: [])
          },
          quota: const RealClipCaptionQuota(
              limit: 120, usedThisMonth: 120, remainingThisMonth: 0));
    await _mount(tester, fixture);
    await _type(tester, 'Original shared caption');
    await tapCaptionEnglishControl(tester, 'uploader-platform-captions-toggle');
    await tapCaptionEnglishControl(tester, 'ai-caption-target-TIKTOK');
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    Navigator.of(tester.element(
            find.byKey(const ValueKey('uploader-platform-ai-preview'))))
        .pop(false);
    await tester.pumpAndSettle();
    await _type(tester, 'Later TikTok text', key: 'uploader-caption-TIKTOK');
    await _type(tester, 'Keep YouTube text',
        key: 'uploader-caption-YOUTUBE_SHORTS');
    await tapCaptionEnglishControl(tester, 'uploader-ai-reopen-result');
    await tester.tap(find.byKey(const ValueKey('uploader-platform-ai-apply')));
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, 'uploader-platform-ai-undo');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-caption-TIKTOK')))
            .controller!
            .text,
        'Later TikTok text');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-caption-YOUTUBE_SHORTS')))
            .controller!
            .text,
        'Keep YouTube text');
    expect(fixture.requests, hasLength(1));
    expect(fixture.uploadRequests, hasLength(1));
  });

  for (final change in ['language', 'session', 'guidance', 'source', 'style']) {
    testWidgets('changed $change cannot reopen old results', (tester) async {
      final fixture = CaptionEnglishFixture();
      await _mount(tester, fixture);
      await _type(tester, 'Original caption');
      await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
      await tester.tap(find.byKey(const ValueKey('uploader-shared-ai-close')));
      await tester.pumpAndSettle();
      await revealCaptionEnglishControl(
          tester, find.byKey(const ValueKey('uploader-ai-reopen-result')));
      expect(find.byKey(const ValueKey('uploader-ai-reopen-result')),
          findsOneWidget);
      if (change == 'language') {
        await tapCaptionEnglishControl(tester, 'uploader-caption-language');
        await tester.tap(find.text('English').last);
      } else if (change == 'session') {
        PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
            userId: captionEnglishOwner, idToken: 'new-caption-session'));
      } else if (change == 'guidance') {
        await tapCaptionEnglishControl(tester, 'uploader-ai-open-panel');
        await _type(tester, 'Changed AI instructions',
            key: 'uploader-ai-guidance-field');
      } else if (change == 'source') {
        await tapCaptionEnglishControl(tester, 'uploader-progress-0');
        fixture.picked = fixture.makeVideo('different-source.mp4');
        await tapCaptionEnglishControl(tester, 'uploader-video-preview-picker');
        await tapCaptionEnglishControl(tester, 'uploader-progress-1');
      } else {
        await tapCaptionEnglishControl(tester, 'uploader-ai-open-panel');
        await tapCaptionEnglishControl(tester, 'uploader-ai-style-button');
        await tapCaptionEnglishControl(
            tester, 'uploader-ai-style-tone-friendly');
        await tapCaptionEnglishControl(tester, 'uploader-ai-style-save');
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('uploader-ai-reopen-result')),
          findsNothing);
      expect(fixture.requests, hasLength(1));
    });
  }
}
