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

const _thaiBody = 'การใช้งาน PostDee ถือว่าคุณยอมรับข้อกำหนดต่อไปนี้\n\n'
    'การใช้งานบริการ\n'
    '- ใช้แอปเพื่อโพสต์คอนเทนต์ที่คุณมีสิทธิ์เผยแพร่เท่านั้น\n'
    '- ปฏิบัติตามนโยบายของแต่ละแพลตฟอร์มโซเชียลที่เชื่อมต่อ\n'
    '- คุณต้องเลือกช่องทางเองและตรวจรูปแบบเผยแพร่ของแต่ละช่องทางก่อนยืนยัน\n'
    '- TikTok เลือกส่งเป็นร่างเพื่อแก้ต่อใน TikTok หรือโพสต์ตรงตามตัวเลือกผู้ชมล่าสุดของบัญชี โดยต้องยืนยันสิทธิ์เพลงและข้อกำหนดที่เกี่ยวข้องก่อนส่ง ผลเผยแพร่อาจต้องรอ TikTok ประมวลผล\n'
    '- YouTube Shorts เลือกการมองเห็นได้, Instagram ตามบัญชีที่เชื่อม และ Facebook Reels บนเพจเลือกเผยแพร่หรือร่างได้; หากระบุรูปแบบไม่ได้ ระบบจะไม่ให้ยืนยัน\n'
    '- การตั้งเวลาต้องเป็นเวลาในอนาคต: Starter ไม่เกิน 14 วัน และ Pro ไม่เกิน 30 วัน; การเลื่อนเวลาใช้สิทธิ์แพ็กเกจปัจจุบัน โดยคิวที่รับไว้แล้วไม่ถูกยกเลิกอัตโนมัติ\n\n'
    'ฉบับร่าง\n'
    '- ฉบับร่างโพสต์เก็บเฉพาะในพื้นที่ของแอป ไม่ใช่โพสต์บนเซิร์ฟเวอร์และไม่ซิงก์ข้ามเครื่อง\n'
    '- ระบบปฏิบัติการอาจสำรองไฟล์ร่างตามการตั้งค่า และการลบบัญชีอาจไม่ลบสำเนาเฉพาะเครื่องหรือ backup\n\n'
    'แพ็กเกจและการชำระเงิน\n'
    '- แพ็กเกจ Starter และ Pro เป็นแบบรายเดือนผ่านสโตร์ของ Apple/Google\n'
    '- จัดการหรือยกเลิกการสมัครได้จากการตั้งค่าสโตร์ของอุปกรณ์\n\n'
    'เนื้อหาและความรับผิดชอบ\n'
    '- คุณเป็นผู้รับผิดชอบเนื้อหาที่โพสต์ผ่านบัญชีของคุณ\n'
    '- ห้ามใช้แอปเพื่อสแปม หลอกลวง หรือผิดกฎหมาย\n\n'
    'การเปลี่ยนแปลง\n'
    '- เราอาจปรับปรุงบริการและข้อกำหนด โดยจะแจ้งให้ทราบล่วงหน้าตามสมควร\n\n'
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
      userId: 'terms-owner',
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
      throw StateError('Reading Terms must not save a profile draft');
  @override
  Future<void> clear() async =>
      throw StateError('Reading Terms must not clear a profile draft');
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
                document: PostDeeLegalDocuments.termsOfService,
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
        ? 'Terms of service'
        : 'ข้อกำหนดการใช้งาน';
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
    final output = Platform.environment['POSTDEE_TERMS_ENGLISH_PREVIEW_DIR'];
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

Finder get _englishBody => find.textContaining('postdee.support@gmail.com');

