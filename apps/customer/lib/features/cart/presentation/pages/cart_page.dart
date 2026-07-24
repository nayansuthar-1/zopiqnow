import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/bill_summary.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;

/// The cart: what's in it, what it costs, and the hand-off to checkout.
class CartPage extends ConsumerWidget {
  const CartPage({required this.onBrowse, required this.onCheckout, super.key});

  /// Sends an empty-cart customer back to discovery.
  final VoidCallback onBrowse;

  /// Opens checkout. The route is auth-guarded, so a signed-out customer lands
  /// on the login screen and is returned here-onward after verifying.
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Cart cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your cart'),
        actions: <Widget>[
          if (cart.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context, ref),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: cart.isEmpty
          ? _EmptyCart(onBrowse: onBrowse)
          : _CartBody(cart: cart),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CheckoutBar(
              bill: CartBill.of(cart),
              itemCount: cart.itemCount,
              onCheckout: onCheckout,
            ),
    );
  }

  /// Clearing a cart the customer spent five minutes building is not something
  /// to do on one stray tap of a text button in the corner.
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Empty your cart?'),
        content: const Text('Everything in it will be removed.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Empty cart'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) ref.read(cartProvider.notifier).clear();
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.lg,
        ZopiqSpacing.lg,
        ZopiqSpacing.lg,
        ZopiqSpacing.xl,
      ),
      children: <Widget>[
        ZopiqReveal(child: _RestaurantHeader(cart: cart)),
        const SizedBox(height: ZopiqSpacing.md),
        ZopiqReveal(
          index: 1,
          child: ZopiqCard(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < cart.lines.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(height: ZopiqSpacing.lg, color: context.zc.divider),
                  _CartLineTile(
                    key: ValueKey<String>(cart.lines[i].lineId),
                    line: cart.lines[i],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        ZopiqReveal(index: 2, child: BillSummary(bill: CartBill.of(cart))),
      ],
    );
  }
}

/// Who is cooking this, and how much of it there is. The cart used to say this
/// in the app-bar title, where a long restaurant name was truncated to nothing.
class _RestaurantHeader extends StatelessWidget {
  const _RestaurantHeader({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final int count = cart.itemCount;

    return Row(
      children: <Widget>[
        ClipRRect(
          borderRadius: ZopiqRadii.rMd,
          child: SizedBox.square(
            dimension: 44,
            child: GradientImagePlaceholder(
              seed: cart.restaurantId ?? '',
              icon: Icons.storefront_rounded,
              iconSize: 20,
            ),
          ),
        ),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                cart.restaurantName ?? 'Your order',
                style: t.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$count item${count == 1 ? '' : 's'}',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line, super.key});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CartNotifier cart = ref.read(cartProvider.notifier);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey<String>('dismiss-${line.lineId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: ZopiqSpacing.lg),
        decoration: BoxDecoration(
          color: zc.nonVeg.withValues(alpha: 0.12),
          borderRadius: ZopiqRadii.rMd,
        ),
        child: Icon(Icons.delete_outline_rounded, color: zc.nonVeg),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        final CartLine removed = line;
        // Captured *before* the removal: taking out the last line empties the
        // cart, and an empty cart has no restaurant. Undo would otherwise put
        // the dish back into a cart that belongs to nobody.
        final Cart before = ref.read(cartProvider);
        cart.removeLine(removed.lineId);
        // Undo, not "are you sure?". A swipe is a confident gesture and a
        // dialog after one is an insult; but a swipe is also easy to do by
        // accident, so the way back has to be one tap and it has to be here.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${removed.item.name} removed'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => cart.restoreLine(
                  removed,
                  restaurantId: before.restaurantId,
                  restaurantName: before.restaurantName,
                ),
              ),
            ),
          );
      },
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: ZopiqRadii.rSm,
            child: SizedBox.square(
              dimension: 48,
              child: ZopiqNetworkImage(
                url: line.item.imageUrl,
                fallback: GradientImagePlaceholder(
                  seed: line.item.id,
                  icon: Icons.restaurant_menu_rounded,
                  iconSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ZopiqVegIndicator(isVeg: line.item.isVeg),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Expanded(
                      child: Text(
                        line.item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge,
                      ),
                    ),
                  ],
                ),
                // The chosen variant/add-ons, if any — "Full, Extra cheese".
                if (line.options.isNotEmpty) ...<Widget>[
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    line.optionsLabel,
                    style: t.bodySmall?.copyWith(color: zc.primary),
                  ),
                ],
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  // The as-configured unit price, base plus options.
                  '₹${line.unitPrice}',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: ZopiqSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              AddToCartControl(
                quantity: line.quantity,
                // A line only exists at quantity >= 1, so ADD is unreachable.
                onAdd: () => cart.increment(line.lineId),
                onIncrement: () => cart.increment(line.lineId),
                onDecrement: () => cart.decrement(line.lineId),
                width: 96,
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              ZopiqAnimatedAmount(
                amount: line.lineTotal,
                style: t.titleSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The sticky hand-off. Lifted off the page with a shadow rather than a divider,
/// so the list feels like it runs *under* it — which it does.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.bill,
    required this.itemCount,
    required this.onCheckout,
  });

  final CartBill bill;
  final int itemCount;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: zc.cardShadow,
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(ZopiqSpacing.lg),
        child: Row(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ZopiqAnimatedAmount(amount: bill.total, style: t.titleLarge),
                Text(
                  'Total · $itemCount item${itemCount == 1 ? '' : 's'}',
                  style: t.labelSmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
            const SizedBox(width: ZopiqSpacing.lg),
            Expanded(
              child: ZopiqButton(
                label: 'Proceed to checkout',
                variant: ZopiqButtonVariant.cta,
                icon: Icons.arrow_forward_rounded,
                onPressed: onCheckout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: ZopiqReveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  size: 52,
                  color: zc.primary,
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              Text('Your cart is empty', style: t.titleMedium),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Good food is always cooking. Go ahead, order some.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqButton(
                label: 'Browse restaurants',
                expand: false,
                onPressed: onBrowse,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
