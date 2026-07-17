import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

/// What to cook — the line items of one order, quantity boxed and loud.
///
/// Shared by the live ticket and the history card: an order's lines are written
/// once by `place_order` and never change, so the same read serves both, and
/// `orderLinesProvider` caches it per id.
///
/// The live ticket wants only *what* to cook, so it leaves prices off. The
/// detail sheet reconciles a bill, so it turns [showPrices] on and each line
/// carries its total.
class OrderLines extends ConsumerWidget {
  const OrderLines({required this.orderId, this.showPrices = false, super.key});

  final String orderId;
  final bool showPrices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final AsyncValue<List<OrderLine>> lines = ref.watch(
      orderLinesProvider(orderId),
    );

    return lines.when(
      loading: () => ZopiqShimmer(
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: zc.shimmerBase,
              borderRadius: ZopiqRadii.rMd,
            ),
          ),
        ),
      ),
      error: (Object _, StackTrace _) => Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: zc.nonVeg),
          const SizedBox(width: ZopiqSpacing.sm),
          Expanded(
            child: Text(
              'Couldn\'t load the items',
              style: t.bodyMedium?.copyWith(color: zc.nonVeg),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(orderLinesProvider(orderId)),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (List<OrderLine> data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final OrderLine line in data)
            Padding(
              padding: const EdgeInsets.only(bottom: ZopiqSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // The quantity is the thing that gets misread across a hot
                  // kitchen, so it is the thing that is big and boxed.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZopiqSpacing.sm,
                      vertical: ZopiqSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: zc.primary.withValues(alpha: 0.10),
                      borderRadius: ZopiqRadii.rSm,
                    ),
                    child: Text(
                      '${line.quantity}×',
                      style: t.titleSmall?.copyWith(
                        color: zc.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: ZopiqSpacing.md),
                  Expanded(
                    child: Text(
                      line.name,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (showPrices) ...<Widget>[
                    const SizedBox(width: ZopiqSpacing.sm),
                    Text(
                      formatRupees(line.lineTotal),
                      style: t.titleSmall?.copyWith(
                        color: zc.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
