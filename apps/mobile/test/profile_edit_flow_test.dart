import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/profile/profile_draft_store.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';

void main() {
  testWidgets('edits the profile and can undo the local change',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-token',
        email: 'seller@example.com',
        displayName: 'ชื่อเดิม',
        emailVerified: false,
      ),
    );
    addTearDown(sessionStore.clear);
    final draftStore = _MemoryProfileDraftStore();

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
            apiClient: _ProfileApiClient(),
            profileDraftStore: draftStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-edit-button')));
    await tester.pumpAndSettle();

    expect(find.text('แก้ไขโปรไฟล์'), findsOneWidget);
    expect(find.text('อีเมลยังไม่ยืนยัน'), findsOneWidget);
    expect(find.text('บันทึกเฉพาะในอุปกรณ์นี้'), findsOneWidget);
    expect(
      find.text(
        'ชื่อที่แก้จะใช้เฉพาะในเครื่องนี้ และยังไม่ซิงก์กับบัญชีหรืออุปกรณ์อื่น',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('จะแสดงบนหน้าโปรไฟล์ลิงก์'),
      findsNothing,
    );
    expect(find.text('ยืนยันแล้ว'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('edit-profile-display-name')),
      'มีนา',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-profile-store-name')),
      'ร้านมีนาขายดี',
    );
    await tester.tap(find.byKey(const ValueKey('edit-profile-save')));
    await tester.pumpAndSettle();

    expect(find.text('มีนา'), findsOneWidget);
    expect(draftStore.saved?.storeName, 'ร้านมีนาขายดี');
    expect(draftStore.saved?.accountEmail, 'seller@example.com');
    expect(find.byKey(const ValueKey('postdee-undo-toast')), findsOneWidget);

    await tester.tap(find.text('เลิกทำ'));
    await tester.pumpAndSettle();

    expect(find.text('ชื่อเดิม'), findsOneWidget);
    expect(draftStore.saved?.displayName, 'ชื่อเดิม');
  });
}

class _MemoryProfileDraftStore implements ProfileDraftStore {
  ProfileDraft? saved;

  @override
  Future<void> clear() async => saved = null;

  @override
  Future<ProfileDraft?> load() async => saved;

  @override
  Future<void> save(ProfileDraft draft) async => saved = draft;
}

class _ProfileApiClient extends PostDeeApiClient {
  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async =>
      const [];

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async =>
      const SubscriptionStatusResult(
        userId: 'seller',
        plan: 'BASIC',
        status: 'ACTIVE',
        phoneVerified: true,
        requiresPhoneVerification: false,
        canUseFreePostQuota: true,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false,
      );
}
