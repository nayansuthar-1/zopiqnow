import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_tracking_card.dart';

/// One order in full: where it is right now if it is still coming, and the lines
/// as they were charged, the bill that was actually billed, and where it went.
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
    final AsyncValue<CustomerOrder?> order = ref.watch(
      orderByIdProvider(orderId),
    );

    return order.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // The fetch failed — which is not the same as "no such order", and must
      // not be told to the customer as though it were.
      error: (Object _, StackTrace _) => _OrderMessage(
        title: 'We couldn\'t load this order',
        body: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(orderByIdProvider(orderId)),
      ),
      data: (CustomerOrder? data) => data == null
          // No such order, or not this customer's — the policy makes those the
          // same answer, deliberately.
          ? _OrderMessage(
              title: 'Order not found',
              body: 'It may belong to another account.',
              actionLabel: 'Your orders',
              onAction: () => context.goNamed(Routes.orders),
            )
          : _OrderBody(order: data),
    );
  }
}

class _OrderBody extends StatelessWidget {
  const _OrderBody({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    // An order still on its way gets the live timeline; a finished one gets the
    // chip. Only one of them says what the status is, so the two never contradict
    // each other — a static chip beside a live card is a chip that goes stale.
    final bool isOpen = order.status.isOpen;

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
              if (!isOpen) ...<Widget>[
                const SizedBox(width: ZopiqSpacing.sm),
                OrderStatusChip(status: order.status),
              ],
            ],
          ),
          const SizedBox(height: ZopiqSpacing.lg),

          if (isOpen) ...<Widget>[
            OrderTrackingCard(order: order),
            const SizedBox(height: ZopiqSpacing.md),
          ],

          ZopiqCard(
            elevated: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Items', style: t.titleSmall),
                const SizedBox(height: ZopiqSpacing.md),
                for (final OrderLine line in order.lines) ...<Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${line.quantity} × ${line.name}',
                              style: t.bodyMedium,
                            ),
                            // The variant/add-ons chosen, if any.
                            if (line.options.isNotEmpty)
                              Text(
                                line.optionsLabel,
                                style: t.bodySmall?.copyWith(
                                  color: context.zc.textMuted,
                                ),
                              ),
                          ],
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
                    Expanded(
                      // The screen is now shown *before* the food arrives, and
                      // a cash order that has not been handed over has not been
                      // paid. The word has to earn itself.
                      child: Text(
                        isOpen ? 'Total' : 'Total paid',
                        style: t.titleSmall,
                      ),
                    ),
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
                  text: isOpen
                      ? 'Delivering to ${order.deliveryTo}'
                      : 'Delivered to ${order.deliveryTo}',
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

/// The two dead ends — "no such order" and "we couldn't ask" — which differ only
/// in their words and in whether the button retries or leaves.
class _OrderMessage extends StatelessWidget {
  const _OrderMessage({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, style: t.titleMedium),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                body,
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqButton(
                label: actionLabel,
                expand: false,
                onPressed: onAction,
              ),
            ],
          ),
        ),
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
