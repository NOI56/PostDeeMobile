import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('refreshes an expired plan when returning to the app',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [],
      subscription: const SubscriptionStatusResult(
        userId: 'seller',
        plan: 'PRO',
        status: 'ACTIVE',
        remainingPostsThisMonth: 250,
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: true,
      ),
    );
    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-plan-pro')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    apiClient.subscription = _basicSubscription();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(apiClient.subscriptionLoadCalls, 2);
    expect(find.byKey(const ValueKey('profile-plan-free')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-pro')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab refresh ignores an older Pro response and hidden resume',
      (tester) async {
    final initialLoad = Completer<SubscriptionStatusResult>();
    // Only the initial request waits; the newer request reads expired access.
    var loads = 0;
    final refreshedClient = _FakeSocialApiClient(
      connections: const [],
      subscriptionLoader: () {
        loads++;
        return loads == 1
            ? initialLoad.future
            : Future.value(_basicSubscription());
      },
    );
    await tester.pumpWidget(_hostProfile(apiClient: refreshedClient));
    await tester.pump();
    await tester
        .pumpWidget(_hostProfile(apiClient: refreshedClient, isActive: false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(loads, 1);

    await tester.pumpWidget(_hostProfile(apiClient: refreshedClient));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.byKey(const ValueKey('profile-plan-free')), findsOneWidget);
    initialLoad.complete(const SubscriptionStatusResult(
      userId: 'seller',
      plan: 'PRO',
      status: 'ACTIVE',
      remainingPostsThisMonth: 250,
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-plan-free')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-pro')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('social OAuth uses the native Android Custom Tab without url_launcher',
      () async {
    final connectUri = Uri.parse('https://www.tiktok.com/v2/auth/authorize');
    var nativeCustomTabOpened = false;
    var externalLauncherCalled = false;

    final launched = await launchSocialConnectUrl(
      connectUri,
      preferAndroidCustomTab: true,
      launchCustomTab: (uri) async {
        expect(uri, connectUri);
        nativeCustomTabOpened = true;
        return true;
      },
      launch: (
        _, {
        required mode,
        required browserConfiguration,
      }) async {
        externalLauncherCalled = true;
        return true;
      },
    );

    expect(launched, isTrue);
    expect(nativeCustomTabOpened, isTrue);
    expect(externalLauncherCalled, isFalse);
  });

  test('social OAuth falls back to an external browser, never a WebView',
      () async {
    LaunchMode? launchedMode;

    final launched = await launchSocialConnectUrl(
      Uri.parse('https://accounts.google.com/o/oauth2/auth'),
      preferAndroidCustomTab: true,
      launchCustomTab: (_) async => false,
      launch: (
        _, {
        required mode,
        required browserConfiguration,
      }) async {
        launchedMode = mode;
        return true;
      },
    );

    expect(launched, isTrue);
    expect(launchedMode, LaunchMode.externalApplication);
    expect(launchedMode, isNot(LaunchMode.inAppWebView));
  });

  test(
      'social OAuth uses the external browser on platforms without a reliable dismiss callback',
      () async {
    var nativeCustomTabCalled = false;
    LaunchMode? launchedMode;

    await launchSocialConnectUrl(
      Uri.parse('https://accounts.google.com/o/oauth2/auth'),
      preferAndroidCustomTab: false,
      launchCustomTab: (_) async {
        nativeCustomTabCalled = true;
        return true;
      },
      launch: (
        _, {
        required mode,
        required browserConfiguration,
      }) async {
        launchedMode = mode;
        return true;
      },
    );

    expect(nativeCustomTabCalled, isFalse);
    expect(launchedMode, LaunchMode.externalApplication);
  });

  test('social OAuth falls back externally when the native Custom Tab fails',
      () async {
    LaunchMode? launchedMode;

    await launchSocialConnectUrl(
      Uri.parse('https://www.tiktok.com/v2/auth/authorize'),
      preferAndroidCustomTab: true,
      launchCustomTab: (_) async => throw StateError('Custom Tab unavailable'),
      launch: (
        _, {
        required mode,
        required browserConfiguration,
      }) async {
        launchedMode = mode;
        return true;
      },
    );

    expect(launchedMode, LaunchMode.externalApplication);
  });

  test('social OAuth accepts only trusted hosts for the requested platform',
      () {
    expect(
      isTrustedSocialConnectUrl(
        'https://www.tiktok.com/v2/auth/authorize',
        SocialPlatform.tiktok,
      ),
      isTrue,
    );
    expect(
      isTrustedSocialConnectUrl(
        'https://accounts.google.com/o/oauth2/auth',
        SocialPlatform.youtubeShorts,
      ),
      isTrue,
    );
    expect(
      isTrustedSocialConnectUrl(
        'https://www.facebook.com/dialog/oauth',
        SocialPlatform.instagramReels,
      ),
      isTrue,
    );
    expect(
      isTrustedSocialConnectUrl(
        'https://www.tiktok.com.evil.example/auth',
        SocialPlatform.tiktok,
      ),
      isFalse,
    );
    expect(
      isTrustedSocialConnectUrl(
        r'https://evil.example\.tiktok.com/auth',
        SocialPlatform.tiktok,
      ),
      isFalse,
    );
    expect(
      isTrustedSocialConnectUrl(
        r'https://www.tiktok.com\oauth',
        SocialPlatform.tiktok,
      ),
      isFalse,
    );
    expect(
      isTrustedSocialConnectUrl(
        'https://user@www.tiktok.com/auth',
        SocialPlatform.tiktok,
      ),
      isFalse,
    );
    expect(
      isTrustedSocialConnectUrl(
        'https://@www.tiktok.com/auth',
        SocialPlatform.tiktok,
      ),
      isFalse,
    );
    expect(
      isTrustedSocialConnectUrl(
        '/relative/connect',
        SocialPlatform.tiktok,
      ),
      isFalse,
    );
  });

  testWidgets('groups account menus and shows only the current package', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileScreen(
            languageController: PostDeeLanguageController(),
            themeController: PostDeeThemeController(),
            onOpenTemplates: () {},
            onDeleteAccount: () {},
            apiClient: _FakeSocialApiClient(connections: const []),
          ),
        ),
      ),
    );

    Finder cachedText(String text) => find.text(text, skipOffstage: false);

    await tester.pumpAndSettle();
    expect(cachedText('บัญชีของฉัน'), findsOneWidget);
    expect(cachedText('ช่องทางและเครื่องมือ'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-plan-free'), skipOffstage: false),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(cachedText('แพ็กเกจของฉัน'), findsOneWidget);
    expect(cachedText('ฟรี'), findsOneWidget);
    expect(cachedText('แพ็กเกจปัจจุบัน'), findsOneWidget);
    expect(cachedText('ดูแพ็กเกจทั้งหมด'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-plan-starter'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('profile-plan-pro'), skipOffstage: false),
      findsNothing,
    );
    expect(cachedText('199 ฿/ด.'), findsNothing);
    expect(cachedText('299 ฿/ด.'), findsNothing);
    expect(cachedText('รายงานวิเคราะห์เชิงลึก'), findsNothing);
    expect(cachedText('โควต้าตัดต่อ AI'), findsNothing);
  });

  for (final locale in [const Locale('th'), const Locale('en')]) {
    testWidgets(
      'hides template and profile link shortcuts while keeping account menus in ${locale.languageCode}',
      (tester) async {
        await tester.pumpWidget(_hostProfile(locale: locale));
        await tester.pumpAndSettle();

        expect(find.text('ยืนยันเบอร์โทร'), findsOneWidget);
        final connections =
            find.byKey(const ValueKey('profile-connections-row'));
        await tester.scrollUntilVisible(
          connections,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text('เชื่อมต่อช่องทาง'), findsOneWidget);
        expect(find.text('ช่องทางและเครื่องมือ'), findsOneWidget);
        expect(find.text('เทมเพลตแคปชั่น', skipOffstage: false), findsNothing);
        expect(find.text('ลิงก์หน้าโปรไฟล์', skipOffstage: false), findsNothing);

        final plan = find.byKey(const ValueKey('profile-view-plans'));
        await tester.scrollUntilVisible(
          plan,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(plan, findsOneWidget);

        final theme = find.byKey(const ValueKey('profile-theme-row'));
        await tester.scrollUntilVisible(
          theme,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(theme, findsOneWidget);
        expect(find.byKey(const ValueKey('profile-language-row')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('opens language choices only when requested', (tester) async {
    final language = PostDeeLanguageController();
    await tester.pumpWidget(_hostProfile(languageController: language));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('profile-language-row'));
    await tester.scrollUntilVisible(
      row,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsNothing);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(language.locale, const Locale('en'));
    expect(find.byKey(const ValueKey('profile-setting-sheet')), findsNothing);
    expect(
      find.descendant(of: row, matching: find.text('English')),
      findsOneWidget,
    );
  });

  testWidgets('opens theme choices and saves the selected mode', (
    tester,
  ) async {
    final theme = PostDeeThemeController(
      preferenceStore: const SharedPreferencesThemePreferenceStore(),
    );
    await tester.pumpWidget(_hostProfile(themeController: theme));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('profile-theme-row'));
    await tester.scrollUntilVisible(
      row,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('มืด'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.dark);
    expect(
      find.descendant(of: row, matching: find.text('มืด')),
      findsOneWidget,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SharedPreferencesThemePreferenceStore.themeModeKey),
      'dark',
    );
    await theme.setLightMode(true);
  });

  testWidgets('keeps grouped menus usable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var signOutCalls = 0;
    await tester.pumpWidget(
      _hostProfile(
        textScaler: const TextScaler.linear(2),
        onSignOut: () => signOutCalls += 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final row = find.byKey(const ValueKey('profile-theme-row'));
    await tester.scrollUntilVisible(
      row,
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('สว่าง'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    final signOut = find.text('ออกจากระบบ');
    await tester.scrollUntilVisible(
      signOut,
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.ensureVisible(signOut);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    expect(signOutCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aligns menu arrows at the right edge even with a setting value',
      (tester) async {
    await tester.pumpWidget(_hostProfile());
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('profile-language-row'));
    await tester.scrollUntilVisible(row, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final arrow = find.descendant(
        of: row, matching: find.byIcon(Icons.chevron_right));
    expect(tester.getRect(row).right - tester.getRect(arrow).right,
        closeTo(15, 1));
  });

  testWidgets('does not present zero connections or Basic as loaded data',
      (tester) async {
    final connections = Completer<List<SocialConnectionResult>>();
    final subscription = Completer<SubscriptionStatusResult>();
    addTearDown(() {
      if (!connections.isCompleted) connections.complete(const []);
      if (!subscription.isCompleted) {
        subscription.complete(_basicSubscription());
      }
    });

    await tester.pumpWidget(
      _hostProfile(
        apiClient: _FakeSocialApiClient(
          connections: const [],
          connectionsLoader: () => connections.future,
          subscriptionLoader: () => subscription.future,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('กำลังโหลดช่องทาง...'), findsWidgets);
    expect(
        find.textContaining('0/${connectablePlatforms.length}'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('profile-subscription-loading'),
        skipOffstage: false,
      ),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );

    expect(
      find.text('กำลังโหลดข้อมูลแพ็กเกจ...', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('แพ็กเกจปัจจุบัน'), findsNothing);
  });

  testWidgets('shows profile data failures and retries them', (tester) async {
    var connectionCalls = 0;
    var subscriptionCalls = 0;
    final apiClient = _FakeSocialApiClient(
      connections: const [],
      connectionsLoader: () async {
        connectionCalls += 1;
        if (connectionCalls == 1) throw Exception('connections unavailable');
        return const [
          SocialConnectionResult(platform: 'TIKTOK', connected: true),
        ];
      },
      subscriptionLoader: () async {
        subscriptionCalls += 1;
        if (subscriptionCalls == 1) throw Exception('subscription unavailable');
        return _basicSubscription();
      },
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    expect(find.text('โหลดข้อมูลช่องทางไม่สำเร็จ'), findsWidgets);
    expect(
        find.textContaining('0/${connectablePlatforms.length}'), findsNothing);

    final connectionRetry =
        find.byKey(const ValueKey('profile-retry-connections')).first;
    await tester.ensureVisible(connectionRetry);
    await tester.pumpAndSettle();
    await tester.tap(connectionRetry);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-connections-row')),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1/${connectablePlatforms.length} เชื่อมต่อ'),
        findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('profile-retry-subscription'),
        skipOffstage: false,
      ),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    expect(
      find.text('โหลดข้อมูลแพ็กเกจไม่สำเร็จ', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('แพ็กเกจปัจจุบัน'), findsNothing);

    tester
        .widget<TextButton>(
          find.byKey(
            const ValueKey('profile-retry-subscription'),
            skipOffstage: false,
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(
      find.text('แพ็กเกจปัจจุบัน', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
    'keeps loading error and retry states usable at 393dp with 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialConnections = Completer<List<SocialConnectionResult>>();
      final initialSubscription = Completer<SubscriptionStatusResult>();
      var connectionCalls = 0;
      var subscriptionCalls = 0;
      addTearDown(() {
        if (!initialConnections.isCompleted) {
          initialConnections.complete(const []);
        }
        if (!initialSubscription.isCompleted) {
          initialSubscription.complete(_basicSubscription());
        }
      });

      final apiClient = _FakeSocialApiClient(
        connections: const [],
        connectionsLoader: () {
          connectionCalls += 1;
          return connectionCalls == 1
              ? initialConnections.future
              : Future.value(const [
                  SocialConnectionResult(platform: 'TIKTOK', connected: true),
                ]);
        },
        subscriptionLoader: () {
          subscriptionCalls += 1;
          return subscriptionCalls == 1
              ? initialSubscription.future
              : Future.value(_basicSubscription());
        },
      );

      await tester.pumpWidget(
        _hostProfile(
          apiClient: apiClient,
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pump();

      expect(find.text('กำลังโหลดช่องทาง...'), findsWidgets);
      expect(tester.takeException(), isNull);

      initialConnections.completeError(Exception('connections unavailable'));
      initialSubscription.completeError(Exception('subscription unavailable'));
      await tester.pumpAndSettle();

      expect(find.text('โหลดข้อมูลช่องทางไม่สำเร็จ'), findsWidgets);
      expect(tester.takeException(), isNull);

      final connectionRetry =
          find.byKey(const ValueKey('profile-retry-connections')).first;
      await tester.ensureVisible(connectionRetry);
      await tester.pumpAndSettle();
      await tester.tap(connectionRetry);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-connections-row')),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('1/${connectablePlatforms.length} เชื่อมต่อ'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final subscriptionRetry = find.byKey(
        const ValueKey('profile-retry-subscription'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        subscriptionRetry,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await tester.pump();
      tester.widget<TextButton>(subscriptionRetry).onPressed!();
      await tester.pumpAndSettle();

      expect(subscriptionCalls, 2);
      expect(find.text('แพ็กเกจปัจจุบัน', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('security copy matches email and Google Firebase sign-in',
      (tester) async {
    await tester.pumpWidget(_hostProfile());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('ความปลอดภัย'),
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.ensureVisible(find.text('ความปลอดภัย'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ความปลอดภัย'));
    await tester.pumpAndSettle();

    expect(find.textContaining('อีเมลหรือ Google'), findsOneWidget);
    expect(find.textContaining('Firebase Authentication'), findsOneWidget);
    expect(find.textContaining('Google หรือ Apple เท่านั้น'), findsNothing);
    expect(find.textContaining('ผู้ช่วย/ทีมงาน'), findsNothing);
  });

  testWidgets('does not load or market retired AI editing for Pro',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [],
      subscription: const SubscriptionStatusResult(
        userId: 'pro-user',
        plan: 'PRO',
        status: 'ACTIVE',
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: true,
      ),
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ความปลอดภัย'),
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    expect(find.text('โควต้าตัดต่อ AI'), findsNothing);
    expect(find.text('/ 200 นาที'), findsNothing);
    expect(find.text('AI ตัดต่อ 200 นาที/เดือน', skipOffstage: false),
        findsNothing);
    expect(apiClient.aiEditQuotaCalls, 0);
  });

  testWidgets('refreshes the profile plan after returning from the paywall',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [],
      subscription: const SubscriptionStatusResult(
        userId: 'plan-refresh-user',
        plan: 'BASIC',
        status: 'INACTIVE',
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false,
      ),
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-view-plans'), skipOffstage: false),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-view-plans')));
    await tester.pumpAndSettle();
    expect(find.text('เลือกแพ็กเกจ'), findsOneWidget);

    apiClient.subscription = const SubscriptionStatusResult(
      userId: 'plan-refresh-user',
      plan: 'PRO',
      status: 'ACTIVE',
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true,
    );
    await tester.tap(find.byTooltip('กลับ'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-plan-pro'), skipOffstage: false),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    expect(apiClient.subscriptionLoadCalls, 3);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-plan-pro')),
        matching: find.text('แพ็กเกจปัจจุบัน'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ignores a stale Basic plan after returning from the paywall',
      (tester) async {
    final initialLoad = Completer<SubscriptionStatusResult>();
    var subscriptionLoadCalls = 0;
    const basic = SubscriptionStatusResult(
      userId: 'profile-stale-user',
      plan: 'BASIC',
      status: 'INACTIVE',
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );
    const pro = SubscriptionStatusResult(
      userId: 'profile-stale-user',
      plan: 'PRO',
      status: 'ACTIVE',
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true,
    );
    final apiClient = _FakeSocialApiClient(
      connections: const [],
      subscriptionLoader: () {
        subscriptionLoadCalls += 1;
        return switch (subscriptionLoadCalls) {
          1 => initialLoad.future,
          2 => Future.value(basic),
          _ => Future.value(pro),
        };
      },
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-view-plans'), skipOffstage: false),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-view-plans')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('กลับ'));
    await tester.pumpAndSettle();

    initialLoad.complete(basic);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-plan-pro'), skipOffstage: false),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    expect(subscriptionLoadCalls, 3);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-plan-pro')),
        matching: find.text('แพ็กเกจปัจจุบัน'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows connected social platforms from the API', (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    // Connections now live on their own screen behind the profile menu row.
    await _openConnectionsScreen(tester);

    expect(
      find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK')),
      findsOneWidget,
    );
    expect(find.text('@seller_one'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testWidgets('shows the live connected count once in the connection menu', (
    tester,
  ) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile-connections-row')),
      findsOneWidget,
    );
    expect(find.text('1/4 เชื่อมต่อ'), findsOneWidget);
  });

  testWidgets('updates the summary pill after refreshing connections',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      refreshedConnections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    expect(find.text('0/4 เชื่อมต่อ'), findsOneWidget);

    await _openConnectionsScreen(tester);

    await tester.tap(find.byKey(const ValueKey('profile-platforms-refresh')));
    await tester.pumpAndSettle();

    // Back on the profile tab, the summary pill reflects the new count.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('1/4 เชื่อมต่อ'), findsOneWidget);
  });

  testWidgets('a stale profile load cannot overwrite a newer connected count',
      (tester) async {
    final initialLoad = Completer<List<SocialConnectionResult>>();
    var connectionLoadCalls = 0;
    final apiClient = _FakeSocialApiClient(
      connections: const [],
      connectionsLoader: () {
        connectionLoadCalls += 1;
        if (connectionLoadCalls == 1) return initialLoad.future;
        return Future.value(const [
          SocialConnectionResult(
            platform: 'TIKTOK',
            connected: true,
            displayName: '@seller_one',
          ),
          SocialConnectionResult(
            platform: 'YOUTUBE_SHORTS',
            connected: false,
          ),
          SocialConnectionResult(
            platform: 'INSTAGRAM_REELS',
            connected: false,
          ),
          SocialConnectionResult(
            platform: 'FACEBOOK_REELS',
            connected: false,
          ),
        ]);
      },
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pump();
    await _openConnectionsScreen(tester);
    expect(connectionLoadCalls, 2);

    initialLoad.complete(const [
      SocialConnectionResult(platform: 'TIKTOK', connected: false),
      SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
      SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
      SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('1/4 เชื่อมต่อ'), findsOneWidget);
  });

  testWidgets(
    'returning after failed connection refresh hides the old profile count',
    (tester) async {
      var calls = 0;
      var unavailable = false;
      final apiClient = _FakeSocialApiClient(
        connections: const [],
        connectionsLoader: () async {
          calls += 1;
          if (unavailable) {
            throw const ApiException('Request failed', statusCode: 503);
          }
          return const [
            SocialConnectionResult(platform: 'TIKTOK', connected: true),
          ];
        },
        refreshLoader: () async {
          unavailable = true;
          throw const ApiException('Request failed', statusCode: 503);
        },
      );
      await tester.pumpWidget(_hostProfile(apiClient: apiClient));
      await tester.pumpAndSettle();
      expect(find.text('1/4 เชื่อมต่อ'), findsOneWidget);
      await _openConnectionsScreen(tester);
      await tester.tap(find.byKey(const ValueKey('profile-platforms-refresh')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(calls, 3);
      expect(find.text('1/4 เชื่อมต่อ'), findsNothing);
      expect(find.text('0/4 เชื่อมต่อ'), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-connections-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-retry-connections')),
        findsOneWidget,
      );

    unavailable = false;
    await tester.tap(find.byKey(const ValueKey('profile-retry-connections')));
    await tester.pumpAndSettle();
    expect(find.text('1/4 เชื่อมต่อ'), findsOneWidget);
  });

  testWidgets('connecting a platform opens its PostPeer connect URL',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      connectLink: SocialConnectLinkResult(
        connectUrl: 'https://www.tiktok.com/v2/auth/authorize',
        expiresAt: DateTime.utc(2026, 6, 26, 9, 10),
      ),
    );
    Uri? launched;

    await tester.pumpWidget(
      _hostProfile(
        apiClient: apiClient,
        launchConnectUrl: (uri) async {
          launched = uri;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await _openConnectionsScreen(tester);

    final tiktokConnect =
        find.byKey(const ValueKey('profile-platform-connect-TIKTOK'));
    expect(tester.widget<FilledButton>(tiktokConnect).onPressed, isNotNull);

    await tester.tap(tiktokConnect);
    await tester.pumpAndSettle();

    expect(apiClient.connectCalls, ['TIKTOK']);
    expect(
      launched,
      Uri.parse('https://www.tiktok.com/v2/auth/authorize'),
    );
    expect(
      find.textContaining('PostDee ไม่ได้รับรหัสผ่านของคุณ'),
      findsOneWidget,
    );
  });

  testWidgets('does not open OAuth after the connections screen is closed',
      (tester) async {
    final connectLink = Completer<SocialConnectLinkResult>();
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      connectLinkLoader: (_) => connectLink.future,
    );
    var launchCalled = false;

    await tester.pumpWidget(
      _hostProfile(
        apiClient: apiClient,
        launchConnectUrl: (_) async {
          launchCalled = true;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await _openConnectionsScreen(tester);

    await tester.tap(
      find.byKey(const ValueKey('profile-platform-connect-TIKTOK')),
    );
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    connectLink.complete(
      const SocialConnectLinkResult(
        connectUrl: 'https://www.tiktok.com/v2/auth/authorize',
      ),
    );
    await tester.pumpAndSettle();

    expect(apiClient.connectCalls, ['TIKTOK']);
    expect(launchCalled, isFalse);
  });

  testWidgets('allows only one social account operation at a time',
      (tester) async {
    final connectLink = Completer<SocialConnectLinkResult>();
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      connectLinkLoader: (_) => connectLink.future,
    );

    await tester.pumpWidget(
      _hostProfile(
        apiClient: apiClient,
        launchConnectUrl: (_) async => true,
      ),
    );
    await tester.pumpAndSettle();
    await _openConnectionsScreen(tester);

    await tester.tap(
      find.byKey(const ValueKey('profile-platform-connect-TIKTOK')),
    );
    await tester.pump();

    final youtubeConnect =
        find.byKey(const ValueKey('profile-platform-connect-YOUTUBE_SHORTS'));
    expect(tester.widget<FilledButton>(youtubeConnect).onPressed, isNull);
    expect(apiClient.connectCalls, ['TIKTOK']);

    connectLink.complete(
      const SocialConnectLinkResult(
        connectUrl: 'https://www.tiktok.com/v2/auth/authorize',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(youtubeConnect).onPressed, isNotNull);
  });

  testWidgets('disables account actions while connection status is loading',
      (tester) async {
    final pendingConnections = Completer<List<SocialConnectionResult>>();
    var connectionLoadCalls = 0;
    final apiClient = _FakeSocialApiClient(
      connections: const [],
      connectionsLoader: () {
        connectionLoadCalls += 1;
        if (connectionLoadCalls == 1) {
          return Future.value(const [
            SocialConnectionResult(platform: 'TIKTOK', connected: false),
            SocialConnectionResult(
                platform: 'YOUTUBE_SHORTS', connected: false),
            SocialConnectionResult(
                platform: 'INSTAGRAM_REELS', connected: false),
            SocialConnectionResult(
                platform: 'FACEBOOK_REELS', connected: false),
          ]);
        }
        return pendingConnections.future;
      },
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เชื่อมต่อช่องทาง'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final tiktokUnknown =
        find.byKey(const ValueKey('profile-platform-status-unknown-TIKTOK'));
    expect(tester.widget<OutlinedButton>(tiktokUnknown).onPressed, isNull);
    expect(find.byKey(const ValueKey('profile-platform-connect-TIKTOK')),
        findsNothing);

    pendingConnections.complete(const [
      SocialConnectionResult(platform: 'TIKTOK', connected: false),
      SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
      SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
      SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
    ]);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('profile-platform-connect-TIKTOK')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('rejects an insecure social connect URL before launching it',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      connectLink: SocialConnectLinkResult(
        connectUrl: 'http://www.tiktok.com/v2/auth/authorize',
      ),
    );
    var launchCalled = false;

    await tester.pumpWidget(
      _hostProfile(
        apiClient: apiClient,
        launchConnectUrl: (_) async {
          launchCalled = true;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await _openConnectionsScreen(tester);

    await tester.tap(
      find.byKey(const ValueKey('profile-platform-connect-TIKTOK')),
    );
    await tester.pumpAndSettle();

    expect(launchCalled, isFalse);
    expect(
      find.text('ลิงก์เชื่อมบัญชีไม่ปลอดภัย กรุณาลองใหม่อีกครั้ง'),
      findsOneWidget,
    );
  });

  testWidgets('does not refresh after the secure browser fails to open',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      connectLink: SocialConnectLinkResult(
        connectUrl: 'https://www.tiktok.com/v2/auth/authorize',
      ),
    );

    await tester.pumpWidget(
      _hostProfile(
        apiClient: apiClient,
        launchConnectUrl: (_) async => false,
      ),
    );
    await tester.pumpAndSettle();
    await _openConnectionsScreen(tester);

    await tester.tap(
      find.byKey(const ValueKey('profile-platform-connect-TIKTOK')),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(apiClient.refreshCalls, 0);
    expect(find.text('เชื่อมบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง'), findsOneWidget);
  });

  testWidgets('refreshes connections after returning from PostPeer OAuth',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      refreshedConnections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      connectLink: SocialConnectLinkResult(
        connectUrl: 'https://www.tiktok.com/v2/auth/authorize',
        expiresAt: DateTime.utc(2026, 6, 26, 9, 10),
      ),
    );

    await tester.pumpWidget(
      _hostProfile(
        apiClient: apiClient,
        launchConnectUrl: (_) async => true,
      ),
    );
    await tester.pumpAndSettle();
    await _openConnectionsScreen(tester);

    await tester.tap(
      find.byKey(const ValueKey('profile-platform-connect-TIKTOK')),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(apiClient.refreshCalls, 1);
    expect(
      find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK')),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(apiClient.refreshCalls, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('1/4 เชื่อมต่อ'), findsOneWidget);
  });

  testWidgets('refreshing pulls connected status from PostPeer',
      (tester) async {
    final apiClient = _FakeSocialApiClient(
      connections: const [
        SocialConnectionResult(platform: 'TIKTOK', connected: false),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
      refreshedConnections: const [
        SocialConnectionResult(
          platform: 'TIKTOK',
          connected: true,
          displayName: '@seller_one',
        ),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: false),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'FACEBOOK_REELS', connected: false),
      ],
    );

    await tester.pumpWidget(_hostProfile(apiClient: apiClient));
    await tester.pumpAndSettle();

    await _openConnectionsScreen(tester);

    await tester.tap(find.byKey(const ValueKey('profile-platforms-refresh')));
    await tester.pumpAndSettle();

    expect(apiClient.refreshCalls, 1);
    expect(
      find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK')),
      findsOneWidget,
    );
    expect(find.text('@seller_one'), findsOneWidget);
  });

  testWidgets('shows the signed-in account instead of test profile copy',
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

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileScreen(
            languageController: PostDeeLanguageController(),
            themeController: PostDeeThemeController(),
            onOpenTemplates: () {},
            onDeleteAccount: () {},
          ),
        ),
      ),
    );

    expect(find.text('PostDee Seller'), findsOneWidget);
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(find.text('บัญชีทดลองสำหรับทดสอบ UI และ flow หลักของ PostDee'),
        findsNothing);
    expect(find.text('โหมดทดสอบ'), findsNothing);
    expect(find.text('พร้อมลอง UI'), findsNothing);
  });

  testWidgets('does not offer retired AI editing top-up', (tester) async {
    await tester.pumpWidget(
      _hostProfile(
        apiClient: _FakeSocialApiClient(
          connections: const [],
          subscription: const SubscriptionStatusResult(
            userId: 'pro-user',
            plan: 'PRO',
            status: 'ACTIVE',
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
        ),
      ),
    );

    final topUpButton =
        find.widgetWithText(OutlinedButton, 'เติม 120 นาที · 49 บาท');

    await tester.scrollUntilVisible(
      find.text('ความปลอดภัย'),
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    expect(topUpButton, findsNothing);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('320'), findsNothing);
  });

  testWidgets(
    'warns that deleting PostDee does not cancel a store subscription',
    (tester) async {
      var manageSubscriptionCalls = 0;
      await tester.pumpWidget(
        _hostProfile(
          onManageSubscription: () async {
            manageSubscriptionCalls += 1;
          },
        ),
      );

      await tester.pumpAndSettle();

      final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
      await tester.scrollUntilVisible(
        deleteButton,
        500,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('ก่อนลบบัญชี'), findsOneWidget);
      expect(
        find.textContaining('ไม่ได้ยกเลิกแพ็กเกจ Starter/Pro'),
        findsOneWidget,
      );
      expect(
        find.textContaining('ฉบับร่างและไฟล์ในเครื่องนี้'),
        findsOneWidget,
      );
      expect(find.text('ลบบัญชีถาวร'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('delete-account-confirm-sheet')),
          matching: find.text('จัดการสมาชิก'),
        ),
      );
      await tester.pump();
      expect(manageSubscriptionCalls, 1);
    },
  );

  testWidgets('keeps delete actions usable with large accessibility text',
      (tester) async {
    await tester.pumpWidget(
      _hostProfile(textScaler: const TextScaler.linear(2)),
    );
    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    final sheetScrollable = find.descendant(
      of: find.byKey(const ValueKey('delete-account-confirm-sheet')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('ลบบัญชีถาวร'),
      200,
      scrollable: sheetScrollable,
    );

    expect(find.text('ลบบัญชีถาวร'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Taps the "เชื่อมต่อช่องทาง" menu row to push the connections screen.
Future<void> _openConnectionsScreen(WidgetTester tester) async {
  await tester.tap(find.text('เชื่อมต่อช่องทาง'));
  await tester.pumpAndSettle();
}

Widget _hostProfile({
  Locale locale = const Locale('th'),
  bool isActive = true,
  PostDeeApiClient? apiClient,
  Future<bool> Function(Uri uri)? launchConnectUrl,
  Future<void> Function()? onManageSubscription,
  PostDeeLanguageController? languageController,
  PostDeeThemeController? themeController,
  VoidCallback? onSignOut,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    locale: locale,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: PostDeeLocalizations.supportedLocales,
    home: Scaffold(
      body: ProfileScreen(
        isActive: isActive,
        languageController: languageController ??
            PostDeeLanguageController(initialLocale: locale),
        themeController: themeController ?? PostDeeThemeController(),
        onOpenTemplates: () {},
        onDeleteAccount: () {},
        onSignOut: onSignOut,
        apiClient: apiClient ?? _FakeSocialApiClient(connections: const []),
        launchConnectUrl: launchConnectUrl,
        onManageSubscription: onManageSubscription,
      ),
    ),
  );
}

SubscriptionStatusResult _basicSubscription() => const SubscriptionStatusResult(
      userId: 'basic-user',
      plan: 'BASIC',
      status: 'INACTIVE',
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );

class _FakeSocialApiClient extends PostDeeApiClient {
  _FakeSocialApiClient({
    required this.connections,
    this.connectLink,
    this.connectLinkLoader,
    this.refreshedConnections,
    this.connectionsLoader,
    this.refreshLoader,
    this.subscription,
    this.subscriptionLoader,
  });

  List<SocialConnectionResult> connections;
  final SocialConnectLinkResult? connectLink;
  final Future<SocialConnectLinkResult> Function(String platform)?
      connectLinkLoader;
  final List<SocialConnectionResult>? refreshedConnections;
  final Future<List<SocialConnectionResult>> Function()? connectionsLoader;
  final Future<List<SocialConnectionResult>> Function()? refreshLoader;
  SubscriptionStatusResult? subscription;
  final Future<SubscriptionStatusResult> Function()? subscriptionLoader;
  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];
  int refreshCalls = 0;
  int subscriptionLoadCalls = 0;
  int aiEditQuotaCalls = 0;

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    subscriptionLoadCalls += 1;
    final loader = subscriptionLoader;
    if (loader != null) {
      return loader();
    }
    return subscription ??
        const SubscriptionStatusResult(
          userId: 'basic-user',
          plan: 'BASIC',
          status: 'INACTIVE',
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false,
        );
  }

  @override
  Future<AiEditQuota> fetchAiEditQuota() async {
    aiEditQuotaCalls += 1;
    return const AiEditQuota(
      limitMinutes: 200,
      usedMinutes: 25,
      remainingMinutes: 175,
    );
  }

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async {
    final loader = connectionsLoader;
    return loader == null ? connections : loader();
  }

  @override
  Future<List<SocialConnectionResult>> refreshSocialConnections() async {
    refreshCalls++;
    if (refreshLoader != null) return refreshLoader!();
    connections = refreshedConnections ?? connections;
    return connections;
  }

  @override
  Future<SocialConnectLinkResult> createSocialConnectionLink(
      String platform) async {
    connectCalls.add(platform);
    final loader = connectLinkLoader;
    if (loader != null) {
      return loader(platform);
    }
    final link = connectLink;
    if (link == null) {
      throw const ApiException(
        'Social account linking is not available. Please try again later.',
        statusCode: 503,
      );
    }
    return link;
  }

  @override
  Future<void> disconnectSocialConnection(String platform) async {
    disconnectCalls.add(platform);
    connections = [
      for (final connection in connections)
        if (connection.platform == platform)
          SocialConnectionResult(platform: platform, connected: false)
        else
          connection,
    ];
  }
}
