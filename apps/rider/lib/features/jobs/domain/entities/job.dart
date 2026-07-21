import 'package:flutter/foundation.dart';

/// Where the rider is on a job. Mirrors `deliveries.state` (migration 0025).
///
/// Deliberately a different axis from the order's own status: the customer app
/// throws on an order status it does not recognise, so the rider's lifecycle was
/// kept out of `orders.status` entirely.
enum JobState {
  claimed,
  pickedUp,
  delivered,
  cancelled;

  static JobState fromWire(String value) => switch (value) {
    'claimed' => claimed,
    'picked_up' => pickedUp,
    'delivered' => delivered,
    'cancelled' => cancelled,
    // Tolerant on purpose. A rider standing in a stairwell holding somebody's
    // dinner is the worst possible audience for a crash, and this drives one
    // line of copy and which button is showing — not a receipt.
    _ => claimed,
  };

  bool get isLive => this == claimed || this == pickedUp;
}

/// A job on the board: an order that is cooked, or nearly, and unclaimed.
///
/// Note what is *not* here: the customer's phone number. The board is visible to
/// every signed-in rider, and a board that hands out phone numbers is a list of
/// everyone who ordered dinner tonight. It arrives with [Job] instead, after the
/// rider has committed — that is `available_deliveries` vs `my_deliveries` in
/// 0025, and the split is enforced in Postgres, not here.
@immutable
class JobOffer {
  const JobOffer({
    required this.orderId,
    required this.restaurantName,
    required this.deliverTo,
    required this.total,
    required this.isCash,
    required this.isReady,
    required this.placedAt,
  });

  factory JobOffer.fromJson(Map<String, dynamic> json) => JobOffer(
    orderId: json['order_id'] as String,
    restaurantName: json['restaurant_name'] as String? ?? 'Restaurant',
    deliverTo: json['deliver_to'] as String? ?? '',
    total: json['total'] as int? ?? 0,
    isCash: json['payment_method'] == 'cod',
    isReady: json['status'] == 'ready_for_pickup',
    placedAt: DateTime.parse(json['placed_at'] as String).toLocal(),
  );

  final String orderId;
  final String restaurantName;
  final String deliverTo;
  final int total;

  /// Whether the rider will be collecting cash. The one thing on the board worth
  /// knowing before accepting, because it changes what they carry.
  final bool isCash;

  /// Packed and waiting, as opposed to still being cooked. A rider can claim
  /// either — seeing a job while it cooks is what lets them ride over in time.
  final bool isReady;

  final DateTime placedAt;
}

/// A job this rider is actually carrying.
@immutable
class Job {
  const Job({
    required this.orderId,
    required this.state,
    required this.orderStatus,
    required this.restaurantName,
    required this.deliverTo,
    required this.customerPhone,
    required this.total,
    required this.isCash,
    required this.claimedAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    orderId: json['order_id'] as String,
    state: JobState.fromWire(json['state'] as String),
    orderStatus: json['order_status'] as String? ?? '',
    restaurantName: json['restaurant_name'] as String? ?? 'Restaurant',
    deliverTo: json['deliver_to'] as String? ?? '',
    customerPhone: json['customer_phone'] as String? ?? '',
    total: json['total'] as int? ?? 0,
    isCash: json['payment_method'] == 'cod',
    claimedAt: DateTime.parse(json['claimed_at'] as String).toLocal(),
  );

  final String orderId;
  final JobState state;

  /// The *order's* status, which is not the job's. Needed for one question the
  /// rider asks constantly while standing at a counter: is it packed yet?
  final String orderStatus;

  final String restaurantName;
  final String deliverTo;
  final String customerPhone;
  final int total;
  final bool isCash;
  final DateTime claimedAt;

  /// Whether the kitchen has finished. Until this is true there is no code to
  /// type, because there is nothing on the counter to hand over.
  bool get isReadyToCollect => orderStatus == 'ready_for_pickup';

  bool get isCarrying => state == JobState.pickedUp;
}
