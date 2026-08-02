import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/core/widgets/vendor_svg_icons.dart';
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
      child: ZopiqPressable(
        onTap: () => showOrderDetail(context, order),
        child: ZopiqCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      order.id,
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  OrderStatusBadge(status: order.status),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Icon(Icons.access_time_rounded, size: 13, color: zc.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    formatOrderDate(order.placedAt),
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: ZopiqSpacing.md),

              OrderLines(orderId: order.id),

              const SizedBox(height: ZopiqSpacing.md),
              Divider(height: 1, color: zc.divider.withValues(alpha: 0.5)),
              const SizedBox(height: ZopiqSpacing.md),

              Row(
                children: <Widget>[
                  VendorSvgIcon(
                    type: order.paymentMethod.isCash
                        ? VendorSvgType.receiptDetail
                        : VendorSvgType.verifiedCheck,
                    size: 18,
                    color: order.paymentMethod.isCash ? zc.primary : zc.veg,
                  ),
                  const SizedBox(width: ZopiqSpacing.sm),
                  Expanded(
                    child: Text(
                      order.paymentMethod.isCash
                          ? 'Collect Cash: ${formatRupees(order.total)}'
                          : 'Prepaid Online: ${formatRupees(order.total)}',
                      style: t.bodyMedium?.copyWith(
                        color: zc.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: zc.textMuted, size: 18),
                ],
              ),
              if (order.deliveryTo.isNotEmpty) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.xs),
                Row(
                  children: <Widget>[
                    Icon(Icons.location_on_rounded, size: 16, color: zc.textMuted),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Expanded(
                      child: Text(
                        order.deliveryTo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
