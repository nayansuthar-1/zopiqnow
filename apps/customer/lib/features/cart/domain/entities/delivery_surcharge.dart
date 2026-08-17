import 'package:flutter/foundation.dart';

/// What is being added to the cost of delivery right now, and why.
///
/// Two surcharges, ₹20 each, and they stack (migration 0129):
///
///   * **night** — an order placed between 20:00 and 06:00, Asia/Kolkata;
///   * **rain**  — an order placed while it is raining on the kitchen's town.
///
/// **Read from the server, never worked out here.** The clock half could be
/// computed on the phone and deliberately is not: a device whose timezone or
/// clock is wrong would quote a fee the server does not charge, and the rain
/// half is not knowable on the device at all. `delivery_surcharge_now` is the
/// one place the rule lives, and `place_order` and `checkout_preflight` call
/// the same function — so this is a faithful copy of the server's answer rather
/// than a second implementation of it.
///
/// [none] is what a failed read collapses to, and it is the right failure: the
/// bill under-quotes by ₹20 rather than inventing a charge, and the amount
/// actually taken comes from `checkout_preflight` at the moment of payment, not
/// from this.
@immutable
class DeliverySurcharge {
  const DeliverySurcharge({required this.night, required this.rain});

  factory DeliverySurcharge.fromJson(Map<String, dynamic> json) {
    return DeliverySurcharge(
      night: (json['night'] as num?)?.toInt() ?? 0,
      rain: (json['rain'] as num?)?.toInt() ?? 0,
    );
  }

  /// Nothing extra — daytime, dry, or a read that did not come back.
  static const DeliverySurcharge none = DeliverySurcharge(night: 0, rain: 0);

  /// Rupees added because of the hour.
  final int night;

  /// Rupees added because of the weather.
  final int rain;

  int get total => night + rain;

  bool get isEmpty => total == 0;

  /// What the bill calls this line. Null when there is no line to draw.
  ///
  /// One line and not two even when both apply, because the customer is being
  /// asked about one number: a bill that itemises ₹20 twice invites the reading
  /// that it could have been ₹20 once.
  String? get label {
    if (night > 0 && rain > 0) return 'Late night & rain fee';
    if (night > 0) return 'Late night fee';
    if (rain > 0) return 'Rain fee';
    return null;
  }

  /// The sentence under the line — the difference between a surcharge and a
  /// number that appeared.
  ///
  /// **States when it applies, and does not say where the money goes.** The
  /// obvious wording ("extra for riders out in the rain") would be a claim
  /// about rider pay, and rider pay is distance-based (`rider_pay_quote`,
  /// 0043/0122) and does not move with the weather or the hour — so this app
  /// would be telling customers something the payout tables do not do. If that
  /// changes, this is the line that changes with it.
  String? get reason {
    if (night > 0 && rain > 0) {
      return 'Applies after 8pm and while it is raining.';
    }
    if (night > 0) return 'Applies to orders placed after 8pm.';
    if (rain > 0) return 'Applies while it is raining in your area.';
    return null;
  }
}
