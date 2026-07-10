import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';

/// The priced breakdown of a [Cart].
///
/// Lives in the domain, not the cart screen, so the arithmetic is unit-testable
/// without a widget tree — a wrong total is the most expensive bug this app can
/// ship.
///
/// The fee and tax rules below are **placeholders**. Real delivery fees depend
/// on distance, surge, and subscription status, and real tax depends on the
/// item's HSN category. Both move server-side when the pricing engine lands
/// (SAD: Cart service + pricing engine); this class is then fed by the API
/// rather than computing anything.
@immutable
class CartBill {
  const CartBill({
    required this.subtotal,
    required this.deliveryFee,
    required this.taxes,
    this.discount = 0,
  });

  /// Prices a cart. An empty cart bills nothing — not even a delivery fee.
  ///
  /// [discount] comes from a coupon the order service has already validated
  /// (see `AppliedCoupon`) — this class subtracts it, it never computes it.
  factory CartBill.of(Cart cart, {int discount = 0}) {
    if (cart.isEmpty) {
      return const CartBill(subtotal: 0, deliveryFee: 0, taxes: 0);
    }
    final int subtotal = cart.subtotal;
    return CartBill(
      subtotal: subtotal,
      deliveryFee: subtotal >= _freeDeliveryThreshold ? 0 : _flatDeliveryFee,
      taxes: (subtotal * _taxRate).round(),
      discount: discount,
    );
  }

  static const int _flatDeliveryFee = 40;
  static const int _freeDeliveryThreshold = 500;
  static const double _taxRate = 0.05;

  /// Sum of the line totals, in whole rupees.
  final int subtotal;
  final int deliveryFee;
  final int taxes;

  /// Coupon discount in whole rupees; 0 when no coupon is applied.
  final int discount;

  int get total => subtotal + deliveryFee + taxes - discount;

  bool get hasFreeDelivery => subtotal >= _freeDeliveryThreshold;

  /// Rupees still needed to unlock free delivery; 0 once unlocked.
  int get amountToFreeDelivery =>
      hasFreeDelivery ? 0 : _freeDeliveryThreshold - subtotal;
}
