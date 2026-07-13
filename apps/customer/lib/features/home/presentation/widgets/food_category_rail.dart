import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/presentation/widgets/category_art.dart';

/// The "What's on your mind?" rail — a horizontally scrolling row of circular
/// dish categories.
class FoodCategoryRail extends StatelessWidget {
  const FoodCategoryRail({
    required this.categories,
    this.onTapCategory,
    super.key,
  });

  final List<FoodCategory> categories;
  final ValueChanged<FoodCategory>? onTapCategory;

  static const double _artSize = 40;
  static const double _tileWidth = 48;

  /// Art + top pad + gap + one line of label, so the rail never reflows on long names.
  static const double railHeight = _artSize + ZopiqSpacing.lg + ZopiqSpacing.sm + 18;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(
          left: ZopiqSpacing.md,
          right: ZopiqSpacing.md,
          top: ZopiqSpacing.lg,
        ),
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          final FoodCategory category = categories[i];
          // Each tile paints independently: pressing one must not repaint the row.
          return RepaintBoundary(
            child: _CategoryTile(
              category: category,
              onTap: onTapCategory == null
                  ? null
                  : () => onTapCategory!(category),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, this.onTap});

  final FoodCategory category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ZopiqPressable(
      onTap: onTap,
      child: SizedBox(
        width: FoodCategoryRail._tileWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CategoryArt(category: category, size: FoodCategoryRail._artSize),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}
