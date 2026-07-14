import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:zopiqnow/features/home/domain/entities/food_category.dart';

/// Circular tile holding one dish category's artwork.
class CategoryArt extends StatelessWidget {
  const CategoryArt({required this.category, required this.size, super.key});

  final FoodCategory category;
  final double size;

  /// Inset of the artwork inside the disc, as a fraction of [size].
  static const double _insetFactor = 0.14;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? asset = category.imageAsset;

    return SizedBox.square(
      dimension: size,
      child: category.id == 'view_more'
          ? Center(
              child: Icon(
                Icons.arrow_forward,
                size: size * 0.4,
                color: theme.colorScheme.primary,
              ),
            )
          : asset == null
              ? Center(
                  child: Icon(
                    Icons.restaurant_rounded,
                    size: size * 0.4,
                    color: theme.colorScheme.primary,
                  ),
                )
              : asset.endsWith('.svg')
              ? Builder(
                  builder: (context) {
                    final bool isSmall = category.id == 'sandwich' ||
                        category.id == 'pizza' ||
                        category.id == 'burger';
                    final double s = size + (isSmall ? 3 : 8);
                    return OverflowBox(
                      maxWidth: s,
                      maxHeight: s,
                      child: SvgPicture.asset(
                        asset,
                        fit: BoxFit.contain,
                        width: s,
                        height: s,
                      ),
                    );
                  },
                )
              : Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  cacheWidth:
                      (size * MediaQuery.devicePixelRatioOf(context)).round(),
                ),
    );
  }
}
