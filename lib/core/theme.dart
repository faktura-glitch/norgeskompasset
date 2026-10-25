import 'package:flutter/material.dart';

/// NorgesKompasset design system.
/// Scandinavian outdoor identity: deep mountain blue, forest green,
/// clean white cards, restrained shadows, generous spacing.
class NkColors {
  NkColors._();

  /// Flipped by the app-level builder to match the resolved theme
  /// brightness — surface/text getters below follow it. Accent hues
  /// stay constant (they read well on both themes).
  static bool dark = false;

  static const Color primaryBlue = Color(0xFF174A78);
  static const Color primaryBlueDark = Color(0xFF10385D);
  static const Color forestGreen = Color(0xFF237A55);
  static const Color forestGreenDark = Color(0xFF1B6144);
  static const Color warningAmber = Color(0xFFE5A33D);
  static const Color dangerRed = Color(0xFFD94841);

  // ── Theme-aware surfaces and text ──────────────────────────
  static Color get background =>
      dark ? const Color(0xFF10161B) : const Color(0xFFF5F8FA);
  static Color get card => dark ? const Color(0xFF1A2229) : Colors.white;
  static Color get mapLightBlue =>
      dark ? const Color(0xFF1E2A36) : const Color(0xFFDCEAF5);
  static Color get textPrimary =>
      dark ? const Color(0xFFEDF1F4) : const Color(0xFF172033);
  static Color get textSecondary =>
      dark ? const Color(0xFF9AA5B1) : const Color(0xFF667085);
  static Color get border =>
      dark ? const Color(0xFF2A3540) : const Color(0xFFE2E8F0);

  /// Text-safe warning color: pure amber fails contrast at small
  /// sizes on light surfaces — use this darker tone for warning
  /// text/chips. In dark mode the bright amber reads fine.
  static Color get warning => dark ? warningAmber : const Color(0xFF8A5B0B);

  static const Color easyGreen = Color(0xFF237A55);
  static const Color moderateAmber = Color(0xFFE5A33D);
  static const Color challengingOrange = Color(0xFFD97A2B);
  static const Color demandingRed = Color(0xFFD94841);
}

class NkTheme {
  static ThemeData build() => _build(false);
  static ThemeData buildDark() => _build(true);

  static ThemeData _build(bool dark) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: NkColors.primaryBlue,
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: NkColors.primaryBlue,
        secondary: NkColors.forestGreen,
        error: NkColors.dangerRed,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF10161B)
          : const Color(0xFFF5F8FA),
    );

    final cardColor = dark ? const Color(0xFF1A2229) : Colors.white;
    final borderColor = dark
        ? const Color(0xFF2A3540)
        : const Color(0xFFE2E8F0);
    final accent = dark ? const Color(0xFF7FB2E0) : NkColors.primaryBlue;

    return base.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NkColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NkColors.forestGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NkColors.forestGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        isDense: true,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: borderColor, thickness: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

extension ContextX on BuildContext {
  bool get isWide => MediaQuery.of(this).size.width >= 900;
  bool get isMedium =>
      MediaQuery.of(this).size.width >= 600 &&
      MediaQuery.of(this).size.width < 900;
}
