import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

/// The numbers on the home screen — a day's shape at a glance.
@immutable
class TodayStats {
  const TodayStats({
    required this.orders,
    required this.revenue,
    required this.delivered,
    required this.inQueue,
    required this.newOrders,
  });

  /// Orders placed today, whatever became of them.
  final int orders;

  /// Money taken today — the total of orders delivered today.
  final int revenue;

  /// How many of today's orders reached the customer.
  final int delivered;

  /// Orders still open right now — the whole queue, not just today's. A ticket
  /// placed at 11pm is still work at 12:05am, and the count that means "there is
  /// something to do" must not reset at midnight.
  final int inQueue;

  /// Open orders still waiting to be accepted — the same figure the Orders tab
  /// badges.
  final int newOrders;

  static const TodayStats empty = TodayStats(
    orders: 0,
    revenue: 0,
    delivered: 0,
    inQueue: 0,
    newOrders: 0,
  );
}

/// Today's finished orders — a one-shot read, not a subscription.
///
/// The live stream is a bounded window now, so the day's takings can no longer
/// be counted off it: a restaurant busier than the window would under-report its
/// own revenue by evening, and quietly. This asks the database the question
/// directly instead, over the same `fetchHistory` the History screen uses.
///
/// Re-read whenever the stream ticks, because an order finishing *is* an event
/// on the stream — so the figures stay live without a second socket, and go
/// quiet the moment the kitchen does. Riverpod keeps the previous value while it
/// refreshes, so the tiles do not blink between reads.
///
/// "Today" is the local calendar day: the kitchen's day, not UTC's.
final FutureProvider<List<VendorOrder>> todayFinishedProvider =
    FutureProvider<List<VendorOrder>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) return Future<List<VendorOrder>>.value(<VendorOrder>[]);

      ref.watch(ordersProvider);

      final DateTime now = DateTime.now();
      return ref
          .watch(vendorOrderDataSourceProvider)
          .fetchHistory(
            restaurantId: vendor.restaurantId,
            from: DateTime(now.year, now.month, now.day),
            to: now,
            // A day, and a backstop rather than a bound: no kitchen reaches it,
            // and one that did would be reading a number it can survive being
            // approximate for one evening.
            limit: 1000,
          );
    });

/// Today's snapshot, from the day's finished orders and the live queue.
///
/// Two sources because they answer two questions — how the day went, and what is
/// happening right now — and they cannot overlap: `fetchHistory` returns only
/// finished orders, so an order placed today and still cooking is counted once,
/// on the queue side.
final Provider<TodayStats> todayStatsProvider = Provider<TodayStats>((Ref ref) {
  final List<VendorOrder> finished =
      ref.watch(todayFinishedProvider).valueOrNull ?? <VendorOrder>[];
  final List<VendorOrder> live =
      ref.watch(ordersProvider).valueOrNull ?? <VendorOrder>[];

  final DateTime now = DateTime.now();
  bool isToday(DateTime d) =>
      d.year == now.year && d.month == now.month && d.day == now.day;

  int todayCount = 0;
  int revenue = 0;
  int delivered = 0;
  int inQueue = 0;
  int newOrders = 0;

  // How the day went. Already bounded to today by the query, so every row counts.
  for (final VendorOrder o in finished) {
    todayCount++;
    if (o.status == OrderStatus.delivered) {
      delivered++;
      revenue += o.total;
    }
  }

  // What is still going on. The whole queue, not just today's — a ticket placed
  // at 11pm is still work at 12:05am.
  for (final VendorOrder o in live) {
    if (!o.status.isOpen) continue;
    inQueue++;
    if (o.status == OrderStatus.placed) newOrders++;
    if (isToday(o.placedAt)) todayCount++;
  }

  return TodayStats(
    orders: todayCount,
    revenue: revenue,
    delivered: delivered,
    inQueue: inQueue,
    newOrders: newOrders,
  );
});
