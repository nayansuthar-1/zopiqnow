import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/bill_summary.dart';

/// The cart: line items, the bill breakdown, and the checkout hand-off.
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
        title: Text(cart.isEmpty ? 'Cart' : cart.restaurantName ?? 'Cart'),
        actions: <Widget>[
          if (cart.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: cart.isEmpty
          ? _EmptyCart(onBrowse: onBrowse)
          : _CartBody(cart: cart),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CheckoutBar(bill: CartBill.of(cart), onCheckout: onCheckout),
    );
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      children: <Widget>[
        for (final CartLine line in cart.lines)
          _CartLineTile(key: ValueKey<String>(line.item.id), line: line),
        const SizedBox(height: ZopiqSpacing.xl),
        BillSummary(bill: CartBill.of(cart)),
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
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.lg),
      child: Row(
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
          const SizedBox(width: ZopiqSpacing.sm),
          AddToCartControl(
            quantity: line.quantity,
            // A line only exists at quantity >= 1, so ADD is unreachable here.
            onAdd: () => cart.increment(line.item.id),
            onIncrement: () => cart.increment(line.item.id),
            onDecrement: () => cart.decrement(line.item.id),
            width: 96,
          ),
          const SizedBox(width: ZopiqSpacing.md),
          SizedBox(
            width: 64,
            child: Text(
              '₹${line.lineTotal}',
              textAlign: TextAlign.end,
              style: t.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.bill, required this.onCheckout});

  final CartBill bill;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return SafeArea(
      minimum: const EdgeInsets.all(ZopiqSpacing.lg),
      child: Row(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('₹${bill.total}', style: t.titleLarge),
              Text(
                'Total',
                style: t.labelSmall?.copyWith(color: context.zc.textMuted),
              ),
            ],
          ),
          const SizedBox(width: ZopiqSpacing.lg),
          Expanded(
            child: ZopiqButton(
              label: 'Proceed to checkout',
              variant: ZopiqButtonVariant.cta,
              onPressed: onCheckout,
            ),
          ),
        ],
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.shopping_bag_outlined, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
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
    );
  }
}
