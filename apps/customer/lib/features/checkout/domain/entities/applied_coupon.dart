import 'package:flutter/foundation.dart';

/// A coupon the order service has validated against the current cart.
///
/// The discount arrives pre-computed: coupon rules (minimum order value,
/// percentage caps) are the promotion engine's business, not the app's. The
/// client never derives a discount locally — a client-side rule that drifts
/// from the server's is a refund waiting to happen.
@immutable
class AppliedCoupon {
  const AppliedCoupon({required this.code, required this.discount});

  final String code;

  /// Rupees off the bill, already capped by the coupon's rules.
  final int discount;
}
