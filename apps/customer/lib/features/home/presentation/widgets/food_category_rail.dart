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
    this.selectedId,
    super.key,
  });

  final List<FoodCategory> categories;
  final ValueChanged<FoodCategory>? onTapCategory;

  /// Which tile is currently being browsed, or null on Home where none is.
  final String? selectedId;

  /// The diameter of a category disc, everywhere it is drawn. Public because
  /// the "View More" sheet draws the same discs and has to draw them the same
  /// size — a grid that sized its art from the cell instead came out at nearly
  /// twice this, and the two screens stopped looking like one product.
  static const double artSize = 58;

  static const double _tileWidth = 66;

  /// The bar under the selected tile. Reserved on Home too, where nothing is
  /// selected — the rail is the same widget on both screens, and a height that
  /// changed with selection would make the whole feed jump on the way in.
  static const double indicatorHeight = 3;
  static const double _indicatorGap = 5;

  /// Art + top pad + gap + one line of label + the selection bar, so the rail
  /// never reflows on long names.
  static const double railHeight =
      artSize +
      ZopiqSpacing.lg +
      ZopiqSpacing.sm +
      18 +
      _indicatorGap +
      indicatorHeight;

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
              selected: category.id == selectedId,
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
  const _CategoryTile({
    required this.category,
    this.selected = false,
    this.onTap,
  });

  final FoodCategory category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    // The bar carries two facts at once: which category is open, and whether it
    // is vegetarian. Same green and red the veg indicator uses on every dish, so
    // it needs no explaining.
    final Color accent = category.isVeg ? zc.veg : zc.nonVeg;

    return ZopiqPressable(
      onTap: onTap,
      child: SizedBox(
        width: FoodCategoryRail._tileWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CategoryArt(category: category, size: FoodCategoryRail.artSize),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : null,
                color: selected ? zc.textStrong : null,
              ),
            ),
            const SizedBox(height: FoodCategoryRail._indicatorGap),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              height: FoodCategoryRail.indicatorHeight,
              width: selected ? FoodCategoryRail._tileWidth * 0.62 : 0,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(
                  FoodCategoryRail.indicatorHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
