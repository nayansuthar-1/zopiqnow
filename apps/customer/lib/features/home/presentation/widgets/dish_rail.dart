import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/home/domain/entities/dish_suggestion.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;
import 'package:zopiqnow/features/menu/presentation/widgets/dish_add_flow.dart';

/// A horizontal rail of dishes — the shape "Recommended for you" takes now.
///
/// It used to be a rail of restaurants, which asked the customer to pick a
/// kitchen and then go find something to eat in it. A dish is the thing being
/// recommended, so a dish is what the card shows, and the ADD button means the
/// recommendation can be taken without leaving Home.
class DishRail extends StatelessWidget {
  const DishRail({required this.dishes, required this.onOpenDish, super.key});

  final List<DishSuggestion> dishes;

  /// Tapping the card — anywhere but the ADD control, which handles its own
  /// taps — opens the dish where the rest of its menu is.
  final ValueChanged<DishSuggestion> onOpenDish;

  static const double _cardWidth = 156;

  /// Fixed, because a horizontally scrolling list has to be given a height.
  ///
  /// The card's parts add up to about 226 at the default text scale — photo,
  /// four single lines, and a 36pt ADD control that does not scale. The slack on
  /// top is for the ones that do: at the largest system font sizes those four
  /// lines grow by roughly 20pt in total, and a card that overflows its rail is
  /// a black-and-yellow bar across the middle of Home.
  static const double _railHeight = 248;

  @override
  Widget build(BuildContext context) {
    if (dishes.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: ZopiqSpacing.pagePadding,
        physics: const BouncingScrollPhysics(),
        itemCount: dishes.length,
        separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.md),
        itemBuilder: (BuildContext context, int i) => RepaintBoundary(
          child: SizedBox(
            width: _cardWidth,
            child: _DishCard(
              dish: dishes[i],
              onTap: () => onOpenDish(dishes[i]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Photo, what it is, who cooks it, what it costs, and a way to add it.
///
/// The ADD control sits under the photo rather than straddling it — the same
/// call the menu row made, and for the same reason: the column then takes its
/// own height instead of one that has to be kept in step with the control's.
class _DishCard extends ConsumerWidget {
  const _DishCard({required this.dish, required this.onTap});

  final DishSuggestion dish;
  final VoidCallback onTap;

  static const double _imageHeight = 112;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    // Watch only this dish's quantity: adding dish A must not rebuild dish B.
    final int quantity = ref.watch(
      cartProvider.select((Cart c) => c.quantityOf(dish.item.id)),
    );

    return ZopiqPressable(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: ZopiqRadii.rMd,
            child: SizedBox(
              height: _imageHeight,
              width: double.infinity,
              child: ZopiqNetworkImage(
                url: dish.item.imageUrl,
                // Plenty of dishes have no photo. That is not an error state.
                fallback: GradientImagePlaceholder(
                  seed: dish.item.id,
                  icon: Icons.fastfood_rounded,
                  iconSize: 28,
                ),
              ),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          Row(
            children: <Widget>[
              ZopiqVegIndicator(isVeg: dish.item.isVeg, size: 12),
              const SizedBox(width: ZopiqSpacing.xs),
              Expanded(
                child: Text(
                  dish.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZopiqSpacing.xxs),
          // The kitchen, not the dish: on Home a dish with no restaurant on it
          // is a price with nowhere to go.
          Text(
            dish.restaurant.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          Row(
            children: <Widget>[
              Text(
                // A customisable dish's price is a floor — options add to it.
                dish.item.isCustomizable
                    ? '₹${dish.item.price}+'
                    : '₹${dish.item.price}',
                style: t.titleSmall,
              ),
              if (dish.item.rating != null) ...<Widget>[
                const SizedBox(width: ZopiqSpacing.xs),
                Icon(Icons.star_rounded, size: 13, color: zc.rating),
                const SizedBox(width: ZopiqSpacing.xxs),
                Flexible(
                  child: Text(
                    dish.item.rating!.toStringAsFixed(1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelMedium?.copyWith(color: zc.textMuted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          AddToCartControl(
            quantity: dish.item.isCustomizable ? 0 : quantity,
            width: double.infinity,
            onAdd: () => addSuggestedDish(context, ref, dish),
            onIncrement: () =>
                ref.read(cartProvider.notifier).increment(dish.item.id),
            onDecrement: () =>
                ref.read(cartProvider.notifier).decrement(dish.item.id),
          ),
        ],
      ),
    );
  }
}

/// Adds a recommended dish to the cart.
///
/// A thin wrapper over [addDishToCart] so the rail and the search results do not
/// each restate which halves of a [DishSuggestion] the cart needs. Everything
/// that can interrupt the add — the options sheet, the "start a new cart"
/// prompt when the cart belongs to another restaurant — is already handled in
/// there, which is what makes an ADD button outside a menu screen safe at all.
Future<void> addSuggestedDish(
  BuildContext context,
  WidgetRef ref,
  DishSuggestion dish,
) {
  return addDishToCart(
    context,
    ref,
    item: dish.item,
    restaurantId: dish.restaurant.id,
    restaurantName: dish.restaurant.name,
  );
}
