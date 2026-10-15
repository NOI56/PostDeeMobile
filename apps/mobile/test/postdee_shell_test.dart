import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/caption_writing_style.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/auth/firebase_account_access_revoker.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';
import 'package:postdee_mobile/features/billing/paywall_screen.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';
import 'package:postdee_mobile/features/captions/caption_writing_style_store.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';
import 'package:postdee_mobile/features/shell/postdee_shell.dart';
import 'package:postdee_mobile/features/notifications/push_messaging_gateway.dart';
import 'package:postdee_mobile/features/legal/legal_document_screen.dart';
import 'package:postdee_mobile/features/templates/templates_screen.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:postdee_mobile/features/notifications/push_notification.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_publish_media_identity.dart';
import 'support/test_tiktok_video_preparer.dart';

Finder _referenceNav() =>
    find.byKey(const ValueKey('postdee-reference-bottom-nav'));

Finder _referenceNavButton(String label) => find.descendant(
      of: _referenceNav(),
      matching: find.bySemanticsLabel(label),
    );

Widget _shellApp(
  PostDeeShell shell, {
  bool disableAnimations = false,
  bool tickerEnabled = true,
  TextDirection? textDirection,
  double? textScale,
}) =>
    MaterialApp(
      theme: AppTheme.dark,
      locale: const Locale('en'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: textScale == null
              ? MediaQuery.of(context).textScaler
              : TextScaler.linear(textScale),
        ),
        child: TickerMode(
          enabled: tickerEnabled,
          child: textDirection == null
              ? child!
              : Directionality(textDirection: textDirection, child: child!),
        ),
      ),
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: PostDeeLocalizations.supportedLocales,
      home: shell,
    );

PostDeeLanguageController _signInShell() {
  SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
  final sessionStore = PostDeeAuthSessionStore.instance;
  final languageController = PostDeeLanguageController(
    initialLocale: const Locale('en'),
  );
  sessionStore.signIn(
    const AuthSession(
      userId: 'firebase-user-shell',
      idToken: 'firebase-id-token',
      email: 'seller@example.com',
      displayName: 'PostDee Seller',
    ),
  );
  addTearDown(sessionStore.clear);
  addTearDown(languageController.dispose);
  return languageController;
}

class _ShellDraftStore implements PublishDraftStore {
  final Map<String, PublishDraft> drafts = {};

  @override
  Future<void> deleteAllDrafts() async => drafts.clear();

  @override
  Future<void> deleteDraft(String draftId) async => drafts.remove(draftId);

  @override
  Future<List<PublishDraft>> listDrafts() async => drafts.values.toList();

  @override
  Future<PublishDraft?> loadDraft(String draftId) async => drafts[draftId];

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    final fingerprint = testPublishMediaFingerprint(request);
    final draft = PublishDraft(
      version: publishDraftManifestVersion,
      id: request.id,
      ownerUserId: 'firebase-user-shell',
      submissionRequestId:
          'submit_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      videoPath: request.videoFile.path,
      videoName: request.videoName,
      videoSizeBytes: request.videoFile.lengthSync(),
      videoWidth: request.videoWidth,
      videoHeight: request.videoHeight,
      caption: request.caption,
      aiGuidance: request.aiGuidance,
      watermarkEnabled: request.watermarkEnabled,
      platformApiValues: request.platformApiValues,
      platformSettings: request.platformSettings,
      scheduledAt: request.scheduledAt,
      mediaContentFingerprint: fingerprint,
      uploadedMedia:
          request.uploadedMedia?.mediaContentFingerprint == fingerprint
              ? request.uploadedMedia
              : null,
    );
    drafts[draft.id] = draft;
    return draft;
  }
}

class _ShellEmailRecoveryGateway
    implements EmailAuthGateway, EmailAccountRecoveryGateway {
  final resets = <String>[];
  @override
  Future<AuthSession> signIn(
          {required String email,
          required String password,
          required bool createAccount}) async =>
      const AuthSession(userId: 'seller', idToken: 'token');
  @override
  Future<void> sendPasswordResetEmail(String email) async => resets.add(email);
  @override
  Future<void> sendEmailVerification() async {}
  @override
  Future<AuthSession> reloadSession() async =>
      const AuthSession(userId: 'seller', idToken: 'token');
}

const _navMotionTabs = {
  'Home': 0,
  'Calendar': 1,
  'Store link': 3,
  'Account': 4
};

Finder _navMotionKey(String kind, int slot) =>
    find.byKey(ValueKey('postdee-nav-icon-$kind-$slot'));

Finder _navMotionIndicator() =>
    find.byKey(const ValueKey('postdee-nav-selected-indicator'));

double _navMotionScale(WidgetTester tester, int slot,
        {bool selection = false}) =>
    tester
        .widget<Transform>(
            _navMotionKey(selection ? 'selection' : 'feedback', slot))
        .transform
        .entry(0, 0);

double _navMotionLift(WidgetTester tester, int slot) =>
    tester.widget<Transform>(_navMotionKey('lift', slot)).transform.entry(1, 3);

BoxDecoration _navMotionHalo(WidgetTester tester, int slot) =>
    tester.widget<DecoratedBox>(_navMotionKey('halo', slot)).decoration
        as BoxDecoration;

Color? _navMotionIconColor(WidgetTester tester, String label) => tester
    .widget<Icon>(find.descendant(
        of: _referenceNavButton(label), matching: find.byType(Icon)))
    .color;

void _expectNavMotionSelection(WidgetTester tester, String selected) {
  for (final entry in _navMotionTabs.entries) {
    final active = entry.key == selected;
    expect(_navMotionScale(tester, entry.value, selection: true),
        closeTo(active ? 1.08 : 1, .0001));
    expect(_navMotionLift(tester, entry.value), active ? -2 : 0);
    expect(_navMotionHalo(tester, entry.value).color!.a,
        closeTo(active ? .12 : 0, .0001));
    expect(_navMotionIconColor(tester, entry.key),
        active ? AppTheme.navActive : AppTheme.textSecondary);
  }
  expect(tester.getSize(_navMotionIndicator()), const Size(4, 4));
  expect(tester.getCenter(_navMotionIndicator()).dx,
      closeTo(tester.getCenter(_referenceNavButton(selected)).dx, .1));
}

