import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';

/// The itemised bill card. Shared by the cart and checkout screens so the two
/// can never disagree about what a bill looks like.
class BillSummary extends StatelessWidget {
  const BillSummary({required this.bill, super.key});

  final CartBill bill;

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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add ₹${bill.amountToFreeDelivery} more for free delivery',
                style: t.bodySmall?.copyWith(color: zc.primary),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
            child: Divider(color: zc.divider),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('To pay', style: t.titleMedium),
              Text('₹${bill.total}', style: t.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

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
          Text(
            value,
            style: t.bodyMedium?.copyWith(color: valueColor ?? zc.textStrong),
          ),
        ],
      ),
    );
  }
}
