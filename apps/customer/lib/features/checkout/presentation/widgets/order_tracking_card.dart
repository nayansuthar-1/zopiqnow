import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart'
    show formatClockTime;

/// Where the order is right now, and where it goes next.
///
/// Subscribes to the order's status and falls back to the status the order was
/// fetched with — a dropped socket costs the customer live updates, not the
/// screen. Rendered only for an *open* order: a delivered receipt has nothing
/// left to say, and a timeline that is already finished is a picture of the past.
class OrderTrackingCard extends ConsumerWidget {
  const OrderTrackingCard({required this.order, super.key});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OrderStatus status =
        ref.watch(orderStatusProvider(order.id)).valueOrNull ?? order.status;

    return ZopiqCard(
      child: status == OrderStatus.cancelled
          ? _Cancelled(placedAt: order.placedAt)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Headline(status: status, order: order),
                const SizedBox(height: ZopiqSpacing.lg),
                _Timeline(status: status),
              ],
            ),
    );
  }
}

/// The one sentence the customer actually reads, plus the time they care about.
class _Headline extends StatelessWidget {
  const _Headline({required this.status, required this.order});

  final OrderStatus status;
  final CustomerOrder order;

  static String _sentence(OrderStatus status) => switch (status) {
    OrderStatus.placed => 'Waiting for the restaurant to accept',
    OrderStatus.accepted => 'Your order is confirmed',
    OrderStatus.preparing => 'Your food is being prepared',
    OrderStatus.outForDelivery => 'On its way to you',
    OrderStatus.delivered => 'Delivered. Enjoy!',
    // Rendered by _Cancelled, which this never sees.
    OrderStatus.cancelled => 'This order was cancelled',
  };

  static IconData _icon(OrderStatus status) => switch (status) {
    OrderStatus.placed => Icons.receipt_long_rounded,
    OrderStatus.accepted => Icons.check_circle_outline_rounded,
    OrderStatus.preparing => Icons.soup_kitchen_rounded,
    OrderStatus.outForDelivery => Icons.delivery_dining_rounded,
    OrderStatus.delivered => Icons.done_all_rounded,
    OrderStatus.cancelled => Icons.cancel_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDelivered = status == OrderStatus.delivered;
    final Color color = isDelivered ? zc.veg : zc.primary;

    // The ETA the customer was quoted, as a clock time — "arriving in about 30
    // min" is only true at the moment it is said, and this screen is one they
    // come back to. The promise is not recomputed: `eta_minutes` is what the
    // order service committed to, and a screen that quietly moves the estimate
    // is a screen that never has to admit the food is late.
    final DateTime arrivesBy = order.placedAt.add(
      Duration(minutes: order.etaMinutes),
    );

    return Row(
      children: <Widget>[
        // Fixed-size, so a status change repaints a circle and lays out nothing.
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(_icon(status), color: color, size: 24),
        ),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // The sentence is the thing that changes, so it is the thing that
              // animates. Fade only — no size transition, which would jog the
              // whole card every time the kitchen moves.
              AnimatedSwitcher(
                duration: ZopiqDurations.base,
                switchInCurve: ZopiqCurves.enter,
                child: Text(
                  _sentence(status),
                  key: ValueKey<OrderStatus>(status),
                  style: t.titleSmall,
                ),
              ),
              if (!isDelivered) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  'Arriving by ${formatClockTime(arrivesBy)}',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The five stages, with everything behind the current one filled in.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final int current = status.step;

    return Column(
      children: <Widget>[
        for (int i = 0; i < OrderStatus.journey.length; i++)
          _Step(
            label: OrderStatus.journey[i].label,
            isDone: i < current,
            isCurrent: i == current,
            isLast: i == OrderStatus.journey.length - 1,
          ),
      ],
    );
  }
}

/// One stage: a dot, the rail down to the next one, and what it is called.
class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
  });

  final String label;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;

  /// Fixed. A step that grew when it became the current one would push every
  /// step below it down the card each time the kitchen moved.
  static const double _rowHeight = 40;
  static const double _dot = 16;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final Color color = isDone
        ? zc.veg
        : isCurrent
        ? zc.primary
        : zc.divider;

    return SizedBox(
      height: isLast ? _dot : _rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _dot,
            child: Column(
              children: <Widget>[
                // Colour only — the box never changes size, so this animates a
                // repaint and not a layout.
                AnimatedContainer(
                  duration: ZopiqDurations.base,
                  curve: ZopiqCurves.standard,
                  width: _dot,
                  height: _dot,
                  decoration: BoxDecoration(
                    // Filled once reached, hollow until then: "done" and "still
                    // to come" have to be legible without reading the colour,
                    // for the same reason the veg indicator is a shape.
                    color: isDone || isCurrent
                        ? color
                        : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                    shape: BoxShape.circle,
                  ),
                  child: isDone
                      ? const Icon(
                          Icons.check_rounded,
                          size: 10,
                          color: Colors.white,
                        )
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: AnimatedContainer(
                        duration: ZopiqDurations.base,
                        curve: ZopiqCurves.standard,
                        width: 2,
                        // The rail below a completed step is completed too.
                        color: isDone ? zc.veg : zc.divider,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Text(
            label,
            style: isCurrent
                ? t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
                : t.bodyMedium?.copyWith(
                    color: isDone ? null : zc.textMuted,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A cancelled order is not a timeline with a gap in it. It left the journey.
class _Cancelled extends StatelessWidget {
  const _Cancelled({required this.placedAt});

  final DateTime placedAt;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Icon(Icons.cancel_outlined, color: zc.textMuted, size: 28),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('This order was cancelled', style: t.titleSmall),
              const SizedBox(height: ZopiqSpacing.xxs),
              Text(
                'Placed ${formatClockTime(placedAt)}',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