void _resumeNavMotion(WidgetTester tester) {
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

class _NavMotionFixture {
  _NavMotionFixture({ThemeMode mode = ThemeMode.light}) {
    addTearDown(theme.dispose);
    addTearDown(() => AppTheme.applyThemeMode(ThemeMode.light));
    theme.setThemeMode(mode);
  }

  final language = _signInShell();
  final theme = PostDeeThemeController();
  final drafts = _ShellDraftStore();
  var calendarLoads = 0;
  var recentLoads = 0;
  var subscriptionLoads = 0;
  var videoPicks = 0;
  late final shell = PostDeeShell(
    languageController: language,
    themeController: theme,
    uploaderDraftStore: drafts,
    loadScheduledPosts: () async {
      calendarLoads++;
      return const [];
    },
    loadRecentPosts: () async {
      recentLoads++;
      return const [];
    },
    loadSocialConnections: () async => const [],
    loadSubscription: () async {
      subscriptionLoads++;
      return const SubscriptionStatusResult(
        userId: 'firebase-user-shell',
        plan: 'BASIC',
        status: 'INACTIVE',
        remainingPostsThisMonth: 3,
        monthlyPostLimit: 3,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false,
      );
    },
    pickVideo: () async {
      videoPicks++;
      return null;
    },
  );

  Widget app({
    bool reduced = false,
    bool ticker = true,
    TextDirection? direction,
    double? textScale,
  }) =>
      _shellApp(shell,
          disableAnimations: reduced,
          tickerEnabled: ticker,
          textDirection: direction,
          textScale: textScale);
}

void main() {
  testWidgets('bottom nav motion keeps all four selected halos finite and flat',
      (tester) async {
    final fixture = _NavMotionFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    for (final entry in _navMotionTabs.entries) {
      await tester.tap(_referenceNavButton(entry.key));
      await tester.pumpAndSettle();
      _expectNavMotionSelection(tester, entry.key);
      for (final slot in _navMotionTabs.values) {
        final halo = _navMotionHalo(tester, slot);
        expect(tester.getSize(_navMotionKey('halo', slot)), const Size(36, 36));
        expect(halo.shape, BoxShape.circle);
        expect(halo.boxShadow ?? const <BoxShadow>[], isEmpty);
        expect(halo.gradient, isNull);
        expect(_navMotionScale(tester, slot), 1);
        for (final transform in ['selection', 'feedback', 'lift']) {
          expect(
              tester
                  .widget<Transform>(_navMotionKey(transform, slot))
                  .transformHitTests,
              isFalse);
        }
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    }
    expect(fixture.drafts.drafts, isEmpty);
    expect(fixture.videoPicks, 0);
  });

  testWidgets(
      'bottom nav motion preserves semantics edge taps and cancellation',
      (tester) async {
    final fixture = _NavMotionFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    try {
      final calendar = _referenceNavButton('Calendar');
      final bounds = tester.getRect(calendar);
      final loads = fixture.calendarLoads;
      final gesture =
          await tester.startGesture(bounds.topLeft + const Offset(2, 40));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 90));
      expect(_navMotionScale(tester, 1), closeTo(.9, .0001));
      expect(tester.getRect(calendar), bounds);
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
      expect(fixture.calendarLoads, loads);
      expect(tester.getSemantics(calendar),
          isSemantics(label: 'Calendar', isButton: true, hasTapAction: true));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_navMotionScale(tester, 1), 1);
      expect(fixture.calendarLoads, loads);
      await tester.tapAt(bounds.bottomRight - const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(fixture.calendarLoads, loads + 1,
          reason: 'One native tap activates the existing calendar once.');
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
      expect(tester.getRect(calendar), bounds);
      _expectNavMotionSelection(tester, 'Calendar');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('bottom nav motion updates selection before the finite visual',
      (tester) async {
    final fixture = _NavMotionFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    try {
      await tester.tap(_referenceNavButton('Calendar'));
      await tester.pump();
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
      expect(tester.getSemantics(_referenceNavButton('Calendar')),
          isSemantics(isSelected: true, hasTapAction: true));
      expect(tester.getSemantics(_referenceNavButton('Home')),
          isSemantics(isSelected: false));
      await tester.pump(const Duration(milliseconds: 80));
      expect(_navMotionScale(tester, 1, selection: true),
          inExclusiveRange(1, 1.08));
      expect(_navMotionLift(tester, 1), inExclusiveRange(-2, 0));
      expect(_navMotionHalo(tester, 1).color!.a, inExclusiveRange(0, .12));
      expect(_navMotionIconColor(tester, 'Calendar'),
          isNot(AppTheme.textSecondary));
      expect(
          _navMotionIconColor(tester, 'Calendar'), isNot(AppTheme.navActive));
      expect(tester.getSize(_navMotionIndicator()).width, greaterThan(4));
      await tester.pumpAndSettle();
      _expectNavMotionSelection(tester, 'Calendar');
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'bottom nav motion rapid retarget keeps tab state and final target',
      (tester) async {
    final fixture = _NavMotionFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final home = tester.state(find.byType(HomeScreen));
    final calendar =
        tester.state(find.byType(CalendarScreen, skipOffstage: false));
    final profile =
        tester.state(find.byType(ProfileScreen, skipOffstage: false));
    await tester.tap(_referenceNavButton('Account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final interrupted = _navMotionScale(tester, 4, selection: true);
    final indicatorX = tester.getCenter(_navMotionIndicator()).dx;
    expect(interrupted, inExclusiveRange(1, 1.08));
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pump();
    expect(_navMotionScale(tester, 4, selection: true),
        closeTo(interrupted, .0001));
    expect(tester.getCenter(_navMotionIndicator()).dx, closeTo(indicatorX, .1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    _expectNavMotionSelection(tester, 'Home');
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(tester.state(find.byType(HomeScreen)), same(home));
    expect(tester.state(find.byType(CalendarScreen, skipOffstage: false)),
        same(calendar));
    expect(tester.state(find.byType(ProfileScreen, skipOffstage: false)),
        same(profile));
    for (final label in _navMotionTabs.keys) {
      expect(_referenceNavButton(label), findsOneWidget);
    }
    expect(find.byType(UploaderScreen), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom nav motion reduced start keeps static feedback usable',
      (tester) async {
    final fixture = _NavMotionFixture();
    await tester.pumpWidget(fixture.app(reduced: true));
    await tester.pumpAndSettle();
    final account = _referenceNavButton('Account');
    final gesture = await tester.startGesture(tester.getCenter(account));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 90));
    expect(_navMotionScale(tester, 4), 1);
    await gesture.up();
    await tester.pump();
    _expectNavMotionSelection(tester, 'Account');
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 5);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final block in ['reduced', 'ticker', 'background']) {
    testWidgets('bottom nav motion $block settles every in-flight feedback',
        (tester) async {
      addTearDown(() => _resumeNavMotion(tester));
      final fixture = _NavMotionFixture();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      final shellState = tester.state(find.byType(PostDeeShell));
      final create = _referenceNavButton('Create post');
      final createSurface =
          find.byKey(const ValueKey('postdee-nav-create-surface'));
      final createIdleWidth = tester.getRect(createSurface).width;
      await tester.tap(_referenceNavButton('Account'));
      await tester.pump();
      final ordinaryGesture = await tester.startGesture(
          tester.getCenter(_referenceNavButton('Calendar')),
          pointer: 31);
      final createGesture =
          await tester.startGesture(tester.getCenter(create), pointer: 32);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 90));
      expect(_navMotionScale(tester, 1), closeTo(.9, .0001));
      expect(tester.getRect(createSurface).width, lessThan(createIdleWidth));
      expect(_navMotionScale(tester, 4, selection: true),
          inExclusiveRange(1, 1.08));
      expect(tester.getSize(_navMotionIndicator()).width, greaterThan(4));
      if (block == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
        await tester.pump();
      } else {
        await tester.pumpWidget(fixture.app(
            reduced: block == 'reduced', ticker: block != 'ticker'));
      }
      _expectNavMotionSelection(tester, 'Account');
      expect(_navMotionScale(tester, 1), 1);
      expect(
          tester.getRect(createSurface).width, closeTo(createIdleWidth, .0001));
      expect(tester.state(find.byType(PostDeeShell)), same(shellState));
      expect(find.byType(UploaderScreen), findsNothing);
      await ordinaryGesture.cancel();
      await createGesture.cancel();
      if (block == 'background') {
        _resumeNavMotion(tester);
        await tester.pump();
      } else {
        await tester.pumpWidget(fixture.app());
      }
      await tester.pump(const Duration(milliseconds: 40));
      _expectNavMotionSelection(tester, 'Account');
      expect(_navMotionScale(tester, 1), 1);
      expect(
          tester.getRect(createSurface).width, closeTo(createIdleWidth, .0001));
      await tester.pumpAndSettle();
      expect(find.byType(UploaderScreen), findsNothing);
      expect(fixture.drafts.drafts, isEmpty);
      expect(fixture.videoPicks, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'bottom nav motion disposes held controls without stale callbacks',
      (tester) async {
    for (final label in ['Calendar', 'Create post']) {
      final fixture = _NavMotionFixture();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      final loads = fixture.calendarLoads;
      final gesture = await tester
          .startGesture(tester.getCenter(_referenceNavButton(label)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 90));
      if (label == 'Calendar') {
        expect(_navMotionScale(tester, 1), closeTo(.9, .0001));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(fixture.calendarLoads, loads);
      expect(fixture.drafts.drafts, isEmpty);
      expect(fixture.videoPicks, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('bottom nav motion keeps RTL and 2x text at 320dp in $mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _NavMotionFixture(mode: mode);
      await tester
          .pumpWidget(fixture.app(direction: TextDirection.rtl, textScale: 2));
      await tester.pumpAndSettle();
      final bounds = {
        for (final label in _navMotionTabs.keys)
          label: tester.getRect(_referenceNavButton(label)),
      };
      expect(
          bounds['Home']!.center.dx, greaterThan(bounds['Account']!.center.dx));
      for (final label in ['Account', 'Calendar', 'Store link', 'Home']) {
        await tester.tap(_referenceNavButton(label));
        await tester.pumpAndSettle();
        _expectNavMotionSelection(tester, label);
        for (final entry in bounds.entries) {
          expect(tester.getRect(_referenceNavButton(entry.key)), entry.value);
          expect(entry.value.width, greaterThanOrEqualTo(48));
          expect(entry.value.height, 84);
        }
        expect(tester.takeException(), isNull);
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('bottom nav motion keeps the center composer visually separate',
      (tester) async {
    final fixture = _NavMotionFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final create = _referenceNavButton('Create post');
    final surface = find.byKey(const ValueKey('postdee-nav-create-surface'));
    final bounds = tester.getRect(create);
    final width = tester.getRect(surface).width;
    for (final effect in ['feedback', 'selection', 'lift', 'halo']) {
      expect(_navMotionKey(effect, 2), findsNothing);
    }
    expect(find.descendant(of: create, matching: find.text('Create post')),
        findsNothing);
    expect(find.descendant(of: create, matching: _navMotionIndicator()),
        findsNothing);
    final decoration =
        tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;
    expect(decoration.color, AppTheme.accent);
    expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
    final gesture = await tester.startGesture(bounds.center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getRect(surface).width, closeTo(width * .9, .01));
    expect(tester.getRect(create), bounds);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen), findsOneWidget);
    expect(_referenceNav(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(tester.getRect(create), bounds);
    expect(tester.getRect(surface).width, closeTo(width, .01));
    _expectNavMotionSelection(tester, 'Home');
    expect(fixture.videoPicks, 0);
    expect(fixture.drafts.drafts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom nav motion created while paused resumes without replay',
      (tester) async {
    addTearDown(() => _resumeNavMotion(tester));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    final fixture = _NavMotionFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    _expectNavMotionSelection(tester, 'Home');
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resumeNavMotion(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    _expectNavMotionSelection(tester, 'Home');
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home create shares the guarded composer and awaits its return',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: languageController,
      uploaderDraftStore: _ShellDraftStore(),
      loadRecentPosts: () async => const [],
      loadScheduledPosts: () async => const [],
      loadSocialConnections: () async => const [],
    )));
    await tester.pumpAndSettle();
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    var returned = false;
    final first = home.onCreatePost!().then((_) => returned = true);
    unawaited(home.onCreatePost!());
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen), findsOneWidget);
    expect(returned, isFalse);
    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    await first;
    expect(returned, isTrue);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });

  testWidgets('Home resumes the persisted draft and excludes another owner',
      (tester) async {
    final languageController = _signInShell();
    final draftStore = _ShellDraftStore();
    final draft = PublishDraft(
      version: publishDraftManifestVersion,
      id: 'home-owned',
      ownerUserId: 'firebase-user-shell',
      submissionRequestId: 'submit_${List.filled(64, 'a').join()}',
      createdAt: DateTime.utc(2026, 10, 10),
      updatedAt: DateTime.utc(2026, 10, 11),
      videoPath: '/not-present/clip.mp4',
      videoName: 'clip.mp4',
      videoSizeBytes: 128,
      caption: 'ร่างที่บันทึกไว้',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: const {},
    );
    final otherDraft = PublishDraft(
      version: publishDraftManifestVersion,
      id: 'home-other',
      ownerUserId: 'other-owner',
      submissionRequestId: 'submit_${List.filled(64, 'b').join()}',
      createdAt: DateTime.utc(2026, 10, 10),
      updatedAt: DateTime.utc(2026, 10, 12),
      videoPath: '/not-present/other.mp4',
      videoName: 'other.mp4',
      videoSizeBytes: 128,
      caption: 'ข้อมูลบัญชีอื่น',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: const {},
    );
    draftStore.drafts.addAll({draft.id: draft, otherDraft.id: otherDraft});
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: languageController,
      uploaderDraftStore: draftStore,
      loadRecentPosts: () async => const [],
      loadScheduledPosts: () async => const [],
      loadSocialConnections: () async => const [],
    )));
    await tester.pumpAndSettle();
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    expect(await home.loadDrafts!(), [draft]);
    await home.onResumeDraft!(otherDraft);
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen), findsNothing);
    final resume = home.onResumeDraft!(draft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<UploaderScreen>(find.byType(UploaderScreen)).initialDraftId,
      draft.id,
    );
    expect(find.textContaining('ไม่พบวิดีโอของฉบับร่าง'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    await resume;
  });

  testWidgets('Home calendar action reuses the existing calendar tab',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: languageController,
      uploaderDraftStore: _ShellDraftStore(),
      loadRecentPosts: () async => const [],
      loadScheduledPosts: () async => const [],
      loadSocialConnections: () async => const [],
    )));
    await tester.pumpAndSettle();
    final calendarState = tester.state(
      find.byType(CalendarScreen, skipOffstage: false),
    );
    tester.widget<HomeScreen>(find.byType(HomeScreen)).onOpenCalendar!();
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    expect(tester.state(find.byType(CalendarScreen)), same(calendarState));
    expect(_referenceNav(), findsOneWidget);
  });

  testWidgets('Home connections action pauses Home and refreshes on return',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: languageController,
      uploaderDraftStore: _ShellDraftStore(),
      loadRecentPosts: () async => const [],
      loadScheduledPosts: () async => const [],
      loadSocialConnections: () async => const [],
    )));
    await tester.pumpAndSettle();
    tester.widget<HomeScreen>(find.byType(HomeScreen)).onOpenConnections!();
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionsScreen), findsOneWidget);
    expect(
      tester
          .widget<HomeScreen>(find.byType(HomeScreen, skipOffstage: false))
          .isActive,
      isFalse,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<HomeScreen>(find.byType(HomeScreen)).isActive, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home state is replaced when the signed-in owner changes',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: languageController,
      uploaderDraftStore: _ShellDraftStore(),
      loadRecentPosts: () async => const [],
      loadScheduledPosts: () async => const [],
      loadSocialConnections: () async => const [],
    )));
    await tester.pumpAndSettle();
    final previousState = tester.state(find.byType(HomeScreen));
    PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(userId: 'new-home-owner', idToken: 'new-token'),
    );
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(HomeScreen)), isNot(same(previousState)));
    expect(find.byKey(const ValueKey('home-new-home-owner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home upcoming loader excludes explicitly foreign-owned posts',
      (tester) async {
    final languageController = _signInShell();
    ScheduledPostResult scheduled(String id, String? owner) =>
        ScheduledPostResult(
          id: id,
          userId: owner,
          caption: id,
          videoS3Key: '$id.mp4',
          platforms: const ['YOUTUBE_SHORTS'],
          scheduledAt: DateTime.utc(2027, 1, 1),
          status: 'QUEUED',
          createdAt: DateTime.utc(2026, 10, 11),
        );
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: languageController,
      uploaderDraftStore: _ShellDraftStore(),
      loadRecentPosts: () async => const [],
      loadScheduledPosts: () async => [
        scheduled('mine', 'firebase-user-shell'),
        scheduled('foreign', 'other-owner'),
        scheduled('legacy', null),
      ],
      loadSocialConnections: () async => const [],
    )));
    await tester.pumpAndSettle();
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    final posts = await home.loadScheduledPosts!();
    expect(posts.map((post) => post.id), ['mine', 'legacy']);
    expect(find.text('foreign'), findsNothing);
  });

  for (final origin in ['Home', 'Account', 'Calendar']) {
    testWidgets(
        '$origin composer return refreshes only the visible package snapshot',
        (tester) async {
      final languageController = _signInShell();
      var isPro = true;
      var subscriptionLoads = 0;
      await tester.pumpWidget(_shellApp(PostDeeShell(
        languageController: languageController,
        uploaderDraftStore: _ShellDraftStore(),
        loadRecentPosts: () async => const [],
        loadScheduledPosts: () async => const [],
        loadSocialConnections: () async => const [],
        loadSubscription: () async {
          subscriptionLoads++;
          return SubscriptionStatusResult(
            userId: 'firebase-user-shell',
            plan: isPro ? 'PRO' : 'BASIC',
            status: isPro ? 'ACTIVE' : 'INACTIVE',
            monthlyPostLimit: isPro ? 250 : 3,
            remainingPostsThisMonth: isPro ? 250 : 0,
            canSchedule: isPro,
            canUseAiCaptions: isPro,
            canUseAnalytics: isPro,
          );
        },
      )));
      await tester.pumpAndSettle();
      final home = find.byType(HomeScreen, skipOffstage: false);
      final profile = find.byType(ProfileScreen, skipOffstage: false);
      final homeState = tester.state(home);
      final profileState = tester.state(profile);
      await tester.tap(_referenceNavButton(origin));
      await tester.pumpAndSettle();
      final loadsBeforeComposer = subscriptionLoads;
      await tester.tap(_referenceNavButton('Create post'));
      await tester.pumpAndSettle();
      expect(subscriptionLoads, loadsBeforeComposer);

      isPro = false;
      await tester.tap(find.byKey(const ValueKey('uploader-close')));
      await tester.pumpAndSettle();
      expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
      expect(tester.state(home), same(homeState));
      expect(tester.state(profile), same(profileState));
      expect(subscriptionLoads,
          loadsBeforeComposer + (origin == 'Calendar' ? 0 : 1));
      if (origin == 'Home') {
        expect(find.text('Free package'), findsOneWidget);
        expect(find.text('0/3 units left'), findsOneWidget);
        expect(find.text('Pro package'), findsNothing);
      } else if (origin == 'Account') {
        expect(find.byKey(const ValueKey('profile-plan-free')), findsOneWidget);
        expect(find.text('เหลือโพสต์ 0 / 3 หน่วยเดือนนี้'), findsOneWidget);
        expect(find.text('Pro package', skipOffstage: false), findsOneWidget);
      } else {
        expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
        expect(find.text('Pro package', skipOffstage: false), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'shares fresh package and quota across profile paywall returns and tab activation',
      (tester) async {
    final languageController = _signInShell();
    var backend = const SubscriptionStatusResult(
      userId: 'firebase-user-shell',
      plan: 'FREE',
      status: 'ACTIVE',
      monthlyPostLimit: 3,
      remainingPostsThisMonth: 0,
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );
    final loadedPlans = <String>[];
    await tester.pumpWidget(_shellApp(PostDeeShell(
      uploaderDraftStore: _ShellDraftStore(),
      languageController: languageController,
      loadRecentPosts: () async => const [],
      loadScheduledPosts: () async => const [],
      loadSocialConnections: () async => const [],
      loadSubscription: () async {
        loadedPlans.add(backend.plan);
        return backend;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Free package'), findsOneWidget);
    expect(find.text('0/3 units left'), findsOneWidget);

    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    final viewPlans = find.byKey(const ValueKey('profile-view-plans'));
    await tester.scrollUntilVisible(
      viewPlans,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-plan-free')), findsOneWidget);
    expect(find.text('เหลือโพสต์ 0 / 3 หน่วยเดือนนี้'), findsOneWidget);

    final loadsBeforePaywall = loadedPlans.length;
    await tester.tap(viewPlans);
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('paywall-subscription-error')), findsNothing);
    expect(loadedPlans.length, greaterThan(loadsBeforePaywall));
    backend = const SubscriptionStatusResult(
      userId: 'firebase-user-shell',
      plan: 'PRO',
      status: 'ACTIVE',
      monthlyPostLimit: 250,
      remainingPostsThisMonth: 247,
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-plan-pro')), findsOneWidget);
    expect(find.text('เหลือโพสต์ 247 / 250 หน่วยเดือนนี้'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-free')), findsNothing);

    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Pro package'), findsOneWidget);
    expect(find.text('247/250 units left'), findsOneWidget);

    backend = const SubscriptionStatusResult(
      userId: 'firebase-user-shell',
      plan: 'BASIC',
      status: 'ACTIVE',
      monthlyPostLimit: 3,
      remainingPostsThisMonth: 2,
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-plan-free')), findsOneWidget);
    expect(find.text('เหลือโพสต์ 2 / 3 หน่วยเดือนนี้'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-pro')), findsNothing);
    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Free package'), findsOneWidget);
    expect(find.text('2/3 units left'), findsOneWidget);
    expect(loadedPlans, containsAll(['FREE', 'PRO', 'BASIC']));
    expect(PostDeeAuthSessionStore.instance.session.stableUserId,
        'firebase-user-shell');
    expect(tester.takeException(), isNull);
  });

  testWidgets('email form provides safe password recovery feedback',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    PostDeeAuthSessionStore.instance.clear();
    final language =
        PostDeeLanguageController(initialLocale: const Locale('en'));
    addTearDown(language.dispose);
    final gateway = _ShellEmailRecoveryGateway();
    await tester.pumpWidget(_shellApp(PostDeeShell(
        uploaderDraftStore: _ShellDraftStore(),
        languageController: language,
        emailAuthGateway: gateway)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('login-email-sign-in')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, ' seller@example.com ');
    await tester.tap(find.byKey(const ValueKey('email-forgot-password')));
    await tester.pumpAndSettle();
    expect(gateway.resets, ['seller@example.com']);
    expect(find.textContaining('หากอีเมลนี้มีบัญชี'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('login legal links open the existing legal documents',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    PostDeeAuthSessionStore.instance.clear();
    final language =
        PostDeeLanguageController(initialLocale: const Locale('en'));
    addTearDown(language.dispose);
    await tester.pumpWidget(_shellApp(PostDeeShell(
        uploaderDraftStore: _ShellDraftStore(), languageController: language)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('login-terms')));
    await tester.tap(find.byKey(const ValueKey('login-terms')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LegalDocumentScreen>(find.byType(LegalDocumentScreen))
            .document,
        PostDeeLegalDocuments.termsOfService);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('login-privacy')));
    await tester.tap(find.byKey(const ValueKey('login-privacy')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LegalDocumentScreen>(find.byType(LegalDocumentScreen))
            .document,
        PostDeeLegalDocuments.privacyPolicy);
  });
  testWidgets('a fresh sign-in for the same owner rebuilds the shop screen', (tester) async {
    final language = _signInShell();
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: language, uploaderDraftStore: _ShellDraftStore())));
    await tester.pumpAndSettle();
    final shop = find.byType(LinkInBioScreen, skipOffstage: false);
    final before = tester.state(shop);
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(userId: 'firebase-user-shell', idToken: 'new-token'));
    await tester.pumpAndSettle();
    expect(identical(tester.state(shop), before), isFalse);
  });

  testWidgets('a late bell initialization cannot open notifications for a later account', (tester) async {
    final language = _signInShell();
    final ready = Completer<void>();
    final gateway = _FakePushMessagingGateway()..initialization = ready.future;
    await tester.pumpWidget(_shellApp(PostDeeShell(languageController: language,
      uploaderDraftStore: _ShellDraftStore(), pushMessagingGateway: gateway)));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Notifications'));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(userId: 'b', idToken: 'b'));
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('การแจ้งเตือน'), findsNothing);
  });

  testWidgets('account transitions clear the shared notification history', (tester) async {
    final language = _signInShell();
    await tester.pumpWidget(_shellApp(PostDeeShell(languageController: language,
      uploaderDraftStore: _ShellDraftStore())));
    await tester.pumpAndSettle();
    PostDeeNotificationCenter.instance.add(PostDeeNotification(title: 'private A', body: 'body', receivedAt: DateTime(2026)));
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(userId: 'b', idToken: 'b'));
    expect(PostDeeNotificationCenter.instance.items, isEmpty);
  });

  testWidgets('late account deletion cannot sign out a replacement account', (tester) async {
    final language = _signInShell();
    final deleted = Completer<void>();
    var cleanupCalls = 0;
    await tester.pumpWidget(_shellApp(PostDeeShell(languageController: language,
      uploaderDraftStore: _ShellDraftStore(),
      checkAccountDeletionReady: () async => true, deleteAccount: () => deleted.future,
      deleteLocalPublishDrafts: () async { cleanupCalls++; })));
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(button, 400, scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'ลบบัญชีถาวร')).onPressed!();
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(userId: 'b', idToken: 'b'));
    deleted.complete();
    await tester.pumpAndSettle();
    expect(PostDeeAuthSessionStore.instance.session.userId, 'b');
    expect(cleanupCalls, 0);
    expect(find.text('ลบบัญชีและออกจากระบบแล้ว'), findsNothing);
  });
  testWidgets('opens one full screen composer without a hidden uploader',
      (tester) async {
    final languageController = _signInShell();
    var connectionLoads = 0;
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          languageController: languageController,
          uploaderDraftStore: _ShellDraftStore(),
          loadSocialConnections: () async {
            connectionLoads += 1;
            return const [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
    expect(connectionLoads, 1,
        reason:
            'Home reads the connection summary without creating an uploader.');

    final createAction = tester
        .widget<Semantics>(
          _referenceNavButton('Create post'),
        )
        .properties
        .onTap!;
    createAction();
    createAction();
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen, skipOffstage: false), findsOneWidget);
    expect(_referenceNav(), findsNothing);
    expect(connectionLoads, 2,
        reason:
            'Only the visible composer makes an additional connection read.');
    expect(
      ModalRoute.of(tester.element(find.byType(UploaderScreen)))?.settings.name,
      '/create-post',
    );
    expect(find.byKey(const ValueKey('uploader-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });

  testWidgets('calendar hands immediate partial activity to detail without a fake schedule',
      (tester) async {
    final languageController = _signInShell();
    final now = DateTime.now();
    final post = CalendarPostResult(id: 'immediate-partial', caption: 'Immediate partial',
        userId: 'firebase-user-shell', videoS3Key: 'uploads/clip.mp4',
        platforms: const ['YOUTUBE_SHORTS'], status: 'PARTIAL_PUBLISHED',
        createdAt: now, publishedAt: now);
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: languageController,
      loadCalendarPosts: () async => [post],
      uploaderDraftStore: _ShellDraftStore(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    final calendar = tester.widget<CalendarScreen>(find.byType(CalendarScreen));
    calendar.onOpenCalendarPostDetail!(post);
    await tester.pumpAndSettle();
    final detail = tester.widget<PostDetailScreen>(find.byType(PostDetailScreen));
    expect(detail.post.id, post.id);
    expect(detail.post.scheduledAt, isNull);
    expect(detail.post.status, 'PARTIAL_PUBLISHED');
  });

  testWidgets('calendar starts the composer and returns to the same calendar',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          languageController: languageController,
          uploaderDraftStore: _ShellDraftStore(),
          loadScheduledPosts: () async => const [],
          loadSocialConnections: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    final calendarState = tester.state(find.byType(CalendarScreen));
    final calendar = tester.widget<CalendarScreen>(find.byType(CalendarScreen));
    calendar.onAddPost!();
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsNothing);
    expect(find.byType(UploaderScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    expect(tester.state(find.byType(CalendarScreen)), same(calendarState));
  });

  testWidgets('calendar passes the chosen date into a new composer',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(_shellApp(PostDeeShell(
      languageController: languageController,
      uploaderDraftStore: _ShellDraftStore(),
      loadScheduledPosts: () async => const [],
      loadSocialConnections: () async => const [],
    )));
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    final calendarState = tester.state(find.byType(CalendarScreen));
    final calendar = tester.widget<CalendarScreen>(find.byType(CalendarScreen));
    final today = DateTime.now();
    final chosen = DateTime(today.year, today.month, today.day + 3);
    calendar.onAddPostForDate!(chosen);
    await tester.pumpAndSettle();
    final uploader = tester.widget<UploaderScreen>(find.byType(UploaderScreen));
    expect(uploader.initialScheduleDate, chosen);
    expect(uploader.initialDraftId, isNull);
    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    expect(tester.state(find.byType(CalendarScreen)), same(calendarState));
  });

  testWidgets('composer callbacks close only their own active route',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          languageController: languageController,
          uploaderDraftStore: _ShellDraftStore(),
          loadSocialConnections: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    final oldUploader = tester.widget<UploaderScreen>(
      find.byType(UploaderScreen),
    );
    oldUploader.onPublishFinished!();
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    oldUploader.onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen), findsOneWidget);
    expect(_referenceNav(), findsNothing);
    final activeUploader = tester.widget<UploaderScreen>(
      find.byType(UploaderScreen),
    );
    activeUploader.onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
    expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('owner changes close ordinary private routes above the shell',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(
      _shellApp(PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController)),
    );
    await tester.pumpAndSettle();
    final profile = tester.widget<ProfileScreen>(
      find.byType(ProfileScreen, skipOffstage: false),
    );
    profile.onOpenTemplates();
    await tester.pumpAndSettle();
    expect(find.byType(TemplatesScreen), findsOneWidget);

    PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'refreshed-id-token',
        email: 'seller@example.com',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TemplatesScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(TemplatesScreen))).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Private child route')),
      ),
    );
    await tester.pumpAndSettle();
    PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(
        userId: 'different-shell-user',
        idToken: 'different-id-token',
        email: 'other@example.com',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TemplatesScreen, skipOffstage: false), findsNothing);
    expect(find.text('Private child route', skipOffstage: false), findsNothing);
    expect(_referenceNav(), findsOneWidget);
    expect(ModalRoute.of(tester.element(_referenceNav()))?.isFirst, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the signed-in owner closes the active composer',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          languageController: languageController,
          uploaderDraftStore: _ShellDraftStore(),
          loadSocialConnections: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    final oldUploader = tester.widget<UploaderScreen>(
      find.byType(UploaderScreen),
    );
    Navigator.of(tester.element(find.byType(UploaderScreen))).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Composer child route')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Composer child route'), findsOneWidget);
    PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(
        userId: 'different-shell-user',
        idToken: 'different-id-token',
        email: 'other@example.com',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
    expect(find.text('Composer child route'), findsNothing);
    expect(_referenceNav(), findsOneWidget);
    oldUploader.onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(_referenceNav(), findsOneWidget);
  });

  for (final width in const [360.0, 393.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets(
          'login actions fit ${width}dp with ${textScale}x accessibility text',
          (tester) async {
        SharedPreferences.setMockInitialValues({
          'postdee_onboarding_seen': true,
        });
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sessionStore = PostDeeAuthSessionStore.instance;
        final languageController = PostDeeLanguageController(
          initialLocale: const Locale('th'),
        );
        sessionStore.clear();
        addTearDown(sessionStore.clear);
        addTearDown(languageController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            locale: const Locale('th'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: PostDeeLocalizations.supportedLocales,
            home: PostDeeShell(
                uploaderDraftStore: _ShellDraftStore(),
                languageController: languageController),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
        final googleButton = find.ancestor(
          of: find.byKey(const ValueKey('google-sign-in-logo')),
          matching: find.byType(FilledButton),
        );
        expect(tester.getSize(googleButton).height, greaterThanOrEqualTo(54));
        expect(tester.takeException(), isNull);

        final scrollable = find.byType(SingleChildScrollView);
        for (var attempt = 0; attempt < 8; attempt += 1) {
          await tester.drag(scrollable, const Offset(0, -260));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('เข้าสู่ระบบด้วยอีเมล'), findsOneWidget);
      });
    }
  }

  testWidgets('requests notification permission only after tapping the bell',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    final pushGateway = _FakePushMessagingGateway();
    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController,
          pushMessagingGateway: pushGateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(pushGateway.initializeCalls, 0);
    await tester.tap(find.bySemanticsLabel('Notifications'));
    await tester.pumpAndSettle();
    expect(pushGateway.initializeCalls, 1);
    expect(find.text('การแจ้งเตือน'), findsOneWidget);
  });

  testWidgets('opens the email sign-in form from the login gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    sessionStore.clear();
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    final brandMark = tester.widget<Image>(
      find.byKey(const ValueKey('login-brand-mark')),
    );
    expect(
      (brandMark.image as AssetImage).assetName,
      'assets/images/brand/postdee_mark.png',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('login-brand-mark-box'))),
      const Size.square(64),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('login-brand-gap'))).width,
      4,
    );

    await tester.tap(find.byKey(const ValueKey('login-email-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('email-sign-in-form')), findsOneWidget);
  });

  testWidgets('uses docked bottom navigation in the approved tab order',
      (tester) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomNavigationBar), findsNothing);
    final referenceNav =
        find.byKey(const ValueKey('postdee-reference-bottom-nav'));
    expect(referenceNav, findsOneWidget);
    for (final label in [
      'Home',
      'Calendar',
      'Create post',
      'Store link',
      'Account'
    ]) {
      expect(
        find.descendant(
          of: referenceNav,
          matching: find.bySemanticsLabel(label),
        ),
        findsOneWidget,
      );
    }

    final homeX = tester.getCenter(_referenceNavButton('Home')).dx;
    final storeLinkX = tester.getCenter(_referenceNavButton('Store link')).dx;
    final createX = tester.getCenter(_referenceNavButton('Create post')).dx;
    final calendarX = tester.getCenter(_referenceNavButton('Calendar')).dx;
    final accountX = tester.getCenter(_referenceNavButton('Account')).dx;
    expect(homeX, lessThan(calendarX));
    expect(calendarX, lessThan(createX));
    expect(createX, lessThan(storeLinkX));
    expect(storeLinkX, lessThan(accountX));

    final createButton = _referenceNavButton('Create post');
    expect(
      find.descendant(of: referenceNav, matching: find.text('Create post')),
      findsNothing,
      reason: 'The center upload action is icon-only in the approved design.',
    );
    expect(
      tester
          .widget<Tooltip>(find.descendant(
            of: createButton,
            matching: find.byType(Tooltip),
          ))
          .message,
      'Create post',
      reason: 'The unlabeled action keeps its accessible name and tooltip.',
    );
    expect(
      find.descendant(
        of: createButton,
        matching: find.byIcon(Icons.ios_share_outlined),
      ),
      findsOneWidget,
      reason:
          'Create post starts by uploading a video, so use the upload icon.',
    );
    expect(
      find.ancestor(
        of: createButton,
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
      reason: 'The circular create button must not be clipped by the nav.',
    );

    final navSurface = tester.widget<Material>(
      find.byKey(const ValueKey('postdee-nav-surface')),
    );
    expect(navSurface.color, AppTheme.navSurface);
    expect(navSurface.color!.a, 1);
    expect(navSurface.elevation, 0);
    final surfaceRect = tester.getRect(
      find.byKey(const ValueKey('postdee-nav-surface')),
    );
    final viewportSize =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    final bottomSafeArea =
        tester.view.padding.bottom / tester.view.devicePixelRatio;
    expect(surfaceRect.left, 0);
    expect(surfaceRect.right, viewportSize.width);
    expect(surfaceRect.bottom, viewportSize.height);
    expect(
      tester.getBottomLeft(_referenceNavButton('Home')).dy,
      surfaceRect.bottom - bottomSafeArea,
      reason: 'The opaque surface fills the bottom safe area as well.',
    );
    final outerNav = tester.widget(referenceNav);
    if (outerNav is DecoratedBox && outerNav.decoration is BoxDecoration) {
      expect(
        (outerNav.decoration as BoxDecoration).boxShadow ?? const <BoxShadow>[],
        isEmpty,
      );
    }
    for (final decoratedBox in tester.widgetList<DecoratedBox>(
      find.descendant(of: referenceNav, matching: find.byType(DecoratedBox)),
    )) {
      if (decoratedBox.decoration case final BoxDecoration decoration) {
        expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
      }
    }
    expect(
      find.descendant(of: referenceNav, matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: 'The approved bar has an opaque surface instead of blur.',
    );

    final createSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('postdee-nav-create-surface')),
    );
    final createDecoration = createSurface.decoration as BoxDecoration;
    expect(createDecoration.shape, BoxShape.circle);
    expect(createDecoration.color, AppTheme.accent);
    expect(createDecoration.gradient, isNull);
    expect(createDecoration.boxShadow ?? const <BoxShadow>[], isEmpty);
    final navRect = tester.getRect(referenceNav);
    final createRect = tester.getRect(
      find.byKey(const ValueKey('postdee-nav-create-surface')),
    );
    expect(navRect.contains(createRect.topLeft), isTrue);
    expect(navRect.contains(createRect.bottomRight), isTrue);

    const tabIndices = {
      'Home': 0,
      'Calendar': 3,
      'Store link': 1,
      'Account': 5,
    };
    final selectedIndicator =
        find.byKey(const ValueKey('postdee-nav-selected-indicator'));
    for (final currentTab in tabIndices.entries) {
      await tester.tap(_referenceNavButton(currentTab.key));
      await tester.pumpAndSettle();

      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
          currentTab.value);
      expect(selectedIndicator, findsOneWidget);
      for (final label in [...tabIndices.keys, 'Create post']) {
        final button = _referenceNavButton(label);
        expect(
          tester.getSemantics(button),
          isSemantics(
            label: label,
            isButton: true,
            hasTapAction: true,
            isSelected: label == currentTab.key,
            hasSelectedState: true,
          ),
        );
      }
      expect(tester.getSize(selectedIndicator), const Size(4, 4));
      expect(
        tester.getCenter(selectedIndicator).dx,
        closeTo(tester.getCenter(_referenceNavButton(currentTab.key)).dx, 0.1),
        reason: 'The shared running dot settles beneath the selected tab.',
      );
      expect(
        find.descendant(
          of: _referenceNavButton('Create post'),
          matching: selectedIndicator,
        ),
        findsNothing,
        reason: 'The center composer action has no selection dot.',
      );
    }

    // Publishing can still open Analytics, which is not one of the five nav
    // destinations. It must not incorrectly mark another destination selected.
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsNothing);
    final uploader = tester.widget<UploaderScreen>(
      find.byType(UploaderScreen),
    );
    expect(uploader.onViewAnalytics, isNotNull);
    uploader.onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
    expect(_referenceNav(), findsOneWidget);
    expect(selectedIndicator, findsNothing);
    for (final label in [...tabIndices.keys, 'Create post']) {
      expect(
        tester.getSemantics(_referenceNavButton(label)),
        isSemantics(isSelected: false),
      );
    }
    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(selectedIndicator, findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
      'running dot slides and stretches before settling on the selected tab',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _shellApp(PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: _signInShell())),
    );
    await tester.pumpAndSettle();
    final indicator =
        find.byKey(const ValueKey('postdee-nav-selected-indicator'));
    final homeX = tester.getCenter(_referenceNavButton('Home')).dx;
    final calendarX = tester.getCenter(_referenceNavButton('Calendar')).dx;
    expect(tester.getSize(indicator), const Size(4, 4));
    expect(tester.getCenter(indicator).dx, closeTo(homeX, 0.1));

    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final movingRect = tester.getRect(indicator);
    expect(movingRect.center.dx, greaterThan(homeX));
    expect(movingRect.center.dx, lessThan(calendarX));
    expect(movingRect.width, greaterThan(4));
    expect(movingRect.height, 4);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    expect(
      tester.getSemantics(_referenceNavButton('Calendar')),
      isSemantics(isSelected: true),
      reason: 'The page and accessibility state update before motion finishes.',
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(indicator), const Size(4, 4));
    expect(tester.getCenter(indicator).dx, closeTo(calendarX, 0.1));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'running dot retargets rapid taps without jumping or selecting an old tab',
      (tester) async {
    await tester.pumpWidget(
      _shellApp(PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: _signInShell())),
    );
    await tester.pumpAndSettle();
    final indicator =
        find.byKey(const ValueKey('postdee-nav-selected-indicator'));
    await tester.tap(_referenceNavButton('Account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final interruptedX = tester.getCenter(indicator).dx;

    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pump();
    expect(tester.getCenter(indicator).dx, closeTo(interruptedX, 0.1));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();

    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(tester.getSize(indicator), const Size(4, 4));
    expect(
      tester.getCenter(indicator).dx,
      closeTo(tester.getCenter(_referenceNavButton('Home')).dx, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'running dot stays absent in the composer and Analytics then returns',
      (tester) async {
    await tester.pumpWidget(
      _shellApp(PostDeeShell(
        languageController: _signInShell(),
        uploaderDraftStore: _ShellDraftStore(),
        loadSocialConnections: () async => const [],
      )),
    );
    await tester.pumpAndSettle();
    final indicator =
        find.byKey(const ValueKey('postdee-nav-selected-indicator'));
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsNothing);
    expect(indicator, findsNothing);

    tester
        .widget<UploaderScreen>(find.byType(UploaderScreen))
        .onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
    expect(indicator, findsNothing);
    await tester.tap(_referenceNavButton('Store link'));
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator), const Size(4, 4));
    expect(
      tester.getCenter(indicator).dx,
      closeTo(tester.getCenter(_referenceNavButton('Store link')).dx, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('running dot updates immediately when animations are disabled',
      (tester) async {
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: _signInShell()),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    final indicator =
        find.byKey(const ValueKey('postdee-nav-selected-indicator'));
    await tester.tap(_referenceNavButton('Account'));
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 5);
    expect(tester.getSize(indicator), const Size(4, 4));
    expect(
      tester.getCenter(indicator).dx,
      closeTo(tester.getCenter(_referenceNavButton('Account')).dx, 0.1),
    );
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.getSize(indicator), const Size(4, 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('running dot stops when reduced motion is enabled mid-flight',
      (tester) async {
    final shell = PostDeeShell(
        uploaderDraftStore: _ShellDraftStore(),
        languageController: _signInShell());
    await tester.pumpWidget(_shellApp(shell));
    await tester.pumpAndSettle();
    final indicator =
        find.byKey(const ValueKey('postdee-nav-selected-indicator'));
    await tester.tap(_referenceNavButton('Account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(indicator).width, greaterThan(4));

    await tester.pumpWidget(_shellApp(shell, disableAnimations: true));
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 5);
    expect(tester.getSize(indicator), const Size(4, 4));
    final accountX = tester.getCenter(_referenceNavButton('Account')).dx;
    expect(tester.getCenter(indicator).dx, closeTo(accountX, 0.1));
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.getSize(indicator), const Size(4, 4));
    expect(tester.getCenter(indicator).dx, closeTo(accountX, 0.1));

    await tester.pumpWidget(_shellApp(shell));
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(indicator).width, greaterThan(4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    expect(tester.getSize(indicator), const Size(4, 4));
    expect(
      tester.getCenter(indicator).dx,
      closeTo(tester.getCenter(_referenceNavButton('Calendar')).dx, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('running dot aligns with RTL tabs at 320dp and 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: _signInShell()),
        textDirection: TextDirection.rtl,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    final indicator =
        find.byKey(const ValueKey('postdee-nav-selected-indicator'));
    expect(
      tester.getCenter(_referenceNavButton('Home')).dx,
      greaterThan(tester.getCenter(_referenceNavButton('Account')).dx),
    );
    for (final label in ['Home', 'Account', 'Home']) {
      await tester.tap(_referenceNavButton(label));
      await tester.pumpAndSettle();
      expect(tester.getSize(indicator), const Size(4, 4));
      expect(
        tester.getCenter(indicator).dx,
        closeTo(tester.getCenter(_referenceNavButton(label)).dx, 0.1),
      );
      expect(tester.getSize(_referenceNavButton(label)).width,
          greaterThanOrEqualTo(48));
      expect(tester.getSize(_referenceNavButton(label)).height,
          greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    }
  });

  for (final disableAnimations in [false, true]) {
    testWidgets(
        'create action keeps its tap target and honors reduced motion $disableAnimations',
        (tester) async {
      await tester.pumpWidget(
        _shellApp(
          PostDeeShell(
            languageController: _signInShell(),
            uploaderDraftStore: _ShellDraftStore(),
            loadSocialConnections: () async => const [],
          ),
          disableAnimations: disableAnimations,
        ),
      );
      await tester.pumpAndSettle();
      final createButton = _referenceNavButton('Create post');
      final createSurface =
          find.byKey(const ValueKey('postdee-nav-create-surface'));
      final hitRect = tester.getRect(createButton);
      final idleWidth = tester.getRect(createSurface).width;
      expect(hitRect.width, greaterThanOrEqualTo(48));
      expect(hitRect.height, greaterThanOrEqualTo(48));
      final gesture = await tester.startGesture(hitRect.center);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getRect(createButton), hitRect);
      expect(find.byType(UploaderScreen), findsNothing);
      if (disableAnimations) {
        expect(tester.getRect(createSurface).width, idleWidth);
      } else {
        expect(tester.getRect(createSurface).width, lessThan(idleWidth));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(UploaderScreen), findsOneWidget);
      expect(_referenceNav(), findsNothing);

      await tester.tap(find.byKey(const ValueKey('uploader-close')));
      await tester.pumpAndSettle();
      expect(tester.getRect(createSurface).width, closeTo(idleWidth, 0.1));
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
      expect(
        find.descendant(
          of: createButton,
          matching:
              find.byKey(const ValueKey('postdee-nav-selected-indicator')),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'opens profile links from home and nav while keeping navigation visible',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    expect(_referenceNav(), findsOneWidget);
    final linkShortcut =
        find.byKey(const ValueKey('home-link-in-bio-shortcut'));
    await tester.ensureVisible(linkShortcut);
    await tester.tap(linkShortcut);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('link-in-bio-back')), findsOneWidget);
    expect(_referenceNav(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-advanced-toggle')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-duration-slider')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('link-in-bio-back')));
    await tester.pumpAndSettle();

    expect(_referenceNav(), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-editing-back')), findsNothing);
    expect(linkShortcut, findsOneWidget);
    await tester.tap(_referenceNavButton('Store link'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-in-bio-back')), findsOneWidget);
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-back')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-back')), findsOneWidget);
  });

  testWidgets('opens profile from the reference bottom navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    expect(_referenceNavButton('Account'), findsOneWidget);
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();

    // Profile is now a tab, so its content shows with the nav still visible.
    expect(find.text('บัญชีและโปรไฟล์'), findsOneWidget);
    expect(find.text('PostDee Seller'), findsOneWidget);
    expect(_referenceNavButton('Account'), findsOneWidget);
  });

  testWidgets('deletes the account then returns to the login gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    const ownerDrafts = SharedPreferencesLinkInBioDraftStore(
      ownerUserId: 'firebase-user-shell',
    );
    const otherDrafts = SharedPreferencesLinkInBioDraftStore(
      ownerUserId: 'another-user',
    );
    await ownerDrafts.saveDraft(LinkInBioDraft.defaults());
    await otherDrafts.saveDraft(LinkInBioDraft.defaults());

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var deleteCalls = 0;
    final deletionCalls = <String>[];

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    const styleStore = SharedPreferencesCaptionWritingStyleStore();
    await styleStore.save(
      'firebase-user-shell',
      const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(tone: CaptionWritingTone.friendly),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    const ownerStyleKey =
        'postdee.caption_writing_style.v1.firebase-user-shell';
    const otherStyleKey = 'postdee.caption_writing_style.v1.another-user';
    final otherStyle = jsonEncode(
      const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(tone: CaptionWritingTone.playful),
      ).toJson(),
    );
    await preferences.setString(otherStyleKey, otherStyle);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController,
          checkAccountDeletionReady: () async {
            deletionCalls.add('ready');
            return false;
          },
          accountAccessRevoker: _RecordingAccountAccessRevoker(deletionCalls),
          deleteAccount: () async {
            deleteCalls += 1;
            deletionCalls.add('delete');
          },
          loadLocalPublishDraftDeleter: () async {
            deletionCalls.add('capture-local-drafts');
            return () async {
              deletionCalls.add('local-drafts');
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();

    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(deleteCalls, 1);
    expect(await ownerDrafts.loadDraft(), isNull);
    expect(await otherDrafts.loadDraft(), isNotNull);
    expect(preferences.getString(ownerStyleKey), isNull);
    expect(preferences.getString(otherStyleKey), otherStyle);
    expect(deletionCalls, [
      'capture-local-drafts',
      'ready',
      'revoke',
      'delete',
      'local-drafts',
    ]);
    // Back on the login gate after the account is removed.
    expect(find.text('Sign in to PostDee'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('postdee-undo-toast')),
      findsOneWidget,
    );
    final toastRect = tester.getRect(
      find.byKey(const ValueKey('postdee-undo-toast')),
    );
    final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(toastRect.width, greaterThan(0));
    expect(toastRect.height, greaterThan(0));
    expect(toastRect.left, greaterThanOrEqualTo(0));
    expect(toastRect.top, greaterThanOrEqualTo(0));
    expect(toastRect.right, lessThanOrEqualTo(viewSize.width));
    expect(toastRect.bottom, lessThanOrEqualTo(viewSize.height));
    final toast = tester.widget<SnackBar>(
      find.byKey(const ValueKey('postdee-undo-toast')),
    );
    expect(toast.behavior, SnackBarBehavior.floating);
    expect(toast.action, isNull);
    expect(find.text('ลบบัญชีและออกจากระบบแล้ว'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('เลิกทำ'), findsNothing);
  });

  testWidgets(
    'still signs out and warns when local draft cleanup cannot finish',
    (tester) async {
      SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

      final sessionStore = PostDeeAuthSessionStore.instance;
      final languageController = PostDeeLanguageController(
        initialLocale: const Locale('en'),
      );
      sessionStore.signIn(
        const AuthSession(
          userId: 'firebase-user-shell',
          idToken: 'firebase-id-token',
          email: 'seller@example.com',
          displayName: 'PostDee Seller',
        ),
      );
      addTearDown(sessionStore.clear);
      addTearDown(languageController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('en'),
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: PostDeeLocalizations.supportedLocales,
          home: PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: languageController,
            checkAccountDeletionReady: () async => true,
            deleteAccount: () async {},
            deleteLocalPublishDrafts: () async {
              throw const FileSystemException('disk unavailable');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_referenceNavButton('Account'));
      await tester.pumpAndSettle();
      final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
      await tester.scrollUntilVisible(
        deleteButton,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
          )
          .onPressed!();
      await tester.pumpAndSettle();

      expect(find.text('Sign in to PostDee'), findsOneWidget);
      expect(
        find.text(
          'ลบบัญชีแล้ว แต่ลบข้อมูลในเครื่องไม่ครบ กรุณาล้างข้อมูลแอป',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('preserves caption styles when remote account deletion fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);
    const styleStore = SharedPreferencesCaptionWritingStyleStore();
    await styleStore.save(
      'firebase-user-shell',
      const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(tone: CaptionWritingTone.friendly),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    const otherStyleKey = 'postdee.caption_writing_style.v1.another-user';
    final otherStyle = jsonEncode(
      const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(tone: CaptionWritingTone.playful),
      ).toJson(),
    );
    await preferences.setString(otherStyleKey, otherStyle);
    var localCleanupCalls = 0;

    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController,
          checkAccountDeletionReady: () async => true,
          deleteAccount: () async => throw const ApiException(
            'remote cleanup failed',
            statusCode: 503,
            code: 'ACCOUNT_MEDIA_CLEANUP_FAILED',
          ),
          deleteLocalPublishDrafts: () async {
            localCleanupCalls += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(sessionStore.session.stableUserId, 'firebase-user-shell');
    expect(localCleanupCalls, 0);
    expect(
      (await styleStore.load('firebase-user-shell')).style.tone,
      CaptionWritingTone.friendly,
    );
    expect(preferences.getString(otherStyleKey), otherStyle);
    expect(
      find.text('ลบวิดีโอยังไม่สำเร็จ บัญชีของคุณยังอยู่ กรุณาลองใหม่'),
      findsOneWidget,
    );
  });

  testWidgets('retries deletion without revoking Apple when identity is gone',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    final deletionCalls = <String>[];
    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController,
          checkAccountDeletionReady: () async {
            deletionCalls.add('ready');
            return true;
          },
          accountAccessRevoker: _RecordingAccountAccessRevoker(deletionCalls),
          deleteAccount: () async => deletionCalls.add('delete'),
          deleteLocalPublishDrafts: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(deletionCalls, ['ready', 'delete']);
    expect(find.text('Sign in to PostDee'), findsOneWidget);
  });

  for (final code in [
    'ACCOUNT_DELETION_UNAVAILABLE',
    'ACCOUNT_REAUTHENTICATION_REQUIRED',
    'ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE',
  ]) {
    testWidgets(
        'does not revoke Apple access when deletion preflight fails: $code',
        (tester) async {
      SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
      final sessionStore = PostDeeAuthSessionStore.instance;
      final languageController = PostDeeLanguageController(
        initialLocale: const Locale('en'),
      );
      final deletionCalls = <String>[];
      sessionStore.signIn(
        const AuthSession(
          userId: 'firebase-user-shell',
          idToken: 'firebase-id-token',
          email: 'seller@example.com',
        ),
      );
      addTearDown(sessionStore.clear);
      addTearDown(languageController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('en'),
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: PostDeeLocalizations.supportedLocales,
          home: PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: languageController,
            checkAccountDeletionReady: () async {
              deletionCalls.add('ready');
              throw ApiException(
                'unavailable',
                statusCode:
                    code == 'ACCOUNT_REAUTHENTICATION_REQUIRED' ? 403 : 503,
                code: code,
              );
            },
            accountAccessRevoker: _RecordingAccountAccessRevoker(deletionCalls),
            deleteAccount: () async => deletionCalls.add('delete'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_referenceNavButton('Account'));
      await tester.pumpAndSettle();
      final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
      await tester.scrollUntilVisible(
        deleteButton,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
          )
          .onPressed!();
      await tester.pumpAndSettle();

      expect(deletionCalls, ['ready']);
      expect(sessionStore.session.isSignedIn, isTrue);
      if (code == 'ACCOUNT_DELETION_UNAVAILABLE') {
        expect(find.text('ระบบลบบัญชียังไม่พร้อม กรุณาลองใหม่ภายหลัง'),
            findsOneWidget);
      }
    });
  }

  testWidgets('explains how to reauthenticate before retrying deletion',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController,
          checkAccountDeletionReady: () async => false,
          accountAccessRevoker: _RecordingAccountAccessRevoker(<String>[]),
          deleteAccount: () async => throw const ApiException(
            'reauthentication required',
            statusCode: 401,
            code: 'ACCOUNT_REAUTHENTICATION_REQUIRED',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(
      find.text(
        'กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ จากนั้นลบบัญชีภายใน 5 นาที',
      ),
      findsOneWidget,
    );
    expect(sessionStore.session.isSignedIn, isTrue);
  });

  testWidgets('keeps reference bottom nav buttons touch-friendly',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    final homeSize = tester.getSize(_referenceNavButton('Home'));
    final createSize = tester.getSize(_referenceNavButton('Create post'));
    final profileSize = tester.getSize(_referenceNavButton('Account'));

    expect(homeSize.width, greaterThanOrEqualTo(44));
    expect(homeSize.height, greaterThanOrEqualTo(44));
    expect(createSize.width, greaterThanOrEqualTo(44));
    expect(createSize.height, greaterThanOrEqualTo(44));
    expect(profileSize.width, greaterThanOrEqualTo(44));
    expect(profileSize.height, greaterThanOrEqualTo(44));
  });

  for (final width in const [360.0, 393.0, 411.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets(
          'shows Thai bottom nav labels at ${width}dp with ${textScale}x text',
          (tester) async {
        SharedPreferences.setMockInitialValues({
          'postdee_onboarding_seen': true,
        });
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sessionStore = PostDeeAuthSessionStore.instance;
        final languageController = PostDeeLanguageController(
          initialLocale: const Locale('th'),
        );
        sessionStore.signIn(
          const AuthSession(
            userId: 'firebase-user-shell',
            idToken: 'firebase-id-token',
            email: 'seller@example.com',
            displayName: 'PostDee Seller',
          ),
        );
        addTearDown(sessionStore.clear);
        addTearDown(languageController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            locale: const Locale('th'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: PostDeeLocalizations.supportedLocales,
            home: PostDeeShell(
                uploaderDraftStore: _ShellDraftStore(),
                languageController: languageController),
          ),
        );
        await tester.pumpAndSettle();

        final navRect = tester.getRect(_referenceNav());
        for (final label in const [
          'หน้าหลัก',
          'ปฏิทิน',
          'สร้างโพสต์',
          'ลิงก์ร้าน',
          'บัญชี',
        ]) {
          final button = _referenceNavButton(label);
          expect(button, findsOneWidget);
          final buttonRect = tester.getRect(button);
          expect(buttonRect.width, greaterThanOrEqualTo(44));
          expect(buttonRect.height, greaterThanOrEqualTo(44));
          final visibleLabel = find.descendant(
            of: _referenceNav(),
            matching: find.text(label),
          );
          if (label == 'สร้างโพสต์') {
            expect(visibleLabel, findsNothing);
            continue;
          }
          expect(visibleLabel, findsOneWidget);
          final labelRect = tester.getRect(visibleLabel);
          expect(labelRect.left, greaterThanOrEqualTo(navRect.left));
          expect(labelRect.right, lessThanOrEqualTo(navRect.right));
          expect(labelRect.top, greaterThanOrEqualTo(navRect.top));
          expect(labelRect.bottom, lessThanOrEqualTo(navRect.bottom));
          expect(labelRect.left, greaterThanOrEqualTo(buttonRect.left));
          expect(labelRect.right, lessThanOrEqualTo(buttonRect.right));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('opens and refreshes calendar after a scheduled post succeeds',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var calendarLoadCount = 0;
    CreatePostRequest? createdPostRequest;
    var scheduledPosts = <ScheduledPostResult>[];
    var preparationCalls = 0;
    final tempDirectory = Directory.systemTemp.createTempSync(
      'postdee-shell-upload-',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final videoFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}scheduled-shell.mp4',
    )..writeAsBytesSync([1, 2, 3, 4]);

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          loadSocialConnections: () async => const [
            SocialConnectionResult(
              platform: 'TIKTOK',
              connected: true,
              externalAccountId: 'tiktok-seller',
            ),
          ],
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller-pro',
            plan: 'PRO',
            status: 'ACTIVE',
            phoneVerified: true,
            requiresPhoneVerification: false,
            canUseFreePostQuota: false,
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
          pickVideo: () async => PickedVideoFile(
            name: 'scheduled-shell.mp4',
            path: videoFile.path,
            sizeBytes: videoFile.lengthSync(),
            width: 1080,
            height: 1920,
          ),
          prepareTikTokVideo: (request) async {
            preparationCalls++;
            expect(request.inputFile.path, videoFile.path);
            return testPrepareTikTokVideo(request);
          },
          createUpload: (request) async {
            expect(preparationCalls, 1);
            expect(request.width, 1080);
            expect(request.height, 1920);
            return const UploadResult(
              id: 'upload-1',
              videoS3Key: 'uploads/scheduled-shell.mp4',
              storageProvider: 'mock',
            );
          },
          uploadVideoFile: (_, __) async {},
          checkPublishingReadiness: () async {},
          createPost: (request) async {
            createdPostRequest = request;
            scheduledPosts = [
              ScheduledPostResult(
                id: 'post-shell',
                caption: 'Scheduled shell clip',
                videoS3Key: request.videoS3Key,
                platforms: request.platforms,
                scheduledAt: request.scheduledAt!,
                status: 'QUEUED',
                createdAt: DateTime(2026, 6, 1),
              ),
            ];

            return QueuedPostResult(
              id: 'post-shell',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'QUEUED',
            );
          },
          uploaderDraftStore: _ShellDraftStore(),
          loadScheduledPosts: () async {
            calendarLoadCount += 1;
            return scheduledPosts;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    final pickVideoButton =
        find.byKey(const ValueKey('uploader-video-preview-picker'));
    await tester.ensureVisible(pickVideoButton);
    await tester.pumpAndSettle();
    await tester.tap(pickVideoButton);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();
    final captionField = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.enterText(captionField, 'Scheduled shell clip');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();

    final selectAll =
        find.byKey(const ValueKey('uploader-select-all-platforms'));
    await tester.scrollUntilVisible(
      selectAll,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();

    final scheduleButton =
        find.byKey(const ValueKey('uploader-schedule-later'));
    await tester.scrollUntilVisible(
      scheduleButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pumpAndSettle();

    expect(createdPostRequest?.scheduledAt, isNotNull);
    expect(preparationCalls, 1);
    expect(find.text('จัดคิวส่งตามเวลาแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('publish-flow-finish')));
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();

    expect(calendarLoadCount, greaterThanOrEqualTo(2));
    expect(find.text('Scheduled shell clip'), findsOneWidget);
  });

  testWidgets('refreshes calendar whenever the user returns to its tab',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var calendarLoadCount = 0;

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController,
          loadScheduledPosts: () async {
            calendarLoadCount += 1;
            return const [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Home reads its next-post summary. The inactive calendar adds no read.
    expect(calendarLoadCount, 1);

    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    expect(calendarLoadCount, 2);

    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    expect(calendarLoadCount, 3,
        reason: 'Only the reactivated Home refreshes its next-post summary.');
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    expect(calendarLoadCount, 4);
  });

  testWidgets('opens published calendar posts in the detail screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    final today = DateTime.now();
    final publishedAt = DateTime(today.year, today.month, today.day, 19, 25);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController,
          loadScheduledPosts: () async => [
            ScheduledPostResult(
              id: 'published-calendar-post',
              caption: 'Published calendar clip',
              videoS3Key: 'uploads/published.mp4',
              platforms: const ['YOUTUBE_SHORTS'],
              scheduledAt: publishedAt,
              publishedAt: publishedAt,
              status: 'PUBLISHED',
              createdAt: publishedAt.subtract(const Duration(minutes: 10)),
              platformResults: [
                PostPlatformResult(
                  postId: 'published-calendar-post',
                  platform: 'YOUTUBE_SHORTS',
                  status: 'PUBLISHED',
                  externalPostId: 'https://youtube.example/private-video',
                  publishedAt: publishedAt,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Published calendar clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Published calendar clip'));
    await tester.pumpAndSettle();

    expect(find.text('รายละเอียดโพสต์'), findsOneWidget);
    expect(find.text('เผยแพร่สำเร็จ'), findsOneWidget);
  });

  testWidgets('refreshes latest home posts whenever the user returns home',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var recentPostsLoadCount = 0;

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          uploaderDraftStore: _ShellDraftStore(),
          languageController: languageController,
          loadRecentPosts: () async {
            recentPostsLoadCount += 1;
            return const [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(recentPostsLoadCount, 1);

    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    expect(recentPostsLoadCount, 1);

    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    expect(recentPostsLoadCount, 2);
  });

  testWidgets('shows first-run onboarding once, then goes to home',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
            uploaderDraftStore: _ShellDraftStore(),
            languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    // First run: the three-step intro shows before the main shell.
    expect(find.text('เชื่อมช่องทางครั้งเดียว'), findsOneWidget);
    expect(_referenceNav(), findsNothing);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('คลิปเดียว โพสต์ได้ทุกที่'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('ตั้งเวลา + ดูยอดที่เดียว'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    // "เริ่มใช้งาน" lands on the main shell and persists the seen flag.
    expect(_referenceNav(), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('postdee_onboarding_seen'), isTrue);
  });
}

class _RecordingAccountAccessRevoker implements AccountAccessRevoker {
  _RecordingAccountAccessRevoker(this.calls);

  final List<String> calls;

  @override
  Future<void> revokeBeforeAccountDeletion() async {
    calls.add('revoke');
  }
}

class _FakePushMessagingGateway implements PushMessagingGateway {
  int initializeCalls = 0;
  Future<void>? initialization;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    await initialization;
  }

  @override
  Future<void> dispose() async {}
}
