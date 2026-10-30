import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/monitoring/postdee_analytics.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/analytics/analytics_screen.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:postdee_mobile/features/notifications/push_messaging_gateway.dart';
import 'package:postdee_mobile/features/onboarding/onboarding_flow.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';
import 'package:postdee_mobile/features/shell/postdee_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_english_test.dart' show loadOnboardingEnglishFonts;

const _seenKey = 'flutter.postdee_onboarding_seen';
const _session = AuthSession(
  userId: 'onboarding-owner',
  idToken: 'onboarding-fake-token',
  displayName: 'ร้านของฉัน Raw seller',
);
const _titles = [
  'Connect your channels once',
  'One video. Every channel.',
  'Schedule and track in one place',
];

final _next = find.byKey(const ValueKey('onboarding-next'));
final _skip = find.byKey(const ValueKey('onboarding-skip'));
final _nav = find.byKey(const ValueKey('postdee-reference-bottom-nav'));

// Exercise the store's existing platform boundary without changing real prefs.
class _Preferences {
  static const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final values = <String, Object>{};
  final writes = <({String key, Object value})>[];
  int reads = 0;
  Object? loadError;
  Object? writeError;
  Future<void>? loadGate;
  Future<void>? writeGate;

  Iterable<({String key, Object value})> get seenWrites =>
      writes.where((write) => write.key == _seenKey);

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'getAll' || call.method == 'getAllWithParameters') {
      reads++;
      await loadGate;
      if (loadError case final error?) throw error;
      return Map<String, Object>.from(values);
    }
    if (call.method.startsWith('set')) {
      final arguments = Map<String, Object>.from(call.arguments as Map);
      final key = arguments['key']! as String;
      final value = arguments['value']!;
      writes.add((key: key, value: value));
      await writeGate;
      if (writeError case final error?) throw error;
      values[key] = value;
      return true;
    }
    throw StateError('Unexpected preferences operation: ${call.method}');
  }
}

class _DraftStore implements PublishDraftStore {
  int reads = 0;
  int writes = 0;

  @override
  Future<List<PublishDraft>> listDrafts() async {
    reads++;
    return const [];
  }

  @override
  Future<PublishDraft?> loadDraft(String draftId) async => null;

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    writes++;
    throw StateError('Onboarding must not save a publishing draft');
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    writes++;
  }

  @override
  Future<void> deleteAllDrafts() async {
    writes++;
  }
}

class _Fixture {
  _Fixture({String locale = 'en'})
      : language = PostDeeLanguageController(initialLocale: Locale(locale));

  final PostDeeLanguageController language;
  final preferences = _Preferences();
  final drafts = _DraftStore();
  final analytics = <RecordedAnalyticsEvent>[];
  int uploadWrites = 0;
  int publishWrites = 0;
  int videoPicks = 0;

  PostDeeShell shell() => PostDeeShell(
        languageController: language,
        uploaderDraftStore: drafts,
        pushMessagingGateway: const DisabledPushMessagingGateway(),
        loadScheduledPosts: () async => const [],
        loadCalendarPosts: () async => const [],
        loadRecentPosts: () async => const [],
        loadSocialConnections: () async => const [],
        loadSubscription: () async => const SubscriptionStatusResult(
          userId: 'onboarding-owner',
          plan: 'BASIC',
          status: 'INACTIVE',
          remainingPostsThisMonth: 3,
          monthlyPostLimit: 3,
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false,
        ),
        pickVideo: () async {
          videoPicks++;
          return null;
        },
        createUpload: (_) async {
          uploadWrites++;
          throw StateError('Onboarding must not upload a video');
        },
        createPost: (_) async {
          publishWrites++;
          throw StateError('Onboarding must not create a post');
        },
      );

  Widget app() => ListenableBuilder(
        listenable: language,
        builder: (_, __) => MaterialApp(
          theme: AppTheme.light,
          locale: language.locale,
          supportedLocales: PostDeeLocalizations.supportedLocales,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: shell(),
        ),
      );

