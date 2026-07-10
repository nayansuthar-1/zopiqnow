import 'dart:math' as math;

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// In-memory stand-in for the order service, faithful to the contract the real
/// endpoints will enforce: coupons carry a minimum order value and a discount
/// cap, and validation happens service-side against the submitted subtotal.
///
/// Modelling the rules now means the coupon field already has "unknown code"
/// and "cart too small" states to render, and the HTTP swap (Step 7) changes
/// the transport, not the UI's failure modes.
class OrderMockDataSource {
  OrderMockDataSource({this.latency = const Duration(milliseconds: 600)});

  final Duration latency;

  /// The coupon book the real promotions service will own. The checkout screen
  /// surfaces these codes as hints — there is no campaign to learn them from.
  static const List<CouponRule> coupons = <CouponRule>[
    CouponRule(code: 'WELCOME50', minSubtotal: 199, flatOff: 50),
    CouponRule(code: 'ZOPIQ20', minSubtotal: 299, percentOff: 20, maxOff: 100),
  ];

  int _orderSeq = 0;

  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
  }) async {
    await Future<void>.delayed(latency);

    final String normalized = code.trim().toUpperCase();
    CouponRule? rule;
    for (final CouponRule r in coupons) {
      if (r.code == normalized) rule = r;
    }
    if (rule == null) {
      throw const CouponFailure('This code isn\'t valid.');
    }
    if (subtotal < rule.minSubtotal) {
      throw CouponFailure(
        'Add items worth ₹${rule.minSubtotal - subtotal} more to use '
        '${rule.code}.',
      );
    }
    return AppliedCoupon(code: rule.code, discount: rule.discountOn(subtotal));
  }

  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required CartBill bill,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
  }) async {
    await Future<void>.delayed(latency);

    _orderSeq++;
    return PlacedOrder(
      id: 'ZPQ-${1000 + _orderSeq}',
      restaurantName: cart.restaurantName ?? '',
      deliveryTo: deliveryAddress.shortDisplay,
      total: bill.total,
      paymentMethod: paymentMethod,
      // Deterministic per restaurant, 25–35 min. A real ETA comes from the
      // dispatch engine with tracking (Step 8).
      etaMinutes: 25 + (cart.restaurantId ?? '').hashCode.toUnsigned(32) % 11,
    );
  }
}

/// One row of the mock coupon book: either a flat discount or a capped
/// percentage, gated by a minimum order value.
class CouponRule {
  const CouponRule({
    required this.code,
    required this.minSubtotal,
    this.flatOff,
    this.percentOff,
    this.maxOff,
  }) : assert(
         (flatOff != null) ^ (percentOff != null && maxOff != null),
         'A rule is flat XOR capped-percent',
       );

  final String code;
  final int minSubtotal;
  final int? flatOff;
  final int? percentOff;
  final int? maxOff;

  int discountOn(int subtotal) =>
      flatOff ?? math.min((subtotal * percentOff! / 100).round(), maxOff!);

  /// What the checkout screen's hint shows, e.g. `WELCOME50 · ₹50 off`.
  String get summary => flatOff != null
      ? '$code · ₹$flatOff off'
      : '$code · $percentOff% off up to ₹$maxOff';
}
