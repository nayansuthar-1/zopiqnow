import 'package:flutter/widgets.dart';

/// Motion tokens (Rule 2.6 — smooth, consistent micro-interactions).
@immutable
abstract final class ZopiqDurations {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration shimmer = Duration(milliseconds: 1200);
}

/// Easing tokens.
@immutable
abstract final class ZopiqCurves {
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve enter = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
}
