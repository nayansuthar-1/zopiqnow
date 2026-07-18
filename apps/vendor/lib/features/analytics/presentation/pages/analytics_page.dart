import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/core/widgets/vendor_message.dart';
import 'package:zopiq_vendor/features/analytics/domain/entities/analytics_summary.dart';
import 'package:zopiq_vendor/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:zopiq_vendor/features/analytics/presentation/widgets/hourly_bar_chart.dart';

/// The insight screen: what the kitchen sold, and when the rush came.
///
/// Payments answers "how much did I earn"; this answers the questions around it
/// — the three headline numbers, the dishes that carry the menu, and the shape
/// of the day. All read-only, all computed live from delivered orders (0019).
class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AnalyticsRange range = ref.watch(analyticsRangeProvider);
    final AsyncValue<AnalyticsSummary> analytics = ref.watch(
      analyticsProvider(range),
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: context.zc.primary,
          onRefresh: () async {
            ref.invalidate(analyticsProvider(range));
            await ref.read(analyticsProvider(range).future);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: ZopiqSpacing.xxl),
            children: <Widget>[
              // ── Custom Header ──
              const ZopiqReveal(
                index: 0,
                child: _Header(),
              ),

              ZopiqReveal(
                index: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
                  child: _RangeSelector(
                    range: range,
                    onChanged: (AnalyticsRange r) =>
                        ref.read(analyticsRangeProvider.notifier).state = r,
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
                child: analytics.when(
                  loading: () => const _AnalyticsSkeleton(),
                  error: (Object _, StackTrace _) => VendorMessage(
                    icon: Icons.cloud_off_rounded,
                    title: 'We couldn\'t load your analytics',
                    body: 'Check the internet and try again.',
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(analyticsProvider(range)),
                  ),
                  data: (AnalyticsSummary a) => a.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: ZopiqSpacing.xxl),
                          child: VendorMessage(
                            icon: Icons.insights_rounded,
                            title: 'Nothing to show yet',
                            body: 'Once you\'ve delivered orders in this window, '
                                'your best-sellers and busiest hours appear here.',
                          ),
                        )
                      : ZopiqReveal(
                          index: 2,
                          child: _Body(summary: a),
                        ),
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
                  'Analytics & Insights',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  'See what sells and when you\'re busy',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.range, required this.onChanged});

  final AnalyticsRange range;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AnalyticsRange>(
      segments: <ButtonSegment<AnalyticsRange>>[
        for (final AnalyticsRange r in AnalyticsRange.values)
          ButtonSegment<AnalyticsRange>(value: r, label: Text(r.label)),
      ],
      selected: <AnalyticsRange>{range},
      showSelectedIcon: false,
      onSelectionChanged: (Set<AnalyticsRange> s) => onChanged(s.first),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.summary});

  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _StatTile(
                icon: Icons.receipt_long_rounded,
                label: 'Orders',
                value: '${summary.orderCount}',
                accentColor: zc.primary,
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.restaurant_menu_rounded,
                label: 'Items sold',
                value: '${summary.itemsSold}',
                accentColor: zc.veg,
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.analytics_rounded,
                label: 'Avg order',
                value: formatRupees(summary.avgOrderValue),
                accentColor: const Color(0xFF3B82F6), // clean blue
              ),
            ),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.xl),
        Text(
          'Best sellers',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          'The dishes that moved the most, this window.',
          style: t.bodySmall?.copyWith(color: context.zc.textMuted),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        ZopiqCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < summary.topDishes.length; i++) ...<Widget>[
                _DishRow(rank: i + 1, dish: summary.topDishes[i]),
                if (i < summary.topDishes.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: ZopiqSpacing.xl),
        Text(
          'Busiest hours',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          'When orders come in, across the window.',
          style: t.bodySmall?.copyWith(color: context.zc.textMuted),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        ZopiqCard(
          child: SizedBox(
            height: 180,
            child: HourlyBarChart(hourly: summary.hourly),
          ),
        ),
      ],
    );
  }
}

/// One of the three headline numbers, restyled to match "Today's Performance".
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Accent bar at top
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ZopiqRadii.lg),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: accentColor),
                ),
                const SizedBox(height: ZopiqSpacing.md),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(label, style: t.labelSmall?.copyWith(color: zc.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.rank, required this.dish});

  final int rank;
  final DishSales dish;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: t.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: zc.primary,
              ),
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  dish.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  '${dish.qty} sold',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          Text(
            formatRupees(dish.revenue),
            style: t.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: zc.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

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
