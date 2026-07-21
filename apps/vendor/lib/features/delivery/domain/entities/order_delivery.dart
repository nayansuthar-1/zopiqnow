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
    required this.pickupOtp,
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
      pickupOtp: json['pickup_otp'] as String,
    );
  }

  final String orderId;
  final String riderName;
  final String riderPhone;
  final DeliveryState state;

  /// The code the kitchen reads out and the rider types in. Shown on the ticket
  /// only while it is still needed — see [showsPickupCode].
  final String pickupOtp;

  /// Whether the counter still has a bag to hand over. Once the rider has typed
  /// the code the handover is done and the digits are noise on the ticket.
  bool get showsPickupCode => state == DeliveryState.claimed;
}

/// Where the *rider* is, which is not the same question as where the order is.
///
/// Deliberately a separate axis from `orders.status`: the customer app throws on
/// an order status it does not know, so the rider's lifecycle was kept out of
/// that column entirely (migration 0025).
enum DeliveryState {
  claimed,
  pickedUp,
  delivered,
  cancelled;

  /// Unknown values fall back to [claimed] rather than throwing. This is the
  /// opposite of the customer app's choice on `orders.status`, and deliberately:
  /// a status drives a receipt, this drives one line on a ticket, and a kitchen
  /// losing its whole queue because a future migration added a state would be a
  /// far worse trade than a rider strip that reads slightly wrong for a day.
  static DeliveryState fromWire(String value) => switch (value) {
    'claimed' => claimed,
    'picked_up' => pickedUp,
    'delivered' => delivered,
    'cancelled' => cancelled,
    _ => claimed,
  };
}
