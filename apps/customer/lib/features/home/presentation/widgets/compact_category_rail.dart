import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/food_category.dart';

/// A compact, horizontally scrolling row of category icons (images only).
/// Used in the collapsed home app bar below the search pill.
class CompactCategoryRail extends StatelessWidget {
  const CompactCategoryRail({
    required this.categories,
    this.onTapCategory,
    super.key,
  });

  final List<FoodCategory> categories;
  final ValueChanged<FoodCategory>? onTapCategory;

  static const double height = 66;
  static const double _artSize = 58;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: ZopiqSpacing.pagePadding,
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.md),
        itemBuilder: (BuildContext context, int i) {
          final FoodCategory category = categories[i];
          final String? asset = category.imageAsset;
          
          return ZopiqPressable(
            onTap: onTapCategory == null ? null : () => onTapCategory!(category),
            child: SizedBox.square(
              dimension: _artSize,
              child: category.id == 'view_more'
                  ? Center(
                      child: Icon(
                        Icons.arrow_forward,
                        size: _artSize * 0.5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : asset == null
                      ? Center(
                          child: Icon(
                            Icons.restaurant_rounded,
                            size: _artSize * 0.5,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      : asset.endsWith('.svg')
                          ? Builder(
                              builder: (context) {
                                final bool isSmall = category.id == 'sandwich' ||
                                    category.id == 'pizza' ||
                                    category.id == 'burger';
                                final double s = _artSize + (isSmall ? 3 : 8);
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
                              cacheWidth: (_artSize * MediaQuery.devicePixelRatioOf(context)).round(),
                            ),
            ),
          );
        },
      ),
    );
  }
}
