import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/profile/profile_draft_store.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';

const _owner = 'english-profile-owner';
const _basic = SubscriptionStatusResult(
    userId: _owner,
    plan: 'BASIC',
    status: 'INACTIVE',
    monthlyPostLimit: 3,
    remainingPostsThisMonth: 3,
    canSchedule: false,
    canUseAiCaptions: false,
    canUseAnalytics: false);

class _Api extends PostDeeApiClient {
  List<SocialConnectionResult> connections = const [];
  SubscriptionStatusResult subscription = _basic;
  Object? channelError;
  Object? planError;
  Future<List<SocialConnectionResult>>? channelGate;
  Future<SubscriptionStatusResult>? planGate;
  int channelReads = 0;
  int planReads = 0;
  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async {
    channelReads++;
    if (channelError != null) {
      throw channelError!;
    }
    return channelGate == null ? connections : await channelGate!;
  }

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    planReads++;
    if (planError != null) {
      throw planError!;
    }
    return planGate == null ? subscription : await planGate!;
  }
}

class _Drafts implements ProfileDraftStore {
  ProfileDraft? value;
  Future<ProfileDraft?>? gate;
  int reads = 0;
  @override
  Future<ProfileDraft?> load() async {
    reads++;
    return gate == null ? value : await gate!;
  }

  @override
  Future<void> save(ProfileDraft draft) async =>
      throw StateError('Unexpected draft write');
  @override
  Future<void> clear() async => throw StateError('Unexpected draft clear');
}

class _Themes implements PostDeeThemePreferenceStore {
  final saved = <ThemeMode>[];
  @override
  Future<ThemeMode?> loadThemeMode() async => null;
  @override
  Future<void> saveThemeMode(ThemeMode mode) async => saved.add(mode);
}

class _Fixture {
  _Fixture({Locale locale = const Locale('en'), bool dark = false})
      : language = PostDeeLanguageController(initialLocale: locale) {
    theme = PostDeeThemeController(
        initialMode: dark ? ThemeMode.dark : ThemeMode.light,
        preferenceStore: themes);
  }
  final _Api api = _Api();
  final _Drafts drafts = _Drafts();
  final PostDeeLanguageController language;
  final _Themes themes = _Themes();
  late final PostDeeThemeController theme;
  void dispose() {
    language.dispose();
    theme.dispose();
  }

  ProfileScreen screen({bool active = true}) => ProfileScreen(
        key: const ValueKey('english-profile'),
        languageController: language,
        themeController: theme,
        onOpenTemplates: () {},
        onDeleteAccount: () {},
        onSignOut: () {},
        apiClient: api,
        profileDraftStore: drafts,
        isActive: active,
        verifyPhone: (_) async => null,
      );
}

