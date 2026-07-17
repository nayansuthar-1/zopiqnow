import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/payments/domain/entities/earnings_summary.dart';

/// The net-earnings trend, one bar a day.
///
/// One widget, two readings: [compact] draws a bare row of bars for the Home
/// dashboard's weekly glance; the full form adds a baseline of dates for the
/// Payments screen. Both draw [DailyEarning.net] — what the kitchen keeps — not
/// gross, because the trend that matters is the one that lands in the account.
class EarningsBarChart extends StatelessWidget {
  const EarningsBarChart({required this.daily, this.compact = false, super.key});

  final List<DailyEarning> daily;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    // A flat zero-line still reads as "no earnings" rather than an empty box;
    // give the axis a little headroom so a single busy day is not clipped.
    final double maxNet = daily.fold<int>(0, (int m, DailyEarning d) {
      return d.net > m ? d.net : m;
    }).toDouble();
    final double maxY = maxNet <= 0 ? 1 : maxNet * 1.2;

    final int n = daily.length;
    // ~5 date labels at most, so a 90-day window doesn't smear its baseline.
    final int labelEvery = n <= 1 ? 1 : (n / 5).ceil();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxY,
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: !compact,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => zc.textStrong,
            getTooltipItem: (_, _, BarChartRodData rod, _) {
              final int i = rod.toY.round();
              return BarTooltipItem(
                '₹$i',
                TextStyle(
                  color: Theme.of(context).colorScheme.surface,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: !compact,
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: !compact,
              reservedSize: 22,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int i = value.toInt();
                if (i < 0 || i >= n) return const SizedBox.shrink();
                if (i % labelEvery != 0 && i != n - 1) {
                  return const SizedBox.shrink();
                }
                final DateTime d = daily[i].day;
                return Padding(
                  padding: const EdgeInsets.only(top: ZopiqSpacing.xs),
                  child: Text(
                    '${d.day}/${d.month}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: zc.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (int i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: daily[i].net.toDouble(),
                  width: compact ? 6 : 10,
                  color: daily[i].net == 0
                      ? zc.divider
                      : zc.primary.withValues(alpha: compact ? 0.55 : 0.9),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(ZopiqRadii.xs),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
