import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/account/presentation/providers/veg_mode_provider.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/category_art.dart';
import 'package:zopiqnow/features/home/presentation/widgets/food_category_rail.dart';

/// The "View More" sheet: the full dish grid the Home rail only shows a slice
/// of. Opens at just over half the screen and can be dragged taller, which is
/// the shape a person expects from a browse sheet — enough to see there is more
/// without covering the screen they came from.
Future<void> showMoreCategoriesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // The sheet paints its own rounded surface, so the route must not paint a
    // second one behind it.
    backgroundColor: Colors.transparent,
    builder: (_) => const MoreCategoriesSheet(),
  );
}

class MoreCategoriesSheet extends ConsumerWidget {
  const MoreCategoriesSheet({super.key});

  /// The resting height, and the one snap it settles back to.
  static const double _restingExtent = 0.55;

  /// One grid cell: the same disc the Home rail draws, a gap, and two lines of
  /// label. Two rather than the rail's one because four across is a narrower
  /// column and this list has the long names in it — "White Sauce Pasta".
  ///
  /// The label's share is scaled rather than fixed. 18 per line is the rail's
  /// own budget; at 1.4× accessibility text a constant would leave the second
  /// line half-drawn, which the `Expanded` below would clip rather than
  /// complain about — a silent wrong, and the worst kind.
  static double _tileHeight(BuildContext context) =>
      FoodCategoryRail.artSize +
      ZopiqSpacing.sm +
      MediaQuery.textScalerOf(context).scale(18) * 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ZopiqColors zc = context.zc;
    final List<FoodCategory> categories = ref.watch(moreFoodCategoriesProvider);
    final bool vegOnly = ref.watch(vegModeProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: _restingExtent,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      // Snapping is what makes the drag feel like two positions rather than a
      // free-floating panel: let go anywhere and it settles at half or full.
      snap: true,
      snapSizes: const <double>[_restingExtent],
      builder: (BuildContext context, ScrollController controller) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZopiqRadii.xl),
            ),
          ),
          child: Column(
            children: <Widget>[
              const _DragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZopiqSpacing.pageGutter,
                  0,
                  ZopiqSpacing.sm,
                  ZopiqSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'What\'s on your mind?',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    // The mode is set on the Account page, so say why meat is
                    // missing rather than leaving a shorter grid unexplained.
                    if (vegOnly) ...<Widget>[
                      const ZopiqVegIndicator(isVeg: true),
                      const SizedBox(width: ZopiqSpacing.xs),
                      Text(
                        'Veg only',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: zc.veg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: zc.textMuted,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                    ZopiqSpacing.pageGutter,
                    ZopiqSpacing.sm,
                    ZopiqSpacing.pageGutter,
                    ZopiqSpacing.xl,
                  ),
                  physics: const BouncingScrollPhysics(),
                  // Four across, and a fixed row height rather than an aspect
                  // ratio. The art is a constant size, so a ratio would only be
                  // a way of expressing that constant in terms of the screen
                  // width and getting it wrong on the next screen size.
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: ZopiqSpacing.sm,
                    mainAxisSpacing: ZopiqSpacing.lg,
                    mainAxisExtent: _tileHeight(context),
                  ),
                  itemCount: categories.length,
                  itemBuilder: (BuildContext context, int i) => RepaintBoundary(
                    child: _CategoryGridTile(category: categories[i]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: context.zc.textMuted.withValues(alpha: 0.35),
          borderRadius: ZopiqRadii.rXs,
        ),
      ),
    );
  }
}

class _CategoryGridTile extends StatelessWidget {
  const _CategoryGridTile({required this.category});

  final FoodCategory category;

  @override
  Widget build(BuildContext context) {
    return ZopiqPressable(
      // Closed first, then pushed — a sheet left open behind a page it opened is
      // still there when Back returns.
      onTap: () {
        Navigator.of(context).pop();
        context.pushNamed(
          Routes.category,
          pathParameters: <String, String>{'id': category.id},
        );
      },
      child: Column(
        children: <Widget>[
          // The Home rail's disc, at the Home rail's size. It used to be sized
          // from the grid cell, which made it grow with the screen and land at
          // nearly twice the rail's — the same dish, twice as big, one tap away.
          CategoryArt(category: category, size: FoodCategoryRail.artSize),
          const SizedBox(height: ZopiqSpacing.sm),
          Expanded(
            child: Text(
              category.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}
