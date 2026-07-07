import 'package:flutter/material.dart';

/// Typographic scale (Rule 2 — crisp, consistent typography).
///
/// [fontFamily] is intentionally a single switch: today it falls back to the
/// platform default (Roboto on Android). To adopt the premium brand face,
/// bundle the font under `assets/fonts/` + declare it in pubspec, then set
/// [fontFamily] here — every text style updates in one place.
@immutable
abstract final class ZopiqTypography {
  static const String? fontFamily = null; // TODO(design): bundle brand font.

  // Weights used across the system.
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// Builds a full [TextTheme] in a single ink [color], driven by the tokens.
  static TextTheme textTheme(Color color) {
    TextStyle s(double size, FontWeight weight, double height, double spacing) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color,
      );
    }

    return TextTheme(
      displayLarge: s(32, bold, 1.2, -0.5),
      displayMedium: s(28, bold, 1.2, -0.5),
      headlineLarge: s(24, bold, 1.25, -0.3),
      headlineMedium: s(20, semibold, 1.3, -0.2),
      titleLarge: s(18, semibold, 1.3, -0.1),
      titleMedium: s(16, semibold, 1.35, 0),
      titleSmall: s(14, semibold, 1.4, 0),
      bodyLarge: s(16, regular, 1.45, 0),
      bodyMedium: s(14, regular, 1.45, 0),
      bodySmall: s(12, regular, 1.4, 0.1),
      labelLarge: s(14, semibold, 1.2, 0.2), // buttons
      labelMedium: s(12, semibold, 1.2, 0.3),
      labelSmall: s(11, semibold, 1.2, 0.4),
    );
  }
}
