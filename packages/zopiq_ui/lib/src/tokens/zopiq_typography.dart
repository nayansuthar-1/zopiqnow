import 'package:flutter/material.dart';

/// Typographic scale (Rule 2 — crisp, consistent typography).
///
/// The brand face is **Figtree** (SIL Open Font License, bundled under
/// `assets/fonts/`) — a geometric-humanist sans chosen as the closest
/// freely-licensable relative of Swiggy's Proxima Nova. Proxima Nova is a paid
/// face; if a mobile-app license is ever purchased, drop the `.ttf` next to
/// Figtree, update the pubspec `fonts:` entry, and change [fontFamily] here.
/// Nothing else in the codebase references a font name.
///
/// Figtree ships as a single *variable* font with a `wght` axis. Real weights
/// therefore come from [FontVariation] — [FontWeight] alone would make the text
/// engine synthesise (fake-bold) the heavier styles, which smears the glyphs.
/// Both are set: the variation drives rendering, the weight drives fallback.
@immutable
abstract final class ZopiqTypography {
  /// Package-qualified so it resolves from the app *and* from zopiq_ui itself.
  static const String fontFamily = 'packages/zopiq_ui/Figtree';

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
        fontVariations: <FontVariation>[
          FontVariation('wght', weight.value.toDouble()),
        ],
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
