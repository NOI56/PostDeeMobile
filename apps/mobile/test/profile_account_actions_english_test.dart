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
import 'package:shared_preferences/shared_preferences.dart';

const _owner = AuthSession(
    userId: 'account-actions-owner',
    idToken: 'fixture-token',
    email: 'seller@example.com',
    displayName: 'Seller');
const _paid = SubscriptionStatusResult(
    userId: 'account-actions-owner',
    plan: 'PRO',
    status: 'ACTIVE',
    addonPostUnits: 70,
    addonAiCaptions: 25,
    canSchedule: true,
    canUseAiCaptions: true,
    canUseAnalytics: true);
const _deleteWarning =
    'Your account data on PostDee services will be permanently '
    'deleted. Drafts and files on this device, including system backups, may '
    'remain. To remove them, delete drafts before deleting your account, or clear '
    'app data and manage backups separately.';
const _knownCredits =
    'You have purchased credits remaining: 70 post units · 25 '
    'AI caption credits. These credits cannot be used after account deletion. '
    'Review them before confirming.';
const _unknownCredits = 'Any purchased credits remaining cannot be used after '
    'account deletion. Check your balance before confirming.';
const _storeWarning =
    'Deleting your PostDee account does not cancel Starter/Pro '
    'subscriptions purchased through the App Store or Google Play. To stop '
    'renewal, cancel your subscription in the store before deleting your account.';

class _Api extends PostDeeApiClient {
  Future<SubscriptionStatusResult> Function()? subscription;

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async =>
      const [];

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() =>
      subscription?.call() ?? Future.value(_paid);
}

class _Drafts implements ProfileDraftStore {
  int saves = 0;
  int clears = 0;
  ProfileDraft? saved;

  @override
  Future<ProfileDraft?> load() async => saved;

