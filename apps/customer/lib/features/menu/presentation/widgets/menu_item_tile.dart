import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/dish_add_flow.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/dish_detail_sheet.dart';

/// One dish row: details on the left, art + the ADD control on the right.
///
/// A summary, and kept one — tapping it opens [showDishDetailSheet] for the
/// photo at a readable size, the whole description, and anything else the
/// restaurant has said about the dish.
class MenuItemTile extends ConsumerWidget {
  const MenuItemTile({
    required this.item,
    required this.restaurantId,
    required this.restaurantName,
    this.enabled = true,
    super.key,
  });

  final MenuItem item;
  final String restaurantId;
  final String restaurantName;

  /// Whether this dish can be added. False when the restaurant is closed — the
  /// ADD control is inert, though the real refusal lives in `place_order`.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    // Watch only this item's quantity: adding dish A must not rebuild dish B.
    final int quantity = ref.watch(
      cartProvider.select((c) => c.quantityOf(item.id)),
    );

    return InkWell(
      // The ADD control sits inside this row and handles its own taps, so it
      // wins over this one — tapping ADD adds, tapping anywhere else opens the
      // dish. The whole row is the target because a two-line description clipped
      // mid-sentence is the thing that makes somebody want a closer look.
      onTap: () => showDishDetailSheet(
        context,
        item: item,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        enabled: enabled,
      ),
      // A hairline under every row, rather than rows floating in whitespace.
      // On a menu where a dish is a photo, a price and three lines of text, the
      // line is what tells the eye where one dish ends and the next begins.
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.lg),
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
                  ZopiqVegIndicator(isVeg: item.isVeg),
                  if (item.isBestseller) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xs),
                    _BestsellerTag(color: zc.primaryDeep),
                  ],
                  const SizedBox(height: ZopiqSpacing.xs),
                  Text(
                    item.name,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Row(
                    children: <Widget>[
                      Text(
                        // A customisable dish's price is a floor — options add to it.
                        item.isCustomizable
                            ? '₹${item.price} onwards'
                            : '₹${item.price}',
                        style: t.titleSmall,
                      ),
                      // The restaurant's stated former price. Struck through and
                      // muted, after the live price, so the number that is charged
                      // is the one the eye lands on first.
                      if (item.originalPrice != null) ...<Widget>[
                        const SizedBox(width: ZopiqSpacing.xs),
                        Text(
                          '₹${item.originalPrice}',
                          style: t.bodySmall?.copyWith(
                            color: zc.textMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.rating != null ||
                      item.prepMinutes != null) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xs),
                    Row(
                      children: <Widget>[
                        if (item.rating != null)
                          _ItemRating(rating: item.rating!, color: zc.rating),
                        if (item.rating != null && item.prepMinutes != null)
                          const SizedBox(width: ZopiqSpacing.sm),
                        if (item.prepMinutes != null)
                          Text(
                            '${item.prepMinutes} min',
                            style: t.labelMedium?.copyWith(color: zc.textMuted),
                          ),
                      ],
                    ),
                  ],
                  if (item.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.sm),
                    // Two lines and then "more" — the ellipsis alone says the
                    // text was cut, and says nothing about there being anywhere
                    // to read the rest. Tapping anywhere on the row opens it, so
                    // this is a label on the gesture rather than a second target
                    // that would compete with it.
                    RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        text: item.description,
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                        children: <InlineSpan>[
                          TextSpan(
                            text: '  more',
                            style: t.bodySmall?.copyWith(
                              color: zc.textStrong,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: ZopiqSpacing.lg),
            _ItemArtAndControl(
              item: item,
              // A customisable dish always shows ADD (each tap re-opens the choice
              // sheet, since taps may build different configurations); the tile's
              // stepper is for plain dishes, whose single line is keyed by the id.
              quantity: item.isCustomizable ? 0 : quantity,
              enabled: enabled,
              onAdd: () => addDishToCart(
                context,
                ref,
                item: item,
                restaurantId: restaurantId,
                restaurantName: restaurantName,
              ),
              onIncrement: () =>
                  ref.read(cartProvider.notifier).increment(item.id),
              onDecrement: () =>
                  ref.read(cartProvider.notifier).decrement(item.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemArtAndControl extends StatelessWidget {
  const _ItemArtAndControl({
    required this.item,
    required this.quantity,
    required this.enabled,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  final MenuItem item;
  final int quantity;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  static const double _width = 118;
  static const double _imageHeight = 96;
  static const double _totalHeight = 118;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _totalHeight,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _imageHeight,
            child: ClipRRect(
              borderRadius: ZopiqRadii.rMd,
              child: ZopiqNetworkImage(
                url: item.imageUrl,
                // Plenty of dishes have no photo. That is not an error state.
                fallback: GradientImagePlaceholder(
                  seed: item.id,
                  icon: Icons.fastfood_rounded,
                  iconSize: 28,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 7,
            right: 7,
            child: AddToCartControl(
              quantity: quantity,
              enabled: enabled,
              onAdd: onAdd,
              onIncrement: onIncrement,
              onDecrement: onDecrement,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestsellerTag extends StatelessWidget {
  const _BestsellerTag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.star_rounded, size: 14, color: color),
        const SizedBox(width: ZopiqSpacing.xxs),
        Text(
          'Bestseller',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ItemRating extends StatelessWidget {
  const _ItemRating({required this.rating, required this.color});

  final double rating;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.star_rounded, size: 14, color: color),
        const SizedBox(width: ZopiqSpacing.xxs),
        Text(
          rating.toStringAsFixed(1),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
