import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `7:42 pm`.
String formatClockTime(DateTime dt) {
  final int hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final String minute = dt.minute.toString().padLeft(2, '0');
  final String meridiem = dt.hour < 12 ? 'am' : 'pm';
  return '$hour12:$minute $meridiem';
}

/// `14 Jul 2026, 7:42 pm`.
///
/// Hand-rolled rather than `intl`: the package is a dependency we have not taken
/// (version freeze — DEVELOPMENT_PLAN Rule 4), and one date format is not a
/// reason to take one. It becomes a reason the day the app is localized, and
/// then this function is the single place that changes.
String formatOrderTimestamp(DateTime dt) =>
    '${dt.day} ${_months[dt.month - 1]} ${dt.year}, ${formatClockTime(dt)}';

/// Where the order is, as a chip. Open orders wear the brand colour; a delivered
/// order is green and a cancelled one is not shouted about.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({required this.status, super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color color = switch (status) {
      OrderStatus.delivered => zc.veg,
      OrderStatus.cancelled => zc.textMuted,
      _ => zc.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One past order in the history list: who cooked it, when, what was in it, and
/// what it cost — plus the reorder button, which is why anyone opens this screen.
class OrderCard extends StatelessWidget {
  const OrderCard({
    required this.order,
    required this.onTap,
    required this.onReorder,
    this.isReordering = false,
    super.key,
  });

  final CustomerOrder order;
  final VoidCallback onTap;
  final VoidCallback onReorder;

  /// True while *this* card's reorder is in flight — the menu is being fetched.
  final bool isReordering;

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
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: ZopiqRadii.rMd,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: ZopiqNetworkImage(
                      url: order.restaurantImageUrl,
                      fallback: GradientImagePlaceholder(
                        seed: order.restaurantId,
                        icon: Icons.restaurant_rounded,
                        iconSize: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        order.restaurantName,
                        style: t.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: ZopiqSpacing.xxs),
                      Text(
                        '${order.id} · ${formatOrderTimestamp(order.placedAt)}',
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.sm),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.md),
            Text(
              order.itemsLabel,
              style: t.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: ZopiqSpacing.md),
            Divider(height: 1, color: zc.divider),
            const SizedBox(height: ZopiqSpacing.sm),
            Row(
              children: <Widget>[
                Text('₹${order.total}', style: t.titleSmall),
                const SizedBox(width: ZopiqSpacing.xs),
                Text(
                  '· ${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
                const Spacer(),
                ZopiqButton(
                  label: 'Reorder',
                  variant: ZopiqButtonVariant.outline,
                  expand: false,
                  isLoading: isReordering,
                  onPressed: onReorder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
