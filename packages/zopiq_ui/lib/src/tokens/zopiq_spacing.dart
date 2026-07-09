import 'package:flutter/widgets.dart';

/// 8pt spacing grid (Rule 2.4). Every gap, padding, and margin in feature code
/// must come from these tokens — no magic numbers.
@immutable
abstract final class ZopiqSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Standard horizontal page gutter for screens.
  static const double pageGutter = lg;

  // Ready-made EdgeInsets for the common cases.
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: pageGutter,
  );
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

/// SizedBox gap helpers to keep layout code terse and consistent.
@immutable
abstract final class Gap {
  static const Widget xs = SizedBox(
    width: ZopiqSpacing.xs,
    height: ZopiqSpacing.xs,
  );
  static const Widget sm = SizedBox(
    width: ZopiqSpacing.sm,
    height: ZopiqSpacing.sm,
  );
  static const Widget md = SizedBox(
    width: ZopiqSpacing.md,
    height: ZopiqSpacing.md,
  );
  static const Widget lg = SizedBox(
    width: ZopiqSpacing.lg,
    height: ZopiqSpacing.lg,
  );
  static const Widget xl = SizedBox(
    width: ZopiqSpacing.xl,
    height: ZopiqSpacing.xl,
  );
  static const Widget xxl = SizedBox(
    width: ZopiqSpacing.xxl,
    height: ZopiqSpacing.xxl,
  );
}
