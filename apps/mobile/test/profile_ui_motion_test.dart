import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/profile/edit_profile_screen.dart';
import 'package:postdee_mobile/features/profile/profile_draft_store.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';
import 'package:postdee_mobile/features/shared/postdee_press_feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _content => _key('profile-content-motion');
Finder get _sheet => _key('profile-setting-sheet');

class _Api extends PostDeeApiClient {
  var subscriptions = 0;
  var connections = 0;
  var failSubscription = false;

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async {
    connections++;
    return const [];
  }

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    subscriptions++;
    if (failSubscription) throw StateError('controlled subscription failure');
    return const SubscriptionStatusResult(
      userId: 'motion-seller',
      plan: 'BASIC',
      status: 'INACTIVE',
      remainingPostsThisMonth: 3,
      monthlyPostLimit: 3,
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );
  }
}

class _DraftStore implements ProfileDraftStore {
  var loads = 0;
  var saves = 0;
  var clears = 0;

  @override
  Future<ProfileDraft?> load() async {
    loads++;
    return null;
  }

  @override
  Future<void> save(ProfileDraft draft) async => saves++;

  @override
  Future<void> clear() async => clears++;
}

class _ThemeStore implements PostDeeThemePreferenceStore {
  final saved = <ThemeMode>[];

  @override
  Future<ThemeMode?> loadThemeMode() async => null;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async => saved.add(mode);
}

class _Fixture {
  final api = _Api();
  final drafts = _DraftStore();
  final themeStore = _ThemeStore();
  final language = PostDeeLanguageController();
  late final theme = PostDeeThemeController(preferenceStore: themeStore);
  var deletes = 0;
  var signsOut = 0;
  var manages = 0;
  var phoneRequests = 0;
  var emailSends = 0;
  var emailRefreshes = 0;
  Completer<bool>? emailGate;

  Widget app({
    bool reduced = false,
    bool active = true,
    bool ticker = true,
    bool deleting = false,
    double textScale = 1,
  }) =>
      AnimatedBuilder(
        animation: Listenable.merge([language, theme]),
        builder: (context, child) => MaterialApp(
          locale: language.locale,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.themeMode,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: PostDeeLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: TickerMode(
              enabled: ticker,
              child: ProfileScreen(
                languageController: language,
                themeController: theme,
                isActive: active,
                isDeletingAccount: deleting,
                apiClient: api,
                profileDraftStore: drafts,
                onOpenTemplates: () {},
                onDeleteAccount: () => deletes++,
                onSignOut: () => signsOut++,
                onManageSubscription: () async => manages++,
                verifyPhone: (_) async {
                  phoneRequests++;
                  return null;
                },
                onSendEmailVerification: () async {
                  emailSends++;
                  return await emailGate?.future ?? true;
                },
                onRefreshEmailVerification: () async {
                  emailRefreshes++;
                  return true;
                },
              ),
            ),
          ),
        ),
      );

  void expectNoAccountActions() {
    expect(deletes, 0);
    expect(signsOut, 0);
    expect(manages, 0);
    expect(phoneRequests, 0);
    expect(emailSends, 0);
    expect(emailRefreshes, 0);
    expect(drafts.saves, 0);
    expect(drafts.clears, 0);
    expect(themeStore.saved, isEmpty);
  }
}

