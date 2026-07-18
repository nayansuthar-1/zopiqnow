import 'package:flutter/foundation.dart';

/// One dish and how it sold in the window — a row of the best-sellers list.
@immutable
class DishSales {
  const DishSales({
    required this.name,
    required this.qty,
    required this.revenue,
  });

  final String name;

  /// Units sold across all delivered orders in the window.
  final int qty;

  /// Rupees those units brought in — the sum of their line totals.
  final int revenue;
}

/// Orders placed in one hour of the day, summed across the window. The unit the
/// "busiest hours" chart is drawn from.
@immutable
class HourBucket {
  const HourBucket({required this.hour, required this.orders});

  /// 0–23, in India where the kitchens are.
  final int hour;
  final int orders;
}

/// The Analytics screen's read: what a restaurant sold in a window, and when.
///
/// Computed live by `vendor_analytics` from delivered orders (0019) — never
/// stored, so it is current the moment a kitchen looks. Payments answers "how
/// much"; this answers "what" and "when".
@immutable
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.from,
    required this.to,
    required this.orderCount,
    required this.itemsSold,
    required this.avgOrderValue,
    required this.topDishes,
    required this.hourly,
  });

  final DateTime from;
  final DateTime to;

  final int orderCount;
  final int itemsSold;

  /// Average subtotal of a delivered order, in whole rupees.
  final int avgOrderValue;

  /// Best-sellers, most units first.
  final List<DishSales> topDishes;

  /// Order volume by hour of day. Only hours that saw an order appear, so the
  /// chart fills the gaps to a full 0–23 baseline itself.
  final List<HourBucket> hourly;

  bool get isEmpty => orderCount == 0;

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    final List<dynamic> dishes =
        (json['top_dishes'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> hours =
        (json['hourly'] as List<dynamic>?) ?? const <dynamic>[];
    return AnalyticsSummary(
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      orderCount: (json['order_count'] as num).toInt(),
      itemsSold: (json['items_sold'] as num).toInt(),
      avgOrderValue: (json['avg_order_value'] as num).toInt(),
      topDishes: dishes
          .map((dynamic d) {
            final Map<String, dynamic> m = d as Map<String, dynamic>;
            return DishSales(
              name: m['name'] as String,
              qty: (m['qty'] as num).toInt(),
              revenue: (m['revenue'] as num).toInt(),
            );
          })
          .toList(growable: false),
      hourly: hours
          .map((dynamic h) {
            final Map<String, dynamic> m = h as Map<String, dynamic>;
            return HourBucket(
              hour: (m['hour'] as num).toInt(),
              orders: (m['orders'] as num).toInt(),
            );
          })
          .toList(growable: false),
    );
  }
}