  Future<void> mount(WidgetTester tester, {bool signedIn = true}) async {
    SharedPreferences.resetStatic();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_Preferences.channel, preferences.handle);
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.clear();
    if (signedIn) sessions.signIn(_session);
    PostDeeAnalytics.instance.configure(
      isEnabled: true,
      logEvent: (event) async => analytics.add(event),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      sessions.clear();
      PostDeeAnalytics.instance.configure(isEnabled: false);
      SharedPreferences.resetStatic();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_Preferences.channel, null);
      language.dispose();
      AppTheme.applyThemeMode(ThemeMode.light);
    });
    await tester.runAsync(loadOnboardingEnglishFonts);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  void expectNoPublishing() {
    expect(uploadWrites, 0);
    expect(publishWrites, 0);
    expect(videoPicks, 0);
    expect(drafts.writes, 0);
    expect(analytics, isEmpty);
    expect(find.byType(AnalyticsScreen, skipOffstage: false), findsNothing);
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _chooseLanguage(WidgetTester tester, String name) async {
  await _tap(tester, find.byKey(const ValueKey('onboarding-language')));
  await _tap(tester, find.text(name).last);
}

Future<void> _remount(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  SharedPreferences.resetStatic();
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unseen signed-in Shell starts English intro without publishing',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    expect(find.text(_titles[0]), findsOneWidget);
    expect(find.text('เชื่อมช่องทางครั้งเดียว'), findsNothing);
    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(_nav, findsNothing);
    expect(fixture.preferences.seenWrites, isEmpty);
    fixture.expectNoPublishing();
  });

  testWidgets('Shell language menu changes Thai to English without losing step',
      (tester) async {
    final fixture = _Fixture(locale: 'th');
    await fixture.mount(tester);
    await _tap(tester, _next);
    final previousState = tester.state(find.byType(OnboardingFlow));
    expect(find.text('คลิปเดียว โพสต์ได้ทุกที่'), findsOneWidget);
    await _chooseLanguage(tester, 'English');
    expect(fixture.language.locale, const Locale('en'));
    expect(find.text(_titles[1]), findsOneWidget);
    expect(tester.state(find.byType(OnboardingFlow)), same(previousState));
    expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);
    expect(fixture.preferences.seenWrites, isEmpty);
    fixture.expectNoPublishing();
  });

  testWidgets('Next and Back never mark seen before Get started completes',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await _tap(tester, _next);
    expect(find.text(_titles[1]), findsOneWidget);
    await _tap(tester, find.bySemanticsLabel('Back'));
    expect(find.text(_titles[0]), findsOneWidget);
    expect(fixture.preferences.seenWrites, isEmpty);
    await _tap(tester, _next);
    await _tap(tester, _next);
    expect(find.text(_titles[2]), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(fixture.preferences.seenWrites, isEmpty);
    await _tap(tester, _next);
    expect(_nav, findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(fixture.preferences.seenWrites.toList(),
        [(key: _seenKey, value: true)]);
    fixture.expectNoPublishing();
  });

  for (var step = 0; step < 3; step++) {
    testWidgets('Skip on step ${step + 1} marks seen once and survives remount',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      for (var index = 0; index < step; index++) {
        await _tap(tester, _next);
      }
      expect(find.text(_titles[step]), findsOneWidget);
      expect(fixture.preferences.seenWrites, isEmpty);
      await _tap(tester, _skip);
      expect(_nav, findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(fixture.preferences.seenWrites.toList(),
          [(key: _seenKey, value: true)]);

      await _remount(tester, fixture);
      expect(find.byType(OnboardingFlow), findsNothing);
      expect(_nav, findsOneWidget);
      expect(fixture.preferences.seenWrites, hasLength(1));
      fixture.expectNoPublishing();
    });
  }

  testWidgets('signed-out first run keeps auth gate before English onboarding',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, signedIn: false);
    expect(find.byKey(const ValueKey('login-email-sign-in')), findsOneWidget);
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(_nav, findsNothing);
    expect(fixture.preferences.seenWrites, isEmpty);
    fixture.expectNoPublishing();

    PostDeeAuthSessionStore.instance.signIn(_session);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.text(_titles[0]), findsOneWidget);
    expect(_nav, findsNothing);
    expect(fixture.preferences.seenWrites, isEmpty);
    fixture.expectNoPublishing();
  });

  testWidgets('leaving intro unfinished shows first step again without writes',
      (tester) async {
    final fixture = _Fixture();
    fixture.preferences.values['flutter.saved_caption'] =
        'ราคา 199 ฿ #ไทย\nRaw seller caption';
    await fixture.mount(tester);
    await _tap(tester, _next);
    expect(find.text(_titles[1]), findsOneWidget);
    await _remount(tester, fixture);
    expect(find.text(_titles[0]), findsOneWidget);
    expect(_nav, findsNothing);
    expect(fixture.preferences.values['flutter.saved_caption'],
        'ราคา 199 ฿ #ไทย\nRaw seller caption');
    expect(fixture.preferences.writes, isEmpty);
    fixture.expectNoPublishing();
  });

  testWidgets('preferences read failure before sign-in fails open to Home',
      (tester) async {
    final fixture = _Fixture();
    fixture.preferences.loadError =
        PlatformException(code: 'fake-read-failure');
    // Keep unrelated offstage Profile prefs reads behind the auth gate while
    // exercising the onboarding store's actual failed platform read.
    await fixture.mount(tester, signedIn: false);
    expect(fixture.preferences.reads, greaterThan(0));
    expect(find.byKey(const ValueKey('login-email-sign-in')), findsOneWidget);
    expect(fixture.preferences.seenWrites, isEmpty);

    fixture.preferences.loadError = null;
    PostDeeAuthSessionStore.instance.signIn(_session);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(_nav, findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(fixture.preferences.seenWrites, isEmpty);
    fixture.expectNoPublishing();
    expect(tester.takeException(), isNull);
  });

  testWidgets('seen write failure is nonfatal and permits intro next launch',
      (tester) async {
    final fixture = _Fixture();
    fixture.preferences.writeError =
        PlatformException(code: 'fake-write-failure');
    await fixture.mount(tester);
    await _tap(tester, _skip);
    expect(_nav, findsOneWidget);
    expect(fixture.preferences.seenWrites, hasLength(1));
    expect(fixture.preferences.values[_seenKey], isNull);
    expect(tester.takeException(), isNull);

    await _remount(tester, fixture);
    expect(find.text(_titles[0]), findsOneWidget);
    expect(_nav, findsNothing);
    expect(fixture.preferences.seenWrites, hasLength(1));
    fixture.expectNoPublishing();
  });

  testWidgets('stored seen flag bypasses intro in both display languages',
      (tester) async {
    final fixture = _Fixture();
    fixture.preferences.values[_seenKey] = true;
    await fixture.mount(tester);
    expect(_nav, findsOneWidget);
    expect(find.byType(OnboardingFlow), findsNothing);
    fixture.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    expect(_nav, findsOneWidget);
    expect(find.byType(OnboardingFlow), findsNothing);
    fixture.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(_nav, findsOneWidget);
    expect(fixture.preferences.seenWrites, isEmpty);
    fixture.expectNoPublishing();
  });

  testWidgets('completion opens Home while seen save waits without duplicate',
      (tester) async {
    final pending = Completer<void>();
    final fixture = _Fixture();
    fixture.preferences.writeGate = pending.future;
    await fixture.mount(tester);
    await _tap(tester, _next);
    await _tap(tester, _next);
    await _tap(tester, _next);
    expect(_nav, findsOneWidget);
    expect(fixture.preferences.seenWrites, hasLength(1));
    expect(fixture.preferences.values[_seenKey], isNull);
    fixture.language.setLocale(const Locale('th'));
    await tester.pumpAndSettle();
    fixture.language.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(_nav, findsOneWidget);
    expect(fixture.preferences.seenWrites, hasLength(1));

    pending.complete();
    await tester.pumpAndSettle();
    expect(fixture.preferences.values[_seenKey], isTrue);
    fixture.expectNoPublishing();
    expect(tester.takeException(), isNull);
  });
}
