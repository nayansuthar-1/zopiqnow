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
          _Line(
            label: 'Commission',
            value: formatRupees(-settlement.commission),
            muted: true,
          ),
          _Line(
            label: 'Orders',
            value: '${settlement.orderCount}',
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
