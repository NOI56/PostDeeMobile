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

const _englishBody = 'PostDee protects your account and data.\n\n'
    '- Email and Google sign-in are handled by Firebase Authentication. '
    'The app does not store your password.\n'
    '- Social account connection tokens are stored securely on the server.\n'
    '- AI service secret keys stay on the server and are never included in the app.\n\n'
    'If you notice suspicious activity, contact postdee.support@gmail.com.';

const _thaiBody = 'PostDee ดูแลความปลอดภัยของบัญชีและข้อมูลของคุณ\n\n'
    '- การเข้าสู่ระบบด้วยอีเมลหรือ Google จัดการผ่าน Firebase Authentication '
    'และแอปไม่เก็บรหัสผ่านของคุณ\n'
    '- โทเคนการเชื่อมต่อบัญชีโซเชียลถูกเก็บอย่างปลอดภัยบนเซิร์ฟเวอร์\n'
    '- คีย์ลับของระบบ AI อยู่ฝั่งเซิร์ฟเวอร์เท่านั้น ไม่อยู่ในแอป\n\n'
    'หากพบกิจกรรมที่น่าสงสัย ติดต่อ postdee.support@gmail.com';

class _Api extends PostDeeApiClient {
  int channelReads = 0;
  int subscriptionReads = 0;

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async {
    channelReads++;
    return const [];
  }

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    subscriptionReads++;
    return const SubscriptionStatusResult(
      userId: 'security-owner',
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
      throw StateError('Reading Security must not save a profile draft');

  @override
  Future<void> clear() async =>
      throw StateError('Reading Security must not clear a profile draft');
}

class _Fixture {
  _Fixture({
    Locale locale = const Locale('en'),
    this.dark = false,
    this.scale = 1,
    this.withDelegate = true,
  })  : language = PostDeeLanguageController(initialLocale: locale),
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
  final boundaryKey = GlobalKey();
  int accountActions = 0;

  Widget app({LegalDocument? document}) => AnimatedBuilder(
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
            key: boundaryKey,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
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
                  ),
                ),
        ),
      );

  Future<void> mount(WidgetTester tester, {LegalDocument? document}) async {
    await tester.runAsync(_loadFonts);
    await tester.pumpWidget(app(document: document));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    final label = withDelegate && language.locale?.languageCode == 'en'
        ? 'Security'
        : 'ความปลอดภัย';
    await tester.scrollUntilVisible(
      find.text(label),
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
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
    final output = Platform.environment['POSTDEE_SECURITY_ENGLISH_PREVIEW_DIR'];
    if (output == null || output.isEmpty) return;
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
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
  final fonts = FontLoader('Anuphan');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    fonts.addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
  }
  await fonts.load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  _fontsLoaded = true;
}

