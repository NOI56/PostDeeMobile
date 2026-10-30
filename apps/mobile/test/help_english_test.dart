import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/legal/legal_document_screen.dart';
import 'package:postdee_mobile/features/profile/profile_draft_store.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _thaiBody = 'ต้องการความช่วยเหลือใช่ไหม?\n\n'
    'เริ่มต้นใช้งาน\n'
    '1. เลือกคลิปวิดีโอแนวตั้ง 9:16\n'
    '2. เลือกแพลตฟอร์มที่จะโพสต์\n'
    '3. โพสต์ทันที หรือ ตั้งเวลาไว้ในปฏิทิน\n\n'
    'คำถามที่พบบ่อย\n'
    '- โควตาโพสต์ฟรีคิดอย่างไร? แพ็กเกจ Basic ได้ 3 หน่วยต่อเดือนหลังยืนยันเบอร์\n'
    '  1 ช่องทางใช้ 1 หน่วย เช่น 1 คลิปลง 3 ช่องทาง ใช้ 3 หน่วย\n'
    '- ตั้งเวลาโพสต์ได้ไหม? Starter ล่วงหน้าได้ 14 วัน และ Pro 30 วัน\n\n'
    'ติดต่อทีมงาน: กดแชทกับทีมงานในหน้าบัญชี หรืออีเมล postdee.support@gmail.com';

class _Api extends PostDeeApiClient {
  int reads = 0;
  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async {
    reads++;
    return const [];
  }

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    reads++;
    return const SubscriptionStatusResult(
      userId: 'help-owner',
      plan: 'BASIC',
      status: 'INACTIVE',
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );
  }
}

class _Drafts implements ProfileDraftStore {
  int reads = 0;
  @override
  Future<ProfileDraft?> load() async {
    reads++;
    return null;
  }

  @override
  Future<void> save(ProfileDraft draft) async =>
      throw StateError('Reading Help must not save a profile draft');
  @override
  Future<void> clear() async =>
      throw StateError('Reading Help must not clear a profile draft');
}

class _Fixture {
  _Fixture(
      {Locale locale = const Locale('en'),
      this.dark = false,
      this.scale = 1,
      this.withDelegate = true})
      : language = PostDeeLanguageController(initialLocale: locale),
        theme = PostDeeThemeController(
          initialMode: dark ? ThemeMode.dark : ThemeMode.light,
        );

  final PostDeeLanguageController language;
  final PostDeeThemeController theme;
  final bool dark;
  final double scale;
  final bool withDelegate;
  final api = _Api();
  final drafts = _Drafts();
  final boundary = GlobalKey();
  int supportOpens = 0;
  int accountActions = 0;

  Future<void> mount(WidgetTester tester, {LegalDocument? document}) async {
    await tester.runAsync(_loadFonts);
    await tester.pumpWidget(AnimatedBuilder(
      animation: language,
      builder: (_, __) => MaterialApp(
        locale: language.locale,
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: [
          if (withDelegate) PostDeeLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: child!,
          ),
        ),
        home: document != null
            ? LegalDocumentScreen(document: document)
            : Scaffold(
                body: ProfileScreen(
                  languageController: language,
                  themeController: theme,
                  apiClient: api,
                  profileDraftStore: drafts,
                  onOpenTemplates: () => accountActions++,
                  onDeleteAccount: () => accountActions++,
                  onSignOut: () => accountActions++,
                  onOpenSupportChat: () => supportOpens++,
                ),
              ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    final label = language.locale?.languageCode == 'en' ? 'Help' : 'ช่วยเหลือ';
    await tester.scrollUntilVisible(find.text(label), 250,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    language.dispose();
    theme.dispose();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['POSTDEE_HELP_ENGLISH_PREVIEW_DIR'];
    if (output == null || output.isEmpty) return;
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final font = FontLoader('Anuphan');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    font.addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
  }
  await font.load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  _fontsLoaded = true;
}

Finder get _englishBody => find.textContaining('Need help?');
void _expectEnglish(WidgetTester tester) {
  expect(find.text('Help'), findsOneWidget);
  expect(_englishBody, findsOneWidget);
  final body = tester.widget<Text>(_englishBody).data!;
  for (final text in [
    'Getting started',
    '1. Choose a vertical 9:16 video.',
    '2. Select the platforms you want to post to.',
    '3. Publish now or schedule your post in the calendar.',
    'Frequently asked questions',
    'How does the free posting quota work?',
    'The Basic plan includes 3 post units per month after you verify your phone number.',
    'Each channel uses 1 post unit.',
    'one video sent to 3 channels uses 3 units.',
    'Can I schedule posts?',
    'Starter lets you schedule up to 14 days ahead, and Pro up to 30 days.',
    'Tap "Chat with the team" on the Account page',
    'postdee.support@gmail.com',
  ]) {
    expect(body, contains(text));
  }
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? '', isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'existing_setting': 'keep'});
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: 'help-owner',
        idToken: 'fixture-token',
        email: 'seller@example.com',
        emailVerified: true));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets(
      'English Account opens Help with all steps, quota rules and contact details',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await f.open(tester);
    _expectEnglish(tester);
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('Thai Help keeps every original section and quota qualifier',
      (tester) async {
    final f = _Fixture(locale: const Locale('th'));
    await f.mount(tester);
    await f.open(tester);
    expect(find.text('ช่วยเหลือ'), findsOneWidget);
    expect(find.text(_thaiBody), findsOneWidget);
    expect(_englishBody, findsNothing);
    await f.close(tester);
  });

  testWidgets('Open Help follows language changes without replacing its route',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await f.open(tester);
    final route =
        ModalRoute.of(tester.element(find.byType(LegalDocumentScreen)));
    f.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    expect(find.text(_thaiBody), findsOneWidget);
    f.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    _expectEnglish(tester);
    expect(ModalRoute.of(tester.element(find.byType(LegalDocumentScreen))),
        same(route));
    await f.close(tester);
  });

