import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';

/// The itemised bill summary widget shared by the cart and checkout screens:
/// Presents item total, delivery fee savings, taxes, coupons, free delivery progress,
/// total to pay, and savings highlight strip.
class BillSummary extends StatelessWidget {
  const BillSummary({required this.bill, super.key});

  final CartBill bill;

  int get _saved =>
      bill.discount + (bill.hasFreeDelivery ? CartBill.flatDeliveryFee : 0);

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE8ECEF),
          width: 1.0,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: <Widget>[
          // Header Row
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 20,
                  color: zc.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Bill details',
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _BillRow(label: 'Item total', value: '₹${bill.subtotal}'),
          _BillRow(
            label: 'Delivery fee',
            value: bill.hasFreeDelivery ? 'FREE' : '₹${bill.deliveryFee}',
            valueColor: bill.hasFreeDelivery ? zc.veg : null,
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
            const SizedBox(height: 10),
            _FreeDeliveryProgress(bill: bill),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : const Color(0xFFE2E8F0),
              height: 1,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'To pay',
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                ),
              ),
              Row(
                children: <Widget>[
                  // What the bill would have been without the offer, struck
                  // through beside what it is. The saving is already stated in
                  // the strip below, but a number nobody has to read a strip to
                  // find is the number that makes an offer feel like one.
                  if (bill.discount > 0) ...<Widget>[
                    Text(
                      '₹${bill.total + bill.discount}',
                      style: t.bodyMedium?.copyWith(
                        color: zc.textMuted,
                        decoration: TextDecoration.lineThrough,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ZopiqAnimatedAmount(
                    amount: bill.total,
                    style: t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_saved > 0) ...<Widget>[
            const SizedBox(height: 14),
            _SavingsStrip(saved: _saved),
          ],
        ],
      ),
    );
  }
}

/// "Add ₹124 more for free delivery", with an animated progress bar.
class _FreeDeliveryProgress extends StatelessWidget {
  const _FreeDeliveryProgress({required this.bill});

  final CartBill bill;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final double progress = (bill.subtotal / CartBill.freeDeliveryThreshold)
        .clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: zc.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: zc.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.delivery_dining_rounded, size: 20, color: zc.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add ₹${bill.amountToFreeDelivery} more for free delivery',
                  style: t.bodySmall?.copyWith(
                    color: zc.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }
}

/// Green savings highlight strip at the base of the bill.
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
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: zc.veg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: zc.veg.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.savings_rounded, size: 18, color: zc.veg),
          const SizedBox(width: 8),
          Text(
            'You saved ₹$saved on this order',
            style: t.bodySmall?.copyWith(
              color: zc.veg,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
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
  final String? strikethrough;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: t.bodyMedium?.copyWith(
              color: isDark ? Colors.white70 : const Color(0xFF475569),
              fontSize: 13.5,
            ),
          ),
          Row(
            children: <Widget>[
              if (strikethrough != null) ...<Widget>[
                Text(
                  strikethrough!,
                  style: t.bodySmall?.copyWith(
                    color: zc.textMuted,
                    decoration: TextDecoration.lineThrough,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                value,
                style: t.bodyMedium?.copyWith(
                  color: valueColor ?? (isDark ? Colors.white : const Color(0xFF1E1E1E)),
                  fontWeight: valueColor != null
                      ? FontWeight.w800
                      : FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