Future<void> _mount(WidgetTester tester, _Fixture fixture,
    {double width = 393, double textScale = 1, bool reduced = false}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(fixture.app(reduced: reduced, textScale: textScale));
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Finder finder,
    {Finder? scrollable}) async {
  await tester.scrollUntilVisible(finder, 250,
      scrollable: scrollable ?? find.byType(Scrollable).first, maxScrolls: 35);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Finder _feedback(Finder control) => find
    .ancestor(of: control, matching: find.byType(PostDeePressFeedback))
    .first;

double _scale(WidgetTester tester, Finder control) => tester
    .widget<Transform>(find
        .descendant(
            of: _feedback(control), matching: _key('postdee-press-transform'))
        .first)
    .transform
    .entry(0, 0);

double _opacity(WidgetTester tester, Finder entrance) => tester
    .widget<Opacity>(
        find.descendant(of: entrance, matching: find.byType(Opacity)).first)
    .opacity;

Finder _sheetChoice(String text) =>
    find.descendant(of: _sheet, matching: find.widgetWithText(ListTile, text));

void _resume(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
      AppTheme.applyThemeMode(ThemeMode.light);
    });
    sessions.signIn(const AuthSession(
      userId: 'motion-seller',
      idToken: 'motion-test-token',
      displayName: 'มินา',
      email: 'mina@example.com',
    ));
  });

  testWidgets('account entrance finishes once without replacing data or scroll',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 60));
    expect(_content, findsOneWidget);
    expect(_opacity(tester, _content), inExclusiveRange(0, 1));
    final state = tester.state(find.byType(ProfileScreen));
    final list = tester.element(find.byType(ListView).first);
    await tester.pumpAndSettle();
    expect(_opacity(tester, _content), 1);
    await _show(tester, _key('profile-language-row'));
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final offset = position.pixels;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ProfileScreen)), same(state));
    expect(tester.element(find.byType(ListView).first), same(list));
    expect(position.pixels, offset);
    expect(_opacity(tester, _content), 1);
    expect(fixture.api.subscriptions, 1);
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.loads, 1);
    fixture.expectNoAccountActions();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit press cancels safely and preserves semantics and edge hit',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final semantics = tester.ensureSemantics();
    try {
      final edit = _key('profile-edit-button');
      final bounds = tester.getRect(edit);
      final wrapperBounds = tester.getRect(_feedback(edit));
      final size = tester.getSize(edit);
      final gesture =
          await tester.startGesture(bounds.topLeft + const Offset(2, 25));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scale(tester, edit), closeTo(.97, .001));
      expect(tester.getRect(_feedback(edit)), wrapperBounds);
      expect(tester.getSize(edit), size);
      expect(tester.getRect(edit).width, lessThan(bounds.width));
      expect(
          tester
              .widget<Transform>(find
                  .descendant(
                      of: _feedback(edit),
                      matching: _key('postdee-press-transform'))
                  .first)
              .transformHitTests,
          isFalse);
      final semanticsData = tester.getSemantics(edit).getSemanticsData();
      expect(semanticsData.flagsCollection.isButton, isTrue);
      expect(semanticsData.label, contains('แก้ไขโปรไฟล์'));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_scale(tester, edit), 1);
      expect(find.byType(EditProfileScreen), findsNothing);
      await tester.tapAt(bounds.topLeft + const Offset(2, 25));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      fixture.expectNoAccountActions();
      Navigator.of(tester.element(find.byType(EditProfileScreen))).pop();
      await tester.pumpAndSettle();
      expect(fixture.drafts.saves, 0);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('menu feedback retains exactly one native callback',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final manage = find.text('จัดการสมาชิก');
    await _show(tester, manage);
    final bounds = tester.getRect(_feedback(manage));
    final gesture =
        await tester.startGesture(bounds.topLeft + const Offset(2, 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester, manage), closeTo(.97, .001));
    expect(tester.getRect(_feedback(manage)), bounds);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.manages, 0);
    await tester.tapAt(bounds.topLeft + const Offset(2, 24));
    await tester.pumpAndSettle();
    expect(fixture.manages, 1);
    expect(_scale(tester, manage), 1);
    expect(fixture.api.subscriptions, 1);
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.loads, 1);
    expect(fixture.deletes, 0);
    expect(fixture.signsOut, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'setting feedback closes without change and saves chosen theme once',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final row = _key('profile-theme-row');
    await _show(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(_key('profile-setting-motion'), findsOneWidget);
    final dark = _sheetChoice('มืด');
    final gesture = await tester.startGesture(tester.getCenter(dark));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester, dark), closeTo(.97, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.themeStore.saved, isEmpty);
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(fixture.theme.themeMode, ThemeMode.light);
    fixture.expectNoAccountActions();
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(_sheetChoice('มืด'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(fixture.theme.themeMode, ThemeMode.dark);
    expect(fixture.themeStore.saved, [ThemeMode.dark]);
    expect(_opacity(tester, _content), 1);
    expect(fixture.api.subscriptions, 1);
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'language choice changes once without duplicate settings or reload',
      (tester) async {
    final fixture = _Fixture();
    var changes = 0;
    fixture.language.addListener(() => changes++);
    await _mount(tester, fixture);
    final row = _key('profile-language-row');
    await _show(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final english = _sheetChoice('English');
    expect(english, findsOneWidget);
    expect(_feedback(english), findsOneWidget);
    await tester.tap(english);
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(fixture.language.locale, const Locale('en'));
    expect(_sheet, findsNothing);
    expect(_content, findsOneWidget);
    expect(_opacity(tester, _content), 1);
    expect(fixture.api.subscriptions, 1);
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.loads, 1);
    fixture.expectNoAccountActions();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('email busy state disables feedback and duplicate actions',
      (tester) async {
    final fixture = _Fixture()..emailGate = Completer<bool>();
    await _mount(tester, fixture);
    final send = _key('profile-send-email-verification');
    final refresh = _key('profile-refresh-email-verification');
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(fixture.emailSends, 1);
    expect(tester.widget<TextButton>(send).onPressed, isNull);
    expect(tester.widget<TextButton>(refresh).onPressed, isNull);
    final gesture = await tester.startGesture(tester.getCenter(send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester, send), 1);
    await gesture.up();
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(fixture.emailSends, 1);
    expect(fixture.emailRefreshes, 0);
    fixture.emailGate!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(send).onPressed, isNotNull);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(fixture.emailRefreshes, 1);
    expect(fixture.api.subscriptions, 1);
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete feedback keeps cancellation and disabled guard intact',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final delete = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await _show(tester, delete);
    final gesture = await tester.startGesture(tester.getCenter(delete));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester, delete), closeTo(.97, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_key('delete-account-confirm-sheet'), findsNothing);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(_key('delete-account-confirm-sheet'), findsOneWidget);
    final cancel = find.widgetWithText(OutlinedButton, 'ยกเลิก');
    await _show(tester, cancel,
        scrollable: find.descendant(
            of: _key('delete-account-confirm-sheet'),
            matching: find.byType(Scrollable)));
    expect(_feedback(cancel), findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    fixture.expectNoAccountActions();
    await tester.pumpWidget(fixture.app(deleting: true));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(delete).onPressed, isNull);
    final disabled = await tester.startGesture(tester.getCenter(delete));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester, delete), 1);
    await disabled.up();
    await tester.pumpAndSettle();
    expect(_key('delete-account-confirm-sheet'), findsNothing);
    expect(fixture.deletes, 0);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['reduced', 'ticker', 'inactive']) {
    testWidgets('$mode interrupts account motion without restarting the screen',
        (tester) async {
      final fixture = _Fixture();
      await tester.pumpWidget(fixture.app());
      await tester.pump(const Duration(milliseconds: 50));
      expect(_opacity(tester, _content), inExclusiveRange(0, 1));
      final state = tester.state(find.byType(ProfileScreen));
      final edit = _key('profile-edit-button');
      final gesture = await tester.startGesture(tester.getCenter(edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_scale(tester, edit), lessThan(1));
      await tester.pumpWidget(fixture.app(
          reduced: mode == 'reduced',
          ticker: mode != 'ticker',
          active: mode != 'inactive'));
      await tester.pumpAndSettle();
      expect(_opacity(tester, _content), 1);
      expect(_scale(tester, edit), 1);
      expect(tester.state(find.byType(ProfileScreen)), same(state));
      expect(fixture.api.subscriptions, 1);
      fixture.expectNoAccountActions();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await gesture.cancel();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      expect(_opacity(tester, _content), 1);
      expect(_scale(tester, edit), 1);
      expect(fixture.api.subscriptions, mode == 'inactive' ? 2 : 1);
      expect(fixture.api.connections, 1);
      expect(fixture.drafts.loads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in ['reduced', 'ticker', 'inactive']) {
    testWidgets('$mode suppresses feedback in an already open setting sheet',
        (tester) async {
      final fixture = _Fixture();
      await _mount(tester, fixture);
      await _show(tester, _key('profile-theme-row'));
      await tester.tap(_key('profile-theme-row'));
      await tester.pumpAndSettle();
      final choice = _sheetChoice('มืด');
      final gesture = await tester.startGesture(tester.getCenter(choice));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(_scale(tester, choice), lessThan(1));
      await tester.pumpWidget(fixture.app(
          reduced: mode == 'reduced',
          ticker: mode != 'ticker',
          active: mode != 'inactive'));
      await tester.pumpAndSettle();
      expect(_scale(tester, choice), 1);
      expect(_opacity(tester, _key('profile-setting-motion')), 1);
      expect(_sheet, findsOneWidget);
      expect(fixture.api.subscriptions, 1);
      fixture.expectNoAccountActions();
      await gesture.cancel();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      expect(_scale(tester, choice), 1);
      expect(_opacity(tester, _key('profile-setting-motion')), 1);
      await tester.tap(find.byTooltip('ปิด'));
      await tester.pumpAndSettle();
      expect(fixture.theme.themeMode, ThemeMode.light);
      expect(fixture.api.connections, 1);
      expect(fixture.drafts.loads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('background transition stops motion and retains resume refresh',
      (tester) async {
    addTearDown(() => _resume(tester));
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 50));
    expect(_opacity(tester, _content), inExclusiveRange(0, 1));
    final edit = _key('profile-edit-button');
    final gesture = await tester.startGesture(tester.getCenter(edit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pumpAndSettle();
    expect(_opacity(tester, _content), 1);
    expect(_scale(tester, edit), 1);
    expect(fixture.api.subscriptions, 1);
    fixture.expectNoAccountActions();
    await gesture.cancel();
    _resume(tester);
    await tester.pumpAndSettle();
    expect(_opacity(tester, _content), 1);
    expect(_scale(tester, edit), 1);
    expect(fixture.api.subscriptions, 2);
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.loads, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tab reactivation animates once while preserving scroll and loads',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _show(tester, _key('profile-language-row'));
    final state = tester.state(find.byType(ProfileScreen));
    final list = tester.element(find.byType(ListView).first);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    // Stay below both existing loaded and loading content extents. The legacy
    // subscription refresh can legitimately clamp a position at the very end.
    position.jumpTo(200);
    await tester.pumpAndSettle();
    final offset = position.pixels;
    await tester.pumpWidget(fixture.app(active: false));
    await tester.pumpAndSettle();
    expect(_opacity(tester, _content), 1);
    expect(fixture.api.subscriptions, 1);
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 60));
    expect(_opacity(tester, _content), inExclusiveRange(0, 1));
    expect(tester.state(find.byType(ProfileScreen)), same(state));
    expect(tester.element(find.byType(ListView).first), same(list));
    await tester.pumpAndSettle();
    expect(_opacity(tester, _content), 1);
    expect(position.pixels, offset);
    expect(fixture.api.subscriptions, 2);
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.loads, 1);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_opacity(tester, _content), 1);
    expect(fixture.api.subscriptions, 2);
    fixture.expectNoAccountActions();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'background setting sheet becomes static without refreshing route',
      (tester) async {
    addTearDown(() => _resume(tester));
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _show(tester, _key('profile-theme-row'));
    await tester.tap(_key('profile-theme-row'));
    await tester.pumpAndSettle();
    final choice = _sheetChoice('มืด');
    final gesture = await tester.startGesture(tester.getCenter(choice));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_scale(tester, choice), lessThan(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pumpAndSettle();
    expect(_scale(tester, choice), 1);
    expect(_opacity(tester, _key('profile-setting-motion')), 1);
    fixture.expectNoAccountActions();
    await gesture.cancel();
    _resume(tester);
    await tester.pumpAndSettle();
    expect(_scale(tester, choice), 1);
    expect(_opacity(tester, _key('profile-setting-motion')), 1);
    expect(fixture.api.subscriptions, 1,
        reason: 'the existing profile route refresh waits while sheet is open');
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused creation and disposal leave no pending motion callbacks',
      (tester) async {
    addTearDown(() => _resume(tester));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_content, findsOneWidget);
    expect(_opacity(tester, _content), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(_opacity(tester, _content), 1);
    expect(fixture.api.subscriptions, 2);
    await _show(tester, _key('profile-theme-row'));
    await tester.tap(_key('profile-theme-row'));
    await tester.pumpAndSettle();
    final choice = _sheetChoice('มืด');
    final gesture = await tester.startGesture(tester.getCenter(choice));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_scale(tester, choice), lessThan(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.cancel();
    await tester.pumpAndSettle();
    fixture.expectNoAccountActions();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings and delete remain usable at 320px and text scale two',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, width: 320, textScale: 2);
    expect(tester.takeException(), isNull);
    final row = _key('profile-theme-row');
    await _show(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    expect(_feedback(_sheetChoice('มืด')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    final delete = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await _show(tester, delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    final sheetScroll = find.descendant(
        of: _key('delete-account-confirm-sheet'),
        matching: find.byType(Scrollable));
    final cancel = find.widgetWithText(OutlinedButton, 'ยกเลิก');
    await _show(tester, cancel, scrollable: sheetScroll);
    expect(_feedback(cancel), findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    fixture.expectNoAccountActions();
    expect(tester.takeException(), isNull);
  });

  testWidgets('error retry feedback triggers only the requested reload',
      (tester) async {
    final fixture = _Fixture()..api.failSubscription = true;
    await _mount(tester, fixture);
    expect(_key('profile-subscription-error'), findsOneWidget);
    final retry = _key('profile-retry-subscription');
    await _show(tester, retry);
    final gesture = await tester.startGesture(tester.getCenter(retry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester, retry), closeTo(.97, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.api.subscriptions, 1);
    fixture.api.failSubscription = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(fixture.api.subscriptions, 2);
    expect(fixture.api.connections, 1);
    expect(fixture.drafts.loads, 1);
    expect(_key('profile-plan-free'), findsOneWidget);
    expect(_key('profile-subscription-error'), findsNothing);
    fixture.expectNoAccountActions();
    expect(tester.takeException(), isNull);
  });
}