  @override
  Future<void> save(ProfileDraft draft) async {
    saves++;
    saved = draft;
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

class _Fixture {
  final api = _Api();
  final drafts = _Drafts();
  final language = PostDeeLanguageController(initialLocale: const Locale('en'));
  final theme = PostDeeThemeController();
  Future<void> Function()? manage;
  Future<bool> Function(Uri)? launch;
  Future<bool> Function()? send;
  Future<bool> Function()? refresh;
  int deletions = 0;
  int signOuts = 0;

  Widget app(
      {String languageCode = 'en',
      bool deleting = false,
      bool dark = false,
      double scale = 1}) {
    language.setLocale(Locale(languageCode));
    return MaterialApp(
      locale: Locale(languageCode),
      theme: (dark ? AppTheme.dark : AppTheme.light)
          .copyWith(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true, textScaler: TextScaler.linear(scale)),
          child: child!),
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: PostDeeLocalizations.supportedLocales,
      home: Scaffold(
        body: ProfileScreen(
          key: const ValueKey('account-actions'),
          languageController: language,
          themeController: theme,
          apiClient: api,
          profileDraftStore: drafts,
          onOpenTemplates: () {},
          onDeleteAccount: () => deletions++,
          onSignOut: () => signOuts++,
          isDeletingAccount: deleting,
          onManageSubscription: manage,
          launchSubscriptionManagement: launch,
          onSendEmailVerification: send,
          onRefreshEmailVerification: refresh,
        ),
      ),
    );
  }

  void dispose() {
    language.dispose();
    theme.dispose();
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 260,
        scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _delete() => find.widgetWithText(OutlinedButton, 'Delete account');
Finder _confirmDelete() =>
    find.widgetWithText(FilledButton, 'Delete account permanently');

void main() {
  late _Fixture fixture;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    PostDeeAuthSessionStore.instance.signIn(_owner);
    fixture = _Fixture();
  });
  tearDown(() {
    fixture.dispose();
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('English unknown subscription store offers both stores and Back',
      (tester) async {
    final opened = <Uri>[];
    fixture.launch = (uri) async {
      opened.add(uri);
      return true;
    };
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Manage subscription'));
    expect(find.text('Choose your subscription store'), findsOneWidget);
    expect(
        find.text('Choose the store you paid through, even if you now use a '
            'different device. You can review your subscription before canceling it.'),
        findsOneWidget);
    expect(find.text('Store on this device'), findsOneWidget);
    expect(find.byKey(const ValueKey('manage-subscription-google-play')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('manage-subscription-app-store')),
        findsOneWidget);
    expect(opened, isEmpty);
    await _tap(tester, find.text('Back'));
    expect(find.text('Choose your subscription store'), findsNothing);
    expect(opened, isEmpty);
    expect(fixture.deletions, 0);
  });

  for (final choice in [
    (id: 'app-store', url: 'https://apps.apple.com/account/subscriptions'),
    (
      id: 'google-play',
      url: 'https://play.google.com/store/account/subscriptions'
    ),
  ]) {
    testWidgets('English store choice keeps the exact ${choice.id} URL',
        (tester) async {
      final opened = <Uri>[];
      fixture.launch = (uri) async {
        opened.add(uri);
        return true;
      };
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Manage subscription'));
      await _tap(
          tester, find.byKey(ValueKey('manage-subscription-${choice.id}')));
      expect(opened, [Uri.parse(choice.url)]);
      expect(fixture.deletions, 0);
    });
  }

  testWidgets(
      'injected subscription management skips the unknown-store chooser',
      (tester) async {
    var manages = 0;
    fixture.manage = () async => manages++;
    fixture.launch =
        (_) async => throw StateError('must use injected management');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Manage subscription'));
    expect(manages, 1);
    expect(find.text('Choose your subscription store'), findsNothing);
  });

  for (final throws in [false, true]) {
    testWidgets(
        'English subscription launch failure keeps manual steps (throws=$throws)',
        (tester) async {
      fixture.launch = (_) async {
        if (throws) throw StateError('opaque-launch-error');
        return false;
      };
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Manage subscription'));
      await _tap(
          tester, find.byKey(const ValueKey('manage-subscription-app-store')));
      expect(
          find.text('Could not open subscription management. Open it from the '
              'App Store or Google Play.'),
          findsOneWidget);
      expect(find.textContaining('opaque-launch-error'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late store choice from a different owner cannot launch a URL',
      (tester) async {
    var launches = 0;
    fixture.launch = (_) async {
      launches++;
      return true;
    };
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Manage subscription'));
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'replacement', idToken: 'replacement'));
    await tester.pumpAndSettle();
    await _tap(
        tester, find.byKey(const ValueKey('manage-subscription-google-play')));
    expect(launches, 0);
    expect(fixture.deletions, 0);
  });

  testWidgets('English verification email action does not run before a tap',
      (tester) async {
    var sends = 0;
    fixture.send = () async {
      sends++;
      return true;
    };
    fixture.refresh = () async => true;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.text('Send verification email'), findsOneWidget);
    expect(find.text('Check verification'), findsOneWidget);
    expect(sends, 0);
    await _tap(
        tester, find.byKey(const ValueKey('profile-send-email-verification')));
    expect(sends, 1);
    expect(
        find.text('Verification link sent. Check your inbox and spam folder.'),
        findsOneWidget);
  });

  for (final verified in [false, true]) {
    testWidgets('English verification refresh reports verified=$verified',
        (tester) async {
      var refreshes = 0;
      fixture.send = () async => true;
      fixture.refresh = () async {
        refreshes++;
        if (verified) {
          PostDeeAuthSessionStore.instance.signIn(const AuthSession(
              userId: 'account-actions-owner',
              idToken: 'new-token',
              email: 'seller@example.com',
              emailVerified: true));
        }
        return true;
      };
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _tap(tester,
          find.byKey(const ValueKey('profile-refresh-email-verification')));
      expect(refreshes, 1);
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.text(verified
                  ? 'Email verified'
                  : 'Your email is not verified '
                      'yet. Open the link in your email first.')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('profile-send-email-verification')),
          verified ? findsNothing : findsOneWidget);
    });
  }

  testWidgets(
      'pending email failure uses the current locale and stays single-flight',
      (tester) async {
    final result = Completer<bool>();
    var sends = 0;
    var refreshes = 0;
    fixture.send = () {
      sends++;
      return result.future;
    };
    fixture.refresh = () async {
      refreshes++;
      return true;
    };
    await tester.pumpWidget(fixture.app(languageCode: 'th'));
    await tester.pumpAndSettle();
    await _tap(
        tester, find.byKey(const ValueKey('profile-send-email-verification')));
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('profile-send-email-verification')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find
                .byKey(const ValueKey('profile-refresh-email-verification')))
            .onPressed,
        isNull);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    result.completeError(StateError('opaque-email-error'));
    await tester.pumpAndSettle();
    expect(find.text('Could not complete this action. Please try again.'),
        findsOneWidget);
    expect(find.textContaining('opaque-email-error'), findsNothing);
    expect(sends, 1);
    expect(refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late email completion cannot show a result for a replacement owner',
      (tester) async {
    final result = Completer<bool>();
    fixture.send = () => result.future;
    fixture.refresh = () async => true;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(
        tester, find.byKey(const ValueKey('profile-send-email-verification')));
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: 'replacement',
        idToken: 'replacement',
        email: 'other@example.com'));
    result.complete(true);
    await tester.pumpAndSettle();
    expect(
        find.text('Verification link sent. Check your inbox and spam folder.'),
        findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
        PostDeeAuthSessionStore.instance.session.stableUserId, 'replacement');
  });

  testWidgets(
      'English delete sheet cancels without deleting or clearing drafts',
      (tester) async {
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(tester, _delete());
    expect(find.text('Before deleting your account'), findsOneWidget);
    expect(find.text(_deleteWarning), findsOneWidget);
    expect(find.text(_knownCredits), findsOneWidget);
    expect(find.text(_storeWarning), findsOneWidget);
    expect(_confirmDelete(), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Manage subscription'),
        findsOneWidget);
    expect(fixture.deletions, 0);
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(find.byKey(const ValueKey('delete-account-confirm-sheet')),
        findsNothing);
    expect(fixture.deletions, 0);
    expect(fixture.drafts.clears, 0);
    expect(fixture.drafts.saves, 0);
  });

