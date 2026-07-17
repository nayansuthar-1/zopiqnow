import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';

/// A small coloured pill naming where an order stands — the badge History and
/// the detail sheet share. The colour is the fast read across a room: green when
/// it ended well, red when it was called off, orange while it is still live.
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({required this.status, super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color accent = switch (status) {
      OrderStatus.delivered => zc.veg,
      // Turned away, one way or another — declined or called off.
      OrderStatus.cancelled || OrderStatus.rejected => zc.nonVeg,
      // Everything still open — placed through out-for-delivery — is the brand
      // orange: a thing in motion, not a thing settled.
      _ => zc.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rSm,
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
