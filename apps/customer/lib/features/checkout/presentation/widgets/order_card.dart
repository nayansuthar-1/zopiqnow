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
      // Ended without arriving — stated, not shouted about.
      OrderStatus.cancelled || OrderStatus.rejected => zc.textMuted,
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

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: ZopiqNetworkImage(
                      url: order.restaurantImageUrl,
                      fallback: GradientImagePlaceholder(
                        seed: order.restaurantId,
                        icon: Icons.restaurant_rounded,
                        iconSize: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        order.restaurantName,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: isDark ? Colors.white : const Color(0xFF111111),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${order.id} · ${formatOrderTimestamp(order.placedAt)}',
                        style: t.bodySmall?.copyWith(
                          color: isDark ? Colors.white60 : const Color(0xFF777777),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: ZopiqVegIndicator(isVeg: true, size: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.itemsLabel,
                    style: t.bodyMedium?.copyWith(
                      color: isDark ? Colors.white70 : const Color(0xFF444444),
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '₹${order.total}',
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: isDark ? Colors.white : const Color(0xFF111111),
                      ),
                    ),
                    Text(
                      '${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                      style: t.bodySmall?.copyWith(
                        color: isDark ? Colors.white54 : const Color(0xFF888888),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: zc.primary,
                      side: BorderSide(color: zc.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: isReordering
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: zc.primary,
                            ),
                          )
                        : const Icon(Icons.replay_rounded, size: 16),
                    label: Text(
                      isReordering ? 'Loading' : 'Reorder',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    onPressed: onReorder,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : const Color(0xFFEEEEEE)),
          ],
        ),
      ),
    );
  }
}
