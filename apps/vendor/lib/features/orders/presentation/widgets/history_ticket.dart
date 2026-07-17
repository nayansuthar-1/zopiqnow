import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_detail_sheet.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_lines.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_status_badge.dart';

/// A finished order, as a record rather than a task.
///
/// The same facts as the live ticket minus the buttons — there is nothing left
/// to press. What it adds is the one thing the queue never shows: how the order
/// *ended*, delivered or cancelled, because that is the only reason to open this
/// screen at all. Tapping it opens the full bill.
class HistoryTicket extends StatelessWidget {
  const HistoryTicket({required this.order, super.key});

  final VendorOrder order;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xs,
      ),
      child: ZopiqCard(
        onTap: () => showOrderDetail(context, order),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    order.id,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                OrderStatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.xxs),
            Text(
              formatOrderDate(order.placedAt),
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            OrderLines(orderId: order.id),

            const SizedBox(height: ZopiqSpacing.md),
            Divider(height: 1, color: zc.divider),
            const SizedBox(height: ZopiqSpacing.md),

            _Detail(
              icon: order.paymentMethod.isCash
                  ? Icons.payments_outlined
                  : Icons.check_circle_outline_rounded,
              text: order.paymentMethod.isCash
                  ? 'Cash · ${formatRupees(order.total)}'
                  : 'Paid online · ${formatRupees(order.total)}',
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            _Detail(icon: Icons.location_on_rounded, text: order.deliveryTo),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: zc.textMuted),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
        ),
      ],
    );
  }
}
