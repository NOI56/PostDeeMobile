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
import 'package:shared_preferences/shared_preferences.dart';

const _ownerA = AuthSession(
    userId: 'editor-owner-a',
    idToken: 'fixture-a',
    email: 'Seller@Example.COM',
    displayName: 'Seller');
const _ownerB = AuthSession(
    userId: 'editor-owner-b',
    idToken: 'fixture-b',
    email: 'other@example.com',
    displayName: 'Other Seller');
const _draftA = ProfileDraft(
    displayName: 'Saved Seller',
    storeName: 'Saved Shop',
    accountEmail: 'seller@example.com',
    accountUserId: 'editor-owner-a');
const _draftB = ProfileDraft(
    displayName: 'Other local name',
    storeName: 'Other Shop',
    accountEmail: 'other@example.com',
    accountUserId: 'editor-owner-b');

class _LocalStore implements ProfileDraftStore {
  final byOwner = <String, ProfileDraft>{
    'editor-owner-a': _draftA,
    'editor-owner-b': _draftB,
  };
  final writes = <ProfileDraft>[];
  var clears = 0;

  @override
  Future<ProfileDraft?> load() async =>
      byOwner[PostDeeAuthSessionStore.instance.session.stableUserId];

  @override
  Future<void> save(ProfileDraft draft) async {
    // Record every request so a stale Profile callback cannot be hidden by a
    // defensive fake store. The real store has separate owner-scope tests.
    writes.add(draft);
    byOwner[draft.accountUserId] = draft;
  }

  @override
  Future<void> clear() async => clears++;
}

class _Api extends PostDeeApiClient {
  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async =>
      const [];

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async =>
      const SubscriptionStatusResult(
          userId: 'editor-owner-a',
          plan: 'BASIC',
          status: 'INACTIVE',
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false);
}

class _Fixture {
  final drafts = _LocalStore();
  final api = _Api();
  final language = PostDeeLanguageController(initialLocale: const Locale('en'));
  final theme = PostDeeThemeController();

  Widget app() => MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.light,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
            body: ProfileScreen(
          key: const ValueKey('editor-flow-profile'),
          languageController: language,
          themeController: theme,
          apiClient: api,
          profileDraftStore: drafts,
          onOpenTemplates: () {},
          onDeleteAccount: () {},
        )),
      );

  void dispose() {
    language.dispose();
    theme.dispose();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _open(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await tester.tap(_key('profile-edit-button'));
  await tester.pumpAndSettle();
  expect(find.byType(EditProfileScreen), findsOneWidget);
  expect(find.text('Edit profile'), findsOneWidget);
  expect(find.text('Save'), findsOneWidget);
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(_key('edit-profile-save'));
  await tester.pumpAndSettle();
  await tester.tap(_key('edit-profile-save'));
  await tester.pumpAndSettle();
}

void main() {
  late _Fixture fixture;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(_ownerA);
    AppTheme.applyThemeMode(ThemeMode.light);
    fixture = _Fixture();
  });
  tearDown(() {
    fixture.dispose();
    PostDeeAuthSessionStore.instance.clear();
  });

  testWidgets(
      'English edit save trims local values and Undo restores owner metadata',
      (tester) async {
    await _open(tester, fixture);
    expect(find.text('Saved on this device only'), findsOneWidget);
    expect(
        find.text('Name changes are saved only on this device and are not '
            'synced with your account or other devices.'),
        findsOneWidget);
    expect(fixture.drafts.writes, isEmpty);
    await tester.enterText(
        _key('edit-profile-display-name'), '  Edited Seller  ');
    await tester.enterText(_key('edit-profile-store-name'), '  Edited Shop  ');
    await _save(tester);
    expect(find.byType(EditProfileScreen), findsNothing);
    final saved = fixture.drafts.writes.single;
    expect(saved.displayName, 'Edited Seller');
    expect(saved.storeName, 'Edited Shop');
    expect(saved.accountEmail, 'seller@example.com');
    expect(saved.accountUserId, 'editor-owner-a');
    expect(
        PostDeeAuthSessionStore.instance.session.displayName, 'Edited Seller');
    expect(find.text('Profile saved'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(fixture.drafts.writes, hasLength(2));
    expect(
        fixture.drafts.byOwner['editor-owner-a']?.displayName, 'Saved Seller');
    expect(fixture.drafts.byOwner['editor-owner-a']?.storeName, 'Saved Shop');
    expect(fixture.drafts.byOwner['editor-owner-a']?.accountUserId,
        'editor-owner-a');
    expect(fixture.drafts.byOwner['editor-owner-b'], same(_draftB));
    expect(
        PostDeeAuthSessionStore.instance.session.displayName, 'Saved Seller');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English editor Back discards unconfirmed names without local writes',
      (tester) async {
    await _open(tester, fixture);
    final beforeName = PostDeeAuthSessionStore.instance.session.displayName;
    await tester.enterText(_key('edit-profile-display-name'), 'Not saved');
    await tester.enterText(_key('edit-profile-store-name'), 'Not saved shop');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(fixture.drafts.writes, isEmpty);
    expect(fixture.drafts.clears, 0);
    expect(fixture.drafts.byOwner['editor-owner-a'], same(_draftA));
    expect(PostDeeAuthSessionStore.instance.session.displayName, beforeName);
    expect(find.text('Profile saved'), findsNothing);
    expect(find.text('Saved Seller'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English editor result from an old owner cannot save for a new owner',
      (tester) async {
    await _open(tester, fixture);
    await tester.enterText(_key('edit-profile-display-name'), 'Old owner edit');
    PostDeeAuthSessionStore.instance.signIn(_ownerB);
    await tester.pumpAndSettle();
    final replacementName = PostDeeAuthSessionStore.instance.session.displayName;
    await _save(tester);
    expect(fixture.drafts.writes, isEmpty);
    expect(fixture.drafts.clears, 0);
    expect(fixture.drafts.byOwner['editor-owner-a'], same(_draftA));
    expect(fixture.drafts.byOwner['editor-owner-b'], same(_draftB));
    expect(PostDeeAuthSessionStore.instance.session.displayName, replacementName);
    expect(find.text('Other local name'), findsOneWidget);
    expect(find.text('Profile saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English Undo from an old owner cannot change a replacement draft',
      (tester) async {
    await _open(tester, fixture);
    await tester.enterText(
        _key('edit-profile-display-name'), 'Saved edit for A');
    await _save(tester);
    expect(fixture.drafts.writes, hasLength(1));
    PostDeeAuthSessionStore.instance.signIn(_ownerB);
    await tester.pumpAndSettle();
    final replacementName = PostDeeAuthSessionStore.instance.session.displayName;
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(fixture.drafts.writes, hasLength(1));
    expect(fixture.drafts.clears, 0);
    expect(fixture.drafts.byOwner['editor-owner-a']?.displayName,
        'Saved edit for A');
    expect(fixture.drafts.byOwner['editor-owner-b'], same(_draftB));
    expect(PostDeeAuthSessionStore.instance.session.displayName, replacementName);
    expect(tester.takeException(), isNull);
  });
}
