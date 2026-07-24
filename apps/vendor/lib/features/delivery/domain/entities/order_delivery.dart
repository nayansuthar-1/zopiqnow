import 'package:flutter/foundation.dart';

/// The rider on one of this kitchen's orders.
///
/// Read-only, entirely. A vendor does not claim, hand over or complete a
/// delivery — the rider does all three from their own app, and the vendor's part
/// of the handshake is to read four digits aloud. There is no write path here
/// and no grant behind one.
@immutable
class OrderDelivery {
  const OrderDelivery({
    required this.orderId,
    required this.riderName,
    required this.riderPhone,
    required this.state,
    required this.arrivedAt,
    this.pickupOtp,
  });

  factory OrderDelivery.fromJson(Map<String, dynamic> json) {
    // The embedded partner row. Null would mean a rider deleted out from under a
    // live delivery, which the foreign key forbids — but a missing name is not
    // worth throwing a queue screen away over.
    final Map<String, dynamic>? partner =
        json['delivery_partners'] as Map<String, dynamic>?;

    return OrderDelivery(
      orderId: json['order_id'] as String,
      riderName: partner?['name'] as String? ?? 'Delivery partner',
      riderPhone: partner?['phone'] as String? ?? '',
      state: DeliveryState.fromWire(json['state'] as String),
      arrivedAt: json['arrived_at_restaurant_at'] == null
          ? null
          : DateTime.parse(
              json['arrived_at_restaurant_at'] as String,
            ).toLocal(),
    );
  }

  final String orderId;
  final String riderName;
  final String riderPhone;
  final DeliveryState state;

  /// When the rider said they were at the counter (0049). What lets the ticket
  /// say "waiting 9 min" as a fact rather than a guess off the claim time.
  final DateTime? arrivedAt;

  /// The code the kitchen reads out and the rider types in.
  ///
  /// **Not on this row any more.** 0049 moved both codes to `delivery_codes`, a
  /// table with no policies, because the rider had a select policy on their own
  /// `deliveries` row — so the code that was supposed to prove they had walked
  /// into the shop was readable from the road. It is fetched on demand through
  /// `order_pickup_code`, which answers only a staff member of that order's
  /// restaurant, and only while a rider is actually waiting.
  final String? pickupOtp;

  OrderDelivery withCode(String? code) => OrderDelivery(
    orderId: orderId,
    riderName: riderName,
    riderPhone: riderPhone,
    state: state,
    arrivedAt: arrivedAt,
    pickupOtp: code,
  );

  /// Whether the counter still has a bag to hand over. Once the rider has typed
  /// the code the handover is done and the digits are noise on the ticket.
  bool get showsPickupCode =>
      state == DeliveryState.claimed || state == DeliveryState.arrivedAtRestaurant;

  /// Standing at the counter right now. The line a kitchen actually reacts to.
  bool get isWaitingAtCounter => state == DeliveryState.arrivedAtRestaurant;

  /// Whole minutes since the rider arrived, or null if they have not.
  int? get minutesWaiting => arrivedAt == null
      ? null
      : DateTime.now().difference(arrivedAt!).inMinutes;
}

/// Where the *rider* is, which is not the same question as where the order is.
///
/// Deliberately a separate axis from `orders.status`: the customer app throws on
/// an order status it does not know, so the rider's lifecycle was kept out of
/// that column entirely (migration 0025).
enum DeliveryState {
  claimed,
  arrivedAtRestaurant,
  pickedUp,
  arrivedAtCustomer,
  delivered,
  cancelled;

  /// Unknown values fall back to [claimed] rather than throwing. This is the
  /// opposite of the customer app's choice on `orders.status`, and deliberately:
  /// a status drives a receipt, this drives one line on a ticket, and a kitchen
  /// losing its whole queue because a future migration added a state would be a
  /// far worse trade than a rider strip that reads slightly wrong for a day.
  static DeliveryState fromWire(String value) => switch (value) {
    'claimed' => claimed,
    'arrived_at_restaurant' => arrivedAtRestaurant,
    'picked_up' => pickedUp,
    'arrived_at_customer' => arrivedAtCustomer,
    'delivered' => delivered,
    'cancelled' => cancelled,
    _ => claimed,
  };
}
