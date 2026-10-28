import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/caption_quota_strip.dart';
import 'package:postdee_mobile/features/uploader/platform_caption_fields.dart';

Widget _app(Widget child,
    {Locale locale = const Locale('en'), bool dark = false, double scale = 1}) {
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
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            disableAnimations: true, textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Finder _field(SocialPlatform platform) =>
    find.byKey(ValueKey('uploader-caption-${platform.apiValue}'));

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _readable(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  expect(paragraph.didExceedMaxLines, isFalse,
      reason: 'Clipped text: ${paragraph.text.toPlainText()}');
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - .1),
      reason: 'Clipped text height: ${paragraph.text.toPlainText()}');
}

Widget _previewLauncher(
        Map<SocialPlatform, String> captions, ValueChanged<bool?> onResult,
        {bool fallback = false, bool charged = true}) =>
    Builder(
        builder: (context) => TextButton(
            onPressed: () async => onResult(await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => PlatformCaptionPreviewSheet(
                    captions: captions,
                    isFallback: fallback,
                    charged: charged))),
            child: const Text('Open preview')));

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Anuphan')
      ..addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-SemiBold.ttf'));
    await fonts.load();
  });
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));
  testWidgets('English platform fields label caption and YouTube description',
      (tester) async {
    await tester.pumpWidget(_app(PlatformCaptionFields(
        captions: const {},
        onChanged: (_, __) {},
        validationMessage: (_) => null)));
    await tester.pumpAndSettle();
    expect(find.text('YouTube description'), findsOneWidget);
    expect(find.text('TikTok caption'), findsOneWidget);
    expect(find.text('Instagram caption'), findsOneWidget);
    expect(find.text('Write a caption for this channel...'), findsWidgets);
  });

  testWidgets('English preview labels its channel count and apply action',
      (tester) async {
    await tester.pumpWidget(_app(const PlatformCaptionPreviewSheet(
        captions: {SocialPlatform.tiktok: 'ข้อความร้านของฉัน'},
        isFallback: false,
        charged: true)));
    await tester.pumpAndSettle();
    expect(find.text('AI captions for 1 channel'), findsOneWidget);
    expect(find.text('Use 1 caption'), findsOneWidget);
    expect(find.text('ข้อความร้านของฉัน'), findsOneWidget);
  });

  testWidgets('English quota labels actual credits and keeps numeric progress',
      (tester) async {
    await tester.pumpWidget(_app(const CaptionQuotaStrip(
        plan: 'STARTER',
        quota: RealClipCaptionQuota(
            limit: 50,
            usedThisMonth: 12,
            remainingThisMonth: 38,
            addonRemaining: 8))));
    await tester.pumpAndSettle();
    expect(find.text('AI caption credits remaining'), findsOneWidget);
    expect(find.text('38 / 50 credits', findRichText: true), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        closeTo(.76, .0001));
  });

  testWidgets(
      'platform fields retain raw text, UTF-8 bytes and UTF-16 counts through locale changes',
      (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    final captions = ValueNotifier<Map<SocialPlatform, String>>({
      SocialPlatform.tiktok: 'ตั้งค่าขั้นสูง',
      SocialPlatform.youtubeShorts: ' กก😀 ',
    });
    final changes = <({SocialPlatform platform, String text})>[];
    addTearDown(locale.dispose);
    addTearDown(captions.dispose);
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, language, __) => _app(
            ValueListenableBuilder<Map<SocialPlatform, String>>(
                valueListenable: captions,
                builder: (_, values, __) => PlatformCaptionFields(
                    captions: values,
                    onChanged: (platform, text) {
                      changes.add((platform: platform, text: text));
                      captions.value = {...captions.value, platform: text};
                    },
                    validationMessage: (_) => null)),
            locale: language)));
    await tester.pumpAndSettle();
    expect(find.text('10 / 5,000 bytes · Set the video title in Channels'),
        findsOneWidget);
    await tester.enterText(_field(SocialPlatform.tiktok), ' กก😀 ');
    await tester.pumpAndSettle();
    expect(find.text('4 characters'), findsOneWidget);
    final controller =
        tester.widget<TextField>(_field(SocialPlatform.tiktok)).controller!;
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    for (final language in ['th', 'en']) {
      locale.value = Locale(language);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_field(SocialPlatform.tiktok)).controller,
          same(controller));
      expect(controller.text, ' กก😀 ');
      expect(controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 3));
      expect(
          tester
              .widget<TextField>(_field(SocialPlatform.youtubeShorts))
              .controller!
              .text,
          ' กก😀 ');
    }
    expect(changes, [(platform: SocialPlatform.tiktok, text: ' กก😀 ')]);
  });

  testWidgets(
      'field validation localizes known failures and preserves unknown provider errors',
      (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    const raw = 'provider-code: ข้อความจากภายนอก';
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, language, __) => _app(
            PlatformCaptionFields(
                captions: const {},
                onChanged: (_, __) =>
                    fail('Read-only fields must not dispatch edits'),
                readOnly: true,
                validationMessage: (platform) =>
                    platform == SocialPlatform.tiktok
                        ? 'แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร'
                        : platform == SocialPlatform.youtubeShorts
                            ? raw
                            : null),
            locale: language)));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'The TikTok caption must be no longer than 2,200 characters.'),
        findsOneWidget);
    expect(find.text(raw), findsOneWidget);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(
        find.text('แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร'), findsOneWidget);
    expect(find.text(raw), findsOneWidget);
    for (final platform in captionPlatforms) {
      expect(tester.widget<TextField>(_field(platform)).readOnly, isTrue);
    }
  });

  testWidgets(
      'AI targets keep platform identities and selection callback values',
      (tester) async {
    final selected =
        ValueNotifier(<SocialPlatform>{SocialPlatform.youtubeShorts});
    addTearDown(selected.dispose);
    await tester.pumpWidget(_app(ValueListenableBuilder<Set<SocialPlatform>>(
        valueListenable: selected,
        builder: (_, values, __) => PlatformCaptionAiTargets(
            selectedPlatforms: values,
            onChanged: (value) => selected.value = value))));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('ai-caption-target-TIKTOK')));
    expect(
        selected.value, {SocialPlatform.youtubeShorts, SocialPlatform.tiktok});
    expect(find.text('YouTube Shorts'), findsOneWidget);
  });

  testWidgets(
      'quota singular credits, Basic access and unknown plan labels keep their meaning',
      (tester) async {
    await tester.pumpWidget(_app(const CaptionQuotaStrip(
        plan: 'PRO',
        quota: RealClipCaptionQuota(
            limit: 1,
            usedThisMonth: 1,
            remainingThisMonth: 0,
            addonRemaining: 1))));
    expect(find.text('0 / 1 credit', findRichText: true), findsOneWidget);
    expect(find.text('1 credit used'), findsOneWidget);
    expect(find.text('+ 1 add-on credit'), findsOneWidget);
    await tester.pumpWidget(_app(const CaptionQuotaStrip(
        plan: 'BASIC',
        quota: RealClipCaptionQuota(
            limit: 0,
            usedThisMonth: 7,
            remainingThisMonth: 0,
            addonRemaining: 8))));
    expect(find.text('AI captions are available on Starter or Pro'),
        findsOneWidget);
    expect(find.textContaining('add-on'), findsNothing);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0);
    await tester.pumpWidget(_app(const CaptionQuotaStrip(
        plan: 'แคปชั่น',
        quota: RealClipCaptionQuota(
            limit: 5, usedThisMonth: 1, remainingThisMonth: 4))));
    expect(find.text('แคปชั่น'), findsOneWidget);
  });

  testWidgets(
      'quota live locale preserves the exact quota object and progress semantics',
      (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    const quota = RealClipCaptionQuota(
        limit: 50,
        usedThisMonth: 12,
        remainingThisMonth: 38,
        addonRemaining: 8);
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) => _app(
            const CaptionQuotaStrip(plan: 'STARTER', quota: quota),
            locale: value)));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .semanticsLabel,
        '38 of 50 AI caption credits remaining');
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('38 / 50 เครดิต', findRichText: true), findsOneWidget);
    expect(
        tester.widget<CaptionQuotaStrip>(find.byType(CaptionQuotaStrip)).quota,
        same(quota));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        closeTo(.76, .0001));
  });

  for (final charged in [true, false]) {
    testWidgets(
        'fallback preview keeps charged=$charged explicit and raw captions unchanged',
        (tester) async {
      const captions = {
        SocialPlatform.tiktok: 'ตั้งค่าขั้นสูง',
        SocialPlatform.youtubeShorts: 'สไตล์การเขียน',
        SocialPlatform.instagramReels: 'แคปชั่น',
        SocialPlatform.facebookReels: 'คำค้นของร้าน'
      };
      final results = <bool?>[];
      await tester.pumpWidget(_app(_previewLauncher(captions, results.add,
          fallback: true, charged: charged)));
      await _tap(tester, find.text('Open preview'));
      expect(find.text('Review fallback captions for all 4 channels'),
          findsOneWidget);
      expect(find.textContaining('No AI quota charged'),
          charged ? findsNothing : findsOneWidget);
      for (final caption in captions.values) {
        expect(find.text(caption), findsOneWidget);
      }
      await _tap(
          tester, find.byKey(const ValueKey('uploader-platform-ai-apply')));
      expect(results, [true]);
      expect(captions[SocialPlatform.tiktok], 'ตั้งค่าขั้นสูง');
    });
  }

  testWidgets('preview locale changes preserve captions and Back returns false',
      (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    const captions = {SocialPlatform.tiktok: 'แคปชั่น'};
    final results = <bool?>[];
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) =>
            _app(_previewLauncher(captions, results.add), locale: value)));
    await _tap(tester, find.text('Open preview'));
    expect(find.text('AI captions for 1 channel'), findsOneWidget);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('แคปชั่นจาก AI 1 ช่องทาง'), findsOneWidget);
    expect(find.text('แคปชั่น'), findsOneWidget);
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Back to writing'));
    expect(results, [false]);
  });

  testWidgets(
      'empty preview cannot apply and default apps retain Thai widget copy',
      (tester) async {
    await tester.pumpWidget(_app(const PlatformCaptionPreviewSheet(
        captions: {}, isFallback: false, charged: false)));
    expect(
        tester
            .widget<ButtonStyleButton>(
                find.byKey(const ValueKey('uploader-platform-ai-apply')))
            .onPressed,
        isNull);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: CaptionQuotaStrip(
                plan: 'STARTER',
                quota: RealClipCaptionQuota(
                    limit: 50, usedThisMonth: 12, remainingThisMonth: 38)))));
    expect(find.text('แคปชั่น AI คงเหลือ'), findsOneWidget);
    expect(find.text('ใช้ไป 12 เครดิต'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'platform field labels, hints and errors are readable at 320dp ${scale}x (dark=$dark)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_app(
            Padding(
                padding: const EdgeInsets.all(16),
                child: PlatformCaptionFields(
                    captions: const {},
                    onChanged: (_, __) {},
                    validationMessage: (platform) => switch (platform) {
                          SocialPlatform.tiktok =>
                            'แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร',
                          SocialPlatform.youtubeShorts =>
                            'คำอธิบาย YouTube ต้องไม่เกิน 5,000 ไบต์ กรุณาย่อแคปชั่นก่อนโพสต์',
                          SocialPlatform.instagramReels =>
                            'แคปชั่น Instagram ต้องไม่เกิน 2,200 ตัวอักษร',
                          _ => 'แคปชั่น Facebook ต้องไม่เกิน 63,206 ตัวอักษร',
                        })),
            dark: dark,
            scale: scale));
        await tester.pumpAndSettle();
        _readable(tester, find.text('Write a caption for this channel...'));
        for (final platform in captionPlatforms) {
          await tester.ensureVisible(_field(platform));
          await tester.pumpAndSettle();
          final brand = platform == SocialPlatform.instagramReels
              ? 'Instagram'
              : platform.shortLabel;
          final label = platform == SocialPlatform.youtubeShorts
              ? 'YouTube description'
              : '$brand caption';
          _readable(tester, find.text(label));
          final error = platform == SocialPlatform.youtubeShorts
              ? 'The YouTube description must be no longer than 5,000 bytes. Shorten the caption before posting.'
              : 'The $brand caption must be no longer than ${platform == SocialPlatform.facebookReels ? '63,206' : '2,200'} characters.';
          _readable(tester, find.text(error));
          await tester.tap(_field(platform));
          await tester.pumpAndSettle();
          _readable(tester, find.text(label));
          final counter = platform == SocialPlatform.youtubeShorts
              ? '0 / 5,000 bytes · Set the video title in Channels'
              : '0 characters';
          _readable(tester, find.text(counter));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'credit quota and fallback preview remain readable at 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(
          const Padding(
              padding: EdgeInsets.all(16),
              child: CaptionQuotaStrip(
                  plan: 'STARTER',
                  quota: RealClipCaptionQuota(
                      limit: 50,
                      usedThisMonth: 12,
                      remainingThisMonth: 38,
                      addonRemaining: 8))),
          dark: dark,
          scale: 2));
      await tester.pumpAndSettle();
      _readable(tester, find.text('AI caption credits remaining'));
      _readable(tester, find.text('38 / 50 credits', findRichText: true));
      _readable(tester, find.text('+ 8 add-on credits'));
      expect(tester.takeException(), isNull);
    });

    for (final count in [1, 4]) {
      for (final fallback in [false, true]) {
        for (final charged in [false, true]) {
          testWidgets(
              'preview $count targets fallback=$fallback charged=$charged readable at 320dp 2x (dark=$dark)',
              (tester) async {
            tester.view.physicalSize = const Size(320, 852);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final captions = {
              for (final platform in captionPlatforms.take(count))
                platform: 'Raw ${platform.apiValue} แคปชั่น',
            };
            final results = <bool?>[];
            await tester.pumpWidget(_app(
                _previewLauncher(captions, results.add,
                    fallback: fallback, charged: charged),
                dark: dark,
                scale: 2));
            await _tap(tester, find.text('Open preview'));
            final title = fallback
                ? 'Review fallback captions for ${count == 4 ? 'all 4 channels' : '1 channel'}'
                : 'AI captions for ${count == 4 ? 'all 4 channels' : '1 channel'}';
            _readable(tester, find.text(title));
            final body = fallback
                ? 'AI could not analyze the video. Review the text for $count ${count == 1 ? 'channel' : 'channels'} before use.${charged ? '' : ' · No AI quota charged'}'
                : 'You can edit after using these captions. Your original text stays until you tap Use.';
            _readable(tester, find.text(body));
            final captionArea = find.descendant(
                of: find.byKey(const ValueKey('uploader-platform-ai-preview')),
                matching: find.byType(SingleChildScrollView));
            expect(tester.getSize(captionArea.first).height,
                greaterThanOrEqualTo(100),
                reason: 'The text to review needs a usable scrolling area.');
            for (final caption in captions.values) {
              await tester.ensureVisible(find.text(caption));
              await tester.pumpAndSettle();
              _readable(tester, find.text(caption));
              expect(find.text(caption).hitTestable(), findsOneWidget);
            }
            await _tap(tester,
                find.byKey(const ValueKey('uploader-platform-ai-apply')));
            expect(results, [true]);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
