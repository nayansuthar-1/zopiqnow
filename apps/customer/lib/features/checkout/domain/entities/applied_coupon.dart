import 'package:flutter/foundation.dart';

/// A coupon the order service has validated against the current cart.
///
/// The discount arrives pre-computed: coupon rules (minimum order value,
/// percentage caps) are the promotion engine's business, not the app's. The
/// client never derives a discount locally — a client-side rule that drifts
/// from the server's is a refund waiting to happen.
@immutable
class AppliedCoupon {
  const AppliedCoupon({
    required this.code,
    required this.discount,
    this.freeDelivery = false,
    this.deliveryWaived = 0,
  });

  final String code;

  /// Rupees off the bill, already capped by the coupon's rules.
  ///
  /// 0 for a [freeDelivery] code, and that is not a missing number: free
  /// delivery takes nothing off the food. The saving is the delivery line
  /// disappearing, which [CartBill] draws.
  final int discount;

  /// Whether this code waives the delivery fee (migration 0161).
  ///
  /// The surcharge for a late hour or bad weather is *not* waived — it is a
  /// separate line on the bill and the server charges it either way.
  final bool freeDelivery;

  /// Rupees of delivery fee this code covers, as the *server* priced it against
  /// the fee it is currently charging (migration 0162). 0 for every other kind
  /// of code.
  ///
  /// Beside [freeDelivery] rather than derived from it: the flag says what the
  /// coupon is, this says what it is worth, and only the server knows the
  /// second one.
  final int deliveryWaived;
}
