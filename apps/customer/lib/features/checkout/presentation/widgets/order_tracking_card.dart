import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
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

    // Cancelled and rejected have both left the journey — no timeline, just a
    // line saying how it ended.
    final bool ended =
        status == OrderStatus.cancelled || status == OrderStatus.rejected;

    return ZopiqCard(
      child: ended
          ? _Ended(status: status, placedAt: order.placedAt)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Headline(status: status, order: order),
                // Only while the order is actually out for delivery — which is
                // also the only window the policy behind it will answer in.
                if (status == OrderStatus.outForDelivery)
                  _Rider(orderId: order.id),
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
    OrderStatus.readyForPickup => 'Packed and ready for pickup',
    OrderStatus.outForDelivery => 'On its way to you',
    OrderStatus.delivered => 'Delivered. Enjoy!',
    // Rendered by _Ended, which this never sees.
    OrderStatus.rejected => 'This order wasn\'t accepted',
    OrderStatus.cancelled => 'This order was cancelled',
  };

  static IconData _icon(OrderStatus status) => switch (status) {
    OrderStatus.placed => Icons.receipt_long_rounded,
    OrderStatus.accepted => Icons.check_circle_outline_rounded,
    OrderStatus.preparing => Icons.soup_kitchen_rounded,
    OrderStatus.readyForPickup => Icons.shopping_bag_rounded,
    OrderStatus.outForDelivery => Icons.delivery_dining_rounded,
    OrderStatus.delivered => Icons.done_all_rounded,
    OrderStatus.rejected => Icons.cancel_outlined,
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

/// Who is bringing it, and the number to ring.
///
/// Renders nothing at all until there is a rider to name — no placeholder, no
/// spinner, no "finding a rider" line. The strip appears when the answer does,
/// and a card that reserved space for it would leave a hole on every order a
/// restaurant delivers with its own staff.
class _Rider extends ConsumerWidget {
  const _Rider({required this.orderId});

  final String orderId;

  static String _vehicleLabel(String vehicle) => switch (vehicle) {
    'scooter' => 'On a scooter',
    'bicycle' => 'On a bicycle',
    _ => 'On a bike',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OrderRider? rider = ref.watch(orderRiderProvider(orderId)).valueOrNull;
    if (rider == null) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: ZopiqSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DeliveryCode(orderId: orderId, isAtDoor: rider.isAtDoor),
          Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.delivery_dining_rounded,
              color: zc.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  rider.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  rider.isAtDoor
                      ? 'Waiting outside'
                      : _vehicleLabel(rider.vehicle),
                  style: t.bodySmall?.copyWith(
                    color: rider.isAtDoor ? zc.primary : zc.textMuted,
                    fontWeight: rider.isAtDoor ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ZopiqSpacing.sm),
          // Shown, not dialled: placing a call needs a plugin this app does not
          // carry, and a button that looks like it rings someone and doesn't is
          // worse than a number the customer can read out.
          Text(
            rider.phone,
            style: t.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The four digits the rider needs before the order can be marked delivered.
///
/// Two sizes, one fact. While the rider is still riding it is a quiet line —
/// present so nobody is hunting for it when the doorbell goes. Once they say
/// they are outside it becomes the loudest thing on the screen, because that is
/// the ten seconds it exists for.
///
/// Absent, not empty, when there is no code: a panel reading "—" over a missing
/// number looks broken, and there is nothing the customer could do about it.
class _DeliveryCode extends ConsumerWidget {
  const _DeliveryCode({required this.orderId, required this.isAtDoor});

  final String orderId;
  final bool isAtDoor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? code = ref.watch(deliveryCodeProvider(orderId)).valueOrNull;
    if (code == null) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: ZopiqSpacing.md),
      padding: const EdgeInsets.all(ZopiqSpacing.md),
      decoration: BoxDecoration(
        color: zc.primary.withValues(alpha: isAtDoor ? 0.12 : 0.06),
        borderRadius: ZopiqRadii.rMd,
        border: Border.all(
          color: zc.primary.withValues(alpha: isAtDoor ? 0.4 : 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isAtDoor
                ? 'Your rider is here — share this code'
                : 'Delivery code',
            style: t.labelMedium?.copyWith(
              color: zc.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            code,
            style: (isAtDoor ? t.headlineMedium : t.titleLarge)?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Only share it once the food is in your hands.',
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
        ],
      ),
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

/// An order that ended — cancelled after acceptance, or never accepted at all —
/// is not a timeline with a gap in it. It left the journey, and the only thing
/// that changes between the two is the sentence.
class _Ended extends StatelessWidget {
  const _Ended({required this.status, required this.placedAt});

  final OrderStatus status;
  final DateTime placedAt;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final String title = status == OrderStatus.rejected
        ? 'This order wasn\'t accepted'
        : 'This order was cancelled';

    return Row(
      children: <Widget>[
        Icon(Icons.cancel_outlined, color: zc.textMuted, size: 28),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: t.titleSmall),
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
