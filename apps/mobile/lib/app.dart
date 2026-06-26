import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/auth/firebase_bootstrap.dart';
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
  });

  final FirebaseBootstrapResult? firebaseBootstrapResult;
  final Locale? locale;
  final PostDeeLanguageController? languageController;
  final PostDeeThemeController? themeController;

  /// Shows the animated branded splash before the app. Enabled only for the real
  /// app launch ([main]); left off in widget tests so they reach the shell
  /// immediately.
  final bool showSplash;

  @override
  State<PostDeeApp> createState() => _PostDeeAppState();
}

class _PostDeeAppState extends State<PostDeeApp>
    with SingleTickerProviderStateMixin {
  static const _themeTransition = Duration(milliseconds: 320);

  late final PostDeeLanguageController _languageController;
  late final PostDeeThemeController _themeController;
  late final AnimationController _themeAnimation;

  @override
  void initState() {
    super.initState();
    _languageController =
        widget.languageController ?? PostDeeLanguageController.instance;
    _themeController =
        widget.themeController ?? PostDeeThemeController.instance;
    _themeAnimation = AnimationController(
      vsync: this,
      duration: _themeTransition,
      value: _themeController.isLightMode ? 1 : 0,
    );
    _themeController.addListener(_handleThemeChanged);
  }

  void _handleThemeChanged() {
    _themeAnimation.animateTo(
      _themeController.isLightMode ? 1 : 0,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _themeController.removeListener(_handleThemeChanged);
    _themeAnimation.dispose();
    super.dispose();
  }

  Widget _wrapWithSplash(Widget child) =>
      widget.showSplash ? PostDeeSplashGate(child: child) : child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _languageController,
        _themeController,
        _themeAnimation,
      ]),
      builder: (context, _) {
        // Keep the target mode in sync, then override the snap with the
        // animated progress so shared colors fade smoothly between modes.
        AppTheme.applyThemeMode(_themeController.themeMode);
        AppTheme.transitionProgress = _themeAnimation.value;

        return MaterialApp(
          title: 'PostDee',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _themeController.themeMode,
          themeAnimationDuration: _themeTransition,
          themeAnimationCurve: Curves.easeInOut,
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