  testWidgets(
      'Reading Help and returning twice keeps account data and settings intact',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    final session = PostDeeAuthSessionStore.instance.session;
    final reads = (f.api.reads, f.drafts.reads);
    for (var visit = 0; visit < 2; visit++) {
      await f.open(tester);
      _expectEnglish(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
    }
    expect(PostDeeAuthSessionStore.instance.session, same(session));
    expect((f.api.reads, f.drafts.reads), reads);
    expect(f.accountActions, 0);
    expect(f.supportOpens, 0);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'existing_setting'});
    expect(preferences.getString('existing_setting'), 'keep');
    await f.close(tester);
  });

  testWidgets(
      'Help contact instructions match the existing Account support entry',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await f.open(tester);
    _expectEnglish(tester);
    expect(f.supportOpens, 0);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Chat with the team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat with the team'));
    await tester.pumpAndSettle();
    expect(f.supportOpens, 1);
    expect(f.accountActions, 0);
    await f.close(tester);
  });

  testWidgets('Screen readers can read English Help and activate Back',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final f = _Fixture();
    try {
      await f.mount(tester);
      await f.open(tester);
      _expectEnglish(tester);
      final body = tester.widget<Text>(_englishBody).data!;
      expect(find.bySemanticsLabel('Help'), findsOneWidget);
      expect(find.bySemanticsLabel(body), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentScreen), findsNothing);
      await f.close(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'Help falls back to original Thai without the app localization delegate',
      (tester) async {
    final account = _Fixture();
    await account.mount(tester);
    await account.open(tester);
    final document = tester
        .widget<LegalDocumentScreen>(find.byType(LegalDocumentScreen))
        .document;
    await account.close(tester);
    final f = _Fixture(withDelegate: false);
    await f.mount(tester, document: document);
    expect(find.text('ช่วยเหลือ'), findsOneWidget);
    expect(find.text(_thaiBody), findsOneWidget);
    await f.close(tester);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('Help is readable at ${scale}x in ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            scale == 1 ? const Size(390, 844) : const Size(320, 740);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = _Fixture(dark: dark, scale: scale);
        await f.mount(tester);
        await f.open(tester);
        _expectEnglish(tester);
        for (final label in [find.text('Help'), _englishBody]) {
          final paragraph = tester.renderObject<RenderParagraph>(find
              .descendant(of: label, matching: find.byType(RichText))
              .first);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
              paragraph.size.height,
              greaterThanOrEqualTo(
                  paragraph.getMinIntrinsicHeight(paragraph.size.width) - .5));
          final rect = tester.getRect(label);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
        }
        await f.capture(tester, 'help-${dark ? 'dark' : 'light'}-${scale}x');
        final scroll = find.descendant(
            of: find.byType(LegalDocumentScreen),
            matching: find.byType(Scrollable));
        final position = tester.state<ScrollableState>(scroll).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.getRect(_englishBody).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height));
        await f.capture(
            tester, 'help-${dark ? 'dark' : 'light'}-${scale}x-bottom');
        final back = find.byType(BackButton).hitTestable();
        expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentScreen), findsNothing);
        expect(tester.takeException(), isNull);
        await f.close(tester);
      });
    }
  }
}
