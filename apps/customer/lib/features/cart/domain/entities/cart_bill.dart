import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';

/// The priced breakdown of a [Cart].
///
/// Lives in the domain, not the cart screen, so the arithmetic is unit-testable
/// without a widget tree — a wrong total is the most expensive bug this app can
/// ship.
///
/// **This is a quote, not a price.** `place_order` re-prices every line from the
/// menu when the order is placed, and its figure is the one that is charged. The
/// job of this class is to arrive at the same number, so that the total a
/// customer reads before they tap Pay is the total they are charged — which is
/// why the tax below is computed line by line, at each line's own GST slab, on
/// what is left of the line after its share of the coupon (migration 0078).
/// Guessing at a flat rate on the pre-discount subtotal, as this did until then,
/// quoted a few rupees too many on every discounted cart.
///
/// The delivery-fee rule is still a placeholder: real fees depend on distance,
/// surge and subscription. The server owns it, this mirrors it, and the day it
/// moves it moves in both places.
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
    final List<int> lineTotals = cart.lines
        .map((CartLine l) => l.lineTotal)
        .toList(growable: false);
    final List<int> allocations = _apportion(discount, lineTotals, subtotal);

    // Totalled per slab and rounded once per slab, the way `place_order` does
    // it and the way a GST invoice states it. Rounding line by line would come
    // to a different number: ₹250 and ₹150 each round their 5% up half a rupee,
    // and the customer would be quoted ₹21 on a ₹400 cart that owes ₹20.
    final Map<int, int> taxableByRate = <int, int>{};
    for (int i = 0; i < cart.lines.length; i++) {
      final int rate = cart.lines[i].item.gstRateBps;
      taxableByRate[rate] =
          (taxableByRate[rate] ?? 0) + lineTotals[i] - allocations[i];
    }

    int taxes = 0;
    taxableByRate.forEach((int rate, int taxable) {
      // Integer arithmetic, rounding half up, because that is exactly what
      // Postgres `round(numeric)` does to a positive number. Doing it in
      // doubles would agree with the server almost always, and "almost" is a
      // rupee of difference on somebody's bill.
      taxes += (taxable * rate + 5000) ~/ 10000;
    });

    return CartBill(
      subtotal: subtotal,
      deliveryFee: subtotal >= freeDeliveryThreshold ? 0 : flatDeliveryFee,
      taxes: taxes,
      discount: discount,
    );
  }

  /// Splits [discount] across [lineTotals] in proportion to their value, so that
  /// the parts sum back to the whole to the rupee: every line takes its floor
  /// share, then the leftover rupees go one each to the lines with the largest
  /// fractional claim, ties broken by position.
  ///
  /// The same largest-remainder rule `place_order` applies, in the same order —
  /// the cart sends its lines to the server in this order, and the server
  /// apportions by that ordinality.
  static List<int> _apportion(int discount, List<int> lineTotals, int subtotal) {
    final List<int> alloc = List<int>.filled(lineTotals.length, 0);
    if (discount <= 0 || subtotal <= 0) return alloc;

    final List<int> remainders = List<int>.filled(lineTotals.length, 0);
    int floors = 0;
    for (int i = 0; i < lineTotals.length; i++) {
      alloc[i] = (discount * lineTotals[i]) ~/ subtotal;
      remainders[i] = (discount * lineTotals[i]) % subtotal;
      floors += alloc[i];
    }

    final List<int> order = List<int>.generate(lineTotals.length, (int i) => i)
      ..sort((int a, int b) {
        final int byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });

    for (int n = 0; n < discount - floors; n++) {
      alloc[order[n]] += 1;
    }
    return alloc;
  }

  /// Public because the bill *card* needs them: it strikes through the fee the
  /// customer is not paying, and draws how far they are from not paying it. The
  /// alternative is the UI restating 40 and 500 as its own magic numbers, and
  /// then quietly disagreeing with the bill the day the rule changes.
  static const int flatDeliveryFee = 40;
  static const int freeDeliveryThreshold = 500;

  /// Sum of the line totals, in whole rupees.
  final int subtotal;

  /// What the customer pays for delivery, GST included — the fee stack the
  /// server stores is gross, and this line is the whole of it.
  final int deliveryFee;

  /// GST on the food, charged on top of the discounted subtotal. The tax inside
  /// the delivery fee is not here and is not added again: it is already in
  /// [deliveryFee].
  final int taxes;

  /// Coupon discount in whole rupees; 0 when no coupon is applied.
  final int discount;

  int get total => subtotal + deliveryFee + taxes - discount;

  bool get hasFreeDelivery => subtotal >= freeDeliveryThreshold;

  /// Rupees still needed to unlock free delivery; 0 once unlocked.
  int get amountToFreeDelivery =>
      hasFreeDelivery ? 0 : freeDeliveryThreshold - subtotal;
}
