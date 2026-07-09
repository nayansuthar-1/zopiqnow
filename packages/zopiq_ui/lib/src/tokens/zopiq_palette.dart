import 'package:flutter/material.dart';

/// Raw, mode-agnostic brand colors — the single source of truth for every hex
/// value in zopiqnow (Rule 2). Feature code must NEVER hardcode a `Color(0x..)`;
/// it consumes these through the theme / [ZopiqColors] extension instead.
///
/// Swiggy-aligned palette (look & feel only — zopiqnow ships its own brand
/// assets, per ENGINEERING_RULES Rule 2 note).
@immutable
abstract final class ZopiqPalette {
  // --- Brand (fixed across light & dark) ---
  /// Swiggy Orange — primary brand, active states, highlights.
  static const Color primary = Color(0xFFFC8019);

  /// CTA Orange — strong CTAs ("ADD"/checkout), badges.
  static const Color primaryDeep = Color(0xFFFF5200);

  // --- Neutrals (light mode) ---
  static const Color textDark = Color(0xFF282C3F); // headings / primary text
  static const Color textMuted = Color(0xFF7E808C); // captions / secondary
  static const Color surfaceLight = Color(0xFFFFFFFF); // cards / sheets
  static const Color backgroundLight = Color(0xFFF4F4F5); // app background
  static const Color dividerLight = Color(0xFFE9E9EB);

  // --- Neutrals (dark mode) ---
  static const Color backgroundDark = Color(0xFF0F1013);
  static const Color surfaceDark = Color(0xFF1C1D22);
  static const Color surfaceDarkElevated = Color(0xFF25262C);
  static const Color textLight = Color(0xFFF0F1F5);
  static const Color textMutedDark = Color(0xFF9A9CA8);
  static const Color dividerDark = Color(0xFF2A2B31);

  // --- Semantic (shared, tuned per mode where needed) ---
  static const Color veg = Color(0xFF3D9B6D); // veg indicator / success
  static const Color vegBright = Color(0xFF60B246);
  static const Color nonVeg = Color(0xFFE43B4F); // non-veg / error
  static const Color rating = Color(0xFF48C479); // rating pill green
  static const Color ratingBar = Color(0xFFDB7C38); // low-rating amber

  // --- Utility ---
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
}
