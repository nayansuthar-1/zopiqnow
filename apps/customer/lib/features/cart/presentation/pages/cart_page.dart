import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';

/// The cart: line items, the bill breakdown, and the checkout hand-off.
class CartPage extends ConsumerWidget {
  const CartPage({required this.onBrowse, super.key});

  /// Sends an empty-cart customer back to discovery.
  final VoidCallback onBrowse;

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
          : _CheckoutBar(bill: CartBill.of(cart)),
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
        _BillSummary(bill: CartBill.of(cart)),
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

class _BillSummary extends StatelessWidget {
  const _BillSummary({required this.bill});

  final CartBill bill;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      elevated: false,
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Bill details', style: t.titleMedium),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          _BillRow(label: 'Item total', value: '₹${bill.subtotal}'),
          _BillRow(
            label: 'Delivery fee',
            value: bill.hasFreeDelivery ? 'FREE' : '₹${bill.deliveryFee}',
            valueColor: bill.hasFreeDelivery ? zc.veg : null,
          ),
          _BillRow(label: 'Taxes', value: '₹${bill.taxes}'),
          if (!bill.hasFreeDelivery) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add ₹${bill.amountToFreeDelivery} more for free delivery',
                style: t.bodySmall?.copyWith(color: zc.primary),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
            child: Divider(color: zc.divider),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('To pay', style: t.titleMedium),
              Text('₹${bill.total}', style: t.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: t.bodyMedium?.copyWith(color: zc.textMuted)),
          Text(
            value,
            style: t.bodyMedium?.copyWith(color: valueColor ?? zc.textStrong),
          ),
        ],
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.bill});

  final CartBill bill;

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
              // Checkout needs an address and a payment provider, neither of
              // which exists yet (DEVELOPMENT_PLAN steps 5 and 6). Say so
              // rather than wiring a button to nothing.
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Checkout arrives with addresses and payments.',
                  ),
                ),
              ),
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
