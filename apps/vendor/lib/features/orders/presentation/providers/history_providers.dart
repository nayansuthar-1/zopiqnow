import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

/// The book, filtered.
///
/// History is not the live queue: it is fetched once per date window rather than
/// streamed, because a finished order does not change and a busy restaurant's
/// whole book should not load to show yesterday. The date range is the fetch's
/// bound (it hits Postgres); status, payment and the id search refine the result
/// in memory, because a window is already small and re-querying on every chip
/// tap would be three round trips to filter a list you already hold.

/// The date window History looks back over. `today` is the kitchen's default —
/// the shift they are in.
enum HistoryRange { today, yesterday, last7, last30, custom }

extension HistoryRangeLabel on HistoryRange {
  String get label => switch (this) {
    HistoryRange.today => 'Today',
    HistoryRange.yesterday => 'Yesterday',
    HistoryRange.last7 => 'Last 7 days',
    HistoryRange.last30 => 'Last 30 days',
    HistoryRange.custom => 'Custom',
  };
}

/// How an order ended, as a filter. `all` keeps every outcome.
enum HistoryOutcome { all, delivered, cancelled, rejected }

extension HistoryOutcomeLabel on HistoryOutcome {
  String get label => switch (this) {
    HistoryOutcome.all => 'All',
    HistoryOutcome.delivered => 'Delivered',
    HistoryOutcome.cancelled => 'Cancelled',
    HistoryOutcome.rejected => 'Rejected',
  };
}

/// How it was paid, as a filter.
enum HistoryPayment { all, cash, online }

extension HistoryPaymentLabel on HistoryPayment {
  String get label => switch (this) {
    HistoryPayment.all => 'All',
    HistoryPayment.cash => 'Cash',
    HistoryPayment.online => 'Online',
  };
}

@immutable
class HistoryFilter {
  const HistoryFilter({
    this.range = HistoryRange.today,
    this.customFrom,
    this.customTo,
    this.outcome = HistoryOutcome.all,
    this.payment = HistoryPayment.all,
    this.query = '',
  });

  final HistoryRange range;
  final DateTime? customFrom;
  final DateTime? customTo;
  final HistoryOutcome outcome;
  final HistoryPayment payment;
  final String query;

  /// The `[from, to)` the fetch reads. Computed from the range against `now`,
  /// or the custom pair (its end pushed to the day's close so "to the 5th"
  /// includes the 5th). A record so the fetch provider can watch it by value.
  static (DateTime from, DateTime to) boundsFor(
    HistoryRange range,
    DateTime? customFrom,
    DateTime? customTo,
  ) {
    final DateTime now = DateTime.now();
    final DateTime startOfToday = DateTime(now.year, now.month, now.day);
    return switch (range) {
      HistoryRange.today => (startOfToday, now),
      HistoryRange.yesterday => (
        startOfToday.subtract(const Duration(days: 1)),
        startOfToday,
      ),
      HistoryRange.last7 => (now.subtract(const Duration(days: 7)), now),
      HistoryRange.last30 => (now.subtract(const Duration(days: 30)), now),
      HistoryRange.custom => (
        customFrom ?? startOfToday,
        // Whole-day inclusive: end of the chosen `to`, or now if unset.
        customTo == null
            ? now
            : DateTime(customTo.year, customTo.month, customTo.day, 23, 59, 59),
      ),
    };
  }

  HistoryFilter copyWith({
    HistoryRange? range,
    DateTime? customFrom,
    DateTime? customTo,
    HistoryOutcome? outcome,
    HistoryPayment? payment,
    String? query,
  }) => HistoryFilter(
    range: range ?? this.range,
    customFrom: customFrom ?? this.customFrom,
    customTo: customTo ?? this.customTo,
    outcome: outcome ?? this.outcome,
    payment: payment ?? this.payment,
    query: query ?? this.query,
  );
}

