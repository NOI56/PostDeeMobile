import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/app.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';

Finder _referenceNav() =>
    find.byKey(const ValueKey('postdee-reference-bottom-nav'));

Finder _referenceNavButton(String label) => find.descendant(
      of: _referenceNav(),
      matching: find.bySemanticsLabel(label),
    );

Future<void> _tapReferenceNavButton(
  WidgetTester tester,
  String label,
) async {
  await tester.tap(_referenceNavButton(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('configures supported app locales', (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.clear();
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, const Locale('th'));
    expect(materialApp.supportedLocales, PostDeeLocalizations.supportedLocales);
    expect(
      materialApp.localizationsDelegates,
      contains(PostDeeLocalizations.delegate),
    );
  });

  testWidgets('uses English shell labels when device locale is English',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('en')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(_referenceNav(), findsOneWidget);
    for (final label in [
      'Home',
      'Calendar',
      'Create post',
      'Store link',
      'Account'
    ]) {
      expect(_referenceNavButton(label), findsOneWidget);
    }
  });
  testWidgets('uses English login labels when app locale is English',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.clear();
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('en')));

    expect(find.text('Sign in to PostDee'), findsOneWidget);
    expect(
      find.text('Connect your email before using the app'),
      findsOneWidget,
    );
    expect(
      find.text('Connect an email first so you can post and manage content.'),
      findsOneWidget,
    );
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(
      find.text('Firebase Auth is disabled. Enable Firebase Auth for sign-in.'),
      findsOneWidget,
    );
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('uses English home labels when app locale is English',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Could not check package'), findsOneWidget);
    expect(find.text('Free package'), findsNothing);
    expect(find.text('AI editing'), findsNothing);
    expect(find.text('Views this month'), findsOneWidget);
    expect(find.text('Likes this month'), findsOneWidget);
    expect(find.text('Create a new post'), findsNothing);
    expect(find.text('Profile link'), findsOneWidget);
    expect(find.text('Store link'), findsOneWidget);
    expect(find.text('Latest post status'), findsOneWidget);
    expect(find.text('View all'), findsNothing);
    expect(find.text('Pro package'), findsNothing);
    expect(find.text('23 days left'), findsNothing);
    expect(find.text('+12% from last week'), findsNothing);
    expect(find.text('Posted today 2'), findsNothing);
    expect(find.text('Published'), findsNothing);
    expect(find.text('Processing'), findsNothing);
    expect(find.text('Queued'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-latest-posts-error')),
      findsOneWidget,
    );

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Shortcuts'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Upload'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Templates'), findsNothing);
  });
  testWidgets('keeps home shortcuts hidden on a phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('th')));
    await tester.pumpAndSettle();

    final shortcutsTitle = find.text('ทางลัด');
    final uploadShortcut = find.widgetWithText(TextButton, 'อัปโหลด');
    final templatesShortcut = find.widgetWithText(TextButton, 'เทมเพลต');

    expect(shortcutsTitle, findsNothing);
    expect(uploadShortcut, findsNothing);
    expect(templatesShortcut, findsNothing);
  });

  testWidgets('keeps home shell chrome compact on a phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('th')));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    final surfaceRect = tester.getRect(
      find.byKey(const ValueKey('postdee-nav-surface')),
    );
    final viewportSize =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(surfaceRect.left, 0);
    expect(surfaceRect.right, viewportSize.width);
    expect(surfaceRect.bottom, viewportSize.height);
    expect(tester.getSize(_referenceNav()).height, lessThanOrEqualTo(92));
  });
  testWidgets(
      'keeps upload schedule controls above bottom nav on a phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('th')));
    await tester.pumpAndSettle();

    await _tapReferenceNavButton(tester, 'สร้างโพสต์');

    final bottomNavTop = tester.getTopLeft(_referenceNav()).dy;
    final schedulePanel = find.byKey(
      const ValueKey('uploader-schedule-panel'),
    );
    final postNowButton = find.byKey(
      const ValueKey('uploader-schedule-now'),
    );
    final scheduleButton = find.byKey(
      const ValueKey('uploader-schedule-later'),
    );
    final scheduleAtField = find.byKey(
      const ValueKey('uploader-schedule-at-field'),
    );

    await tester.scrollUntilVisible(
      schedulePanel,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(schedulePanel, findsOneWidget);
    expect(postNowButton, findsOneWidget);
    expect(scheduleButton, findsOneWidget);
    expect(scheduleAtField, findsNothing);
    expect(tester.getBottomLeft(schedulePanel).dy, lessThan(bottomNavTop));
    expect(tester.getBottomLeft(postNowButton).dy, lessThan(bottomNavTop));
    expect(tester.getBottomLeft(scheduleButton).dy, lessThan(bottomNavTop));

    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    expect(scheduleAtField, findsNothing);
    expect(
      find.byKey(const ValueKey('uploader-schedule-day-tomorrow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('uploader-schedule-time-1830')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('uploader-schedule-summary')),
      findsOneWidget,
    );
  });

  testWidgets('keeps upload video preview compact on a phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('th')));
    await tester.pumpAndSettle();

    await _tapReferenceNavButton(tester, 'สร้างโพสต์');

    final videoPreview = find.byKey(
      const ValueKey('uploader-video-preview-picker'),
    );

    expect(videoPreview, findsOneWidget);
    expect(tester.getSize(videoPreview).height, lessThanOrEqualTo(244));
  });

  testWidgets(
      'keeps upload post button sticky above bottom nav on a phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('th')));
    await tester.pumpAndSettle();

    await _tapReferenceNavButton(tester, 'สร้างโพสต์');

    final bottomNavTop = tester.getTopLeft(_referenceNav()).dy;
    final stickyPostButton = find.byKey(
      const ValueKey('uploader-sticky-post-button'),
    );
    final stickyActionBar = find.byKey(
      const ValueKey('uploader-sticky-action-bar'),
    );

    expect(stickyActionBar, findsOneWidget);
    expect(stickyPostButton, findsOneWidget);
    expect(tester.getTopLeft(stickyActionBar).dy, greaterThan(0));
    expect(
      tester.getTopLeft(stickyActionBar).dy,
      lessThan(tester.getTopLeft(stickyPostButton).dy),
    );
    expect(tester.getTopLeft(stickyPostButton).dy, greaterThan(0));
    expect(tester.getBottomLeft(stickyPostButton).dy, lessThan(bottomNavTop));
  });

  for (final themeMode in const [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('uses green selected nav colors in ${themeMode.name} mode',
        (tester) async {
      final initialThemeMode =
          AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
      final themeController = PostDeeThemeController(initialMode: themeMode);
      final sessionStore = PostDeeAuthSessionStore.instance;
      sessionStore.signIn(
        const AuthSession(
          idToken: 'firebase-id-token',
          email: 'seller@example.com',
          displayName: 'PostDee Seller',
        ),
      );
      addTearDown(() {
        sessionStore.clear();
        themeController.dispose();
        AppTheme.applyThemeMode(initialThemeMode);
      });

      await tester.pumpWidget(
        PostDeeApp(locale: const Locale('th'), themeController: themeController),
      );
      await tester.pumpAndSettle();

      final systemIcons =
          themeMode == ThemeMode.light ? Brightness.dark : Brightness.light;
      expect(SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
          systemIcons);
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, systemIcons);

      final surface = tester.widget<Material>(
        find.byKey(const ValueKey('postdee-nav-surface')),
      );
      expect(surface.color, AppTheme.navSurface);
      expect(surface.color!.a, 1);
      expect(surface.elevation, 0);
      expect(
        find.descendant(
          of: _referenceNav(),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(find.byType(BottomNavigationBar), findsNothing);

      void expectMenuColors(String label, IconData icon,
          {required bool selected}) {
        final button = _referenceNavButton(label);
        final expectedColor =
            selected ? AppTheme.navActive : AppTheme.textSecondary;
        expect(
          tester.widget<Icon>(
            find.descendant(of: button, matching: find.byIcon(icon)),
          ).color,
          expectedColor,
        );
        expect(
          tester.widget<Text>(
            find.descendant(of: button, matching: find.text(label)),
          ).style!.color,
          expectedColor,
        );
        final indicator = find.descendant(
          of: button,
          matching: find.byKey(const ValueKey('postdee-nav-selected-indicator')),
        );
        if (selected) {
          final decoration =
              tester.widget<DecoratedBox>(indicator).decoration as BoxDecoration;
          expect(decoration.color, AppTheme.navActive);
        } else {
          expect(indicator, findsNothing);
        }
      }

      expectMenuColors('หน้าหลัก', Icons.home_outlined, selected: true);
      expectMenuColors('ปฏิทิน', Icons.calendar_today_outlined, selected: false);
      expectMenuColors('ลิงก์ร้าน', Icons.link_outlined, selected: false);
      expectMenuColors('บัญชี', Icons.person_outline_rounded, selected: false);
      await _tapReferenceNavButton(tester, 'ปฏิทิน');
      expectMenuColors('หน้าหลัก', Icons.home_outlined, selected: false);
      expectMenuColors('ปฏิทิน', Icons.calendar_today_outlined, selected: true);
      await _tapReferenceNavButton(tester, 'ลิงก์ร้าน');
      expectMenuColors('ลิงก์ร้าน', Icons.link_outlined, selected: true);
      expectMenuColors('ปฏิทิน', Icons.calendar_today_outlined, selected: false);
      await _tapReferenceNavButton(tester, 'บัญชี');
      expectMenuColors('บัญชี', Icons.person_outline_rounded, selected: true);
      expectMenuColors('ลิงก์ร้าน', Icons.link_outlined, selected: false);
      expect(
        tester.widget<Icon>(find.descendant(
          of: _referenceNavButton('สร้างโพสต์'),
          matching: find.byIcon(Icons.ios_share_outlined),
        )).color,
        Colors.white,
      );
      expect(
        find.descendant(of: _referenceNav(), matching: find.text('สร้างโพสต์')),
        findsNothing,
      );
    });
  }
  testWidgets('switches between dark and light mode from profile',
      (tester) async {
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    final themeController = PostDeeThemeController();
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(() {
      sessionStore.clear();
      languageController.dispose();
      themeController.dispose();
      AppTheme.applyThemeMode(ThemeMode.dark);
    });

    await tester.pumpWidget(
      PostDeeApp(
        languageController: languageController,
        themeController: themeController,
      ),
    );
    await tester.pumpAndSettle();

    expect(themeController.themeMode, ThemeMode.light);
    expect(AppTheme.isLightMode, isTrue);
    final homeLinkShortcut = find.byKey(
      const ValueKey('home-link-in-bio-shortcut'),
      skipOffstage: false,
    );
    expect(homeLinkShortcut, findsOneWidget);
    final lightLinkCardColor = tester.widget<Material>(homeLinkShortcut).color;

    await _tapReferenceNavButton(tester, 'Account');

    final darkModeButton = find.text('มืด');
    await tester.scrollUntilVisible(
      darkModeButton,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    // The floating capsule nav overlays the bottom of the list; nudge the
    // button above it so the tap doesn't land on the nav.
    final viewportBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final overlap = tester.getRect(darkModeButton).bottom -
        (viewportBottom - AppTheme.navOverlap);
    if (overlap > 0) {
      await tester.drag(
        find.byType(Scrollable).first,
        Offset(0, -(overlap + 10)),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(darkModeButton);
    await tester.pumpAndSettle();

    expect(themeController.themeMode, ThemeMode.dark);
    expect(AppTheme.isLightMode, isFalse);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    final darkLinkCardColor = tester.widget<Material>(homeLinkShortcut).color;
    expect(darkLinkCardColor, AppTheme.glass);
    expect(darkLinkCardColor, isNot(lightLinkCardColor));

    final lightModeButton = find.text('สว่าง');
    await tester.tap(lightModeButton);
    await tester.pumpAndSettle();

    expect(themeController.themeMode, ThemeMode.light);
    expect(AppTheme.isLightMode, isTrue);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light);
    expect(tester.widget<Material>(homeLinkShortcut).color, lightLinkCardColor);
  });

  testWidgets('switches from English to Thai from the profile language picker',
      (tester) async {
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(
      PostDeeApp(languageController: languageController),
    );
    await tester.pumpAndSettle();

    expect(_referenceNavButton('Home'), findsOneWidget);

    await _tapReferenceNavButton(tester, 'Account');

    expect(find.text('Language'), findsOneWidget);

    final thaiButton = find.text('ไทย');
    await tester.scrollUntilVisible(
      thaiButton,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final viewportBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final overlap = tester.getRect(thaiButton).bottom -
        (viewportBottom - AppTheme.navOverlap);
    if (overlap > 0) {
      await tester.drag(
        find.byType(Scrollable).first,
        Offset(0, -(overlap + 10)),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(thaiButton);
    await tester.pumpAndSettle();

    expect(languageController.locale, const Locale('th'));
    // The profile route sits on top, so assert its now-Thai content rather than
    // the bottom nav, which is offstage behind the pushed route.
    expect(find.text('ภาษา'), findsOneWidget);
  });

  testWidgets('requires sign-in before showing the main shell', (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.clear();
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('th')));

    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
    final googleLogo = tester.widget<Image>(
      find.byKey(const ValueKey('google-sign-in-logo')),
    );
    expect(
      (googleLogo.image as AssetImage).assetName,
      'assets/images/brand/google_sign_in_light_square.png',
    );
    expect(find.text('G'), findsNothing);
    expect(find.text('ลงครั้งเดียว ขายได้ทุกที่'), findsOneWidget);
    expect(
      find.text(
          'โพสต์วิดีโอเดียวไป TikTok, Shorts,\nReels และ Facebook พร้อมกัน'),
      findsOneWidget,
    );
    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบด้วยอีเมล'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('หน้าแรก'), findsNothing);
  });

  testWidgets('renders PostDee shell with primary screens after sign-in',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(const PostDeeApp(locale: Locale('th')));
    await tester.pumpAndSettle();

    expect(find.text('หน้าแรก'), findsOneWidget);
    expect(find.text('หน้าหลัก'), findsOneWidget);
    expect(find.bySemanticsLabel('แจ้งเตือน'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('Google'), findsNothing);
    expect(find.text('เข้าสู่ระบบ Google'), findsNothing);
    expect(_referenceNavButton('หน้าหลัก'), findsOneWidget);
    expect(_referenceNavButton('สร้างโพสต์'), findsOneWidget);
    expect(_referenceNavButton('ปฏิทิน'), findsOneWidget);
    expect(_referenceNavButton('ลิงก์ร้าน'), findsOneWidget);
    expect(_referenceNavButton('บัญชี'), findsOneWidget);
    expect(find.text('เทมเพลต'), findsNothing);

    await _tapReferenceNavButton(tester, 'สร้างโพสต์');

    expect(find.text('สร้างโพสต์ใหม่'), findsOneWidget);
    expect(find.text('1 · เลือกวิดีโอ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('uploader-save-draft-button')),
      findsOneWidget,
    );

    await _tapReferenceNavButton(tester, 'ปฏิทิน');

    expect(find.text('ประวัติ'), findsNothing);
    expect(find.text('ปฏิทินโพสต์'), findsOneWidget);
    expect(find.text('รีวิวคลิปด้วย AI'), findsNothing);

    await _tapReferenceNavButton(tester, 'ลิงก์ร้าน');

    expect(find.byKey(const ValueKey('link-in-bio-add')), findsOneWidget);
    expect(find.text('ตัดต่อด้วย AI'), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-back')), findsOneWidget);
    expect(_referenceNavButton('ลิงก์ร้าน'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('link-in-bio-back')));
    await tester.pumpAndSettle();

    expect(_referenceNavButton('ลิงก์ร้าน'), findsOneWidget);

    await _tapReferenceNavButton(tester, 'บัญชี');

    expect(find.text('บัญชีและโปรไฟล์'), findsOneWidget);
    expect(find.text('PostDee Seller'), findsOneWidget);
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(find.text('โหมดทดสอบ'), findsNothing);
    expect(find.text('0/4 เชื่อมต่อ'), findsNothing);
    expect(find.text('โหลดข้อมูลช่องทางไม่สำเร็จ'), findsWidgets);
    expect(find.text('พร้อมลอง UI'), findsNothing);
    final templatesAction = find.text('เทมเพลตแคปชั่น');
    await tester.scrollUntilVisible(
      templatesAction,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(templatesAction);
    await tester.pumpAndSettle();

    expect(find.text('จัดการแคปชั่นที่ใช้บ่อย'), findsOneWidget);
    expect(find.text('ชื่อเทมเพลต'), findsOneWidget);
  });
}
