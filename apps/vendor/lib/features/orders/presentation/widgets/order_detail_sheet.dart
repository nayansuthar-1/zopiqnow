import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_lines.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_status_badge.dart';

/// Opens the full record of a finished order — the bill laid out line by line,
/// the way the customer agreed to it. History's tickets stay lean (id, outcome,
/// total); this is where someone goes when a customer calls to query a charge.
Future<void> showOrderDetail(BuildContext context, VendorOrder order) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _OrderDetailSheet(order: order),
  );
}

class _OrderDetailSheet extends StatelessWidget {
  const _OrderDetailSheet({required this.order});

  final VendorOrder order;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return SafeArea(
      // Cap at most of the screen; the sheet scrolls within.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            ZopiqSpacing.pageGutter,
            0,
            ZopiqSpacing.pageGutter,
            ZopiqSpacing.xl,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    order.id,
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
            const SizedBox(height: ZopiqSpacing.lg),

            OrderLines(orderId: order.id, showPrices: true),

            const SizedBox(height: ZopiqSpacing.md),
            Divider(height: 1, color: zc.divider),
            const SizedBox(height: ZopiqSpacing.md),

            _BillRow(label: 'Item total', value: order.subtotal),
            _BillRow(label: 'Delivery fee', value: order.deliveryFee),
            _BillRow(label: 'Taxes', value: order.taxes),
            if (order.discount > 0)
              _BillRow(label: 'Discount', value: -order.discount),
            const SizedBox(height: ZopiqSpacing.sm),
            _BillRow(label: 'Total', value: order.total, emphasis: true),

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
            _Detail(icon: Icons.phone_rounded, text: order.customerPhone),
            const SizedBox(height: ZopiqSpacing.sm),
            _Detail(icon: Icons.location_on_rounded, text: order.deliveryTo),
          ],
        ),
      ),
    );
  }
}

/// One line of the bill. A discount arrives negative and is drawn in the veg
/// green a saving reads as; everything else is muted, and the total is bold.
class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final int value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isCredit = value < 0;

    final TextStyle? style = emphasis
        ? t.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : t.bodyMedium?.copyWith(
            color: isCredit ? zc.veg : zc.textMuted,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.xxs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(formatRupees(value), style: style),
        ],
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
          child: Text(text, style: t.bodyMedium?.copyWith(color: zc.textMuted)),
        ),
      ],
    );
  }
}
