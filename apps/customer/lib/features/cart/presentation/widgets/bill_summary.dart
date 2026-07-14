import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';

/// The itemised bill. Shared by the cart and checkout screens so the two can
/// never disagree about what a bill looks like — or, worse, about what it says.
///
/// This is the one screen in the app where the customer is doing arithmetic in
/// their head. So it does the arithmetic out loud for them: what free delivery
/// was worth, how far away it is, what the coupon actually saved. Everything
/// else on the card stays quiet, because a bill that shouts on every line has no
/// way left to shout about the line that matters.
class BillSummary extends StatelessWidget {
  const BillSummary({required this.bill, super.key});

  final CartBill bill;

  /// What the customer is up on: the delivery fee they are not paying, plus the
  /// coupon. Not a field on [CartBill] — it is a *sentence about* a bill, not a
  /// number in one, and the domain has no business phrasing sentences.
  int get _saved =>
      bill.discount + (bill.hasFreeDelivery ? CartBill.flatDeliveryFee : 0);

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      elevated: false,
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Bill details', style: t.titleMedium),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          _BillRow(label: 'Item total', value: '₹${bill.subtotal}'),
          _BillRow(
            label: 'Delivery fee',
            value: bill.hasFreeDelivery ? 'FREE' : '₹${bill.deliveryFee}',
            valueColor: bill.hasFreeDelivery ? zc.veg : null,
            // A struck-through ₹40 beside "FREE" is the difference between being
            // told you got something and being shown what it was worth.
            strikethrough: bill.hasFreeDelivery
                ? '₹${CartBill.flatDeliveryFee}'
                : null,
          ),
          _BillRow(label: 'Taxes', value: '₹${bill.taxes}'),
          if (bill.discount > 0)
            _BillRow(
              label: 'Coupon discount',
              value: '-₹${bill.discount}',
              valueColor: zc.veg,
            ),
          if (!bill.hasFreeDelivery) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.sm),
            _FreeDeliveryProgress(bill: bill),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
            child: Divider(color: zc.divider),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('To pay', style: t.titleMedium),
              ZopiqAnimatedAmount(
                amount: bill.total,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (_saved > 0) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.md),
            _SavingsStrip(saved: _saved),
          ],
        ],
      ),
    );
  }
}

/// "Add ₹124 more for free delivery", with a bar showing how far that is.
///
/// The number alone makes the customer estimate; the bar makes them *see* it,
/// and a customer who can see they are two-thirds of the way to free delivery
/// orders the naan.
class _FreeDeliveryProgress extends StatelessWidget {
  const _FreeDeliveryProgress({required this.bill});

  final CartBill bill;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final double progress = (bill.subtotal / CartBill.freeDeliveryThreshold)
        .clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.delivery_dining_rounded, size: 18, color: zc.primary),
            const SizedBox(width: ZopiqSpacing.sm),
            Expanded(
              child: Text(
                'Add ₹${bill.amountToFreeDelivery} more for free delivery',
                style: t.bodySmall?.copyWith(
                  color: zc.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.sm),
        ClipRRect(
          borderRadius: ZopiqRadii.rPill,
          // Grows as dishes go in, rather than snapping — the bar filling is the
          // reward for adding the item.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: progress, end: progress),
            duration: ZopiqDurations.slow,
            curve: ZopiqCurves.emphasized,
            builder: (BuildContext context, double value, _) =>
                LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: zc.primary.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(zc.primary),
                ),
          ),
        ),
      ],
    );
  }
}

/// The green line at the foot of the bill — deliberately the only saturated
/// thing on the card.
class _SavingsStrip extends StatelessWidget {
  const _SavingsStrip({required this.saved});

  final int saved;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: zc.veg.withValues(alpha: 0.10),
        borderRadius: ZopiqRadii.rMd,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.savings_rounded, size: 18, color: zc.veg),
          const SizedBox(width: ZopiqSpacing.sm),
          Text(
            'You saved ₹$saved on this order',
            style: t.bodySmall?.copyWith(
              color: zc.veg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.strikethrough,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// Rendered struck through, just before [value]: the price that *would* have
  /// applied.
  final String? strikethrough;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: t.bodyMedium?.copyWith(color: zc.textMuted)),
          Row(
            children: <Widget>[
              if (strikethrough != null) ...<Widget>[
                Text(
                  strikethrough!,
                  style: t.bodySmall?.copyWith(
                    color: zc.textMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.sm),
              ],
              Text(
                value,
                style: t.bodyMedium?.copyWith(
                  color: valueColor ?? zc.textStrong,
                  fontWeight: valueColor != null
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
