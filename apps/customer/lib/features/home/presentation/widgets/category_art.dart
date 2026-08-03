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
              // Which folder the art came from, not which extension it has:
              // the flat art stopped being `.svg` when it turned out to be
              // 1536x1024 PNGs in an `<svg>` wrapper, and the file type was
              // never what this branch was really asking about.
              : asset.contains('icons_zopiq')
              ? Builder(
                  builder: (context) {
                    final bool isSmall = category.id == 'sandwich' ||
                        category.id == 'pizza' ||
                        category.id == 'burger';
                    final double s = size + (isSmall ? 3 : 8);
                    return OverflowBox(
                      maxWidth: s,
                      maxHeight: s,
                      child: asset.endsWith('.svg')
                          ? SvgPicture.asset(
                              asset,
                              fit: BoxFit.contain,
                              width: s,
                              height: s,
                            )
                          : Image.asset(
                              asset,
                              fit: BoxFit.contain,
                              width: s,
                              height: s,
                              cacheWidth: (s *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                            ),
                    );
                  },
                )
              // Photographic art carries its own backdrop, so it is cropped to
              // the disc rather than floated inside it like the flat SVGs.
              : ClipOval(
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    cacheWidth:
                        (size * MediaQuery.devicePixelRatioOf(context)).round(),
                  ),
                ),
    );
  }
}
