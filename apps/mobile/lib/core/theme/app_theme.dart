import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  const AppTheme._();

  static const accent = Color(0xFF8B5CF6);
  static const accentCyan = Color(0xFF22D3EE);
  static const accentPink = Color(0xFFFF4FD8);
  static const success = Color(0xFF22C55E);

  // Fixed light-on-dark foreground colors for surfaces that stay dark in both
  // themes (e.g. the video preview placeholder). Content there must not inherit
  // the theme text colors, which flip to dark-on-light and vanish in light mode.
  static const onDarkPrimary = Color(0xFFF5F5F5);
  static const onDarkSecondary = Color(0xFFA7AABD);

  // Deeper "ink" shades of the brand colors used for light mode. The vivid
  // brand hues are tuned for dark surfaces and wash out as text/icons on white,
  // so [accentCyanInk] etc. fade to these in light mode (see the getters below).
  static const _accentCyanInkLight = Color(0xFF0E7490);
  static const _accentPinkInkLight = Color(0xFFC026A3);
  static const _successInkLight = Color(0xFF15803D);

  static const cardRadius = 14.0;
  static const tileRadius = 10.0;
  static const pillRadius = 999.0;

  // Shared spacing scale — use these instead of ad-hoc numbers so every
  // screen keeps the same vertical/horizontal rhythm.
  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 12.0;
  static const spaceLg = 16.0;
  static const spaceXl = 24.0;

  // Standard outer padding for scrollable screen bodies. Keeps a consistent
  // gutter; screens with a floating action area can add extra bottom inset.
  static const screenPadding =
      EdgeInsets.fromLTRB(spaceLg, spaceMd, spaceLg, spaceXl);

  static const brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accentPink, accent, accentCyan],
  );

  static var _isLightMode = false;

  static const _darkPalette = _AppThemePalette(
    pitchBlack: Color(0xFF050507),
    ink: Color(0xFF070A10),
    midnight: Color(0xFF090D16),
    charcoal: Color(0xFF0E131D),
    glass: Color(0xFF111722),
    glassDeep: Color(0xFF080B12),
    border: Color(0xFF273044),
    borderSoft: Color(0xFF1B2434),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFA7AABD),
    textMuted: Color(0xFF74798B),
    navSurface: Color(0xFF030407),
    navBorder: Color(0xFF171B25),
    navActive: Color(0xFFA855F7),
    navInactive: Color(0xFFA8ACB8),
    panelGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0E131D), Color(0xFF080B12)],
    ),
    screenGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF070B13),
        Color(0xFF05070D),
        Color(0xFF030407),
      ],
    ),
  );

  static const _lightPalette = _AppThemePalette(
    pitchBlack: Color(0xFFF7F8FC),
    ink: Color(0xFFFFFFFF),
    midnight: Color(0xFFF3F6FB),
    charcoal: Color(0xFFFFFFFF),
    glass: Color(0xFFFFFFFF),
    glassDeep: Color(0xFFF1F4FA),
    border: Color(0xFFD8DEEA),
    borderSoft: Color(0xFFE8ECF4),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF5B6472),
    textMuted: Color(0xFF8B94A6),
    navSurface: Color(0xFFEFF3FA),
    navBorder: Color(0xFFE5E7EF),
    navActive: Color(0xFFA855F7),
    navInactive: Color(0xFF6B7280),
    panelGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFFFF), Color(0xFFF3F6FB)],
    ),
    screenGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFF9FAFF),
        Color(0xFFF4F7FC),
        Color(0xFFEFF3FA),
      ],
    ),
  );

  // Transition progress between dark (0) and light (1). Shared colors are
  // interpolated by this value so the whole custom UI fades smoothly when the
  // display mode changes (driven by PostDeeApp's animation controller).
  static double _t = 0;

  static void applyThemeMode(ThemeMode mode) {
    _isLightMode = mode == ThemeMode.light;
    // Snap by default so non-animated contexts (tests, first frame) are exact.
    // PostDeeApp overrides [transitionProgress] each frame to animate.
    _t = _isLightMode ? 1 : 0;
  }

  /// Drives the dark→light interpolation (0 = dark, 1 = light).
  static set transitionProgress(double value) {
    _t = value.clamp(0.0, 1.0);
  }

  static bool get isLightMode => _isLightMode;

  static Color _lerp(Color dark, Color light) => Color.lerp(dark, light, _t)!;

  static LinearGradient _lerpGradient(
          LinearGradient dark, LinearGradient light) =>
      LinearGradient.lerp(dark, light, _t)!;

  static Color get pitchBlack =>
      _lerp(_darkPalette.pitchBlack, _lightPalette.pitchBlack);
  static Color get ink => _lerp(_darkPalette.ink, _lightPalette.ink);
  static Color get midnight =>
      _lerp(_darkPalette.midnight, _lightPalette.midnight);
  static Color get charcoal =>
      _lerp(_darkPalette.charcoal, _lightPalette.charcoal);
  static Color get glass => _lerp(_darkPalette.glass, _lightPalette.glass);
  static Color get glassDeep =>
      _lerp(_darkPalette.glassDeep, _lightPalette.glassDeep);
  static Color get border => _lerp(_darkPalette.border, _lightPalette.border);
  static Color get borderSoft =>
      _lerp(_darkPalette.borderSoft, _lightPalette.borderSoft);
  static Color get textPrimary =>
      _lerp(_darkPalette.textPrimary, _lightPalette.textPrimary);
  static Color get textSecondary =>
      _lerp(_darkPalette.textSecondary, _lightPalette.textSecondary);
  static Color get textMuted =>
      _lerp(_darkPalette.textMuted, _lightPalette.textMuted);
  static Color get navSurface =>
      _lerp(_darkPalette.navSurface, _lightPalette.navSurface);
  static Color get navBorder =>
      _lerp(_darkPalette.navBorder, _lightPalette.navBorder);
  static Color get navActive =>
      _lerp(_darkPalette.navActive, _lightPalette.navActive);
  static Color get navInactive =>
      _lerp(_darkPalette.navInactive, _lightPalette.navInactive);
  static LinearGradient get panelGradient =>
      _lerpGradient(_darkPalette.panelGradient, _lightPalette.panelGradient);
  static LinearGradient get screenGradient =>
      _lerpGradient(_darkPalette.screenGradient, _lightPalette.screenGradient);

  // Readable foreground variants of the brand colors. Dark mode keeps the vivid
  // hue (interpolation factor 0); light mode shifts to the deeper ink shade so
  // the same hue stays legible as text/icons on light surfaces.
  static Color get accentCyanInk => _lerp(accentCyan, _accentCyanInkLight);
  static Color get accentPinkInk => _lerp(accentPink, _accentPinkInkLight);
  static Color get successInk => _lerp(success, _successInkLight);

  /// Maps a vivid brand color to its readable light-mode "ink" variant. Use for
  /// foreground icons whose color comes from const data (so the value itself
  /// can't be an interpolated getter). Unknown colors are returned unchanged.
  static Color inkFor(Color brand) {
    if (brand == accentCyan) return accentCyanInk;
    if (brand == accentPink) return accentPinkInk;
    if (brand == success) return successInk;
    return brand;
  }

  static BoxDecoration get screenBackground => BoxDecoration(
        gradient: screenGradient,
      );

  static ThemeData get dark => _theme(Brightness.dark, _darkPalette);

  static ThemeData get light => _theme(Brightness.light, _lightPalette);

  static ThemeData _theme(Brightness brightness, _AppThemePalette palette) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: palette.charcoal,
    );
    final textTheme = (brightness == Brightness.dark
            ? Typography.whiteMountainView
            : Typography.blackMountainView)
        .apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
      fontFamily: 'Prompt',
      fontFamilyFallback: const [
        'Noto Sans Thai',
        'NotoSansThai',
        'Segoe UI',
        'Roboto',
        'sans-serif',
      ],
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      // Match the top of the screen gradient so the status bar / app bar area
      // blends into the body instead of reading as a hard black strip.
      scaffoldBackgroundColor: palette.screenGradient.colors.first,
      colorScheme: colorScheme.copyWith(
        primary: accent,
        secondary: accentCyan,
        tertiary: accentPink,
        surface: palette.charcoal,
        onSurface: palette.textPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        // Transparent so the screen gradient painted behind the Scaffold shows
        // through the app bar and status bar with no hard seam.
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness:
              brightness == Brightness.dark ? Brightness.dark : Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.glass,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: palette.border),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.navSurface,
        selectedItemColor: palette.navActive,
        unselectedItemColor: palette.navInactive,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.glassDeep,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: const BorderSide(color: accentCyan),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.textPrimary,
          foregroundColor: palette.pitchBlack,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: palette.charcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.border),
        ),
        hourMinuteShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tileRadius),
        ),
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : palette.glassDeep,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : palette.textSecondary,
        ),
        dayPeriodShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tileRadius),
        ),
        dayPeriodBorderSide: BorderSide(color: palette.border),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : palette.glassDeep,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : palette.textSecondary,
        ),
        dialBackgroundColor: palette.glassDeep,
        dialHandColor: accent,
        dialTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : palette.textPrimary,
        ),
        entryModeIconColor: palette.textSecondary,
        helpTextStyle: TextStyle(
          color: palette.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: palette.charcoal,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.border),
        ),
        headerBackgroundColor: palette.glassDeep,
        headerForegroundColor: palette.textPrimary,
        dividerColor: palette.borderSoft,
        dayShape: const WidgetStatePropertyAll(CircleBorder()),
        dayForegroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : states.contains(WidgetState.disabled)
                  ? palette.textMuted
                  : palette.textPrimary,
        ),
        dayBackgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : Colors.transparent,
        ),
        todayForegroundColor: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : accent,
        ),
        todayBackgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : Colors.transparent,
        ),
        todayBorder: const BorderSide(color: accent),
        yearForegroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : palette.textPrimary,
        ),
        yearBackgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : Colors.transparent,
        ),
        weekdayStyle: TextStyle(
          color: palette.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: palette.textSecondary,
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: accent,
        ),
      ),
    );
  }
}

class _AppThemePalette {
  const _AppThemePalette({
    required this.pitchBlack,
    required this.ink,
    required this.midnight,
    required this.charcoal,
    required this.glass,
    required this.glassDeep,
    required this.border,
    required this.borderSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.navSurface,
    required this.navBorder,
    required this.navActive,
    required this.navInactive,
    required this.panelGradient,
    required this.screenGradient,
  });

  final Color pitchBlack;
  final Color ink;
  final Color midnight;
  final Color charcoal;
  final Color glass;
  final Color glassDeep;
  final Color border;
  final Color borderSoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color navSurface;
  final Color navBorder;
  final Color navActive;
  final Color navInactive;
  final LinearGradient panelGradient;
  final LinearGradient screenGradient;
}
