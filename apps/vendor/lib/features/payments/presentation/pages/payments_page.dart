import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/core/widgets/vendor_message.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/earnings_summary.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/settlement.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/widgets/earnings_bar_chart.dart';

/// The money screen: what the kitchen has earned, and the payouts that clear it.
///
/// Two questions, in the order a restaurant asks them. First "how am I doing" —
/// the earnings summary and its trend, live and settled-or-not. Then "when do I
/// get paid" — the weekly settlements, each a statement you can open to the order.
class PaymentsPage extends ConsumerWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EarningsRange range = ref.watch(earningsRangeProvider);
    final AsyncValue<EarningsSummary> earnings = ref.watch(
      earningsProvider(range),
    );
    final AsyncValue<List<Settlement>> settlements = ref.watch(
      settlementsProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(earningsProvider(range));
          ref.invalidate(settlementsProvider);
          await ref.read(settlementsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          children: <Widget>[
            _RangeSelector(
              range: range,
              onChanged: (EarningsRange r) =>
                  ref.read(earningsRangeProvider.notifier).state = r,
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            earnings.when(
              loading: () => const _EarningsSkeleton(),
              error: (Object _, StackTrace _) => VendorMessage(
                icon: Icons.cloud_off_rounded,
                title: 'We couldn\'t load your earnings',
                body: 'Check the internet and try again.',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(earningsProvider(range)),
              ),
              data: (EarningsSummary e) => _EarningsCard(summary: e),
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            Text(
              'Settlements',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              'Delivered orders are paid out weekly, food value less commission.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.zc.textMuted,
              ),
            ),
            const SizedBox(height: ZopiqSpacing.md),
            settlements.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(ZopiqSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object _, StackTrace _) => VendorMessage(
                icon: Icons.cloud_off_rounded,
                title: 'We couldn\'t load your settlements',
                body: 'Check the internet and try again.',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(settlementsProvider),
              ),
              data: (List<Settlement> list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: ZopiqSpacing.xxl),
                    child: VendorMessage(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'No payouts yet',
                      body: 'Your first settlement appears here once orders '
                          'you\'ve delivered are rolled up.',
                    ),
                  );
                }
                return Column(
                  children: <Widget>[
                    for (final Settlement s in list) _SettlementTile(settlement: s),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.range, required this.onChanged});

  final EarningsRange range;
  final ValueChanged<EarningsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<EarningsRange>(
      segments: <ButtonSegment<EarningsRange>>[
        for (final EarningsRange r in EarningsRange.values)
          ButtonSegment<EarningsRange>(value: r, label: Text(r.label)),
      ],
      selected: <EarningsRange>{range},
      showSelectedIcon: false,
      onSelectionChanged: (Set<EarningsRange> s) => onChanged(s.first),
    );
  }
}

/// The headline: net earnings, big, with the gross-and-commission arithmetic
/// underneath so the deduction is shown, never implied.
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.summary});

  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Net earnings',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.xxs),
          Text(
            formatRupees(summary.netEarnings),
            style: t.headlineLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: zc.textStrong,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            '${summary.orderCount} delivered '
            '${summary.orderCount == 1 ? 'order' : 'orders'}',
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          if (summary.daily.isNotEmpty) ...<Widget>[
            SizedBox(
              height: 160,
              child: EarningsBarChart(daily: summary.daily),
            ),
            const SizedBox(height: ZopiqSpacing.lg),
          ],
          const Divider(height: 1),
          const SizedBox(height: ZopiqSpacing.md),
          _Line(label: 'Gross sales', value: summary.grossSales),
          _Line(
            label: 'Commission (${summary.commissionPercent.toStringAsFixed(0)}%)',
            value: -summary.commission,
            muted: true,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.muted = false});

  final String label;
  final int value;
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
            formatRupees(value),
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

class _SettlementTile extends StatelessWidget {
  const _SettlementTile({required this.settlement});

  final Settlement settlement;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool paid = settlement.status == SettlementStatus.paid;
    final Color accent = paid ? zc.veg : zc.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: ZopiqCard(
        padding: const EdgeInsets.all(ZopiqSpacing.md),
        onTap: () => context.pushNamed(
          Routes.settlementDetail,
          pathParameters: <String, String>{'id': '${settlement.id}'},
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    periodLabel(settlement.periodStart, settlement.periodEnd),
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    '${settlement.orderCount} '
                    '${settlement.orderCount == 1 ? 'order' : 'orders'}',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  formatRupees(settlement.netPayable),
                  style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.sm,
                    vertical: 1,
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
            const SizedBox(width: ZopiqSpacing.xs),
            Icon(Icons.chevron_right_rounded, color: zc.textMuted),
          ],
        ),
      ),
    );
  }
}

class _EarningsSkeleton extends StatelessWidget {
  const _EarningsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ZopiqCard(
      child: SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// `6–12 Jul`, `30 Jun – 6 Jul`. A settlement's week, read the way a statement
/// names one — by hand, because `intl` is not a dependency this app has.
String periodLabel(DateTime start, DateTime end) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final String sM = months[start.month - 1];
  final String eM = months[end.month - 1];
  if (start.month == end.month) {
    return '${start.day}–${end.day} $sM';
  }
  return '${start.day} $sM – ${end.day} $eM';
}
