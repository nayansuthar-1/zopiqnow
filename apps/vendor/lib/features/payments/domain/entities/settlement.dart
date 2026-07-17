import 'package:flutter/foundation.dart';

/// Where a payout batch stands.
enum SettlementStatus {
  pending('Pending'),
  paid('Paid');

  const SettlementStatus(this.label);

  final String label;

  static SettlementStatus fromWire(String wire) => switch (wire) {
    'paid' => paid,
    _ => pending,
  };
}

/// One weekly payout — a restaurant, a Mon–Sun window, and the delivered orders
/// rolled into it. Read-only in the app: the vendor sees what it is owed and
/// what has cleared, but the figures are the rollup's, not the app's.
@immutable
class Settlement {
  const Settlement({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.orderCount,
    required this.grossSales,
    required this.commission,
    required this.netPayable,
    required this.status,
    required this.createdAt,
    this.reference,
    this.paidAt,
  });

  final int id;

  /// Inclusive at both ends — the week the batch covers.
  final DateTime periodStart;
  final DateTime periodEnd;

  final int orderCount;
  final int grossSales;
  final int commission;
  final int netPayable;

  final SettlementStatus status;
  final DateTime createdAt;

  /// The bank's reference (a UTR) once paid; null while pending.
  final String? reference;
  final DateTime? paidAt;

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
    id: (json['id'] as num).toInt(),
    periodStart: DateTime.parse(json['period_start'] as String),
    periodEnd: DateTime.parse(json['period_end'] as String),
    orderCount: (json['order_count'] as num).toInt(),
    grossSales: (json['gross_sales'] as num).toInt(),
    commission: (json['commission'] as num).toInt(),
    netPayable: (json['net_payable'] as num).toInt(),
    status: SettlementStatus.fromWire(json['status'] as String),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    reference: json['reference'] as String?,
    paidAt: json['paid_at'] == null
        ? null
        : DateTime.parse(json['paid_at'] as String).toLocal(),
  );
}

/// One delivered order inside a settlement — the per-order breakdown a statement
/// drills into. A thin row, not the full [VendorOrder]: a statement needs the id,
/// when it landed, and what it was worth, and nothing about its queue lifecycle.
@immutable
class SettlementOrder {
  const SettlementOrder({
    required this.id,
    required this.placedAt,
    required this.gross,
  });

  final String id;
  final DateTime placedAt;

  /// The order's subtotal — the food value that fed the payout.
  final int gross;
}
