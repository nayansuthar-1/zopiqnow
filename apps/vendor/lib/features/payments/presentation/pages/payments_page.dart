import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/core/widgets/vendor_animations.dart';
import 'package:zopiq_vendor/core/widgets/vendor_message.dart';
import 'package:zopiq_vendor/core/widgets/vendor_svg_icons.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/earnings_summary.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/settlement.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/widgets/earnings_bar_chart.dart';

/// The money screen: revenue dashboard and weekly payouts.
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
      body: SafeArea(
        child: RefreshIndicator(
          color: context.zc.primary,
          onRefresh: () async {
            ref.invalidate(earningsProvider(range));
            ref.invalidate(settlementsProvider);
            await ref.read(settlementsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: ZopiqSpacing.xxl),
            children: <Widget>[
              const VendorFadeSlide(
                child: _Header(),
              ),

              VendorFadeSlide(
                delay: const Duration(milliseconds: 50),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
                  child: _RangeSelector(
                    range: range,
                    onChanged: (EarningsRange r) =>
                        ref.read(earningsRangeProvider.notifier).state = r,
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.lg),

              VendorFadeSlide(
                delay: const Duration(milliseconds: 100),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
                  child: earnings.when(
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
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              
              VendorFadeSlide(
                delay: const Duration(milliseconds: 150),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Weekly Settlements',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: ZopiqSpacing.xs),
                      Text(
                        'Delivered orders are paid out weekly, food value less commission.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.zc.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.md),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
                child: settlements.when(
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
                        for (int i = 0; i < list.length; i++)
                          VendorFadeSlide(
                            delay: Duration(milliseconds: 200 + i * 50),
                            child: _SettlementTile(settlement: list[i]),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Payments & Revenue',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  'Track sales performance and settlement payouts',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(ZopiqSpacing.sm),
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.1),
              borderRadius: ZopiqRadii.rMd,
            ),
            child: VendorSvgIcon(
              type: VendorSvgType.earningsChart,
              size: 24,
              color: zc.primary,
            ),
          ),
        ],
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

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.summary});

  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: zc.primary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ZopiqRadii.lg),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: zc.primary.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: VendorSvgIcon(
                          type: VendorSvgType.earningsChart,
                          size: 18,
                          color: zc.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: ZopiqSpacing.md),
                    Text(
                      'Net Kitchen Earnings',
                      style: t.bodyMedium?.copyWith(
                        color: zc.textMuted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZopiqSpacing.md),
                ZopiqAnimatedAmount(
                  amount: summary.netEarnings,
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
                _Line(label: 'Gross Sales Value', value: summary.grossSales),
                // Only when there is something to explain. A kitchen that runs
                // no offers of its own should not be shown a zero it has to
                // work out the meaning of.
                if (summary.vendorFundedDiscount > 0)
                  _Line(
                    label: 'Your Own Offers',
                    value: -summary.vendorFundedDiscount,
                    muted: true,
                  ),
                _Line(
                  label: 'Platform Commission (${summary.commissionPercent.toStringAsFixed(0)}%)',
                  value: -summary.commission,
                  muted: true,
                ),
              ],
            ),
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
              fontWeight: FontWeight.bold,
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
    final Color accent = paid ? zc.veg : const Color(0xFFF59E0B);

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: ZopiqPressable(
        onTap: () => context.pushNamed(
          Routes.settlementDetail,
          pathParameters: <String, String>{'id': '${settlement.id}'},
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: ZopiqRadii.rLg,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              children: <Widget>[
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(ZopiqRadii.lg),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(ZopiqSpacing.md),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                periodLabel(settlement.periodStart, settlement.periodEnd),
                                style: t.titleSmall?.copyWith(fontWeight: FontWeight.bold),
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
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: ZopiqSpacing.sm),
                        Icon(Icons.chevron_right_rounded, color: zc.textMuted, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
