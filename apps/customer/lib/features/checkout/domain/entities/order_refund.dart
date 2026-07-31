import 'package:flutter/foundation.dart';

/// Where a refund has got to.
///
/// The database's own vocabulary (migration 0077), minus `declined` — a refund
/// support decided was never owed is not shown to the person who never asked for
/// it, and `my_order_refund` does not return one.
enum RefundStatus {
  /// Owed, waiting on somebody at Zopiqnow. Only a partial ever sits here; a
  /// refund on an order that never happened is approved the moment it is
  /// created.
  requested,

  approved,

  /// With the payment gateway. Nothing writes this yet — it is the state
  /// PAY-001's edge function moves a refund into.
  processing,

  paid,

  /// The gateway refused it. A person is now involved.
  failed;

  /// An unknown wire value reads as [processing]: something is in motion and
  /// nobody at this end knows what. The alternative — crashing an older build on
  /// a status added later — is worse than a vague sentence.
  static RefundStatus fromWire(String wire) => switch (wire) {
    'requested' => requested,
    'approved' => approved,
    'paid' => paid,
    'failed' => failed,
    _ => processing,
  };

  bool get isSettled => this == paid;
}

/// Money going back on one order.
///
/// An order can carry more than one: the automatic full refund on a cancellation,
/// and later a goodwill partial. They are shown as separate lines because they
/// arrive separately and on separate dates.
@immutable
class OrderRefund {
  const OrderRefund({
    required this.id,
    required this.amount,
    required this.status,
    required this.reason,
    required this.expectedBy,
    required this.isPartial,
    this.paidAt,
  });

  factory OrderRefund.fromJson(Map<String, dynamic> json) {
    return OrderRefund(
      id: (json['id'] as num).toInt(),
      amount: (json['amount'] as num).toInt(),
      status: RefundStatus.fromWire(json['status'] as String),
      reason: json['reason'] as String? ?? '',
      expectedBy: DateTime.parse(json['expected_by'] as String),
      isPartial: json['is_partial'] as bool? ?? false,
      paidAt: switch (json['paid_at']) {
        final String s => DateTime.parse(s).toLocal(),
        _ => null,
      },
    );
  }

  final int id;
  final int amount;
  final RefundStatus status;

  /// Why the money is coming back, in the words the customer already read on the
  /// order — the automatic path copies the order's own `status_reason`.
  final String reason;

  /// The date promised, frozen when the refund was raised (0077). Deliberately
  /// not recomputed here: a date that moves one day further away every day the
  /// refund sits unpaid is how one support contact becomes four.
  final DateTime expectedBy;

  /// Part of the order rather than all of it — a missing dish, not a
  /// cancellation.
  final bool isPartial;

  final DateTime? paidAt;
}
