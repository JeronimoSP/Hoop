import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Display / brand serif (Evocative World classical feel).
TextStyle brandDisplay({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.cormorantGaramond(
    fontSize: fontSize,
    fontWeight: fontWeight ?? FontWeight.w600,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

ButtonStyle _darkFilledStyle() {
  // Foreground drives label/icon color. Do not bake color into textStyle —
  // GoogleFonts + textTheme.labelLarge otherwise leave black on accent fills.
  return FilledButton.styleFrom(
    backgroundColor: AppColors.accent,
    foregroundColor: AppColors.textOnDark,
    disabledForegroundColor: AppColors.textOnDark.withValues(alpha: 0.55),
    disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.45),
    iconColor: AppColors.textOnDark,
    textStyle: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600),
  );
}

ThemeData buildCirculoTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bgApp,
    colorScheme: ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: AppColors.textOnDark,
      secondary: AppColors.accentPressed,
      onSecondary: AppColors.textOnDark,
      tertiary: AppColors.gold,
      onTertiary: AppColors.textOnDark,
      surface: AppColors.bgElevated,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: AppColors.textOnDark,
    ),
    dividerColor: AppColors.hairline,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgElevated,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.textOnDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.gold, width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: _darkFilledStyle()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _darkElevatedStyle()),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.textOnDark;
          }
          return AppColors.textPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accent;
          }
          return AppColors.bgElevated;
        }),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
  );

  // Larger body copy for Retina / desktop readability (e.g. MacBook Pro).
  // Do not use TextTheme.apply(fontSizeFactor: …): M3/google_fonts leaves
  // some styles with null fontSize, which asserts in TextStyle.apply.
  final bodyTheme = GoogleFonts.sourceSans3TextTheme(base.textTheme).apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  // GoogleFonts text themes often bake in black; re-apply on-primary colors
  // so labels on accent/dark surfaces stay readable (light gold).
  final onDarkTheme =
      GoogleFonts.cormorantGaramondTextTheme(base.primaryTextTheme).apply(
    bodyColor: AppColors.textOnDark,
    displayColor: AppColors.textOnDark,
  );

  final theme = base.copyWith(
    textTheme: bodyTheme.copyWith(
      displayLarge: bodyTheme.displayLarge?.copyWith(
        fontSize: (bodyTheme.displayLarge?.fontSize ?? 57) * 1.2,
      ),
      displayMedium: bodyTheme.displayMedium?.copyWith(
        fontSize: (bodyTheme.displayMedium?.fontSize ?? 45) * 1.2,
      ),
      displaySmall: bodyTheme.displaySmall?.copyWith(
        fontSize: (bodyTheme.displaySmall?.fontSize ?? 36) * 1.2,
      ),
      headlineLarge: bodyTheme.headlineLarge?.copyWith(
        fontSize: (bodyTheme.headlineLarge?.fontSize ?? 32) * 1.2,
      ),
      headlineMedium: bodyTheme.headlineMedium?.copyWith(
        fontSize: (bodyTheme.headlineMedium?.fontSize ?? 28) * 1.2,
      ),
      headlineSmall: bodyTheme.headlineSmall?.copyWith(
        fontSize: (bodyTheme.headlineSmall?.fontSize ?? 24) * 1.2,
      ),
      titleLarge: bodyTheme.titleLarge?.copyWith(
        fontSize: (bodyTheme.titleLarge?.fontSize ?? 22) * 1.2,
      ),
      titleMedium: bodyTheme.titleMedium?.copyWith(
        fontSize: (bodyTheme.titleMedium?.fontSize ?? 16) * 1.2,
      ),
      titleSmall: bodyTheme.titleSmall?.copyWith(
        fontSize: (bodyTheme.titleSmall?.fontSize ?? 14) * 1.2,
      ),
      bodyLarge: bodyTheme.bodyLarge?.copyWith(fontSize: 19, height: 1.5),
      bodyMedium: bodyTheme.bodyMedium?.copyWith(fontSize: 18, height: 1.5),
      bodySmall: bodyTheme.bodySmall?.copyWith(fontSize: 14, height: 1.4),
      labelLarge: bodyTheme.labelLarge?.copyWith(
        fontSize: (bodyTheme.labelLarge?.fontSize ?? 14) * 1.2,
      ),
      labelMedium: bodyTheme.labelMedium?.copyWith(
        fontSize: (bodyTheme.labelMedium?.fontSize ?? 12) * 1.2,
      ),
      labelSmall: bodyTheme.labelSmall?.copyWith(
        fontSize: (bodyTheme.labelSmall?.fontSize ?? 11) * 1.2,
      ),
    ),
    primaryTextTheme: onDarkTheme,
    // Re-assert after copyWith so generated M3 component themes cannot
    // reintroduce dark-on-dark label colors.
    filledButtonTheme: FilledButtonThemeData(style: _darkFilledStyle()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _darkElevatedStyle()),
  );

  return theme;
}

ButtonStyle _darkElevatedStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: AppColors.accent,
    foregroundColor: AppColors.textOnDark,
    disabledForegroundColor: AppColors.textOnDark.withValues(alpha: 0.55),
    disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.45),
    iconColor: AppColors.textOnDark,
    textStyle: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600),
  );
}

/// Chat message / caption body — sized for comfortable reading on desktop.
TextStyle messageBodyStyle({Color? color}) {
  return GoogleFonts.sourceSans3(
    fontSize: 18,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: color ?? AppColors.textPrimary,
  );
}
