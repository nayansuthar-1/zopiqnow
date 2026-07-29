import 'package:flutter/foundation.dart';

/// One offer this kitchen is running, as `vendor_offers` hands it over
/// (migration 0064).
///
/// [timesUsed] and [totalGiven] are counted from the orders that carried the
/// code, not from a tally column — the reason ratings are recomputed rather than
/// incremented: a counter that is bumped on use is a counter that is wrong after
/// the first refund.
@immutable
class VendorOffer {
  const VendorOffer({
    required this.code,
    required this.label,
    required this.minSubtotal,
    required this.isActive,
    required this.timesUsed,
    required this.totalGiven,
    this.flatOff,
    this.percentOff,
    this.maxOff,
    this.validUntil,
  });

  factory VendorOffer.fromJson(Map<String, dynamic> json) => VendorOffer(
    code: json['code'] as String,
    label: json['label'] as String,
    minSubtotal: (json['min_subtotal'] as num).toInt(),
    flatOff: (json['flat_off'] as num?)?.toInt(),
    percentOff: (json['percent_off'] as num?)?.toInt(),
    maxOff: (json['max_off'] as num?)?.toInt(),
    validUntil: json['valid_until'] == null
        ? null
        : DateTime.parse(json['valid_until'] as String).toLocal(),
    isActive: json['is_active'] as bool,
    timesUsed: (json['times_used'] as num).toInt(),
    totalGiven: (json['total_given'] as num).toInt(),
  );

  final String code;

  /// The rule in words — "20% off up to ₹100" — built by the database so the
  /// vendor reads the same sentence the customer is shown.
  final String label;

  final int minSubtotal;
  final int? flatOff;
  final int? percentOff;
  final int? maxOff;
  final DateTime? validUntil;
  final bool isActive;
  final int timesUsed;
  final int totalGiven;

  bool get isFlat => flatOff != null;

  /// Ended by the clock rather than by the switch. Worth distinguishing on
  /// screen: "you turned this off" and "this ran out on Sunday" are different
  /// things to do something about.
  bool get hasExpired =>
      validUntil != null && DateTime.now().isAfter(validUntil!);
}
