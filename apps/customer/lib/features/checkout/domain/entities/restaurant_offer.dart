import 'package:flutter/foundation.dart';

/// One offer a customer can type at checkout, as `restaurant_offers` words it
/// (migration 0064).
///
/// [label] arrives already written — "20% off up to ₹100" — and is not assembled
/// here. The sentence is the *contents of the rule*, and the day the rule grows
/// a case the sentence has to grow with it, in one place, next to the arithmetic
/// that honours it.
@immutable
class RestaurantOffer {
  const RestaurantOffer({
    required this.code,
    required this.label,
    required this.minSubtotal,
    required this.isExclusive,
    this.validUntil,
  });

  factory RestaurantOffer.fromJson(Map<String, dynamic> json) =>
      RestaurantOffer(
        code: json['code'] as String,
        label: json['label'] as String,
        minSubtotal: (json['min_subtotal'] as num).toInt(),
        isExclusive: json['is_exclusive'] as bool? ?? false,
        validUntil: json['valid_until'] == null
            ? null
            : DateTime.parse(json['valid_until'] as String).toLocal(),
      );

  final String code;
  final String label;
  final int minSubtotal;

  /// The kitchen's own offer rather than a Zopiqnow-wide one. Worth saying on
  /// screen: "only at this restaurant" is why it is better than the others.
  final bool isExclusive;

  final DateTime? validUntil;
}
