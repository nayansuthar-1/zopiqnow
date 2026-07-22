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

/// One day's work, as `rider_earnings` counts it (migration 0043).
///
/// Only delivered jobs are in here. A job in hand has not been earned yet, and
/// a rider watching their total rise at pickup would have been told they were
/// paid for a delivery they might still fail to make. The day is the day it was
/// *delivered*, in IST — the day the rider actually worked.
@immutable
class EarningsDay {
  const EarningsDay({
    required this.day,
    required this.jobs,
    required this.earnings,
  });

  factory EarningsDay.fromJson(Map<String, dynamic> json) => EarningsDay(
    day: DateTime.parse(json['day'] as String),
    jobs: json['jobs'] as int? ?? 0,
    earnings: json['earnings'] as int? ?? 0,
  );

  /// A calendar date, not an instant. Deliberately not converted to local time:
  /// Postgres already resolved it to the rider's own day in IST, and calling
  /// `toLocal()` on a midnight date is how a day slides into the one before it.
  final DateTime day;

  final int jobs;
  final int earnings;
}

/// One week's pay, as a batch (migration 0045).
///
/// The rider's twin of a restaurant's settlement, and the same shape: a Mon–Sun
/// window, a count, an amount, and whether the money has actually left. Born in
/// the weekly rollup, marked paid by an admin with the bank's reference — never
/// by anything the rider does.
@immutable
class Payout {
  const Payout({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.deliveryCount,
    required this.amount,
    required this.isPaid,
    required this.reference,
    required this.paidAt,
  });

  factory Payout.fromJson(Map<String, dynamic> json) => Payout(
    id: json['id'] as int,
    periodStart: DateTime.parse(json['period_start'] as String),
    periodEnd: DateTime.parse(json['period_end'] as String),
    deliveryCount: json['delivery_count'] as int? ?? 0,
    amount: json['amount'] as int? ?? 0,
    isPaid: json['status'] == 'paid',
    reference: json['reference'] as String?,
    paidAt: json['paid_at'] == null
        ? null
        : DateTime.parse(json['paid_at'] as String).toLocal(),
  );

  final int id;

  /// Calendar dates, not instants — the same reasoning as [EarningsDay.day].
  final DateTime periodStart;
  final DateTime periodEnd;

  final int deliveryCount;
  final int amount;
  final bool isPaid;

  /// The bank's reference (a UTR), and the reason it is shown rather than kept
  /// for ops: a rider whose bank says nothing arrived needs the number to ask
  /// about, and asking the platform for it is a day lost.
  final String? reference;

  final DateTime? paidAt;
}

/// A job this rider is actually carrying.
@immutable
class Job {
  const Job({
    required this.orderId,
    required this.state,
    required this.orderStatus,
    required this.restaurantName,
    required this.restaurantLat,
    required this.restaurantLng,
    required this.deliverTo,
    required this.deliverLat,
    required this.deliverLng,
    required this.customerPhone,
    required this.total,
    required this.isCash,
    required this.distanceKm,
    required this.payBase,
    required this.payPerKm,
    required this.riderPay,
    required this.claimedAt,
    required this.deliveredAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    orderId: json['order_id'] as String,
    state: JobState.fromWire(json['state'] as String),
    orderStatus: json['order_status'] as String? ?? '',
    restaurantName: json['restaurant_name'] as String? ?? 'Restaurant',
    restaurantLat: (json['restaurant_lat'] as num?)?.toDouble(),
    restaurantLng: (json['restaurant_lng'] as num?)?.toDouble(),
    deliverTo: json['deliver_to'] as String? ?? '',
    deliverLat: (json['deliver_lat'] as num?)?.toDouble(),
    deliverLng: (json['deliver_lng'] as num?)?.toDouble(),
    customerPhone: json['customer_phone'] as String? ?? '',
    total: json['total'] as int? ?? 0,
    isCash: json['payment_method'] == 'cod',
    // `num`, not `int`: these are Postgres `numeric` and arrive as either,
    // depending on whether the value happens to be whole.
    distanceKm: (json['distance_km'] as num?)?.toDouble(),
    payBase: json['pay_base'] as int? ?? 0,
    payPerKm: (json['pay_per_km'] as num?)?.toDouble() ?? 0,
    riderPay: json['rider_pay'] as int? ?? 0,
    claimedAt: DateTime.parse(json['claimed_at'] as String).toLocal(),
    deliveredAt: json['delivered_at'] == null
        ? null
        : DateTime.parse(json['delivered_at'] as String).toLocal(),
  );

  final String orderId;
  final JobState state;

  /// The *order's* status, which is not the job's. Needed for one question the
  /// rider asks constantly while standing at a counter: is it packed yet?
  final String orderStatus;

  final String restaurantName;
  final String deliverTo;
  final String customerPhone;

  /// Both ends of the ride. Returned by `my_deliveries` since 0025 and ignored
  /// by this app until navigation arrived — the restaurant's are null for any
  /// kitchen without a map location on file (see 0042, and seed 0007 for the
  /// eight demo ones), and a null pair means the map gets the address text
  /// instead of a pin.
  final double? restaurantLat;
  final double? restaurantLng;
  final double? deliverLat;
  final double? deliverLng;

  /// Where this job is going *right now* — the kitchen until it is collected,
  /// the customer after. The one question a navigation button has to answer,
  /// and answering it from [state] means the rider never picks the wrong end.
  double? get targetLat => isCarrying ? deliverLat : restaurantLat;
  double? get targetLng => isCarrying ? deliverLng : restaurantLng;
  String get targetLabel => isCarrying ? deliverTo : restaurantName;
  final int total;
  final bool isCash;

  /// Straight-line kilometres from the kitchen to the door, as measured when
  /// the job was claimed — **null when it could not be measured at all**,
  /// which means the restaurant has no coordinates on file. Null is not zero,
  /// and the difference is visible to the rider: an unmeasured job pays the
  /// base fee and says so, rather than showing a confident `0.0 km`.
  final double? distanceKm;

  /// The two halves of the rate that applied *at claim time* (migration 0043).
  /// Kept apart from [riderPay] rather than folded into it so a rider can check
  /// the arithmetic — pay you cannot check is pay you will eventually dispute.
  final int payBase;
  final double payPerKm;

  /// What this job pays, in whole rupees. Earned on delivery, not on claim.
  final int riderPay;

  final DateTime claimedAt;
  final DateTime? deliveredAt;

  /// Whether the kitchen has finished. Until this is true there is no code to
  /// type, because there is nothing on the counter to hand over.
  bool get isReadyToCollect => orderStatus == 'ready_for_pickup';

  bool get isCarrying => state == JobState.pickedUp;

  /// The sum, spelled out: "₹25 + 4.2 km × ₹5".
  ///
  /// The unmeasured case says what actually happened rather than hiding it —
  /// a rider who reads "base fee only" and knows the ride was six kilometres
  /// has been handed the exact sentence to complain with, which is the point.
  String get payExplained => distanceKm == null
      ? '₹$payBase base fee only — this kitchen has no map location'
      : '₹$payBase + ${_trim(distanceKm!)} km × ₹${_trim(payPerKm)}';

  /// 4.20 → "4.2", 5.00 → "5". Trailing zeros on money a rider is reading at a
  /// traffic light are noise.
  static String _trim(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}
