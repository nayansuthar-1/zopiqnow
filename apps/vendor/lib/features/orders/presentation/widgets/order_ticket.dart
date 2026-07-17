import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_lines.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_reason_sheet.dart';

/// One order, as a ticket.
///
/// Everything a cook has to act on and nothing else. There is no bill breakdown
/// on here — no subtotal, no taxes, no coupon — because the kitchen does not
/// reconcile the customer's bill, and a number that nobody acts on is a number
/// somebody eventually misreads. The one figure that survives is the total, and
/// only on a cash order, where it is the amount the rider collects.
class OrderTicket extends ConsumerStatefulWidget {
  const OrderTicket({required this.order, super.key});

  final VendorOrder order;

  @override
  ConsumerState<OrderTicket> createState() => _OrderTicketState();
}

class _OrderTicketState extends ConsumerState<OrderTicket> {
  /// The database's own words, when it refuses a move. Cleared on the next
  /// attempt — an error from a button press two minutes ago is noise.
  String? _refusal;

  Future<void> _move(OrderStatus to, {String? reason}) async {
    setState(() => _refusal = null);
    final String? refusal = await ref
        .read(orderActionControllerProvider.notifier)
        .move(widget.order, to, reason: reason);
    if (mounted && refusal != null) setState(() => _refusal = refusal);
  }

  /// Turning a *new* order away. The reason is required — the sheet enforces it,
  /// and returns null if the kitchen backs out.
  Future<void> _reject() async {
    final String? reason = await showRejectReason(context, widget.order.id);
    if (reason != null) await _move(OrderStatus.rejected, reason: reason);
  }

  /// Calling off an accepted order. The reason is optional: an empty string comes
  /// back when confirmed without one, null when dismissed.
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

    // Rebuilds this ticket's age every 30s without anyone touching the screen.
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    order.id,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                // The age, not the clock time. Nobody in a kitchen converts
                // "7:42 pm" into "that one has been sitting for twenty minutes".
                // Once it is past the quoted window it stops being a timestamp
                // and becomes a warning: red, labelled, the loudest thing on the
                // ticket after the id.
                if (isLate)
                  _LatePill(label: formatAge(order.age))
                else
                  Text(
                    formatAge(order.age),
                    style: t.bodySmall?.copyWith(
                      color: isNew ? zc.primary : zc.textMuted,
                      fontWeight: isNew ? FontWeight.w700 : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.md),

            OrderLines(orderId: order.id),

            const SizedBox(height: ZopiqSpacing.md),
            Divider(height: 1, color: zc.divider),
            const SizedBox(height: ZopiqSpacing.md),

            // Cash is the only thing about payment a kitchen acts on: somebody
            // has to collect it. A prepaid order needs no sentence at all.
            if (order.paymentMethod.isCash)
              _Detail(
                icon: Icons.payments_outlined,
                text: 'Collect ₹${order.total} in cash',
                emphasis: true,
              )
            else
              _Detail(
                icon: Icons.check_circle_outline_rounded,
                text: 'Paid online · ₹${order.total}',
              ),
            const SizedBox(height: ZopiqSpacing.sm),
            _Detail(icon: Icons.phone_rounded, text: order.customerPhone),
            const SizedBox(height: ZopiqSpacing.sm),
            _Detail(icon: Icons.location_on_rounded, text: order.deliveryTo),

            if (_refusal != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.md),
              Text(_refusal!, style: t.bodySmall?.copyWith(color: zc.nonVeg)),
            ],

            const SizedBox(height: ZopiqSpacing.md),
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
                    // The new ticket's button is the loud one. Every other step
                    // is a kitchen keeping itself honest; this one is a customer
                    // sitting in front of a screen that says "waiting for the
                    // restaurant to accept".
                    flex: 2,
                    child: ZopiqButton(
                      label: order.status.nextAction!,
                      variant: isNew
                          ? ZopiqButtonVariant.cta
                          : ZopiqButtonVariant.primary,
                      isLoading: isBusy,
                      onPressed: () => _move(next),
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

/// The overdue marker: a compact red pill reading `Late · 34 min`. A tint, not a
/// glow — it has to catch the eye across a room without turning the ticket into a
/// warning light.
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
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: zc.nonVeg.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.schedule_rounded, size: 14, color: zc.nonVeg),
          const SizedBox(width: ZopiqSpacing.xxs),
          Text(
            'Late · $label',
            style: t.labelMedium?.copyWith(
              color: zc.nonVeg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.icon,
    required this.text,
    this.emphasis = false,
  });

  final IconData icon;
  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Color color = emphasis ? zc.primary : zc.textMuted;

    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: t.bodyMedium?.copyWith(
              color: emphasis ? zc.textStrong : zc.textMuted,
              fontWeight: emphasis ? FontWeight.w700 : null,
            ),
          ),
        ),
      ],
    );
  }
}
