import 'package:flutter/material.dart';

class SafeZoneTheme {
  SafeZoneTheme._();

  static const Color bg = Color(0xFF080E19);
  static const Color surface = Color(0xFF111C2C);
  static const Color surface2 = Color(0xFF162337);
  static const Color border = Color(0xFF283A50);
  static const Color textPrimary = Color(0xFFEBF2FC);
  static const Color textMuted = Color(0xFF96ADC7);
  static const Color lime = Color(0xFFB8F66A);
  static const Color cyan = Color(0xFF63D7DD);
  static const Color amber = Color(0xFFF5CA74);
  static const Color red = Color(0xFFFF8699);

  static ThemeData darkRtlTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: lime,
        secondary: cyan,
        surface: surface,
        error: red,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B1524),
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lime,
          foregroundColor: const Color(0xFF152322),
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: lime);
          }
          return const TextStyle(fontSize: 10, color: textMuted);
        }),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 13),
        bodySmall: TextStyle(color: textMuted, fontSize: 11),
        titleLarge: TextStyle(
            color: textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(
            color: textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
        titleSmall: TextStyle(
            color: textMuted, fontSize: 12, fontWeight: FontWeight.w600),
        labelLarge: TextStyle(
            color: textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
        labelSmall: TextStyle(color: textMuted, fontSize: 10),
      ),
    );
  }
}
