import 'package:flutter/widgets.dart';

/// Soft, premium shadow scale (Rule 2.4 — consistent elevation/shadow scale).
/// Swiggy-style cards use low-spread, soft shadows rather than harsh Material
/// drop shadows.
@immutable
abstract final class ZopiqElevation {
  static const Color _shadow = Color(0x14000000); // ~8% black
  static const Color _shadowStrong = Color(0x1F000000); // ~12% black

  /// Resting cards.
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: _shadow, blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// Bottom sheets / raised surfaces.
  static const List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(color: _shadowStrong, blurRadius: 24, offset: Offset(0, -6)),
  ];

  /// Floating action / sticky checkout bar.
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(color: _shadowStrong, blurRadius: 16, offset: Offset(0, 6)),
  ];
}
