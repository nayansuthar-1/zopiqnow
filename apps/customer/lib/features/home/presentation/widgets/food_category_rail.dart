import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/core/l10n/strings.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/presentation/widgets/category_art.dart';

/// The "What's on your mind?" rail — a horizontally scrolling row of circular
/// dish categories.
class FoodCategoryRail extends StatefulWidget {
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
  State<FoodCategoryRail> createState() => _FoodCategoryRailState();
}

class _FoodCategoryRailState extends State<FoodCategoryRail> {
  final ScrollController _scroll = ScrollController();

  /// One tile plus the gap after it — what an index is worth in scroll offset.
  static const double _stride =
      FoodCategoryRail._tileWidth + ZopiqSpacing.sm;

  @override
  void initState() {
    super.initState();
    // After layout: the viewport has no width until the rail is measured, and
    // the target offset is computed against it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void didUpdateWidget(FoodCategoryRail old) {
    super.didUpdateWidget(old);
    // Switching categories from the rail itself, or arriving on a different one.
    if (old.selectedId != widget.selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the open category into view, centred where there is room for it.
  ///
  /// Without this the rail always started at "Maggi" and the selected tile could
  /// be anywhere off to the right — so a customer who tapped Manchurian landed on
  /// a page whose rail showed five other categories and no sign of the one they
  /// had chosen. The indicator bar was drawn correctly the whole time; it was
  /// just never on screen.
  ///
  /// The offset is computed rather than measured. Every tile is exactly
  /// [_stride] wide, so the arithmetic is exact and needs no per-tile keys.
  void _revealSelected() {
    if (!mounted || !_scroll.hasClients) return;

    final String? id = widget.selectedId;
    if (id == null) return;

    final int index = widget.categories.indexWhere(
      (FoodCategory c) => c.id == id,
    );
    if (index < 0) return;

    final double viewport = _scroll.position.viewportDimension;
    final double tileStart = ZopiqSpacing.md + (index * _stride);
    final double centred =
        tileStart - ((viewport - FoodCategoryRail._tileWidth) / 2);

    _scroll.animateTo(
      centred.clamp(
        _scroll.position.minScrollExtent,
        _scroll.position.maxScrollExtent,
      ),
      duration: ZopiqDurations.base,
      curve: ZopiqCurves.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: FoodCategoryRail.railHeight,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(
          left: ZopiqSpacing.md,
          right: ZopiqSpacing.md,
          top: ZopiqSpacing.lg,
        ),
        physics: const BouncingScrollPhysics(),
        itemCount: widget.categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          final FoodCategory category = widget.categories[i];
          // Each tile paints independently: pressing one must not repaint the row.
          return RepaintBoundary(
            child: _CategoryTile(
              category: category,
              selected: category.id == widget.selectedId,
              onTap: widget.onTapCategory == null
                  ? null
                  : () => widget.onTapCategory!(category),
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
              context.l10n.categoryName(category.id, category.label),
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
