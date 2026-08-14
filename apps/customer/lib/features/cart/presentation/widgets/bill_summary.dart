import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';

/// The itemised bill summary shared by the cart and checkout screens: item
/// total, delivery fee, taxes, coupon, total to pay, and the savings strip.
///
/// The free-delivery progress bar that used to live here is gone with migration
/// 0123 — there is no threshold to make progress towards.
class BillSummary extends StatelessWidget {
  const BillSummary({required this.bill, super.key});

  final CartBill bill;

  /// Coupon only. A waived delivery fee used to count towards this and no
  /// longer can — migration 0123 withdrew the threshold, so there is no waived
  /// fee to add and "you saved ₹40" would be a claim about nothing.
  int get _saved => bill.discount;

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
          // No FREE branch and no strikethrough. The fee is charged on every
          // order now, so a struck-through ₹40 beside the word FREE would be
          // advertising a discount that does not exist.
          _BillRow(label: 'Delivery fee', value: '₹${bill.deliveryFee}'),
          _BillRow(label: 'Taxes', value: '₹${bill.taxes}'),
          if (bill.discount > 0)
            _BillRow(
              label: 'Coupon discount',
              value: '-₹${bill.discount}',
              valueColor: zc.veg,
            ),
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
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
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

