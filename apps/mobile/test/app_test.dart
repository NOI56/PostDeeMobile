import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/app.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';

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
    final bottomNav = find.byType(BottomNavigationBar);

    expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
    expect(find.bySemanticsLabel('User account'), findsOneWidget);
    expect(
      find.descendant(of: bottomNav, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bottomNav, matching: find.text('Upload')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bottomNav, matching: find.text('Calendar')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bottomNav, matching: find.text('Analytics')),
      findsOneWidget,
    );
    // Profile moved out of the bottom nav to the top-right account icon.
    expect(
      find.descendant(of: bottomNav, matching: find.text('Profile')),
      findsNothing,
    );
    expect(find.bySemanticsLabel('User account'), findsOneWidget);
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
    // Home now loads analytics and recent posts on init; let those settle (they
    // fail gracefully to empty in tests) before checking the resting UI.
    await tester.pumpAndSettle();

    expect(find.text('Hello, PostDee Seller'), findsOneWidget);
    expect(find.text("Today's posting overview"), findsOneWidget);
    expect(find.byKey(const ValueKey('home-plan-title')), findsOneWidget);
    expect(find.text('Pro package'), findsNothing);
    expect(find.text('23 days left'), findsNothing);
    expect(find.text('View package'), findsOneWidget);
    expect(find.text('Total views'), findsOneWidget);
    expect(find.text('+12% from last week'), findsNothing);
    expect(find.text('Refresh views'), findsOneWidget);
    expect(find.text('Latest post status'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(find.text('Posted today 2'), findsNothing);
    expect(find.text('Published'), findsNothing);
    expect(find.text('Processing'), findsNothing);
    expect(find.text('Queued'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
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

    expect(tester.getSize(find.byType(AppBar).first).height,
        lessThanOrEqualTo(52));
    expect(
      tester.getSize(find.byType(BottomNavigationBar)).height,
      lessThanOrEqualTo(66),
    );
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

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined).last);
    await tester.pumpAndSettle();

    final bottomNavTop = tester.getTopLeft(find.byType(BottomNavigationBar)).dy;
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

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined).last);
    await tester.pumpAndSettle();

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

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined).last);
    await tester.pumpAndSettle();

    final bottomNavTop = tester.getTopLeft(find.byType(BottomNavigationBar)).dy;
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

  testWidgets('uses the reference bottom nav colors', (tester) async {
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

    final bottomNav = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );

    expect(bottomNav.selectedItemColor, const Color(0xFFA855F7));
    expect(bottomNav.unselectedItemColor, const Color(0xFFA8ACB8));
    expect(bottomNav.backgroundColor, Colors.transparent);
  });

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

    expect(themeController.themeMode, ThemeMode.dark);
    expect(AppTheme.isLightMode, isFalse);

    await tester.tap(find.bySemanticsLabel('User account'));
    await tester.pumpAndSettle();

    final lightModeButton = find.byIcon(Icons.light_mode).last;
    await tester.ensureVisible(lightModeButton);
    await tester.tap(lightModeButton);
    await tester.pumpAndSettle();

    expect(themeController.themeMode, ThemeMode.light);
    expect(AppTheme.isLightMode, isTrue);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light);

    final darkModeButton = find.byIcon(Icons.dark_mode).last;
    await tester.ensureVisible(darkModeButton);
    await tester.tap(darkModeButton);
    await tester.pumpAndSettle();

    expect(themeController.themeMode, ThemeMode.dark);
    expect(AppTheme.isLightMode, isFalse);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
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
    final bottomNav = find.byType(BottomNavigationBar);

    expect(
      find.descendant(of: bottomNav, matching: find.text('Home')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('User account'));
    await tester.pumpAndSettle();

    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.text('ไทย'));
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

    expect(find.text('เข้าสู่ระบบ PostDee'), findsOneWidget);
    expect(find.text('เชื่อมอีเมลก่อนเข้าใช้งาน'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
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
    final bottomNav = find.byType(BottomNavigationBar);

    expect(find.bySemanticsLabel('PostDee logo'), findsOneWidget);
    expect(find.bySemanticsLabel('แจ้งเตือน'), findsOneWidget);
    expect(find.bySemanticsLabel('บัญชีผู้ใช้'), findsOneWidget);
    expect(find.text('Google'), findsNothing);
    expect(find.text('เข้าสู่ระบบ Google'), findsNothing);
    expect(
      find.descendant(of: bottomNav, matching: find.text('หน้าแรก')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bottomNav, matching: find.text('อัปโหลด')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bottomNav, matching: find.text('ปฏิทิน')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bottomNav, matching: find.text('วิเคราะห์')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bottomNav, matching: find.text('โปรไฟล์')),
      findsNothing,
    );
    expect(
      find.descendant(of: bottomNav, matching: find.text('เทมเพลต')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: bottomNav, matching: find.text('อัปโหลด')),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('PostDee logo'), findsNothing);
    expect(find.bySemanticsLabel('แจ้งเตือน'), findsNothing);
    expect(find.bySemanticsLabel('บัญชีผู้ใช้'), findsOneWidget);
    expect(find.text('อัปโหลด'), findsWidgets);
    expect(find.text('บันทึกฉบับร่าง'), findsOneWidget);
    expect(find.text('เลือกวิดีโอ'), findsOneWidget);

    await tester.tap(
      find.descendant(of: bottomNav, matching: find.text('ปฏิทิน')),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('PostDee logo'), findsNothing);
    expect(find.bySemanticsLabel('บัญชีผู้ใช้'), findsOneWidget);
    expect(find.text('ปฏิทิน'), findsWidgets);
    expect(find.text('ประวัติ'), findsNothing);
    expect(find.text('ปฏิทินโพสต์'), findsOneWidget);
    expect(find.text('รีวิวคลิปด้วย AI'), findsNothing);

    await tester.tap(
      find.descendant(of: bottomNav, matching: find.text('วิเคราะห์')),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('PostDee logo'), findsNothing);
    expect(find.bySemanticsLabel('บัญชีผู้ใช้'), findsOneWidget);
    expect(find.text('วิเคราะห์'), findsWidgets);

    // Profile opens from the top-right account icon on every shell tab.
    await tester.tap(find.bySemanticsLabel('บัญชีผู้ใช้'));
    await tester.pumpAndSettle();

    expect(find.text('บัญชีและโปรไฟล์'), findsOneWidget);
    expect(find.text('สถานะบัญชี'), findsOneWidget);
    expect(find.text('PostDee Seller'), findsOneWidget);
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(find.text('โหมดทดสอบ'), findsNothing);
    expect(find.text('0/4 เชื่อมต่อ'), findsOneWidget);
    expect(find.text('พร้อมลอง UI'), findsNothing);
    final templatesAction = find.widgetWithText(OutlinedButton, 'เปิด');
    await tester.scrollUntilVisible(
      templatesAction,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('เทมเพลต'), findsWidgets);
    await tester.tap(templatesAction);
    await tester.pumpAndSettle();

    expect(find.text('จัดการแคปชั่นที่ใช้บ่อย'), findsOneWidget);
    expect(find.text('ชื่อเทมเพลต'), findsOneWidget);
  });
}
