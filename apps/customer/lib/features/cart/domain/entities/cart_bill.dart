import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/delivery_surcharge.dart';

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
    this.surcharge = DeliverySurcharge.none,
    this.deliveryWaived = 0,
  });

  /// Prices a cart. An empty cart bills nothing — not even a delivery fee.
  ///
  /// [discount] comes from a coupon the order service has already validated
  /// (see `AppliedCoupon`) — this class subtracts it, it never computes it.
  ///
  /// [surcharge] likewise comes from the server (`delivery_surcharge_now`), and
  /// defaults to none so that a caller which has not read it yet quotes the
  /// plain fee rather than nothing at all.
  ///
  /// [deliveryFee] is what the server is charging for the ride right now
  /// (`delivery_fee_now`, migration 0162), and defaults to [flatDeliveryFee] for
  /// the same reason [surcharge] defaults to none: a caller whose read has not
  /// landed quotes the shipped number rather than nothing.
  ///
  /// [deliveryWaived] is the applied coupon's, and is the *only* thing that
  /// reduces that fee. It is deliberately not a discount: `place_order` waives
  /// the fee and the 18% inside it rather than taking rupees off the food, so
  /// the food's own GST does not move (migration 0161). Subtracting ₹40 from the
  /// food instead would quote a total two rupees under the one that is charged.
  factory CartBill.of(
    Cart cart, {
    int discount = 0,
    DeliverySurcharge surcharge = DeliverySurcharge.none,
    int deliveryFee = flatDeliveryFee,
    int deliveryWaived = 0,
  }) {
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
      surcharge: surcharge,
      // No basket size earns this back — migration 0123 withdrew the ₹500
      // free-delivery threshold from `place_order` and `checkout_preflight` in
      // one statement, and a cart that still believed in it would quote ₹40 too
      // little and have the order refused after the money was captured.
      //
      // Two things move it now, and both come from the server rather than from
      // a rule restated here: what an admin has set the fee to (0162), and a
      // coupon that waives it (0161). `clamp` because a waiver is priced against
      // the fee the *server* read, and a fee lowered between that read and this
      // frame must not produce a negative line.
      deliveryFee: (deliveryFee - deliveryWaived).clamp(0, deliveryFee),
      taxes: taxes,
      discount: discount,
      deliveryWaived: deliveryWaived,
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

  /// **What this app was built with, not what it charges.** Since migration
  /// 0162 the fee is a settings row an admin can move from the console, read by
  /// `delivery_fee_now` — and by `place_order`, so the number here is not the
  /// number on the bill unless they agree.
  ///
  /// It stays for the two moments there is no server answer to use: the frame
  /// before `deliveryFeeProvider` resolves, and a read that failed. Quoting the
  /// shipped ₹40 is the honest failure — the order is priced by
  /// `checkout_preflight` at the moment of payment either way.
  ///
  /// `freeDeliveryThreshold` used to sit beside this and is gone with migration
  /// 0123 — there is no basket size that earns free delivery any more, so there
  /// is no number to compare against and nothing for the bill card to draw a
  /// progress bar towards.
  static const int flatDeliveryFee = 40;

  /// Sum of the line totals, in whole rupees.
  final int subtotal;

  /// What the customer pays for delivery, GST included — the fee stack the
  /// server stores is gross, and this line is the whole of it.
  final int deliveryFee;

  /// GST on the food, charged on top of the discounted subtotal. The tax inside
  /// the delivery fee is not here and is not added again: it is already in
  /// [deliveryFee].
  final int taxes;

  /// Coupon discount in whole rupees; 0 when no coupon is applied, and 0 for a
  /// free-delivery code, which takes nothing off the food.
  final int discount;

  /// What a coupon paid towards the ride (migration 0161); 0 without one.
  ///
  /// [deliveryFee] is already net of it. This survives beside it because the
  /// bill has two things to say that the net figure alone cannot: *why* the
  /// line is free, and how much that was worth in the savings strip.
  final int deliveryWaived;

  /// Whether a coupon covered the whole ride.
  bool get freeDelivery => deliveryWaived > 0 && deliveryFee == 0;

  /// What the hour and the weather are adding to delivery (migration 0129).
  ///
  /// Kept beside [deliveryFee] rather than folded into it: the server stores it
  /// in its own column (`orders.surge_fee`), the bill draws it as its own line
  /// so it can say why, and a customer who reads ₹40 + ₹20 can tell which part
  /// is tonight and which part is always.
  final DeliverySurcharge surcharge;

  int get total =>
      subtotal + deliveryFee + surcharge.total + taxes - discount;
}
