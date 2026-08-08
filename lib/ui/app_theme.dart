import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF080A0F);
  static const Color surface = Color(0xFF111722);
  static const Color surfaceHigh = Color(0xFF182131);
  static const Color surfaceMuted = Color(0xFF202A3B);
  // Or repris du logo de l'application (micro dore sur fond noir) : jaune
  // dore pour les actions et etats actifs, ambre profond pour les fonds
  // pleins et degrades.
  static const Color primary = Color(0xFFF2B01E);
  static const Color primaryDeep = Color(0xFFC07C08);
  // Texte pose sur un aplat de `primary` : brun tres fonce, lisible sur l'or.
  static const Color onPrimary = Color(0xFF241A02);
  static const Color accent = Color(0xFFFFB86B);
  static const Color danger = Color(0xFFFF5C7A);
  static const Color blue = Color(0xFF72A7FF);
  static const Color text = Color(0xFFF3F7FA);
  static const Color textMuted = Color(0xFF91A0B5);
  static const Color line = Color(0xFF2A3548);

  static BoxDecoration panel({
    Color? borderColor,
    List<Color>? gradient,
    double radius = 18,
  }) {
    return BoxDecoration(
      color: surface,
      gradient: gradient == null
          ? null
          : LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 18,
          offset: Offset(0, 10),
        ),
      ],
    );
  }

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: surface,
    );

    return ThemeData(
      colorScheme: scheme.copyWith(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: danger,
      ),
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      fontFamily: 'Roboto',
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xEE0B111B),
        indicatorColor: primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? primary : textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : textMuted,
            size: 22,
          ),
        ),
      ),
    );
  }
}
