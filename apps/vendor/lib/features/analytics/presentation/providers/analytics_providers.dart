import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/analytics/data/analytics_datasource.dart';
import 'package:zopiq_vendor/features/analytics/domain/entities/analytics_summary.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<AnalyticsDataSource> analyticsDataSourceProvider =
    Provider<AnalyticsDataSource>(
      (Ref ref) => const AnalyticsSupabaseDataSource(),
    );

/// The windows the analytics screen offers. An enum, not a pair of dates, so the
/// family key is stable — a fresh `DateTime.now()` as a key would refetch on
/// every rebuild. Its own type rather than Payments' `EarningsRange` so the two
/// features don't reach into each other.
enum AnalyticsRange {
  last7('7 days', 7),
  last30('30 days', 30),
  last90('90 days', 90);

  const AnalyticsRange(this.label, this.days);

  final String label;
  final int days;

  /// The inclusive window ending today, midnight-aligned so the RPC's `date`
  /// bounds land on whole days.
  ({DateTime from, DateTime to}) window() {
    final DateTime now = DateTime.now();
    final DateTime to = DateTime(now.year, now.month, now.day);
    final DateTime from = to.subtract(Duration(days: days - 1));
    return (from: from, to: to);
  }
}

/// The range the screen is showing.
final StateProvider<AnalyticsRange> analyticsRangeProvider =
    StateProvider<AnalyticsRange>((Ref ref) => AnalyticsRange.last30);

/// Analytics for a window, computed live. A family keyed by range so switching
/// windows and back reuses the fetch instead of re-hitting the RPC.
final FutureProviderFamily<AnalyticsSummary, AnalyticsRange> analyticsProvider =
    FutureProvider.family<AnalyticsSummary, AnalyticsRange>((
      Ref ref,
      AnalyticsRange range,
    ) {
      final Vendor? vendor = ref.watch(vendorProvider);
      final ({DateTime from, DateTime to}) w = range.window();
      if (vendor == null) {
        // A signed-out session has nothing sold, and the router won't show this
        // screen to one anyway. Not an error, not a throw.
        return Future<AnalyticsSummary>.value(
          AnalyticsSummary(
            from: w.from,
            to: w.to,
            orderCount: 0,
            itemsSold: 0,
            avgOrderValue: 0,
            topDishes: const <DishSales>[],
            hourly: const <HourBucket>[],
          ),
        );
      }
      return ref
          .watch(analyticsDataSourceProvider)
          .fetch(from: w.from, to: w.to);
    });
