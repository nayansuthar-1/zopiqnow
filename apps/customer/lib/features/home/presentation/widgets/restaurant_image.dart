import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// A restaurant's photo, with the branded placeholder behind it.
///
/// Shared by the Home list card, the top-chains rail, and the menu header so the
/// three cannot drift apart — and so a vendor with no photo looks deliberate in
/// all three rather than broken in one.
class RestaurantImage extends StatelessWidget {
  const RestaurantImage({
    required this.restaurant,
    this.iconSize = 40,
    super.key,
  });

  final Restaurant restaurant;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ZopiqNetworkImage(
      url: restaurant.imageUrl,
      fallback: GradientImagePlaceholder(
        seed: restaurant.id,
        icon: Icons.restaurant_rounded,
        iconSize: iconSize,
      ),
    );
  }
}

/// Gradient stand-in drawn when a restaurant *or dish* has no usable photo. The
/// hue is derived from [seed], so a given subject always gets the same colour.
class GradientImagePlaceholder extends StatelessWidget {
  const GradientImagePlaceholder({
    required this.seed,
    required this.icon,
    this.iconSize = 40,
    super.key,
  });

  final String seed;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final double hue = (seed.hashCode % 360).abs().toDouble();
    final Color tint = HSLColor.fromAHSL(1, hue, 0.35, 0.55).toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[tint, tint.withValues(alpha: 0.75)],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          color: ZopiqPalette.white.withValues(alpha: 0.85),
          size: iconSize,
        ),
      ),
    );
  }
}
