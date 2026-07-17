import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/payments/data/payments_datasource.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/earnings_summary.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/settlement.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<PaymentsDataSource> paymentsDataSourceProvider =
    Provider<PaymentsDataSource>((Ref ref) => const PaymentsSupabaseDataSource());

/// The windows the earnings screen offers. Kept as an enum, not a pair of dates,
/// so the [earningsProvider] family is keyed by something stable — a fresh
/// `DateTime.now()` as a key would refetch on every rebuild.
enum EarningsRange {
  last7('7 days', 7),
  last30('30 days', 30),
  last90('90 days', 90);

  const EarningsRange(this.label, this.days);

  final String label;
  final int days;

  /// The inclusive window ending today. Midnight-aligned so the RPC's `date`
  /// bounds land on whole days.
  ({DateTime from, DateTime to}) window() {
    final DateTime now = DateTime.now();
    final DateTime to = DateTime(now.year, now.month, now.day);
    final DateTime from = to.subtract(Duration(days: days - 1));
    return (from: from, to: to);
  }
}

/// Earnings for a window, computed live. A family so the Home dashboard's weekly
/// peek ([EarningsRange.last7]) and the Payments screen's selected range share
/// one fetch per range instead of two subscriptions to the same figure.
final FutureProviderFamily<EarningsSummary, EarningsRange> earningsProvider =
    FutureProvider.family<EarningsSummary, EarningsRange>((
      Ref ref,
      EarningsRange range,
    ) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        // Not an error, and not a throw: a signed-out session has no earnings,
        // and the router will not show these screens to one anyway.
        return Future<EarningsSummary>.value(
          EarningsSummary(
            from: range.window().from,
            to: range.window().to,
            commissionBps: 0,
            orderCount: 0,
            grossSales: 0,
            commission: 0,
            netEarnings: 0,
            daily: const <DailyEarning>[],
          ),
        );
      }
      final ({DateTime from, DateTime to}) w = range.window();
      return ref
          .watch(paymentsDataSourceProvider)
          .fetchEarnings(from: w.from, to: w.to);
    });

/// The range the Payments screen is currently showing. Its own state, so the
/// dashboard's fixed weekly peek is never disturbed by a toggle on Payments.
final StateProvider<EarningsRange> earningsRangeProvider =
    StateProvider<EarningsRange>((Ref ref) => EarningsRange.last30);

/// The payout batches, newest first. Empty for a signed-out session.
final FutureProvider<List<Settlement>> settlementsProvider =
    FutureProvider<List<Settlement>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        return Future<List<Settlement>>.value(const <Settlement>[]);
      }
      return ref.watch(paymentsDataSourceProvider).fetchSettlements();
    });

/// The delivered orders inside one batch. Auto-disposed: a statement is opened,
/// read, and left, and its line items need not outlive the screen.
final AutoDisposeFutureProviderFamily<List<SettlementOrder>, int>
settlementOrdersProvider =
    FutureProvider.autoDispose.family<List<SettlementOrder>, int>((
      Ref ref,
      int settlementId,
    ) {
      return ref
          .watch(paymentsDataSourceProvider)
          .fetchSettlementOrders(settlementId);
    });
