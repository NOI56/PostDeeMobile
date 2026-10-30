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

const _thaiBody =
    'PostDee เก็บข้อมูลเท่าที่จำเป็นเพื่อให้บริการโพสต์และตั้งเวลาคลิป '
    'วิดีโอไปยังแพลตฟอร์มโซเชียลของคุณ\n\n'
    'ข้อมูลที่เราเก็บ\n'
    '- บัญชีและอีเมลที่ใช้เข้าสู่ระบบ\n'
    '- วิดีโอและแคปชั่นที่คุณอัปโหลดเพื่อโพสต์หรือตั้งเวลา\n'
    '- โทเคนการเชื่อมต่อบัญชีโซเชียล (เก็บอย่างปลอดภัย ไม่เปิดเผยต่อผู้อื่น)\n\n'
    'ฉบับร่างในเครื่อง\n'
    '- เมื่อกดบันทึกร่าง แอปคัดลอกวิดีโอ หน้าปก และข้อมูลร่างไว้ในพื้นที่ของแอป แยกตามบัญชีที่เข้าสู่ระบบ\n'
    '- การบันทึกร่างไม่อัปโหลดไป API/R2 ไม่ส่งไปแพลตฟอร์ม ไม่เข้าคิว และไม่ใช้โควตาโพสต์\n'
    '- ร่างไม่ซิงก์ข้ามอุปกรณ์ แต่อาจรวมอยู่ในข้อมูลสำรองของระบบปฏิบัติการตามการตั้งค่า\n'
    '- แอปลบร่างหลัง API รับโพสต์เข้าคิว หากขั้นตอนก่อนรับเข้าคิวล้มเหลวจะเก็บร่างไว้ และหากลบไฟล์ไม่สำเร็จแอปจะแจ้งเตือนว่าไฟล์อาจยังอยู่\n\n'
    'การใช้ข้อมูล\n'
    '- ใช้เพื่อโพสต์ ตั้งเวลา และแสดงผลวิเคราะห์ให้คุณเท่านั้น\n'
    '- ไม่ขายข้อมูลส่วนบุคคลให้บุคคลที่สาม\n\n'
    'สิทธิของคุณ\n'
    '- ขอดู แก้ไข หรือลบข้อมูลของคุณได้ทุกเมื่อ\n'
    '- ลบฉบับร่างแต่ละรายการได้จากหน้าร่าง\n'
    '- ลบบัญชีจากหน้าโปรไฟล์เพื่อลบข้อมูลฝั่งบริการ การลบนี้อาจไม่ลบไฟล์เฉพาะเครื่องหรือสำเนาในระบบสำรองข้อมูล จึงควรลบร่างหรือล้างข้อมูลแอปแยกต่างหาก\n\n'
    'ติดต่อ: postdee.support@gmail.com\n\n'
    '(เอกสารฉบับร่าง — จะอัปเดตเป็นฉบับสมบูรณ์ก่อนเผยแพร่จริง)';

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
      userId: 'privacy-owner',
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
      throw StateError('Reading Privacy must not save a profile draft');
  @override
  Future<void> clear() async =>
      throw StateError('Reading Privacy must not clear a profile draft');
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
  final boundary = GlobalKey();
  int accountActions = 0;

  Future<void> mount(WidgetTester tester, {bool standalone = false}) async {
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
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
        home: standalone
            ? const LegalDocumentScreen(
                document: PostDeeLegalDocuments.privacyPolicy,
              )
            : Scaffold(
                body: ProfileScreen(
                  languageController: language,
                  themeController: theme,
                  apiClient: api,
                  profileDraftStore: drafts,
                  onOpenTemplates: () => accountActions++,
                  onDeleteAccount: () => accountActions++,
                  onSignOut: () => accountActions++,
                  onOpenSupportChat: () => accountActions++,
                ),
              ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    final label = language.locale?.languageCode == 'en'
        ? 'Privacy policy'
        : 'นโยบายความเป็นส่วนตัว';
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
    final output = Platform.environment['POSTDEE_PRIVACY_ENGLISH_PREVIEW_DIR'];
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

Finder get _englishBody => find.textContaining('What we collect');

void _expectEnglish(WidgetTester tester) {
  expect(find.text('Privacy policy'), findsOneWidget);
  expect(_englishBody, findsOneWidget);
  final body = tester.widget<Text>(_englishBody).data!;
  for (final text in [
    'What we collect',
    'Drafts on this device',
    'How we use your data',
    'Your rights',
    'Contact: postdee.support@gmail.com',
    'Draft document',
    'before release',
  ]) {
    expect(body, contains(text));
  }
  for (final pattern in [
    r'account and email',
    r'videos and captions.*upload.*publish|videos and captions.*upload.*publishing',
    r'social account connection tokens.*stored securely.*not disclosed',
    r'copies.*video.*cover.*draft.*storage.*(each|per).*account',
    r'does not upload.*API/R2.*send.*platform.*queue.*(use|consume).*post quota',
    r'do not sync across devices.*may be included.*operating system backups.*settings',
    r'deletes? a draft after.*API.*queue',
    r'before.*accepted.*draft is kept',
    r'cannot be deleted.*warns.*may still',
    r'only to publish and schedule.*analytics',
    r'do not sell personal information.*third parties',
    r'request access.*correction.*deletion.*any time',
    r'delete individual drafts.*drafts page',
    r'delete your account.*Account page.*data.*service',
    r'may not delete.*device.*backups.*delete drafts or clear.*app.*data separately',
  ]) {
    expect(body, matches(RegExp(pattern, caseSensitive: false, dotAll: true)),
        reason: 'Privacy disclosure must preserve: $pattern');
  }
  expect(body.indexOf('Draft document'), greaterThan(body.indexOf('Contact:')));
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? '', isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'existing_setting': 'keep'});
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: 'privacy-owner',
      idToken: 'fixture-token',
      email: 'seller@example.com',
      emailVerified: true,
    ));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('English Account opens Privacy with all original disclosures',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await f.open(tester);
    _expectEnglish(tester);
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets(
      'Signed-out standalone Privacy uses the same complete English copy',
      (tester) async {
    PostDeeAuthSessionStore.instance.clear();
    final f = _Fixture();
    await f.mount(tester, standalone: true);
    _expectEnglish(tester);
    expect(PostDeeAuthSessionStore.instance.session.isSignedIn, isFalse);
    expect(f.api.reads, 0);
    expect(f.drafts.reads, 0);
    expect(f.accountActions, 0);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets(
      'Thai Privacy retains every original paragraph and draft disclaimer',
      (tester) async {
    final f = _Fixture(locale: const Locale('th'));
    await f.mount(tester);
    await f.open(tester);
    expect(find.text('นโยบายความเป็นส่วนตัว'), findsOneWidget);
    expect(find.text(_thaiBody), findsOneWidget);
    expect(PostDeeLegalDocuments.privacyPolicy.body, _thaiBody);
    expect(_englishBody, findsNothing);
    await f.close(tester);
  });

  testWidgets('Privacy follows locale changes while preserving its open route',
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
      'Reading Privacy and reopening keeps account, preferences and drafts intact',
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
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'existing_setting'});
    expect(preferences.getString('existing_setting'), 'keep');
    await f.close(tester);
  });

  testWidgets('Screen readers can read English Privacy and activate Back',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final f = _Fixture();
    try {
      await f.mount(tester);
      await f.open(tester);
      _expectEnglish(tester);
      final body = tester.widget<Text>(_englishBody).data!;
      expect(find.bySemanticsLabel('Privacy policy'), findsOneWidget);
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
      'Privacy defaults to the original Thai copy without the app delegate',
      (tester) async {
    final f = _Fixture(withDelegate: false);
    await f.mount(tester, standalone: true);
    expect(find.text('นโยบายความเป็นส่วนตัว'), findsOneWidget);
    expect(find.text(_thaiBody), findsOneWidget);
    expect(_englishBody, findsNothing);
    await f.close(tester);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets(
          'Privacy is readable at ${scale}x in ${dark ? 'dark' : 'light'}',
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
        for (final label in [find.text('Privacy policy'), _englishBody]) {
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
        final scroll = find.descendant(
            of: find.byType(LegalDocumentScreen),
            matching: find.byType(Scrollable));
        final position = tester.state<ScrollableState>(scroll).position;
        for (final fraction in [0.0, 0.33, 0.67, 1.0]) {
          position.jumpTo(position.maxScrollExtent * fraction);
          await tester.pumpAndSettle();
          await f.capture(tester,
              'privacy-${dark ? 'dark' : 'light'}-${scale}x-${(fraction * 100).round()}');
        }
        expect(tester.getRect(_englishBody).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height));
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
