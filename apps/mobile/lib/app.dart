import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/auth/firebase_bootstrap.dart';
import 'core/config/app_config.dart';
import 'core/localization/language_controller.dart';
import 'core/localization/postdee_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/shell/postdee_shell.dart';
import 'features/splash/postdee_splash_screen.dart';

class PostDeeApp extends StatefulWidget {
  const PostDeeApp({
    super.key,
    this.firebaseBootstrapResult,
    this.locale,
    this.languageController,
    this.themeController,
    this.showSplash = false,
    this.showStagingBadge = AppConfig.isStagingBuild,
  });

  final FirebaseBootstrapResult? firebaseBootstrapResult;
  final Locale? locale;
  final PostDeeLanguageController? languageController;
  final PostDeeThemeController? themeController;
  final bool showStagingBadge;

  /// Shows the animated branded splash before the app. Enabled only for the real
  /// app launch ([main]); left off in widget tests so they reach the shell
  /// immediately.
  final bool showSplash;

  @override
  State<PostDeeApp> createState() => _PostDeeAppState();
}

class _PostDeeAppState extends State<PostDeeApp> {
  late final PostDeeLanguageController _languageController;
  late final PostDeeThemeController _themeController;

  @override
  void initState() {
    super.initState();
    _languageController =
        widget.languageController ?? PostDeeLanguageController.instance;
    _themeController =
        widget.themeController ?? PostDeeThemeController.instance;
  }

  Widget _wrapWithSplash(Widget child) =>
      widget.showSplash ? PostDeeSplashGate(child: child) : child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _languageController,
        _themeController,
      ]),
      builder: (context, _) {
        // Snap the shared custom-theme colors to the active mode. The design
        // handoff requires an *instant* switch — a cross-fade transition
        // leaves colors stuck because const/kept-alive subtrees don't repaint
        // every animation frame.
        AppTheme.applyThemeMode(_themeController.themeMode);

        return MaterialApp(
          title: widget.showStagingBadge ? 'PostDee Staging' : 'PostDee',
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final app = child ?? const SizedBox.shrink();
            if (!widget.showStagingBadge) return app;
            // Reserve a small separate strip rather than painting over the
            // notification bell, composer close button or account actions.
            return ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  SafeArea(
                    bottom: false,
                    child: IgnorePointer(
                      child: SizedBox(
                        key: const ValueKey('postdee-staging-badge'),
                        height: 18,
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 12),
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Semantics(
                              label: 'PostDee Staging แอปทดสอบ',
                              child: const ExcludeSemantics(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'STAGING',
                                    style: TextStyle(
                                      color: Color(0xFFB45309),
                                      decoration: TextDecoration.none,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: app,
                    ),
                  ),
                ],
              ),
            );
          },
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _themeController.themeMode,
          themeAnimationDuration: Duration.zero,
          locale: widget.locale ?? _languageController.locale,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: PostDeeLocalizations.supportedLocales,
          home: _wrapWithSplash(
            PostDeeShell(
              firebaseBootstrapResult: widget.firebaseBootstrapResult,
              languageController: _languageController,
              themeController: _themeController,
            ),
          ),
        );
      },
    );
  }
}