void _expectEnglish() {
  expect(find.text('Security'), findsOneWidget);
  expect(find.text(_englishBody), findsOneWidget);
  for (final text in testerTexts()) {
    expect(text, isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
}

Iterable<String> testerTexts() => find.byType(Text).evaluate().map(
      (element) => (element.widget as Text).data ?? '',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'existing_setting': 'keep'});
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: 'security-owner',
      idToken: 'fixture-token',
      email: 'seller@example.com',
      emailVerified: true,
    ));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('Security opened from English Account translates every paragraph',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await f.open(tester);
    _expectEnglish();
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('Thai Security keeps the complete original copy', (tester) async {
    final f = _Fixture(locale: const Locale('th'));
    await f.mount(tester);
    await f.open(tester);
    expect(find.text('ความปลอดภัย'), findsOneWidget);
    expect(find.text(_thaiBody), findsOneWidget);
    expect(find.text(_englishBody), findsNothing);
    await f.close(tester);
  });

  testWidgets('Security defaults to Thai without the app localization delegate',
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
    expect(find.text(_thaiBody), findsOneWidget);
    expect(find.text(_englishBody), findsNothing);
    await f.close(tester);
  });

  testWidgets('Security follows locale changes while the same route is open',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await f.open(tester);
    _expectEnglish();
    final route =
        ModalRoute.of(tester.element(find.byType(LegalDocumentScreen)));
    f.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    expect(find.text(_thaiBody), findsOneWidget);
    expect(find.text('ความปลอดภัย'), findsOneWidget);
    f.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    _expectEnglish();
    expect(ModalRoute.of(tester.element(find.byType(LegalDocumentScreen))),
        same(route));
    await f.close(tester);
  });

  testWidgets('Back and reopen keep the account, settings and profile intact',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    final session = PostDeeAuthSessionStore.instance.session;
    final reads = (f.api.channelReads, f.api.subscriptionReads, f.drafts.reads);
    for (var visit = 0; visit < 2; visit++) {
      await f.open(tester);
      _expectEnglish();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
    }
    expect(PostDeeAuthSessionStore.instance.session, same(session));
    expect(
        (f.api.channelReads, f.api.subscriptionReads, f.drafts.reads), reads);
    expect(f.accountActions, 0);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'existing_setting'});
    expect(preferences.getString('existing_setting'), 'keep');
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('Screen reader can read English Security and use Back',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final f = _Fixture();
    try {
      await f.mount(tester);
      await f.open(tester);
      expect(find.bySemanticsLabel('Security'), findsOneWidget);
      expect(find.bySemanticsLabel(_englishBody), findsOneWidget);
      expect(find.bySemanticsLabel('Back').hitTestable(), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentScreen), findsNothing);
      await f.close(tester);
    } finally {
      semantics.dispose();
    }
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets(
          'Security is readable at ${scale}x in ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            scale == 1 ? const Size(390, 844) : const Size(320, 740);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = _Fixture(dark: dark, scale: scale);
        await f.mount(tester);
        await f.open(tester);
        _expectEnglish();
        for (final label in [find.text('Security'), find.text(_englishBody)]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: label, matching: find.byType(RichText)).first,
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
              paragraph.size.height,
              greaterThanOrEqualTo(
                paragraph.getMinIntrinsicHeight(paragraph.size.width) - .5,
              ));
          final rect = tester.getRect(label);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
        }
        await f.capture(
            tester, 'security-${dark ? 'dark' : 'light'}-${scale}x');
        final scrollable = find.descendant(
          of: find.byType(LegalDocumentScreen),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        final bodyRect = tester.getRect(find.text(_englishBody));
        expect(bodyRect.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height));
        await f.capture(
            tester, 'security-${dark ? 'dark' : 'light'}-${scale}x-bottom');
        final back = find.byType(BackButton).hitTestable();
        expect(back, findsOneWidget);
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

  testWidgets('Documents without English copy keep their original content',
      (tester) async {
    for (final document in [
      const LegalDocument(title: 'เอกสารเดิม', body: 'ข้อความเดิม'),
      PostDeeLegalDocuments.privacyPolicy,
      PostDeeLegalDocuments.termsOfService,
    ]) {
      final f = _Fixture();
      await f.mount(tester, document: document);
      expect(find.text(document.title), findsOneWidget);
      expect(find.text(document.body), findsOneWidget);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    }
  });

  testWidgets(
      'An optional translation falls back separately for title and body',
      (tester) async {
    for (final document in [
      const LegalDocument(
        title: 'หัวข้อเดิม',
        body: 'ข้อความเดิม',
        englishTitle: 'Translated heading',
      ),
      const LegalDocument(
        title: 'หัวข้อเดิม',
        body: 'ข้อความเดิม',
        englishBody: 'Translated content',
      ),
    ]) {
      final f = _Fixture();
      await f.mount(tester, document: document);
      expect(
          find.text(document.englishTitle ?? document.title), findsOneWidget);
      expect(find.text(document.englishBody ?? document.body), findsOneWidget);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    }
  });
}
