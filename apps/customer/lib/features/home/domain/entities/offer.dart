import 'package:flutter/foundation.dart';

/// A promotional offer shown in the Home offers carousel.
@immutable
class Offer {
  const Offer({
    required this.id,
    required this.headline,
    required this.detail,
    required this.code,
  });

  final String id;

  /// Primary copy, e.g. "60% OFF UPTO ₹120".
  final String headline;

  /// Qualifier, e.g. "ABOVE ₹159".
  final String detail;

  /// Coupon code the customer applies at checkout, e.g. "TRYNEW".
  final String code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Offer && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
