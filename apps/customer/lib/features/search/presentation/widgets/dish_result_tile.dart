import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/home/domain/entities/dish_suggestion.dart';
import 'package:zopiqnow/features/home/presentation/widgets/dish_rail.dart'
    show addSuggestedDish;
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;

/// One dish in the search results — a full-width row rather than a rail card.
///
/// Close to the menu's own dish row on purpose, with one difference that matters
/// here: it names the restaurant. On a menu screen that is the heading above
/// everything; in a search that crosses every kitchen on the platform, a dish
/// with no kitchen on it is unplaceable.
///
/// Unlike the Recommended rail, a paused kitchen's dish is still listed — a
/// deliberate query deserves its answer — with the ADD control greyed out and
/// the reason said in words.
class DishResultTile extends ConsumerWidget {
  const DishResultTile({required this.dish, required this.onTap, super.key});

  final DishSuggestion dish;

  /// Opens the dish where the rest of its menu is.
  final VoidCallback onTap;

  static const double _artWidth = 96;
  static const double _imageHeight = 88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool open = dish.restaurant.acceptingOrders;

    final int quantity = ref.watch(
      cartProvider.select((Cart c) => c.quantityOf(dish.item.id)),
    );

    return InkWell(
      // The ADD control inside handles its own taps and wins over this one, so
      // tapping ADD adds and tapping anywhere else opens the menu.
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: zc.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      ZopiqVegIndicator(isVeg: dish.item.isVeg, size: 13),
                      const SizedBox(width: ZopiqSpacing.xs),
                      Expanded(
                        child: Text(
                          dish.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          dish.restaurant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(color: zc.textMuted),
                        ),
                      ),
                      const SizedBox(width: ZopiqSpacing.xs),
                      Icon(Icons.star_rounded, size: 13, color: zc.rating),
                      const SizedBox(width: ZopiqSpacing.xxs),
                      Text(
                        dish.restaurant.rating.toStringAsFixed(1),
                        style: t.labelMedium?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZopiqSpacing.xs),
                  Text(
                    // A customisable dish's price is a floor — options add to it.
                    dish.item.isCustomizable
                        ? '₹${dish.item.price} onwards'
                        : '₹${dish.item.price}',
                    style: t.titleSmall,
                  ),
                  if (!open) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xs),
                    Text(
                      dish.restaurant.pauseReason.isEmpty
                          ? 'Not taking orders right now'
                          : dish.restaurant.pauseReason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: ZopiqSpacing.lg),
            SizedBox(
              width: _artWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: _imageHeight,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: ZopiqRadii.rMd,
                      child: ZopiqNetworkImage(
                        url: dish.item.imageUrl,
                        fallback: GradientImagePlaceholder(
                          seed: dish.item.id,
                          icon: Icons.fastfood_rounded,
                          iconSize: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: ZopiqSpacing.sm),
                  AddToCartControl(
                    // A customisable dish always shows ADD — each tap re-opens
                    // the choice sheet, since taps may build different
                    // configurations. The stepper is for plain dishes, whose
                    // single cart line is keyed by the dish id.
                    quantity: dish.item.isCustomizable ? 0 : quantity,
                    width: double.infinity,
                    enabled: open,
                    onAdd: () => addSuggestedDish(context, ref, dish),
                    onIncrement: () =>
                        ref.read(cartProvider.notifier).increment(dish.item.id),
                    onDecrement: () =>
                        ref.read(cartProvider.notifier).decrement(dish.item.id),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
