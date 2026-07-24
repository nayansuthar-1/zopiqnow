import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/vendor_animations.dart';
import 'package:zopiq_vendor/core/widgets/vendor_svg_icons.dart';
import 'package:zopiq_vendor/features/delivery/domain/entities/order_delivery.dart';
import 'package:zopiq_vendor/features/delivery/presentation/providers/delivery_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_lines.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_prep_sheet.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_reason_sheet.dart';

/// One order ticket with kitchen workflow timeline and vector action buttons.
class OrderTicket extends ConsumerStatefulWidget {
  const OrderTicket({required this.order, super.key});

  final VendorOrder order;

  @override
  ConsumerState<OrderTicket> createState() => _OrderTicketState();
}

class _OrderTicketState extends ConsumerState<OrderTicket> {
  String? _refusal;

  Future<void> _move(OrderStatus to, {String? reason, int? prepMinutes}) async {
    setState(() => _refusal = null);
    final String? refusal = await ref
        .read(orderActionControllerProvider.notifier)
        .move(widget.order, to, reason: reason, prepMinutes: prepMinutes);
    if (mounted && refusal != null) setState(() => _refusal = refusal);
  }

  Future<void> _accept() async {
    final int? prepMinutes = await showPrepTime(context, widget.order.id);
    if (prepMinutes != null) {
      await _move(OrderStatus.accepted, prepMinutes: prepMinutes);
    }
  }

  Future<void> _reject() async {
    final String? reason = await showRejectReason(context, widget.order.id);
    if (reason != null) await _move(OrderStatus.rejected, reason: reason);
  }

  Future<void> _cancel() async {
    final String? reason = await showCancelReason(context, widget.order.id);
    if (reason != null) {
      await _move(
        OrderStatus.cancelled,
        reason: reason.isEmpty ? null : reason,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final VendorOrder order = widget.order;

    ref.watch(clockProvider);

    final bool isBusy = ref.watch(
      orderActionControllerProvider.select(
        (Set<String> busy) => busy.contains(order.id),
      ),
    );
    final bool isNew = order.status == OrderStatus.placed;
    final bool isLate = order.isLate;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xs,
      ),
      child: ZopiqCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Kitchen Stage Progress Bar
            VendorStatusTimeline(status: order.status.name),
            const SizedBox(height: ZopiqSpacing.md),

            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    order.id,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (order.readyBy != null &&
                    (order.status == OrderStatus.accepted ||
                        order.status == OrderStatus.preparing))
                  _PrepCountdown(remaining: order.timeToReady!)
                else if (isLate)
                  _LatePill(label: formatAge(order.age))
                else
                  Text(
                    formatAge(order.age),
                    style: t.bodySmall?.copyWith(
                      color: isNew ? zc.primary : zc.textMuted,
                      fontWeight: isNew ? FontWeight.bold : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.md),

            OrderLines(orderId: order.id),

            const SizedBox(height: ZopiqSpacing.md),
            Divider(height: 1, color: zc.divider.withValues(alpha: 0.5)),
            const SizedBox(height: ZopiqSpacing.md),

            if (order.paymentMethod.isCash)
              _Detail(
                svgType: VendorSvgType.receiptDetail,
                text: 'Collect ₹${order.total} in cash',
                emphasis: true,
              )
            else
              _Detail(
                svgType: VendorSvgType.verifiedCheck,
                text: 'Paid online · ₹${order.total}',
              ),
            const SizedBox(height: ZopiqSpacing.xs),
            _Detail(
              svgType: VendorSvgType.storefront,
              text: order.customerPhone,
            ),

            if (ref.watch(orderDeliveryProvider(order.id))
                case final OrderDelivery delivery) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.md),
              _RiderStrip(delivery: delivery, orderStatus: order.status),
            ],

            if (_refusal != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.md),
              Text(_refusal!, style: t.bodySmall?.copyWith(color: zc.nonVeg)),
            ],

