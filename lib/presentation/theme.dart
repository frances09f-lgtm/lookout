import 'package:flutter/material.dart';

import 'expressive.dart';
import 'press_feedback.dart';

/// Material 3 Expressive theme: warm off-white canvas, pastel rounded
/// surfaces, ink buttons, springy controls. Shared presentation only;
/// no scheduling or storage changes.
class LookoutTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: XColors.ink,
      onPrimary: Colors.white,
      secondary: XColors.lavenderDeep,
      onSecondary: Colors.white,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      surface: XColors.bg,
      onSurface: XColors.ink,
      surfaceContainerHighest: Color(0xFFEDE8E0),
      onSurfaceVariant: XColors.inkSoft,
      outline: Color(0xFFC9C2B8),
      outlineVariant: Color(0xFFE3DDD3),
      primaryContainer: XColors.mint,
      onPrimaryContainer: XColors.mintDeep,
      secondaryContainer: XColors.lavender,
      onSecondaryContainer: XColors.lavenderDeep,
      tertiaryContainer: XColors.peach,
      onTertiaryContainer: XColors.peachDeep,
    );
    return _build(scheme, dark: false);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFF2EDE6),
      onPrimary: XColors.ink,
      secondary: Color(0xFFCDBBF5),
      onSecondary: XColors.ink,
      error: Color(0xFFF2B8B5),
      onError: Color(0xFF601410),
      surface: Color(0xFF171411),
      onSurface: Color(0xFFF2EDE6),
      surfaceContainerHighest: Color(0xFF2A2521),
      onSurfaceVariant: Color(0xFFB4ABA0),
      outline: Color(0xFF6E665D),
      outlineVariant: Color(0xFF3A342E),
      primaryContainer: Color(0xFF23402E),
      onPrimaryContainer: Color(0xFFBCE6C7),
      secondaryContainer: Color(0xFF3A2D5E),
      onSecondaryContainer: Color(0xFFE3D8FB),
      tertiaryContainer: Color(0xFF4E2D14),
      onTertiaryContainer: Color(0xFFFBD9BB),
    );
    return _build(scheme, dark: true);
  }

  static ThemeData _build(ColorScheme scheme, {required bool dark}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF211D19) : XColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF211D19) : XColors.white,
        contentPadding: const EdgeInsets.all(18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ).copyWith(backgroundBuilder: LookoutPressFeedback.buttonLayer),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
          backgroundBuilder: LookoutPressFeedback.buttonLayer,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ).copyWith(backgroundBuilder: LookoutPressFeedback.buttonLayer),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(backgroundBuilder: LookoutPressFeedback.buttonLayer),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(backgroundBuilder: LookoutPressFeedback.buttonLayer),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        side: BorderSide.none,
        backgroundColor: dark ? const Color(0xFF2A2521) : XColors.white,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: XColors.mintDeep,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .6),
      ),
    );
  }
}
