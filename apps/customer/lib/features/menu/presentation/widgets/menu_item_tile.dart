import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

/// One dish row: details on the left, art + the ADD control on the right.
///
/// Owns the "this cart belongs to another restaurant" prompt, because that
/// decision belongs to the moment of adding, not to the cart screen.
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

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final CartNotifier cart = ref.read(cartProvider.notifier);
    final AddToCartResult result = cart.add(
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      item: item,
    );
    if (result == AddToCartResult.added) return;

    final String? existing = ref.read(cartProvider).restaurantName;
    final bool? replace = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Start a new cart?'),
        content: Text(
          'Your cart has items from $existing. Adding this dish will empty it.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep my cart'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start new cart'),
          ),
        ],
      ),
    );

    if (replace ?? false) {
      cart.startNewCartWith(
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        item: item,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    // Watch only this item's quantity: adding dish A must not rebuild dish B.
    final int quantity = ref.watch(
      cartProvider.select((c) => c.quantityOf(item.id)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.lg),
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
                Text(item.name, style: t.titleMedium),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text('₹${item.price}', style: t.titleSmall),
                if (item.rating != null) ...<Widget>[
                  const SizedBox(height: ZopiqSpacing.xs),
                  _ItemRating(rating: item.rating!, color: zc.rating),
                ],
                const SizedBox(height: ZopiqSpacing.sm),
                Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: ZopiqSpacing.lg),
          _ItemArtAndControl(
            item: item,
            quantity: quantity,
            enabled: enabled,
            onAdd: () => _add(context, ref),
            onIncrement: () =>
                ref.read(cartProvider.notifier).increment(item.id),
            onDecrement: () =>
                ref.read(cartProvider.notifier).decrement(item.id),
          ),
        ],
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
