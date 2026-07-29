import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/core/dialler.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/live_delivery_map.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart'
    show formatClockTime;
import 'package:zopiqnow/features/checkout/presentation/widgets/rider_chat_sheet.dart';

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
          ? _Ended(
              status: status,
              placedAt: order.placedAt,
              reason: order.statusReason,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Headline(status: status, order: order),
                // Only while the order is actually out for delivery — which is
                // also the only window the policy behind it will answer in.
                if (status == OrderStatus.outForDelivery)
                  _Rider(orderId: order.id),
                _Map(orderId: order.id, status: status),
                const SizedBox(height: ZopiqSpacing.lg),
                _Timeline(status: status),
              ],
            ),
    );
  }
}

/// The one sentence the customer actually reads, plus the time they care about.
class _Headline extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDelivered = status == OrderStatus.delivered;
    final Color color = isDelivered ? zc.veg : zc.primary;

    // The arrival time, as a clock time — "arriving in about 30 min" is only
    // true at the moment it is said, and this screen is one they come back to.
    //
    // **This used to be a promise nobody revisited**, and the comment here said
    // so: `placedAt + etaMinutes`, picked before a kitchen accepted, before a
    // rider existed, and never touched. B3 replaced it with an estimate the
    // platform recomputes from where the rider actually is (0057) — and with
    // the rule that makes that honest rather than slippery: it may move
    // *earlier* freely, and may only move *later* alongside a reason, which is
    // the line below it. Where the platform cannot name a cause, the old time
    // stands. The original promise is still the fallback for any order nothing
    // has recomputed yet, so this reads exactly as it did before on those.
    final DeliveryRoute? route = ref
        .watch(orderRouteProvider(order.id))
        .valueOrNull;
    final DateTime arrivesBy =
        route?.etaAt ?? order.placedAt.add(Duration(minutes: order.etaMinutes));
    final String? slippedBecause = route?.etaReason;

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
                // B3's rule, made visible: an arrival time that moved later
                // never does so silently. Present only when it has — an order
                // running to time says nothing extra, and an apology on every
                // screen is an apology nobody reads.
                if (slippedBecause != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: Colors.amber.shade800,
                      ),
                      const SizedBox(width: ZopiqSpacing.xxs),
                      Expanded(
                        child: Text(
                          slippedBecause,
                          style: t.bodySmall?.copyWith(
                            color: Colors.amber.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
          const SizedBox(width: ZopiqSpacing.xs),
          // Two ways to reach them, in the order they should be reached in.
          // Chat is the quiet one and comes first; the phone is the interrupt.
          //
          // The number itself is no longer printed. It was, for four phases,
          // because this app carried no dialler — that is what B5 fixed, and a
          // ten-digit string beside a button that dials it is noise.
          _RiderAction(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Message ${rider.name}',
            onTap: () => showRiderChatSheet(
              context,
              orderId: orderId,
              riderName: rider.name,
            ),
          ),
          _RiderAction(
            icon: Icons.call_rounded,
            tooltip: 'Call ${rider.name}',
            onTap: () async {
              final bool ok = await dialNumber(rider.phone);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('This phone can\'t dial.')),
                  );
              }
            },
          ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One round action beside the rider's name. A pair of them, sized for a thumb
/// on a screen somebody is holding while watching for a doorbell.
class _RiderAction extends StatelessWidget {
  const _RiderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return IconButton(
      icon: Icon(icon, size: 20),
      color: zc.primary,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: zc.primary.withValues(alpha: 0.10),
      ),
      onPressed: onTap,
    );
  }
}

/// The ride, drawn (B3).
///
/// Shown from the moment the kitchen accepts, not from pickup — the route is
/// worth seeing while the food is still cooking ("it's coming from across
/// town"), and waiting for a rider would mean the map appears for the last third
/// of the wait only. Before pickup it is the road with two pins; after, it has a
/// bike on it.
///
/// Renders nothing at all when there is nothing to draw: an order with no
/// delivery coordinates, or a route the platform has not resolved yet. Same rule
/// as [_Rider] — the strip appears when the answer does, and never reserves
/// space for one that may not come.
class _Map extends ConsumerWidget {
  const _Map({required this.orderId, required this.status});

  final String orderId;
  final OrderStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nothing to follow before a kitchen has said yes, and the order may still
    // be rejected — a map of a journey that never happens.
    if (status == OrderStatus.placed) return const SizedBox.shrink();

    final DeliveryRoute? route = ref
        .watch(orderRouteProvider(orderId))
        .valueOrNull;
    if (route == null || !route.isMappable) return const SizedBox.shrink();

    // Only asked for once the order is out for delivery, which is the only
    // window `deliveries` is readable in. Null every other time, and the map
    // draws the route without a bike on it.
    final OrderRider? rider = status == OrderStatus.outForDelivery
        ? ref.watch(orderRiderProvider(orderId)).valueOrNull
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: ZopiqSpacing.lg),
      child: LiveDeliveryMap(route: route, rider: rider),
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
  const _Ended({required this.status, required this.placedAt, this.reason});

  final OrderStatus status;
  final DateTime placedAt;

  /// Why, in the words that were recorded when it happened — the kitchen's note,
  /// the customer's own reason, or the auto-decline's sentence. Null when the
  /// order ended without one, which the card handles by saying only what it
  /// knows.
  final String? reason;

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
              // The reason displaces the timestamp rather than joining it. Why
              // an order ended is the thing being looked for; when it was placed
              // is on the receipt three lines down.
              Text(
                reason ?? 'Placed ${formatClockTime(placedAt)}',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
