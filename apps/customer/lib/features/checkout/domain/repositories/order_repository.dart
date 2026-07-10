import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Contract for coupons and order placement (SAD 7.4).
abstract interface class OrderRepository {
  /// Validates [code] against the cart's [subtotal].
  ///
  /// Throws [CouponFailure] with a human-readable reason when the code is
  /// unknown or the cart doesn't meet the coupon's minimum.
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
  });

  /// Places the order and returns the receipt.
  ///
  /// Throws [OrderPlacementFailure] on any transport error.
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required CartBill bill,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
  });
}

/// A coupon the order service rejected. [message] is written for the customer,
/// not the log — the checkout screen renders it under the coupon field.
class CouponFailure implements Exception {
  const CouponFailure(this.message);

  final String message;

  @override
  String toString() => 'CouponFailure: $message';
}

/// Domain-level failure for order placement.
class OrderPlacementFailure implements Exception {
  const OrderPlacementFailure([
    this.message = 'We couldn\'t place your order. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'OrderPlacementFailure: $message';
}
