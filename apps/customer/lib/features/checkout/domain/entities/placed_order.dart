import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';

/// The order service's receipt for a successfully placed order — everything
/// the confirmation screen shows. Live status arrives with order tracking
/// (Step 8); until then this is a snapshot, not a stream.
@immutable
class PlacedOrder {
  const PlacedOrder({
    required this.id,
    required this.restaurantName,
    required this.deliveryTo,
    required this.total,
    required this.paymentMethod,
    required this.etaMinutes,
  });

  /// Human-readable order reference, e.g. `ZPQ-1042`.
  final String id;

  final String restaurantName;

  /// Short display of the delivery address, e.g. `Banjara Hills, Hyderabad`.
  final String deliveryTo;

  /// Amount charged, in whole rupees, after any coupon discount.
  final int total;

  final PaymentMethod paymentMethod;

  final int etaMinutes;
}
