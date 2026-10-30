import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/platform_settings_scaffold.dart';
import 'package:postdee_mobile/features/uploader/tiktok_publishing_settings_sheet.dart';

const _save = ValueKey('uploader-platform-settings-save');
const _cancel = ValueKey('uploader-platform-settings-cancel');
const _direct = ValueKey('uploader-tiktok-mode-direct');
const _privacy = ValueKey('uploader-tiktok-privacy');

TikTokPublishingOptionsResult _options({String nickname = 'ร้านของฉัน'}) =>
    TikTokPublishingOptionsResult(
      connectionId: 'fake-connection',
      creatorInfoRevision: 'a' * 64,
      creatorInfo: TikTokCreatorInfo(
        creatorAvatarUrl: '',
        creatorUsername: 'fake_creator',
        creatorNickname: nickname,
        privacyLevelOptions: TikTokPrivacyLevel.values,
        commentDisabled: false,
        duetDisabled: true,
        stitchDisabled: false,
        maxVideoPostDurationSec: 600,
      ),
    );

Widget _app(Widget home,
    {Locale locale = const Locale('en'), bool dark = false, double scale = 1}) {
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
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            disableAnimations: true, textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(body: home),
  );
}

Widget _launcher(WidgetBuilder builder,
        {ValueChanged<TikTokSettingsSelection?>? onResult}) =>
    Builder(
        builder: (context) => TextButton(
            onPressed: () async {
              final result =
                  await showModalBottomSheet<TikTokSettingsSelection>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: builder);
              onResult?.call(result);
            },
            child: const Text('Open settings')));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _readable(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsWidgets);
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  expect(paragraph.didExceedMaxLines, isFalse, reason: text);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - .1),
      reason: text);
}

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Anuphan');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts
          .addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
    }
    await fonts.load();
  });
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  testWidgets('English scaffold translates actions and missing account only',
      (tester) async {
    await tester.pumpWidget(_app(_launcher(
        (_) => PlatformSettingsScaffold(
            platform: SocialPlatform.tiktok,
            displayName: '',
            onSave: () {},
            child: const Text('merchant supplied content')),
        onResult: (_) {})));
    await _tap(tester, find.text('Open settings'));
    expect(find.text('Account not confirmed'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save settings'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets(
      'English Inbox copy keeps account name raw and makes no options call',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(_launcher(
        (_) => TikTokPublishingSettingsSheet(
            initialSettings: const PlatformPublishSettings(),
            connectionDisplayName: 'บันทึกการตั้งค่า',
            loadOptions: () async {
              calls++;
              return _options();
            },
            isCurrent: () => true),
        onResult: (_) {})));
    await _tap(tester, find.text('Open settings'));
    expect(find.text('Video delivery'), findsOneWidget);
    expect(find.text('Send as draft to TikTok'), findsOneWidget);
    expect(find.text('Continue in TikTok'), findsOneWidget);
    expect(find.text('บันทึกการตั้งค่า'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets(
      'English Direct settings render known controls and raw creator name',
      (tester) async {
    await tester.pumpWidget(_app(_launcher(
        (_) => TikTokPublishingSettingsSheet(
            initialSettings: const PlatformPublishSettings(
                tiktokPublishMode: TikTokPublishMode.directPost),
            loadOptions: () async => _options(nickname: 'ผู้ชมและการโต้ตอบ'),
            isCurrent: () => true),
        onResult: (_) {})));
    await _tap(tester, find.text('Open settings'));
    expect(find.text('Viewers and interactions'), findsOneWidget);
    expect(find.text('Who can view this video'), findsOneWidget);
    expect(find.text('Allow comments'), findsOneWidget);
    expect(find.text('ผู้ชมและการโต้ตอบ'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(_save)).onPressed, isNull);
  });

  testWidgets('Inbox Save and Cancel keep initial values and emit one result',
      (tester) async {
    const initial =
        PlatformPublishSettings(youtubeTitle: 'ชื่อจริง บันทึกการตั้งค่า');
    final before = initial.toDraftJson();
    final results = <TikTokSettingsSelection?>[];
    await tester.pumpWidget(_app(_launcher(
        (_) => TikTokPublishingSettingsSheet(
            initialSettings: initial,
            loadOptions: () async => throw StateError('Inbox must not load'),
            isCurrent: () => true),
        onResult: results.add)));
    await _tap(tester, find.text('Open settings'));
    await _tap(tester, find.byKey(_cancel));
    expect(results, [null]);
    await _tap(tester, find.text('Open settings'));
    await _tap(tester, find.byKey(_save));
    expect(results.length, 2);
    expect(results.last!.settings.youtubeTitle, initial.youtubeTitle);
    expect(
        results.last!.settings.tiktokPublishMode, TikTokPublishMode.inboxDraft);
    expect(results.last!.options, isNull);
    expect(initial.toDraftJson(), before);
  });

  testWidgets(
      'Direct saves raw revision, selected enum and explicit consent only',
      (tester) async {
    final options = _options();
    final results = <TikTokSettingsSelection?>[];
    await tester.pumpWidget(_app(_launcher(
        (_) => TikTokPublishingSettingsSheet(
            initialSettings: const PlatformPublishSettings(
                tiktokPublishMode: TikTokPublishMode.directPost,
                tiktokMusicUsageConfirmed: true,
                youtubeTitle: 'raw title'),
            loadOptions: () async => options,
            isCurrent: () => true),
        onResult: results.add)));
    await _tap(tester, find.text('Open settings'));
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('uploader-tiktok-music-consent')))
            .value,
        isFalse);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('uploader-tiktok-allow-duet')))
            .onChanged,
        isNull);
    await _tap(tester, find.byKey(_privacy));
    await _tap(tester, find.text('Everyone').last);
    await _tap(
        tester, find.byKey(const ValueKey('uploader-tiktok-music-consent')));
    await _tap(tester, find.byKey(_save));
    expect(results.length, 1);
    expect(results.single!.options, same(options));
    expect(results.single!.settings.tiktokPrivacyLevel,
        TikTokPrivacyLevel.publicToEveryone);
    expect(results.single!.settings.tiktokCreatorInfoRevision,
        options.creatorInfoRevision);
    expect(results.single!.settings.tiktokMusicUsageConfirmed, isTrue);
    expect(results.single!.settings.youtubeTitle, 'raw title');
  });

  testWidgets(
      'pending load and cached failure follow locale without extra calls',
      (tester) async {
    final locale = ValueNotifier(const Locale('th'));
    addTearDown(locale.dispose);
    final pending = Completer<TikTokPublishingOptionsResult>();
    var calls = 0;
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) => _app(
            _launcher((_) => TikTokPublishingSettingsSheet(
                initialSettings: const PlatformPublishSettings(
                    tiktokPublishMode: TikTokPublishMode.directPost),
                loadOptions: () {
                  calls++;
                  return pending.future;
                },
                isCurrent: () => true)),
            locale: value)));
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1);
    locale.value = const Locale('en');
    await tester.pump();
    expect(
        find.text(
            'Wait for the latest TikTok account information before setting up Direct post.'),
        findsOneWidget);
    pending.completeError(
        StateError('raw provider must not leak through generic catch'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not load the latest TikTok options. Please try again.'),
        findsOneWidget);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('โหลดตัวเลือก TikTok ล่าสุดไม่สำเร็จ กรุณาลองใหม่'),
        findsOneWidget);
    expect(calls, 1);
  });

  testWidgets(
      'failed options retry is one load and keeps explicit consent required',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(_launcher((_) => TikTokPublishingSettingsSheet(
        initialSettings: const PlatformPublishSettings(
            tiktokPublishMode: TikTokPublishMode.directPost),
        loadOptions: () async {
          if (++calls == 1) throw StateError('fake failure');
          return _options();
        },
        isCurrent: () => true))));
    await _tap(tester, find.text('Open settings'));
    await _tap(
        tester, find.byKey(const ValueKey('uploader-tiktok-options-retry')));
    expect(calls, 2);
    expect(find.byKey(_privacy), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(_save)).onPressed, isNull);
  });

  testWidgets('switching to Inbox ignores a late Direct response',
      (tester) async {
    final pending = Completer<TikTokPublishingOptionsResult>();
    final results = <TikTokSettingsSelection?>[];
    await tester.pumpWidget(_app(_launcher(
        (_) => TikTokPublishingSettingsSheet(
            initialSettings: const PlatformPublishSettings(),
            loadOptions: () => pending.future,
            isCurrent: () => true),
        onResult: results.add)));
    await _tap(tester, find.text('Open settings'));
    await tester.tap(find.byKey(_direct));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('uploader-tiktok-mode-inbox')));
    await tester.pump();
    pending.complete(_options());
    await tester.pumpAndSettle();
    expect(find.byKey(_privacy), findsNothing);
    await _tap(tester, find.byKey(_save));
    expect(results.single!.settings.tiktokPublishMode,
        TikTokPublishMode.inboxDraft);
    expect(results.single!.settings.tiktokCreatorInfoRevision, isNull);
    expect(results.single!.settings.tiktokMusicUsageConfirmed, isFalse);
    expect(results.single!.options, isNull);
  });

  testWidgets('owner change rejects pending capabilities and cannot save',
      (tester) async {
    final store = PostDeeAuthSessionStore.instance;
    final previous = store.session;
    addTearDown(() => store.signIn(previous));
    var current = true;
    final pending = Completer<TikTokPublishingOptionsResult>();
    await tester.pumpWidget(_app(_launcher((_) => TikTokPublishingSettingsSheet(
        initialSettings: const PlatformPublishSettings(
            tiktokPublishMode: TikTokPublishMode.directPost),
        loadOptions: () => pending.future,
        isCurrent: () => current))));
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    current = false;
    store.signIn(AuthSession.authenticated(
        userId: 'other-fake-owner', idToken: 'fake-token'));
    await tester.pump();
    pending.complete(_options());
    await tester.pumpAndSettle();
    expect(find.text('Your account has changed. Reopen TikTok settings.'),
        findsOneWidget);
    expect(find.byKey(_privacy), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(_save)).onPressed, isNull);
  });

  testWidgets('closing during load ignores completion and emits Cancel once',
      (tester) async {
    final pending = Completer<TikTokPublishingOptionsResult>();
    final results = <TikTokSettingsSelection?>[];
    await tester.pumpWidget(_app(_launcher(
        (_) => TikTokPublishingSettingsSheet(
            initialSettings: const PlatformPublishSettings(
                tiktokPublishMode: TikTokPublishMode.directPost),
            loadOptions: () => pending.future,
            isCurrent: () => true),
        onResult: results.add)));
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(_cancel));
    await tester.pumpAndSettle();
    pending.complete(_options());
    await tester.pumpAndSettle();
    expect(results, [null]);
    expect(tester.takeException(), isNull);
  });

  for (final branded in [false, true]) {
    for (final throws in [false, true]) {
      testWidgets(
          'policy branded=$branded throws=$throws keeps URL and requires manual consent',
          (tester) async {
        final urls = <String>[];
        const messengerChannel =
            MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(messengerChannel, (call) async {
          final arguments = call.arguments;
          if (arguments is Map && arguments['url'] is String) {
            urls.add(arguments['url'] as String);
          }
          if (throws) throw PlatformException(code: 'fake-unavailable');
          return false;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(messengerChannel, null));
        await tester.pumpWidget(_app(_launcher((_) =>
            TikTokPublishingSettingsSheet(
                initialSettings: const PlatformPublishSettings(
                    tiktokPublishMode: TikTokPublishMode.directPost),
                loadOptions: () async => _options(),
                isCurrent: () => true))));
        await _tap(tester, find.text('Open settings'));
        await _tap(tester, find.byKey(_privacy));
        await _tap(tester, find.text('Everyone').last);
        if (branded) {
          await _tap(
              tester, find.byKey(const ValueKey('uploader-tiktok-commercial')));
          await _tap(tester,
              find.byKey(const ValueKey('uploader-tiktok-third-party')));
        }
        final label = branded
            ? 'Read Branded Content Policy'
            : 'Read Music Usage Confirmation';
        await _tap(tester, find.text(label));
        final url = branded
            ? 'https://www.tiktok.com/legal/page/global/bc-policy/en'
            : 'https://www.tiktok.com/legal/page/global/music-usage-confirmation/en';
        expect(urls, [url]);
        expect(
            find.text(
                'Could not open TikTok terms. Try again or open this link in your browser: $url'),
            findsOneWidget);
        expect(
            tester
                .widget<CheckboxListTile>(
                    find.byKey(const ValueKey('uploader-tiktok-music-consent')))
                .value,
            isFalse);
        if (branded) {
          expect(
              tester
                  .widget<CheckboxListTile>(find
                      .byKey(const ValueKey('uploader-tiktok-brand-consent')))
                  .value,
              isFalse);
        }
        expect(
            tester.widget<FilledButton>(find.byKey(_save)).onPressed, isNull);
      });
    }
  }

  for (final dark in [false, true]) {
    for (final direct in [false, true]) {
      testWidgets(
          'TikTok ${direct ? 'Direct' : 'Inbox'} readable at320dp2x with keyboard dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(320, 852);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 230);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(_app(
            _launcher((_) => TikTokPublishingSettingsSheet(
                initialSettings: PlatformPublishSettings(
                    tiktokPublishMode: direct
                        ? TikTokPublishMode.directPost
                        : TikTokPublishMode.inboxDraft),
                loadOptions: () async => _options(),
                isCurrent: () => true)),
            dark: dark,
            scale: 2));
        await _tap(tester, find.text('Open settings'));
        _readable(tester, 'Send as draft to TikTok');
        _readable(tester, 'Direct post');
        _readable(tester, 'Cancel');
        _readable(tester, 'Save settings');
        expect(
            tester.getRect(find.byKey(_save)).bottom, lessThanOrEqualTo(622));
        expect(find.byKey(_cancel).hitTestable(), findsOneWidget);
        expect(
            tester
                .getSize(find.byKey(const ValueKey('platform-settings-scroll')))
                .height,
            greaterThan(90));
        if (direct) {
          await tester.ensureVisible(find.byKey(_privacy));
          await tester.pumpAndSettle();
          _readable(tester, 'Who can view this video');
          final semantics = tester.ensureSemantics();
          try {
            await tester.pump();
            expect(
                tester
                    .getSemantics(find.byKey(_privacy))
                    .getSemanticsData()
                    .label,
                contains('Who can view this video'));
          } finally {
            semantics.dispose();
          }
          await tester.tap(find.byKey(_privacy));
          await tester.pumpAndSettle();
          _readable(tester, 'Friends who follow each other');
          await _tap(tester, find.text('Friends who follow each other').last);
          expect(
              tester
                  .widget<DropdownButtonFormField<TikTokPrivacyLevel>>(
                      find.byKey(_privacy))
                  .initialValue,
              TikTokPrivacyLevel.mutualFollowFriends);
          _readable(tester, 'Who can view this video');
          _readable(tester, 'Friends who follow each other');
          final labelRect =
              tester.getRect(find.text('Who can view this video'));
          final selectedRect =
              tester.getRect(find.text('Friends who follow each other').last);
          expect(labelRect.bottom, lessThanOrEqualTo(selectedRect.top + 1),
              reason:
                  'The floating privacy label must not cover the selected audience.');
          final inputRect = tester.getRect(find.byKey(_privacy));
          expect(labelRect.right, lessThanOrEqualTo(inputRect.right + 1));
          expect(selectedRect.bottom, lessThanOrEqualTo(inputRect.bottom + 1));
          await tester.ensureVisible(
              find.byKey(const ValueKey('uploader-tiktok-music-consent')));
          await tester.pumpAndSettle();
          _readable(tester,
              'I confirm my music usage rights and accept TikTok’s Music Usage Confirmation.');
        } else {
          await tester.ensureVisible(find.text('Continue in TikTok'));
          await tester.pumpAndSettle();
          _readable(tester, 'Continue in TikTok');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
