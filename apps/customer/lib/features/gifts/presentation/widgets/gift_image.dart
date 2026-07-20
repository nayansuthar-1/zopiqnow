import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;

/// A gift's photo with the branded gradient placeholder behind it. Shared by the
/// item cards, the shop cards, and the detail sheet so a seller with no photo
/// looks deliberate everywhere rather than broken in one place.
///
/// [seed] fixes the placeholder hue, so a given product always gets the same
/// colour — pass the item or shop id.
class GiftImage extends StatelessWidget {
  const GiftImage({
    required this.url,
    required this.seed,
    this.icon = Icons.card_giftcard_rounded,
    this.iconSize = 40,
    super.key,
  });

  final String url;
  final String seed;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ZopiqNetworkImage(
      url: url,
      fallback: GradientImagePlaceholder(
        seed: seed,
        icon: icon,
        iconSize: iconSize,
      ),
    );
  }
}
