import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Today's snapshot, derived from the one order stream the app already holds — no
/// second subscription. "Today" is the local calendar day: the kitchen's day,
/// not UTC's.
final Provider<TodayStats> todayStatsProvider = Provider<TodayStats>((Ref ref) {
  final List<VendorOrder> orders =
      ref.watch(ordersProvider).valueOrNull ?? <VendorOrder>[];

  final DateTime now = DateTime.now();
  bool isToday(DateTime d) =>
      d.year == now.year && d.month == now.month && d.day == now.day;

  int todayCount = 0;
  int revenue = 0;
  int delivered = 0;
  int inQueue = 0;
  int newOrders = 0;

  for (final VendorOrder o in orders) {
    final bool today = isToday(o.placedAt);
    if (today) todayCount++;
    if (today && o.status == OrderStatus.delivered) {
      delivered++;
      revenue += o.total;
    }
    if (o.status.isOpen) {
      inQueue++;
      if (o.status == OrderStatus.placed) newOrders++;
    }
  }

  return TodayStats(
    orders: todayCount,
    revenue: revenue,
    delivered: delivered,
    inQueue: inQueue,
    newOrders: newOrders,
  );
});
