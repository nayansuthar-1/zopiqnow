import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart';

/// One past order in full: the lines as they were charged, the bill that was
/// actually billed, and where it went.
///
/// Every number here is read from the order, never recomputed. `CartBill` prices
/// a *cart* — a live thing, at today's prices — and running it over a receipt
/// would quietly re-derive history: a delivery-fee rule that changes next month
/// would change what last month's order appears to have cost.
class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final CustomerOrder? order = ref.watch(orderByIdProvider(orderId));

    // A cold deep link to /orders/ZPQ-1042: the history is not loaded, so there
    // is nothing to render. Send them to the list, which loads it.
    if (order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Order not found', style: t.titleMedium),
                const SizedBox(height: ZopiqSpacing.xl),
                ZopiqButton(
                  label: 'Your orders',
                  expand: false,
                  onPressed: () => context.goNamed(Routes.orders),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(order.id)),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.pageGutter,
          vertical: ZopiqSpacing.lg,
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(order.restaurantName, style: t.titleLarge),
                    const SizedBox(height: ZopiqSpacing.xxs),
                    Text(
                      formatOrderTimestamp(order.placedAt),
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZopiqSpacing.sm),
              OrderStatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: ZopiqSpacing.lg),

          ZopiqCard(
            elevated: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Items', style: t.titleSmall),
                const SizedBox(height: ZopiqSpacing.md),
                for (final OrderLine line in order.lines) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${line.quantity} × ${line.name}',
                          style: t.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: ZopiqSpacing.sm),
                      Text('₹${line.lineTotal}', style: t.bodyMedium),
                    ],
                  ),
                  if (line != order.lines.last)
                    const SizedBox(height: ZopiqSpacing.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: ZopiqSpacing.md),

          ZopiqCard(
            elevated: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Bill', style: t.titleSmall),
                const SizedBox(height: ZopiqSpacing.md),
                _BillRow(label: 'Item total', amount: order.subtotal),
                const SizedBox(height: ZopiqSpacing.sm),
                _BillRow(
                  label: 'Delivery fee',
                  amount: order.deliveryFee,
                  // A ₹0 fee is a thing the customer was given, not a thing that
                  // didn't happen. "FREE" says so.
                  freeWhenZero: true,
                ),
                const SizedBox(height: ZopiqSpacing.sm),
                _BillRow(label: 'Taxes', amount: order.taxes),
                if (order.discount > 0) ...<Widget>[
                  const SizedBox(height: ZopiqSpacing.sm),
                  _BillRow(
                    label: order.couponCode == null
                        ? 'Discount'
                        : 'Discount (${order.couponCode})',
                    amount: -order.discount,
                    highlight: true,
                  ),
                ],
                const SizedBox(height: ZopiqSpacing.md),
                Divider(height: 1, color: zc.divider),
                const SizedBox(height: ZopiqSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(child: Text('Total paid', style: t.titleSmall)),
                    Text('₹${order.total}', style: t.titleSmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: ZopiqSpacing.md),

          ZopiqCard(
            elevated: false,
            child: Column(
              children: <Widget>[
                _DetailRow(
                  icon: Icons.location_on_rounded,
                  text: 'Delivered to ${order.deliveryTo}',
                ),
                const SizedBox(height: ZopiqSpacing.md),
                _DetailRow(
                  icon: Icons.payments_outlined,
                  text: order.paymentMethod == PaymentMethod.cod
                      ? 'Cash on delivery'
                      : 'Paid online · ${order.paymentId}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.amount,
    this.highlight = false,
    this.freeWhenZero = false,
  });

  final String label;

  /// Negative for a discount, which is rendered as `−₹50`.
  final int amount;

  final bool highlight;
  final bool freeWhenZero;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Color? color = highlight ? zc.veg : null;

    final String value = amount < 0
        ? '−₹${-amount}'
        : (freeWhenZero && amount == 0 ? 'FREE' : '₹$amount');

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: t.bodyMedium?.copyWith(color: color ?? zc.textMuted),
          ),
        ),
        Text(value, style: t.bodyMedium?.copyWith(color: color)),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: zc.primary),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(child: Text(text, style: t.bodyMedium)),
      ],
    );
  }
}
