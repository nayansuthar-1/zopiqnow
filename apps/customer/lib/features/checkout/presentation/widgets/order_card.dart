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

/// One order in the history list: who cooked it, when, what was in it, and what
/// it cost.
///
/// **Two cards, not one.** An order still on its way and an order from last
/// Tuesday are read for different reasons — one is a question ("where is it?"),
/// the other is a record ("do that again") — and a list where both look
/// identical makes the customer find the live one by reading dates.
///
/// So a live order gets its own tinted, bordered card at the top of the list,
/// and a finished one is compacted: a smaller thumbnail, one line of items
/// instead of two, and tighter spacing, so more history fits on a screen.
///
/// **Reorder is absent while the order is live**, and that is the point of the
/// split rather than a detail of it. Offering "Reorder" on food that has not
/// arrived invites a second order from somebody who thought they were tracking
/// the first — the button is replaced by the only thing worth doing at that
/// moment, which is opening the tracking screen.
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

    // `isOpen` is the entity's own word for "has not ended, one way or another"
    // — delivered, cancelled and rejected are all closed. Reusing it means this
    // card and the detail screen's live subscription can never disagree about
    // which orders are still running.
    final bool isLive = order.status.isOpen;

    final Widget card = Container(
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        // A finished order is a record, and a record can be denser. The live
        // one keeps its breathing room because it is the one being read.
        vertical: isLive ? 16 : 11,
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
                    // Smaller on a finished order — the thumbnail is there to
                    // help you recognise the restaurant, not to be looked at.
                    width: isLive ? 52 : 42,
                    height: isLive ? 52 : 42,
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
                    // One line once it is history. Two lines of dish names is
                    // the single biggest thing between one past order and the
                    // next on screen.
                    maxLines: isLive ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: isLive ? 12 : 8),
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
                // **No Reorder while it is still coming.** Ordering the same
                // food again is not a thing anybody means to do thirty minutes
                // before it arrives, and a customer who taps it thinking it
                // means "see my order" has bought dinner twice. What replaces
                // it is the only useful action at that moment.
                if (isLive)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Track order',
                        style: t.labelLarge?.copyWith(
                          color: zc.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: zc.primary,
                      ),
                    ],
                  )
                else
                  SizedBox(
                    height: 34,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: zc.primary,
                        side: BorderSide(
                          color: zc.primary.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                      ),
                      icon: isReordering
                          ? ZopiqLoader(
                              size: 13,
                              strokeWidth: 2,
                              color: zc.primary,
                            )
                          : const Icon(Icons.replay_rounded, size: 15),
                      label: Text(
                        isReordering ? 'Loading' : 'Reorder',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      onPressed: onReorder,
                    ),
                  ),
              ],
            ),
            // The live card is bounded by its own border, so a divider under it
            // would be a second edge drawn on the same line.
            if (!isLive) ...<Widget>[
              const SizedBox(height: 11),
              Divider(
                height: 1,
                thickness: 1,
                color: isDark ? Colors.white12 : const Color(0xFFEEEEEE),
              ),
            ],
          ],
        ),
    );

    if (!isLive) return InkWell(onTap: onTap, child: card);

    // Tinted and bordered rather than shadowed or glowing: the list is a flat
    // stack of records and one of them is happening now, which is a difference
    // in weight, not in altitude.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: zc.primary.withValues(alpha: isDark ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: zc.primary.withValues(alpha: 0.28)),
            ),
            child: card,
          ),
        ),
      ),
    );
  }
}
