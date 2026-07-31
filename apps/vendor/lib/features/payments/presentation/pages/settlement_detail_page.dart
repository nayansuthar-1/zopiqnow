import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/core/widgets/vendor_message.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart'
    show formatOrderDate;
import 'package:zopiq_vendor/features/payments/domain/entities/settlement.dart';
import 'package:zopiq_vendor/features/payments/presentation/pages/payments_page.dart'
    show periodLabel;
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';

/// One payout, opened: the week's totals, the payment status, and the delivered
/// orders that make up the figure.
///
/// The header settlement is read from the already-loaded [settlementsProvider]
/// list rather than refetched — the app arrived here from that list, so the row
/// is in hand. Only the line items are a fresh read.
class SettlementDetailPage extends ConsumerWidget {
  const SettlementDetailPage({required this.settlementId, super.key});

  final int settlementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Settlement? settlement = ref
        .watch(settlementsProvider)
        .valueOrNull
        ?.where((Settlement s) => s.id == settlementId)
        .firstOrNull;

    final AsyncValue<List<SettlementOrder>> orders = ref.watch(
      settlementOrdersProvider(settlementId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          settlement == null
              ? 'Settlement'
              : periodLabel(settlement.periodStart, settlement.periodEnd),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
        children: <Widget>[
          if (settlement != null) _SummaryCard(settlement: settlement),
          if (settlement != null) _Adjustments(settlementId: settlementId),
          const SizedBox(height: ZopiqSpacing.xl),
          Text(
            'Orders in this payout',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          orders.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(ZopiqSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object _, StackTrace _) => VendorMessage(
              icon: Icons.cloud_off_rounded,
              title: 'We couldn\'t load these orders',
              body: 'Check the internet and try again.',
              actionLabel: 'Retry',
              onAction: () =>
                  ref.invalidate(settlementOrdersProvider(settlementId)),
            ),
            data: (List<SettlementOrder> list) => Column(
              children: <Widget>[
                for (final SettlementOrder o in list) _OrderRow(order: o),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.settlement});

  final Settlement settlement;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool paid = settlement.status == SettlementStatus.paid;
    final Color accent = paid ? zc.veg : zc.primary;

    return ZopiqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Net payable',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: ZopiqRadii.rPill,
                ),
                child: Text(
                  settlement.status.label,
                  style: t.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZopiqSpacing.xxs),
          Text(
            formatRupees(settlement.netPayable),
            style: t.headlineLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: zc.textStrong,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: ZopiqSpacing.md),
          _Line(label: 'Gross sales', value: formatRupees(settlement.grossSales)),
          // The statement has to explain itself, which means naming every
          // deduction separately and in the order they are applied. Commission
          // is charged on what is left after the offers, not on gross — the
          // order of these lines is the maths.
          if (settlement.vendorFundedDiscount > 0)
            _Line(
              label: 'Your own offers',
              value: formatRupees(-settlement.vendorFundedDiscount),
              muted: true,
            ),
          _Line(
            label: 'Commission',
            value: formatRupees(-settlement.commission),
            muted: true,
          ),
          // Missing here since 0077 added it, which left the lines above unable
          // to add up to the figure at the top on any week with a refund in it.
          if (settlement.refunds > 0)
            _Line(
              label: 'Refunds',
              value: formatRupees(-settlement.refunds),
              muted: true,
            ),
          if (settlement.adjustments != 0)
            _Line(
              label: 'Adjustments',
              value: formatRupees(settlement.adjustments),
              muted: true,
            ),
          _Line(
            label: 'Orders',
            value: '${settlement.orderCount}',
          ),
          // Said before the reference and the paid date, because until this
          // passes there is neither. A window worth knowing about is a window
          // you are told about while it is still open.
          if (settlement.isOnHold)
            _Line(
              label: 'Clears on',
              value: formatOrderDate(settlement.holdUntil),
            ),
          if (paid && settlement.reference != null)
            _Line(label: 'Reference', value: settlement.reference!),
          if (paid && settlement.paidAt != null)
            _Line(label: 'Paid on', value: formatOrderDate(settlement.paidAt!)),
        ],
      ),
    );
  }
}

/// Why the statement moved, in the words of whoever moved it.
///
/// Renders nothing at all when there is nothing to say — which is almost every
/// statement — including while it is loading and if the read fails. A missing
/// explanation is a reason to telephone; a spinner or an error banner over a
/// section that is empty 95% of the time is a reason to distrust the screen.
class _Adjustments extends ConsumerWidget {
  const _Adjustments({required this.settlementId});

  final int settlementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<SettlementAdjustment> list =
        ref.watch(settlementAdjustmentsProvider(settlementId)).valueOrNull ??
        const <SettlementAdjustment>[];
    if (list.isEmpty) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: ZopiqSpacing.md),
      child: ZopiqCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Adjustments',
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            for (final SettlementAdjustment a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: ZopiqSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(a.reason, style: t.bodyMedium),
                          Text(
                            formatOrderDate(a.createdAt),
                            style: t.bodySmall?.copyWith(color: zc.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Text(
                      formatRupees(a.amount),
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: t.bodyMedium?.copyWith(color: zc.textMuted)),
          Text(
            value,
            style: t.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: muted ? zc.textMuted : zc.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final SettlementOrder order;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  order.id,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  formatOrderDate(order.placedAt),
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          Text(
            formatRupees(order.gross),
            style: t.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: zc.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}
