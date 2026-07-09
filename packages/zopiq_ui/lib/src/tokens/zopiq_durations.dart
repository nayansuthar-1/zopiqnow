import 'package:flutter/widgets.dart';

/// Motion tokens (Rule 2.6 — smooth, consistent micro-interactions).
@immutable
abstract final class ZopiqDurations {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration shimmer = Duration(milliseconds: 1200);

  /// One in-out cycle of a "breathing" attention loop (e.g. a pulsing CTA).
  static const Duration breath = Duration(milliseconds: 1600);

  /// One revolution of ambient background motion (e.g. rotating hero art).
  /// Slow enough to be felt, not watched.
  static const Duration ambient = Duration(seconds: 24);
}

/// Easing tokens.
@immutable
abstract final class ZopiqCurves {
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve enter = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
}