void _expectEnglish(WidgetTester tester) {
  expect(find.text('Terms of service'), findsOneWidget);
  expect(_englishBody, findsOneWidget);
  final body = tester.widget<Text>(_englishBody).data!;
  for (final text in [
    'Using the service',
    'Local drafts',
    'Plans and payments',
    'Content and responsibility',
    'Changes',
    'TikTok',
    'YouTube Shorts',
    'Instagram',
    'Facebook Page Reels',
    'App Store',
    'Google Play',
    'Contact: postdee.support@gmail.com',
    'Draft document',
    'before release',
  ]) {
    expect(body, contains(text));
  }
  for (final pattern in [
    r'using PostDee.*(?:accept|agree).*terms',
    r'(?:only.*(?:right|rights|permission).*publish|(?:right|rights|permission).*publish.*only)',
    r'(?:follow|comply).*(?:policies.*platform|platform.*policies)',
    r'(?:(?:choose|select).*channels.*yourself|manually (?:choose|select).*channels).*review.*(?:delivery|publishing|publication).*before.*confirm',
    r'TikTok.*draft.*(?:continue editing|edit).*TikTok.*(?:or|alternatively).*direct.*(?:latest|current|most recent).*audience.*account',
    r'confirm.*music rights.*(?:relevant|applicable|related) terms.*before.*send',
    r'(?:publish|publication).*may.*TikTok.*process',
    r'YouTube Shorts.*(?:choose|select).*visibility',
    r'Instagram.*connected account',
    r'Facebook Page Reels.*(?:publish|publication).*draft',
    r'(?:mode|format).*cannot.*(?:confirm|confirmation)|(?:mode|format).*not.*(?:available|determined|identified).*confirm',
    r'schedul.*future.*Starter.*14.*Pro.*30',
    r'reschedul.*current.*(?:plan|entitlement)',
    r'(?:accepted.*queue|queue.*accepted).*not.*(?:automatic.*cancel|cancel.*automatic)',
    r'drafts.*(?:only|locally).*app.*storage',
    r'(?:not.*server posts|not.*posts.*server)',
    r'(?:do not|not).*sync.*(?:across|between).*devices',
    r'operating system.*may.*back ?up.*settings',
    r'(?:delet(?:ing|ion).*account|account deletion).*may not.*(?:device|local).*backup',
    r'Starter and Pro.*monthly',
    r'(?:manage|managing).*cancel.*subscription.*(?:store.*settings|settings.*store)',
    r'(?:you are|your).*responsib.*content.*account',
    r'(?:do not|must not).*spam.*(?:fraud|scam).*illegal',
    r'may (?:update|change|improve).*service.*terms',
    r'(?:reasonable|appropriate).*advance notice|advance notice.*(?:reasonable|appropriate)',
  ]) {
    expect(body, matches(RegExp(pattern, caseSensitive: false, dotAll: true)),
        reason: 'Terms must preserve: $pattern');
  }
  expect(body, isNot(contains('Facebook Page Video')));
  expect(body.indexOf('Draft document'), greaterThan(body.indexOf('Contact:')));
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? '', isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'existing_setting': 'keep'});
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: 'terms-owner',
      idToken: 'fixture-token',
      email: 'seller@example.com',
      emailVerified: true,
    ));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets(
      'English Account opens Terms with all original service conditions',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await f.open(tester);
    _expectEnglish(tester);
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('Signed-out standalone Terms uses the same complete English copy',
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
      'Thai Terms retains every original condition and draft disclaimer',
      (tester) async {
    final f = _Fixture(locale: const Locale('th'));
    await f.mount(tester);
    await f.open(tester);
    expect(find.text('ข้อกำหนดการใช้งาน'), findsOneWidget);
    expect(find.text(_thaiBody), findsOneWidget);
    expect(PostDeeLegalDocuments.termsOfService.body, _thaiBody);
    await f.close(tester);
  });

  testWidgets('Terms follows locale changes while preserving its open route',
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
      'Reading Terms and reopening keeps account, preferences and drafts intact',
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

  testWidgets('Screen readers can read English Terms and activate Back',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final f = _Fixture();
    try {
      await f.mount(tester);
      await f.open(tester);
      _expectEnglish(tester);
      final body = tester.widget<Text>(_englishBody).data!;
      expect(find.bySemanticsLabel('Terms of service'), findsOneWidget);
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
      'Terms defaults to the original Thai copy without the app delegate',
      (tester) async {
    final f = _Fixture(withDelegate: false);
    await f.mount(tester, standalone: true);
    expect(find.text('ข้อกำหนดการใช้งาน'), findsOneWidget);
    expect(find.text(_thaiBody), findsOneWidget);
    await f.close(tester);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets(
          'Terms is readable at ${scale}x in ${dark ? 'dark' : 'light'}',
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
        for (final label in [find.text('Terms of service'), _englishBody]) {
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
              'terms-${dark ? 'dark' : 'light'}-${scale}x-${(fraction * 100).round()}');
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
