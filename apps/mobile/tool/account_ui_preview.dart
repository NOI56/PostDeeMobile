// Offline visual QA entry point. This is not the production app or a real
// account. Run only on a separate emulator with `flutter run -t`.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/profile/profile_draft_store.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PostDeeAuthSessionStore.instance.signIn(const AuthSession(
    idToken: 'offline-visual-fixture',
    email: 'seller@example.com',
    displayName: 'ร้านของฉัน',
    emailVerified: true,
  ));
  runApp(_AccountPreview());
}

class _AccountPreview extends StatelessWidget {
  final language = PostDeeLanguageController();
  final theme = PostDeeThemeController();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([language, theme]),
      builder: (context, _) => MaterialApp(
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
        home: Builder(builder: (context) {
          void notice() => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ตัวอย่างสำหรับทดสอบ UI')));
          return Scaffold(
            body: SafeArea(
              child: ProfileScreen(
                languageController: language,
                themeController: theme,
                apiClient: _PreviewApi(),
                profileDraftStore: _PreviewDrafts(),
                onOpenTemplates: notice,
                onDeleteAccount: notice,
                onSignOut: notice,
                onManageSubscription: () async => notice(),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PreviewApi extends PostDeeApiClient {
  @override
  Future<List<SocialConnectionResult>> listSocialConnections() async => const [
        SocialConnectionResult(platform: 'TIKTOK', connected: true),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: true),
      ];

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async =>
      const SubscriptionStatusResult(
        userId: 'offline-preview',
        plan: 'STARTER',
        status: 'ACTIVE',
        monthlyPostLimit: 120,
        remainingPostsThisMonth: 94,
        phoneVerified: true,
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: false,
      );
}

class _PreviewDrafts implements ProfileDraftStore {
  ProfileDraft? draft;

  @override
  Future<ProfileDraft?> load() async => draft;

  @override
  Future<void> save(ProfileDraft value) async => draft = value;

  @override
  Future<void> clear() async => draft = null;
}