            const SizedBox(height: ZopiqSpacing.lg),
            Row(
              children: <Widget>[
                if (order.status.canReject) ...<Widget>[
                  Expanded(
                    child: ZopiqButton(
                      label: 'Reject',
                      variant: ZopiqButtonVariant.outline,
                      onPressed: isBusy ? null : _reject,
                    ),
                  ),
                  const SizedBox(width: ZopiqSpacing.sm),
                ] else if (order.status.canCancel) ...<Widget>[
                  Expanded(
                    child: ZopiqButton(
                      label: 'Cancel',
                      variant: ZopiqButtonVariant.outline,
                      onPressed: isBusy ? null : _cancel,
                    ),
                  ),
                  const SizedBox(width: ZopiqSpacing.sm),
                ],
                if (order.status.next case final OrderStatus next)
                  Expanded(
                    flex: 2,
                    child: ZopiqButton(
                      label: order.status.nextAction!,
                      variant: isNew
                          ? ZopiqButtonVariant.cta
                          : ZopiqButtonVariant.primary,
                      isLoading: isBusy,
                      onPressed: isNew ? _accept : () => _move(next),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderStrip extends ConsumerWidget {
  const _RiderStrip({required this.delivery, required this.orderStatus});

  final OrderDelivery delivery;
  final OrderStatus orderStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final bool handOverNow =
        delivery.showsPickupCode &&
        orderStatus == OrderStatus.readyForPickup;

    return Container(
      padding: const EdgeInsets.all(ZopiqSpacing.md),
      decoration: BoxDecoration(
        color: zc.primary.withValues(alpha: 0.06),
        borderRadius: ZopiqRadii.rMd,
        border: Border.all(color: zc.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          VendorSvgIcon(
            type: VendorSvgType.riderPickup,
            size: 24,
            color: zc.primary,
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  delivery.riderName,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                // The line a kitchen reacts to. Since 0049 "at the counter" is a
                // fact the rider recorded, not something inferred from how long
                // ago they claimed — so the waiting minutes can be said out loud.
                Text(
                  switch (delivery.state) {
                    DeliveryState.claimed => 'On the way to collect',
                    DeliveryState.arrivedAtRestaurant => switch (delivery
                        .minutesWaiting) {
                      null || 0 => 'At the counter now',
                      final int m => 'At the counter · waiting ${m}m',
                    },
                    DeliveryState.pickedUp => 'Picked up',
                    DeliveryState.arrivedAtCustomer => 'At the customer',
                    DeliveryState.delivered => 'Delivered',
                    DeliveryState.cancelled => 'Dropped the job',
                  },
                  style: t.bodySmall?.copyWith(
                    color: delivery.isWaitingAtCounter ? zc.primary : zc.textMuted,
                    fontWeight: delivery.isWaitingAtCounter
                        ? FontWeight.bold
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (handOverNow) _PickupCode(orderId: delivery.orderId),
        ],
      ),
    );
  }
}

/// The four digits, asked for only when a ticket is actually showing them.
///
/// Long-press to reissue. Buried on purpose: it is needed once in a hundred
/// handovers — after five wrong guesses lock the code — and a visible "new code"
/// button beside a code somebody is reading aloud invites the wrong tap.
class _PickupCode extends ConsumerWidget {
  const _PickupCode({required this.orderId});

  final String orderId;

  Future<void> _reissue(BuildContext context, WidgetRef ref) async {
    final String? failure = await ref.read(reissuePickupCodeProvider(orderId))();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(failure ?? 'New code issued.')),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return GestureDetector(
      onLongPress: () => _reissue(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.md,
          vertical: ZopiqSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: zc.primary,
          borderRadius: ZopiqRadii.rPill,
        ),
        child: ref
            .watch(pickupCodeProvider(orderId))
            .when(
              data: (String code) => Text(
                code,
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 3,
                ),
              ),
              // Dots, not a spinner: the pill keeps its width, so the ticket
              // does not jump under a cook's thumb as the code lands.
              loading: () => Text(
                '••••',
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: 0.6),
                  letterSpacing: 3,
                ),
              ),
              // The rider dropped the job between the queue refreshing and this
              // asking. Say nothing rather than an error a cook cannot act on.
              error: (Object _, StackTrace _) => Text(
                '—',
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 3,
                ),
              ),
            ),
      ),
    );
  }
}

class _PrepCountdown extends StatelessWidget {
  const _PrepCountdown({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final bool overdue = remaining.isNegative;
    final int minutes = remaining.inMinutes.abs();
    final String label = overdue
        ? 'Over by $minutes min'
        : minutes == 0
        ? 'Ready soon'
        : 'Ready in $minutes min';
    final Color color = overdue ? zc.nonVeg : zc.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rSm,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          VendorSvgIcon(
            type: VendorSvgType.prepTimer,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: t.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatePill extends StatelessWidget {
  const _LatePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: zc.nonVeg.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rSm,
        border: Border.all(color: zc.nonVeg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          VendorSvgIcon(
            type: VendorSvgType.prepTimer,
            size: 14,
            color: zc.nonVeg,
          ),
          const SizedBox(width: 4),
          Text(
            'Late · $label',
            style: t.labelMedium?.copyWith(
              color: zc.nonVeg,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.svgType,
    required this.text,
    this.emphasis = false,
  });

  final VendorSvgType svgType;
  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Color color = emphasis ? zc.primary : zc.textMuted;

    return Row(
      children: <Widget>[
        VendorSvgIcon(type: svgType, size: 18, color: color),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: t.bodyMedium?.copyWith(
              color: emphasis ? zc.textStrong : zc.textMuted,
              fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
