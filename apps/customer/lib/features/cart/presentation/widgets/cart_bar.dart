import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';

/// Sticky bottom bar summarising the cart with a call-to-action. Renders
/// nothing when the cart is empty, and animates in/out on the first/last item.
class CartBar extends ConsumerWidget {
  const CartBar({required this.onViewCart, super.key});

  final VoidCallback onViewCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Cart cart = ref.watch(cartProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return AnimatedSwitcher(
      duration: ZopiqDurations.base,
      switchInCurve: ZopiqCurves.emphasized,
      transitionBuilder: (Widget child, Animation<double> anim) => SizeTransition(
        sizeFactor: anim,
        child: child,
      ),
      child: cart.isEmpty
          ? const SizedBox.shrink()
          : SafeArea(
              key: const ValueKey<String>('cart-bar'),
              minimum: const EdgeInsets.all(ZopiqSpacing.lg),
              child: Material(
                color: zc.primaryDeep,
                borderRadius: ZopiqRadii.rMd,
                child: InkWell(
                  borderRadius: ZopiqRadii.rMd,
                  onTap: onViewCart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZopiqSpacing.lg,
                      vertical: ZopiqSpacing.md,
                    ),
                    child: Row(
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${cart.itemCount} ${cart.itemCount == 1 ? 'item' : 'items'}',
                              style: t.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                            Text(
                              '₹${cart.subtotal}',
                              style: t.titleMedium?.copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          'View cart',
                          style: t.labelLarge?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(width: ZopiqSpacing.xs),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
