import 'package:flutter/material.dart';

import 'package:zopiq_ui/src/tokens/zopiq_palette.dart';

/// Brand-semantic colors that Material's [ColorScheme] does not model
/// (veg/non-veg indicators, rating pills, shimmer, muted text, price strike).
///
/// Exposed as a [ThemeExtension] so both light and dark are first-class token
/// variants (Rule 2.3) and are accessed the same way everywhere:
/// `Theme.of(context).extension<ZopiqColors>()!` — or the `context.zc` helper.
@immutable
class ZopiqColors extends ThemeExtension<ZopiqColors> {
  const ZopiqColors({
    required this.primary,
    required this.primaryDeep,
    required this.veg,
    required this.nonVeg,
    required this.rating,
    required this.textStrong,
    required this.textMuted,
    required this.divider,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.cardShadow,
    required this.scrim,
  });

  final Color primary;
  final Color primaryDeep;
  final Color veg;
  final Color nonVeg;
  final Color rating;

  /// Primary ink (headings). Distinct from ColorScheme.onSurface so brand text
  /// can stay intentional even if the scheme is regenerated.
  final Color textStrong;
  final Color textMuted;
  final Color divider;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color cardShadow;
  final Color scrim;

  static const ZopiqColors light = ZopiqColors(
    primary: ZopiqPalette.primary,
    primaryDeep: ZopiqPalette.primaryDeep,
    veg: ZopiqPalette.veg,
    nonVeg: ZopiqPalette.nonVeg,
    rating: ZopiqPalette.rating,
    textStrong: ZopiqPalette.textDark,
    textMuted: ZopiqPalette.textMuted,
    divider: ZopiqPalette.dividerLight,
    shimmerBase: Color(0xFFE9E9EB),
    shimmerHighlight: Color(0xFFF6F6F7),
    cardShadow: Color(0x14000000),
    scrim: Color(0x99000000),
  );

  static const ZopiqColors dark = ZopiqColors(
    primary: ZopiqPalette.primary,
    primaryDeep: ZopiqPalette.primaryDeep,
    veg: ZopiqPalette.vegBright,
    nonVeg: ZopiqPalette.nonVeg,
    rating: ZopiqPalette.rating,
    textStrong: ZopiqPalette.textLight,
    textMuted: ZopiqPalette.textMutedDark,
    divider: ZopiqPalette.dividerDark,
    shimmerBase: Color(0xFF25262C),
    shimmerHighlight: Color(0xFF303138),
    cardShadow: Color(0x33000000),
    scrim: Color(0xB3000000),
  );

  @override
  ZopiqColors copyWith({
    Color? primary,
    Color? primaryDeep,
    Color? veg,
    Color? nonVeg,
    Color? rating,
    Color? textStrong,
    Color? textMuted,
    Color? divider,
    Color? shimmerBase,
    Color? shimmerHighlight,
    Color? cardShadow,
    Color? scrim,
  }) {
    return ZopiqColors(
      primary: primary ?? this.primary,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      veg: veg ?? this.veg,
      nonVeg: nonVeg ?? this.nonVeg,
      rating: rating ?? this.rating,
      textStrong: textStrong ?? this.textStrong,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      cardShadow: cardShadow ?? this.cardShadow,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  ZopiqColors lerp(ThemeExtension<ZopiqColors>? other, double t) {
    if (other is! ZopiqColors) return this;
    return ZopiqColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t)!,
      veg: Color.lerp(veg, other.veg, t)!,
      nonVeg: Color.lerp(nonVeg, other.nonVeg, t)!,
      rating: Color.lerp(rating, other.rating, t)!,
      textStrong: Color.lerp(textStrong, other.textStrong, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// Ergonomic access to brand tokens: `context.zc.veg`, `context.zc.rating`.
extension ZopiqColorsX on BuildContext {
  ZopiqColors get zc => Theme.of(this).extension<ZopiqColors>()!;
}
