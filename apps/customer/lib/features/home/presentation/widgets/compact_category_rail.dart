import 'package:flutter/material.dart';
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

  static const double height = 48;
  static const double _artSize = 40;

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
              child: asset == null
                  ? Center(
                      child: Icon(
                        Icons.restaurant_rounded,
                        size: _artSize * 0.5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
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
