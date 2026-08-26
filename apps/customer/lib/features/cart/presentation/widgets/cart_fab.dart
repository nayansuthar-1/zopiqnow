import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';

/// The way to the cart from a screen the shell's pills do not reach.
///
/// The category page and search both sit *outside* `StatefulShellRoute`, so
/// neither has the bottom bar — and both let a dish be added straight from a
/// card. That left the cart with no door on the screen the customer filled it
/// from: the only route to it was going back to Home first.
///
/// Deliberately not the whole navigation bar. Those screens are pushed, they
/// have a back arrow, and drawing three tabs over them would say the customer is
/// on a tab when they are not. This is one control that does one thing.
///
/// Renders nothing while the cart is empty, and grows in when the first dish
/// lands — the same appear/disappear [CartBar] does on the menu, so the cart
/// behaves the same wherever it is filled from.
class CartFab extends ConsumerWidget {
  const CartFab({super.key});

  /// Room a scroll view has to leave at its bottom so this never lands on the
  /// last row. Zero while the cart is empty, because nothing is drawn then —
  /// a permanent 88pt of blank space under a list nobody has a cart for is the
  /// opposite of the problem this widget exists to fix.
  ///
  /// A method on the button rather than a number copied into each screen: the
  /// two are the same measurement, and the day the pill changes height is the
  /// day the copies stop agreeing with it.
  static double clearance(WidgetRef ref) =>
      ref.watch(cartProvider.select((Cart c) => c.isEmpty)) ? 0 : 88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int itemCount = ref.watch(
      cartProvider.select((Cart c) => c.itemCount),
    );
    final int subtotal = ref.watch(cartProvider.select((Cart c) => c.subtotal));
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return AnimatedScale(
      duration: ZopiqDurations.base,
      curve: ZopiqCurves.emphasized,
      scale: itemCount == 0 ? 0 : 1,
      child: itemCount == 0
          ? const SizedBox.shrink()
          : Material(
              color: zc.primaryDeep,
              borderRadius: ZopiqRadii.rPill,
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.3),
              child: InkWell(
                borderRadius: ZopiqRadii.rPill,
                // `go`, not `push`: the cart is a shell branch, and pushing it
                // over a screen that is already outside the shell would stack a
                // cart on top of a category with two back arrows to unwind. The
                // menu's own "View cart" goes the same way for the same reason.
                onTap: () => context.goNamed(Routes.cart),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.lg,
                    vertical: ZopiqSpacing.md,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.shopping_cart_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: ZopiqSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                            style: t.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          Text(
                            '₹$subtotal',
                            style: t.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