Widget _app(_Fixture fixture,
        {double scale = 1, bool active = true, bool withBack = false}) =>
    AnimatedBuilder(
        animation: Listenable.merge([fixture.language, fixture.theme]),
        builder: (_, __) => MaterialApp(
              locale: fixture.language.locale,
              supportedLocales: PostDeeLocalizations.supportedLocales,
              localizationsDelegates: const [
                PostDeeLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: fixture.theme.themeMode,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: withBack
                  ? const Scaffold()
                  : Scaffold(body: fixture.screen(active: active)),
              initialRoute: withBack ? '/profile' : null,
              routes: withBack
                  ? {
                      '/profile': (_) => Scaffold(
                          appBar: AppBar(),
                          body: fixture.screen(active: active))
                    }
                  : const {},
            ));

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    // Locale changes can move a lazy section above the current build cache.
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(target, 240,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectEnglish(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final value = text.data ?? text.textSpan?.toPlainText() ?? '';
    if (value == 'ไทย') {
      continue;
    }
    expect(value, isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
  expect(tester.takeException(), isNull);
}

void _readable(WidgetTester tester, Finder label) {
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5));
}

SubscriptionStatusResult _plan(
        {String plan = 'PRO',
        String status = 'ACTIVE',
        int? remaining = 248,
        int? limit = 250,
        int posts = 0,
        int ai = 0,
        int? total,
        DateTime? reset,
        bool phone = false}) =>
    SubscriptionStatusResult(
        userId: _owner,
        plan: plan,
        status: status,
        monthlyPostLimit: limit,
        remainingPostsThisMonth: remaining,
        addonPostUnits: posts,
        addonAiCaptions: ai,
        availablePostUnits: total,
        monthlyQuotaResetsAt: reset,
        phoneVerified: phone,
        canSchedule: plan == 'PRO' || plan == 'STARTER',
        canUseAiCaptions: plan == 'PRO' || plan == 'STARTER',
        canUseAnalytics: plan == 'PRO');

Finder _sheetLabel(String label) => find.descendant(
    of: _key('profile-setting-sheet'), matching: find.text(label));

void main() {
  setUp(() => PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: _owner,
      idToken: 'fixture-token',
      displayName: 'Seller Profile',
      email: 'seller@example.com',
      emailVerified: true)));
  tearDown(PostDeeAuthSessionStore.instance.clear);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets('English Account translates its heading and account card',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    expect(find.text('Account and profile'), findsOneWidget);
    expect(find.text('Manage your account and settings'), findsOneWidget);
    expect(find.text('My account'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Email verified'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets('English Profile exposes channel and plan sections',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _reveal(tester, _key('profile-connections-row'));
    expect(find.text('Channels and tools'), findsOneWidget);
    expect(find.text('Connect channels'), findsOneWidget);
    expect(find.text('0/4 connected'), findsOneWidget);
    await _reveal(tester, _key('profile-view-plans'));
    expect(find.text('My plan'), findsOneWidget);
    expect(find.text('View all plans'), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets(
      'stored Profile load errors switch language without extra requests',
      (tester) async {
    final f = _Fixture(locale: const Locale('th'));
    addTearDown(f.dispose);
    f.api.channelError = StateError('private channel failure');
    f.api.planError = StateError('private plan failure');
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _reveal(tester, _key('profile-subscription-error'));
    expect(find.text('โหลดข้อมูลแพ็กเกจไม่สำเร็จ'), findsOneWidget);
    f.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load plan'), findsOneWidget);
    await _reveal(tester, _key('profile-connections-error'));
    expect(find.text('Could not load channels'), findsWidgets);
    expect(f.api.channelReads, 1);
    expect(f.api.planReads, 1);
    expect(f.drafts.reads, 1);
    _expectEnglish(tester);
  });

  for (final count in [1, 2, 3, 4]) {
    testWidgets('English Profile counts $count current supported connections',
        (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.api.connections = [
        for (final platform in const [
          'TIKTOK',
          'YOUTUBE_SHORTS',
          'INSTAGRAM_REELS',
          'FACEBOOK_REELS'
        ].take(count))
          SocialConnectionResult(platform: platform, connected: true),
        const SocialConnectionResult(platform: 'SHOPEE_VIDEO', connected: true),
        const SocialConnectionResult(platform: 'LAZADA_VIDEO', connected: true),
      ];
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      await _reveal(tester, _key('profile-connections-row'));
      expect(find.text('$count/4 connected'), findsOneWidget);
      expect(f.api.channelReads, 1);
      expect(f.api.planReads, 1);
      _expectEnglish(tester);
    });
  }

  testWidgets('English loading does not invent a plan or connection count',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    final channels = Completer<List<SocialConnectionResult>>();
    final plan = Completer<SubscriptionStatusResult>();
    f.api.channelGate = channels.future;
    f.api.planGate = plan.future;
    await tester.pumpWidget(_app(f));
    await tester.pump();
    await tester.scrollUntilVisible(_key('profile-connections-row'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text('Loading channels...'), findsOneWidget);
    expect(find.text('0/4 connected'), findsNothing);
    await tester.scrollUntilVisible(_key('profile-subscription-loading'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text('Loading plan...'), findsOneWidget);
    expect(_key('profile-plan-free'), findsNothing);
    channels.complete(const []);
    plan.complete(_basic);
    await tester.pumpAndSettle();
    expect(_key('profile-plan-free'), findsOneWidget);
    _expectEnglish(tester);
  });

  for (final channels in [false, true]) {
    testWidgets(
        'English ${channels ? 'channel' : 'plan'} retry reloads only the failed data',
        (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      if (channels) {
        f.api.channelError = StateError('private channel diagnostic');
      } else {
        f.api.planError = StateError('private plan diagnostic');
      }
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      final retry = _key(channels
          ? 'profile-retry-connections'
          : 'profile-retry-subscription');
      await _reveal(tester, retry);
      expect(find.textContaining('private '), findsNothing);
      f.api.channelError = null;
      f.api.planError = null;
      await _tap(tester, retry);
      expect(f.api.channelReads, channels ? 2 : 1);
      expect(f.api.planReads, channels ? 1 : 2);
      expect(f.drafts.reads, 1);
      expect(
          _key(channels
              ? 'profile-connections-error'
              : 'profile-subscription-error'),
          findsNothing);
      _expectEnglish(tester);
    });
  }

  for (final tier in const {
    'BASIC': 'Free',
    'FREE': 'Free',
    'STARTER': 'Starter',
    'PRO': 'Pro',
    'FUTURE_PLAN': 'Unknown plan',
  }.entries) {
    testWidgets(
        'English Profile renders ${tier.key} without inventing benefits',
        (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.api.subscription = _plan(plan: tier.key);
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      final key = switch (tier.key) {
        'BASIC' || 'FREE' => 'free',
        'STARTER' => 'starter',
        'PRO' => 'pro',
        _ => 'unknown'
      };
      await _reveal(tester, _key('profile-plan-$key'));
      expect(find.text(tier.value), findsOneWidget);
      expect(find.text('Current plan'), findsOneWidget);
      _expectEnglish(tester);
    });
  }

  for (final status in const {
    'ACTIVE': 'Active',
    'INACTIVE': 'Inactive',
    'EXPIRED': 'Expired',
    'CANCELED': 'Canceled',
    'CANCELLED': 'Canceled',
    'FUTURE_STATUS': 'Check status in Manage subscription',
  }.entries) {
    testWidgets(
        'English Profile keeps ${status.key} subscription status distinct',
        (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.api.subscription = _plan(status: status.key);
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      await _reveal(tester, _key('profile-plan-pro'));
      expect(find.text(status.value), findsOneWidget);
      _expectEnglish(tester);
    });
  }

  testWidgets(
      'English paid quota separates monthly allowance, purchased credits and total',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    f.api.subscription = _plan(posts: 100, ai: 50, total: 348);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _reveal(tester, _key('profile-plan-pro'));
    for (final label in [
      '248 / 250 post units left this month',
      'Purchased credits remaining: 100 post units · 50 AI caption credits',
      'Purchased credits do not expire · Monthly quota is used first',
      'Total available: 348 post units'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    _expectEnglish(tester);
  });

  testWidgets(
      'English Free keeps purchased credits without claiming paid spending access',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    f.api.subscription = _plan(
        plan: 'BASIC',
        status: 'INACTIVE',
        remaining: 3,
        limit: 3,
        posts: 100,
        ai: 50,
        total: 3);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _reveal(tester, _key('profile-plan-free'));
    expect(find.text('3 / 3 post units left this month'), findsOneWidget);
    expect(
        find.text(
            'Purchased credits remaining: 100 post units · 50 AI caption credits'),
        findsOneWidget);
    expect(
        find.text(
            'Your credits are retained and become usable with Starter or Pro'),
        findsOneWidget);
    expect(find.textContaining('Total available:'), findsNothing);
    _expectEnglish(tester);
  });

  for (final missing in ['remaining', 'limit']) {
    testWidgets('English unknown monthly $missing does not appear as zero',
        (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.api.subscription = _plan(
          remaining: missing == 'remaining' ? null : 248,
          limit: missing == 'limit' ? null : 250);
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      await _reveal(tester, _key('profile-plan-pro'));
      expect(find.text('Pro'), findsOneWidget);
      expect(find.textContaining('post units left this month'), findsNothing);
      expect(find.textContaining('Purchased credits remaining:'), findsNothing);
      _expectEnglish(tester);
    });
  }

  testWidgets(
      'English quota reset remains a local Gregorian date separate from credit expiry',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    final reset = DateTime.utc(2026, 11, 1, 0, 5).toLocal();
    f.api.subscription = _plan(reset: reset.toUtc(), posts: 20, ai: 10);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _reveal(tester, _key('profile-plan-pro'));
    final date =
        '${reset.day}/${reset.month}/${reset.year} at ${reset.hour.toString().padLeft(2, '0')}:${reset.minute.toString().padLeft(2, '0')}';
    expect(find.text('Monthly quota resets on $date (local time)'),
        findsOneWidget);
    expect(
        find.text(
            'Purchased credits do not expire · Monthly quota is used first'),
        findsOneWidget);
    expect(find.textContaining('2569'), findsNothing);
    _expectEnglish(tester);
    f.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('${reset.day}/${reset.month}/${reset.year} เวลา'),
        findsOneWidget);
    expect(f.api.planReads, 1);
    expect(f.api.channelReads, 1);
  });

  for (final belongsToOwner in [false, true]) {
    testWidgets(
        'English Profile ${belongsToOwner ? 'preserves' : 'rejects another owners'} Thai saved display name',
        (tester) async {
      const name = 'ชื่อร้านภาษาไทยเดิม';
      final f = _Fixture();
      addTearDown(f.dispose);
      f.drafts.value = ProfileDraft(
          displayName: name,
          storeName: 'ร้านเดิม',
          accountUserId: belongsToOwner ? _owner : 'other-owner',
          accountEmail: 'seller@example.com');
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      expect(find.text(name), belongsToOwner ? findsOneWidget : findsNothing);
      if (!belongsToOwner) {
        expect(find.text('Seller Profile'), findsOneWidget);
      }
      f.language.setLocale(const Locale('th'));
      await tester.pumpAndSettle();
      f.language.setLocale(const Locale('en'));
      await tester.pumpAndSettle();
      expect(find.text(name), belongsToOwner ? findsOneWidget : findsNothing);
      expect(find.text('Account and profile'), findsOneWidget);
      expect(f.api.channelReads, 1);
      expect(f.api.planReads, 1);
      expect(f.drafts.reads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final verified in [false, true]) {
    testWidgets(
        'English phone badge is ${verified ? 'Verified' : 'Not verified'} from loaded data',
        (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.api.subscription = _plan(phone: verified);
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      expect(find.text('Verify phone number'), findsOneWidget);
      expect(find.text(verified ? 'Verified' : 'Not verified'), findsOneWidget);
      expect(f.api.planReads, 1);
      _expectEnglish(tester);
    });
  }

  for (final email in ['unverified', 'missing']) {
    testWidgets(
        'English account displays $email email status without verifying',
        (tester) async {
      PostDeeAuthSessionStore.instance.signIn(AuthSession(
          userId: _owner,
          idToken: 'fixture-token',
          displayName: 'Seller Profile',
          email: email == 'missing' ? null : 'seller@example.com'));
      final f = _Fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      expect(
          find.text(email == 'missing'
              ? 'Email not connected'
              : 'Email not verified'),
          findsOneWidget);
      if (email == 'missing') {
        expect(find.text('Connect your email before using live features.'),
            findsOneWidget);
      }
      _expectEnglish(tester);
    });
  }

  testWidgets('English Display mode chooser closes without saving or reloading',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-theme-row'));
    expect(_sheetLabel('Display mode'), findsOneWidget);
    expect(_sheetLabel('Light'), findsOneWidget);
    expect(_sheetLabel('Dark'), findsOneWidget);
    await _tap(tester, find.byTooltip('Close'));
    expect(_key('profile-setting-sheet'), findsNothing);
    expect(f.themes.saved, isEmpty);
    expect(f.api.channelReads, 1);
    expect(f.api.planReads, 1);
    expect(f.drafts.reads, 1);
    _expectEnglish(tester);
  });

  testWidgets('English Display mode chooser saves one real theme selection',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-theme-row'));
    await _tap(tester, _sheetLabel('Dark'));
    expect(f.theme.themeMode, ThemeMode.dark);
    expect(f.themes.saved, [ThemeMode.dark]);
    expect(
        find.descendant(
            of: _key('profile-theme-row'), matching: find.text('Dark')),
        findsOneWidget);
    expect(f.api.channelReads, 1);
    expect(f.api.planReads, 1);
    expect(f.drafts.reads, 1);
    _expectEnglish(tester);
  });

  testWidgets(
      'English language chooser changes each locale once without data reads',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    var changes = 0;
    f.language.addListener(() => changes++);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-language-row'));
    await _tap(tester, _sheetLabel('ไทย'));
    expect(f.language.locale, const Locale('th'));
    expect(changes, 1);
    await _tap(tester, _key('profile-language-row'));
    await _tap(tester, _sheetLabel('English'));
    expect(f.language.locale, const Locale('en'));
    expect(changes, 2);
    expect(_key('profile-setting-sheet'), findsNothing);
    expect(f.api.channelReads, 1);
    expect(f.api.planReads, 1);
    expect(f.drafts.reads, 1);
    _expectEnglish(tester);
  });

  testWidgets('an open Display mode chooser follows live locale changes',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(_app(f));
    await tester.pumpAndSettle();
    await _tap(tester, _key('profile-theme-row'));
    f.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    expect(_sheetLabel('โหมดการแสดงผล'), findsOneWidget);
    expect(_sheetLabel('สว่าง'), findsOneWidget);
    expect(_sheetLabel('มืด'), findsOneWidget);
    f.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(_sheetLabel('Display mode'), findsOneWidget);
    expect(_sheetLabel('Light'), findsOneWidget);
    await _tap(tester, find.byTooltip('Close'));
    expect(f.themes.saved, isEmpty);
    expect(f.api.channelReads, 1);
    expect(f.api.planReads, 1);
    expect(f.drafts.reads, 1);
    _expectEnglish(tester);
  });

  testWidgets(
      'English owner switch ignores older channel, plan and profile responses',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    final channels = Completer<List<SocialConnectionResult>>();
    final plan = Completer<SubscriptionStatusResult>();
    final draft = Completer<ProfileDraft?>();
    f.api.channelGate = channels.future;
    f.api.planGate = plan.future;
    f.drafts.gate = draft.future;
    await tester.pumpWidget(_app(f));
    await tester.pump();
    f.api.channelGate = null;
    f.api.planGate = null;
    f.drafts.gate = null;
    f.api.subscription = const SubscriptionStatusResult(
        userId: 'current-owner',
        plan: 'STARTER',
        status: 'ACTIVE',
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: false);
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: 'current-owner',
        idToken: 'new-token',
        displayName: 'Current owner',
        email: 'current@example.com',
        emailVerified: true));
    channels.complete(
        const [SocialConnectionResult(platform: 'TIKTOK', connected: true)]);
    plan.complete(_plan());
    draft.complete(const ProfileDraft(
        displayName: 'Old private profile',
        storeName: '',
        accountUserId: _owner));
    await tester.pumpAndSettle();
    expect(find.text('Current owner'), findsOneWidget);
    expect(find.text('Old private profile'), findsNothing);
    await _reveal(tester, _key('profile-plan-starter'));
    expect(find.text('Starter'), findsOneWidget);
    expect(_key('profile-plan-pro'), findsNothing);
    expect(f.api.channelReads, 2);
    expect(f.api.planReads, 2);
    expect(f.drafts.reads, 2);
    _expectEnglish(tester);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'English Profile main menus and setting sheets fit 320dp 2x ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture(dark: dark);
      addTearDown(f.dispose);
      f.api.subscription = _plan(
          posts: 100,
          ai: 50,
          total: 348,
          phone: true,
          reset: DateTime.utc(2026, 11, 1));
      await tester.pumpWidget(_app(f, scale: 2, withBack: true));
      await tester.pumpAndSettle();
      _readable(tester, find.text('Account and profile'));
      _readable(tester, find.text('Email verified'));
      await _reveal(tester, _key('profile-view-plans'));
      for (final label in [
        'Current plan',
        '248 / 250 post units left this month',
        'Purchased credits remaining: 100 post units · 50 AI caption credits',
        'Purchased credits do not expire · Monthly quota is used first',
        'Total available: 348 post units',
        'View all plans',
        'Manage subscription'
      ]) {
        await _reveal(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      await _tap(tester, _key('profile-theme-row'));
      for (final label in ['Display mode', 'Light', 'Dark']) {
        _readable(tester, _sheetLabel(label));
      }
      await _tap(tester, find.byTooltip('Close'));
      await _tap(tester, _key('profile-language-row'));
      for (final label in ['Language', 'ไทย', 'English']) {
        _readable(tester, _sheetLabel(label));
      }
      await _tap(tester, find.byTooltip('Close'));
      await _reveal(tester, find.text('Terms of service'));
      for (final label in [
        'Settings and help',
        'Security',
        'Help',
        'Privacy policy',
        'Terms of service'
      ]) {
        await _reveal(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      _expectEnglish(tester);
      expect(f.api.planReads, 1);
      expect(f.api.channelReads, 1);
      expect(f.themes.saved, isEmpty);
    });

    testWidgets(
        'English Profile unavailable cards and retries fit 320dp 2x ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture(dark: dark);
      addTearDown(f.dispose);
      f.api.channelError = StateError('offline');
      f.api.planError = StateError('offline');
      await tester.pumpWidget(_app(f, scale: 2, withBack: true));
      await tester.pumpAndSettle();
      await _reveal(tester, _key('profile-connections-error'));
      _readable(
          tester,
          find.descendant(
              of: _key('profile-connections-error'),
              matching: find.text('Could not load channels')));
      f.api.channelError = null;
      await _tap(tester, _key('profile-retry-connections'));
      expect(f.api.channelReads, 2);
      await _reveal(tester, _key('profile-subscription-error'));
      _readable(tester, find.text('Could not load plan'));
      f.api.planError = null;
      await _tap(tester, _key('profile-retry-subscription'));
      expect(f.api.planReads, 2);
      expect(_key('profile-subscription-error'), findsNothing);
      _expectEnglish(tester);
    });

    testWidgets(
        'English disconnected account fallback fits 320dp 2x ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PostDeeAuthSessionStore.instance.clear();
      final f = _Fixture(dark: dark);
      addTearDown(f.dispose);
      await tester.pumpWidget(_app(f, scale: 2, withBack: true));
      await tester.pumpAndSettle();
      _readable(tester, find.text('Account not connected'));
      _readable(
          tester, find.text('Connect your email before using live features.'));
      _readable(tester, find.text('Email not connected'));
      _expectEnglish(tester);
    });
  }
}