  testWidgets('unknown subscription status keeps all English deletion warnings',
      (tester) async {
    fixture.api.subscription = () async => throw StateError('offline');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(tester, _delete());
    expect(find.text(_deleteWarning), findsOneWidget);
    expect(find.text(_unknownCredits), findsOneWidget);
    expect(find.text(_knownCredits), findsNothing);
    expect(find.text(_storeWarning), findsOneWidget);
    expect(find.textContaining('opaque'), findsNothing);
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(fixture.deletions, 0);
  });

  testWidgets(
      'open deletion warnings switch from Thai to English without action',
      (tester) async {
    await tester.pumpWidget(fixture.app(languageCode: 'th'));
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(OutlinedButton, 'ลบบัญชี'));
    expect(find.text('ก่อนลบบัญชี'), findsOneWidget);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.text('Before deleting your account'), findsOneWidget);
    expect(find.text(_deleteWarning), findsOneWidget);
    expect(find.text(_knownCredits), findsOneWidget);
    expect(find.text(_storeWarning), findsOneWidget);
    expect(find.text('ก่อนลบบัญชี'), findsNothing);
    expect(fixture.deletions, 0);
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(fixture.deletions, 0);
  });

  testWidgets('pending subscription launch failure uses the current locale',
      (tester) async {
    final result = Completer<bool>();
    final opened = <Uri>[];
    fixture.launch = (uri) {
      opened.add(uri);
      return result.future;
    };
    await tester.pumpWidget(fixture.app(languageCode: 'th'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('จัดการสมาชิก'));
    await _tap(
        tester, find.byKey(const ValueKey('manage-subscription-app-store')));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    result.complete(false);
    await tester.pumpAndSettle();
    expect(
        find.text('Could not open subscription management. Open it from the '
            'App Store or Google Play.'),
        findsOneWidget);
    expect(opened, [Uri.parse('https://apps.apple.com/account/subscriptions')]);
  });

  for (final dark in [false, true]) {
    testWidgets('English deletion controls fit 320dp with 2x text (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(fixture.app(dark: dark, scale: 2));
      await tester.pumpAndSettle();
      await _tap(tester, _delete());
      final manage = find.widgetWithText(OutlinedButton, 'Manage subscription');
      await tester.ensureVisible(manage);
      await tester.pumpAndSettle();
      final label = find.descendant(
          of: manage, matching: find.text('Manage subscription'));
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
          paragraph.size.height,
          greaterThanOrEqualTo(
              paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5));
      expect(manage.hitTestable(), findsOneWidget);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
      expect(fixture.deletions, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'English delete confirmation calls only the injected callback once',
      (tester) async {
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(tester, _delete());
    await _tap(tester, _confirmDelete());
    expect(fixture.deletions, 1);
    expect(fixture.drafts.clears, 0);
    expect(fixture.drafts.saves, 0);
    expect(find.byKey(const ValueKey('delete-account-confirm-sheet')),
        findsNothing);
    expect(PostDeeAuthSessionStore.instance.session.stableUserId,
        'account-actions-owner');
  });

  testWidgets('English delete confirmation rejects an old owner dialog',
      (tester) async {
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(tester, _delete());
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'replacement', idToken: 'replacement'));
    await tester.pumpAndSettle();
    await _tap(tester, _confirmDelete());
    expect(fixture.deletions, 0);
    expect(fixture.drafts.clears, 0);
  });

  testWidgets('busy deletion disables the English entry action',
      (tester) async {
    await tester.pumpWidget(fixture.app(deleting: true));
    await tester.pumpAndSettle();
    if (_delete().evaluate().isEmpty) {
      await tester.scrollUntilVisible(_delete(), 260);
    }
    expect(tester.widget<OutlinedButton>(_delete()).onPressed, isNull);
    expect(fixture.deletions, 0);
    expect(find.byKey(const ValueKey('delete-account-confirm-sheet')),
        findsNothing);
  });

  testWidgets('English Sign out invokes only its injected callback',
      (tester) async {
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.signOuts, 0);
    await _tap(tester, find.text('Sign out'));
    expect(fixture.signOuts, 1);
    expect(fixture.deletions, 0);
    expect(fixture.drafts.clears, 0);
  });

  testWidgets('English Profile saved toast Undo restores only the local edit',
      (tester) async {
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('profile-edit-button')));
    await tester.enterText(
        find.byKey(const ValueKey('edit-profile-display-name')),
        'Edited Seller');
    await _tap(tester, find.byKey(const ValueKey('edit-profile-save')));
    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Edited Seller'), findsOneWidget);
    expect(fixture.drafts.saved?.displayName, 'Edited Seller');
    await _tap(tester, find.text('Undo'));
    expect(find.text('Seller'), findsOneWidget);
    expect(fixture.drafts.saved?.displayName, 'Seller');
    expect(PostDeeAuthSessionStore.instance.session.displayName, 'Seller');
    expect(fixture.deletions, 0);
    expect(tester.takeException(), isNull);
  });
}