class HistoryFilterController extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();

  void setRange(HistoryRange range) =>
      state = state.copyWith(range: range);

  void setCustomRange(DateTime from, DateTime to) => state = state.copyWith(
    range: HistoryRange.custom,
    customFrom: from,
    customTo: to,
  );

  void setOutcome(HistoryOutcome outcome) =>
      state = state.copyWith(outcome: outcome);

  void setPayment(HistoryPayment payment) =>
      state = state.copyWith(payment: payment);

  void setQuery(String query) => state = state.copyWith(query: query);
}

final NotifierProvider<HistoryFilterController, HistoryFilter>
historyFilterProvider =
    NotifierProvider<HistoryFilterController, HistoryFilter>(
      HistoryFilterController.new,
    );

/// The finished orders in the selected window, straight from the datasource.
///
/// Re-fetches only when the *window* changes — the `select` narrows the
/// dependency to the range and custom dates, so flipping a status chip or typing
/// in the search box does not hit the network.
final FutureProvider<List<VendorOrder>> historyOrdersProvider =
    FutureProvider<List<VendorOrder>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        return Future<List<VendorOrder>>.value(const <VendorOrder>[]);
      }

      final ({HistoryRange range, DateTime? from, DateTime? to}) window = ref
          .watch(
            historyFilterProvider.select(
              (HistoryFilter f) => (
                range: f.range,
                from: f.customFrom,
                to: f.customTo,
              ),
            ),
          );

      final (DateTime from, DateTime to) bounds = HistoryFilter.boundsFor(
        window.range,
        window.from,
        window.to,
      );

      return ref
          .watch(vendorOrderDataSourceProvider)
          .fetchHistory(
            restaurantId: vendor.restaurantId,
            from: bounds.$1,
            to: bounds.$2,
          );
    });

/// The window's orders after the in-memory refinements — outcome, payment, and
/// the id search. What the list renders.
final Provider<List<VendorOrder>> filteredHistoryProvider =
    Provider<List<VendorOrder>>((Ref ref) {
      final List<VendorOrder> all =
          ref.watch(historyOrdersProvider).valueOrNull ?? const <VendorOrder>[];
      final HistoryFilter f = ref.watch(historyFilterProvider);
      final String q = f.query.trim().toLowerCase();

      return all.where((VendorOrder o) {
        final bool outcomeOk = switch (f.outcome) {
          HistoryOutcome.all => true,
          HistoryOutcome.delivered => o.status == OrderStatus.delivered,
          HistoryOutcome.cancelled => o.status == OrderStatus.cancelled,
          HistoryOutcome.rejected => o.status == OrderStatus.rejected,
        };
        if (!outcomeOk) return false;

        final bool paymentOk = switch (f.payment) {
          HistoryPayment.all => true,
          HistoryPayment.cash => o.paymentMethod.isCash,
          HistoryPayment.online => !o.paymentMethod.isCash,
        };
        if (!paymentOk) return false;

        if (q.isNotEmpty && !o.id.toLowerCase().contains(q)) return false;
        return true;
      }).toList(growable: false);
    });

/// The figures above the list: how many orders, how many landed, how many were
/// called off, and the gross taken. Gross counts *delivered* totals only — a
/// cancelled order is not revenue. Net (after commission) waits for settlements.
@immutable
class HistorySummary {
  const HistorySummary({
    required this.total,
    required this.delivered,
    required this.cancelled,
    required this.gross,
  });

  final int total;
  final int delivered;
  final int cancelled;
  final int gross;
}

final Provider<HistorySummary> historySummaryProvider =
    Provider<HistorySummary>((Ref ref) {
      final List<VendorOrder> list = ref.watch(filteredHistoryProvider);
      int delivered = 0;
      int cancelled = 0;
      int gross = 0;
      for (final VendorOrder o in list) {
        if (o.status == OrderStatus.delivered) {
          delivered++;
          gross += o.total;
        } else if (o.status == OrderStatus.cancelled) {
          cancelled++;
        }
      }
      return HistorySummary(
        total: list.length,
        delivered: delivered,
        cancelled: cancelled,
        gross: gross,
      );
    });
