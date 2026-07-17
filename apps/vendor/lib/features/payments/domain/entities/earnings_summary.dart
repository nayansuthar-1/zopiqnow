import 'package:flutter/foundation.dart';

/// One day's earnings, the unit the chart is drawn from.
@immutable
class DailyEarning {
  const DailyEarning({
    required this.day,
    required this.orders,
    required this.gross,
    required this.net,
  });

  /// The calendar day, at local midnight.
  final DateTime day;
  final int orders;

  /// Food value sold that day — the subtotal, before the platform's cut.
  final int gross;

  /// What the kitchen keeps: [gross] minus commission.
  final int net;
}

/// The Payments screen's live figure: what a restaurant has earned in a window,
/// settled or not.
///
/// Computed by `vendor_earnings_summary` from delivered orders — never stored,
/// so it is current the moment a kitchen looks, not as of last Monday's payout.
@immutable
class EarningsSummary {
  const EarningsSummary({
    required this.from,
    required this.to,
    required this.commissionBps,
    required this.orderCount,
    required this.grossSales,
    required this.commission,
    required this.netEarnings,
    required this.daily,
  });

  final DateTime from;
  final DateTime to;

  /// The platform's cut in basis points (2000 = 20%). Shown so the deduction is
  /// never a mystery number.
  final int commissionBps;

  final int orderCount;
  final int grossSales;
  final int commission;
  final int netEarnings;

  /// Oldest day first — the order the chart draws left to right.
  final List<DailyEarning> daily;

  double get commissionPercent => commissionBps / 100.0;

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    final List<dynamic> days =
        (json['daily'] as List<dynamic>?) ?? const <dynamic>[];
    return EarningsSummary(
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      commissionBps: (json['commission_bps'] as num).toInt(),
      orderCount: (json['order_count'] as num).toInt(),
      grossSales: (json['gross_sales'] as num).toInt(),
      commission: (json['commission'] as num).toInt(),
      netEarnings: (json['net_earnings'] as num).toInt(),
      daily: days
          .map((dynamic d) {
            final Map<String, dynamic> m = d as Map<String, dynamic>;
            return DailyEarning(
              day: DateTime.parse(m['day'] as String),
              orders: (m['orders'] as num).toInt(),
              gross: (m['gross'] as num).toInt(),
              net: (m['net'] as num).toInt(),
            );
          })
          .toList(growable: false),
    );
  }
}
