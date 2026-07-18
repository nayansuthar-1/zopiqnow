import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/analytics/domain/entities/analytics_summary.dart';

/// Order volume by hour of day, one bar for each of the 24 hours.
///
/// The summary only carries hours that saw an order; this fills the day to a
/// full 0–23 baseline so a quiet 3am reads as an empty bar, not a missing one.
/// Labels every six hours so a full day of bars doesn't smear its axis.
class HourlyBarChart extends StatelessWidget {
  const HourlyBarChart({required this.hourly, super.key});

  final List<HourBucket> hourly;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    // Fill the day: index is the hour, value is that hour's orders (0 if none).
    final List<int> byHour = List<int>.filled(24, 0);
    for (final HourBucket b in hourly) {
      if (b.hour >= 0 && b.hour < 24) byHour[b.hour] = b.orders;
    }

    final int peak = byHour.fold<int>(0, (int m, int v) => v > m ? v : m);
    final double maxY = peak <= 0 ? 1 : peak * 1.2;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxY,
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => zc.textStrong,
            getTooltipItem: (_, _, BarChartRodData rod, _) {
              final int orders = rod.toY.round();
              return BarTooltipItem(
                '$orders',
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
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int h = value.toInt();
                if (h % 6 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: ZopiqSpacing.xs),
                  child: Text(
                    _hourLabel(h),
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
          for (int h = 0; h < 24; h++)
            BarChartGroupData(
              x: h,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: byHour[h].toDouble(),
                  width: 6,
                  color: byHour[h] == 0
                      ? zc.divider
                      : zc.primary.withValues(alpha: 0.9),
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

  /// `12a`, `6a`, `12p`, `6p` — the way a clock is read at a glance.
  static String _hourLabel(int h) {
    final String suffix = h < 12 ? 'a' : 'p';
    final int h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12$suffix';
  }
}
