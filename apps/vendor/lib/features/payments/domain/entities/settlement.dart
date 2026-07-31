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
    required this.vendorFundedDiscount,
    required this.commission,
    required this.netPayable,
    required this.status,
    required this.createdAt,
    required this.holdUntil,
    this.refunds = 0,
    this.adjustments = 0,
    this.reference,
    this.paidAt,
  });

  final int id;

  /// Inclusive at both ends — the week the batch covers.
  final DateTime periodStart;
  final DateTime periodEnd;

  final int orderCount;
  final int grossSales;

  /// The part of this week's discounts the restaurant issued itself, through its
  /// own offers. Deducted from [grossSales] *before* commission, so the platform
  /// charges its cut on what the kitchen actually earned rather than on the
  /// pre-discount menu price. Platform-funded coupons are not in here — those
  /// come out of the platform's promotional spend and never touch a payout.
  final int vendorFundedDiscount;

  final int commission;

  /// Refunds this restaurant funded, charged to this statement (migration 0077).
  /// Not week-scoped like the rest of the row: a refund approved during the
  /// hold lands on the statement its own order is on, and one raised after the
  /// hold closed lands on the next.
  final int refunds;

  /// The signed sum of the adjustments an admin has written against this
  /// statement (migration 0079). Positive is a credit, negative a charge, and
  /// every one of them has a reason attached — see [SettlementAdjustment].
  final int adjustments;

  final int netPayable;

  final SettlementStatus status;
  final DateTime createdAt;

  /// The date on or after which this statement can be paid — the week's end plus
  /// the platform's hold. Until it passes the figure above is not final: a
  /// refund or an adjustment can still move it, which is the window in which
  /// there is any point telephoning about it.
  final DateTime holdUntil;

  bool get isOnHold =>
      status == SettlementStatus.pending && DateTime.now().isBefore(holdUntil);

  /// The bank's reference (a UTR) once paid; null while pending.
  final String? reference;
  final DateTime? paidAt;

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
    id: (json['id'] as num).toInt(),
    periodStart: DateTime.parse(json['period_start'] as String),
    periodEnd: DateTime.parse(json['period_end'] as String),
    orderCount: (json['order_count'] as num).toInt(),
    grossSales: (json['gross_sales'] as num).toInt(),
    vendorFundedDiscount: (json['vendor_funded_discount'] as num?)?.toInt() ?? 0,
    commission: (json['commission'] as num).toInt(),
    refunds: (json['refunds'] as num?)?.toInt() ?? 0,
    adjustments: (json['adjustments'] as num?)?.toInt() ?? 0,
    netPayable: (json['net_payable'] as num).toInt(),
    status: SettlementStatus.fromWire(json['status'] as String),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    // A plain date, so it is parsed as one and not shifted by a zone. A
    // statement that says it clears on the 3rd must say the 3rd everywhere.
    holdUntil: DateTime.parse(json['hold_until'] as String),
    reference: json['reference'] as String?,
    paidAt: json['paid_at'] == null
        ? null
        : DateTime.parse(json['paid_at'] as String).toLocal(),
  );
}

/// One adjustment an admin wrote against a statement (migration 0079), with the
/// reason they gave for it.
///
/// The reason is the whole point of showing these at all. A statement that says
/// "adjustments −₹400" and will not say why is worse than one that says nothing:
/// it tells the kitchen there is a reason and that they are not allowed to see
/// it.
@immutable
class SettlementAdjustment {
  const SettlementAdjustment({
    required this.id,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  factory SettlementAdjustment.fromJson(Map<String, dynamic> json) =>
      SettlementAdjustment(
        id: (json['id'] as num).toInt(),
        amount: (json['amount'] as num).toInt(),
        reason: json['reason'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final int id;

  /// Signed: positive credits the restaurant, negative charges it.
  final int amount;
  final String reason;
  final DateTime createdAt;
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
