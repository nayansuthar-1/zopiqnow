import 'package:flutter/material.dart';

import 'package:zopiq_ui/src/theme/zopiq_colors.dart';

/// The familiar square veg / non-veg food-type mark — a bordered box with a
/// centered dot (green = veg, red = non-veg). Color comes from tokens so it
/// stays correct in both themes.
class ZopiqVegIndicator extends StatelessWidget {
  const ZopiqVegIndicator({required this.isVeg, this.size = 16, super.key});

  final bool isVeg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color color = isVeg ? zc.veg : zc.nonVeg;

    return Semantics(
      label: isVeg ? 'Vegetarian' : 'Non-vegetarian',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
        alignment: Alignment.center,
        child: Container(
          width: size * 0.45,
          height: size * 0.45,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
