import 'package:flutter/foundation.dart';

/// A restaurant as shown in the customer Home discovery list.
///
/// Pure domain entity — no JSON, no Flutter. The data layer maps API/mock
/// payloads into this; the UI reads only this (SAD 7.4 repository pattern).
@immutable
class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.cuisines,
    required this.rating,
    required this.ratingCount,
    required this.etaMinutes,
    required this.priceForTwo,
    required this.distanceKm,
    required this.isVeg,
    required this.imageUrl,
    this.promoText,
  });

  final String id;
  final String name;
  final List<String> cuisines;
  final double rating;
  final int ratingCount;
  final int etaMinutes;

  /// Indicative price for two, in whole rupees.
  final int priceForTwo;
  final double distanceKm;
  final bool isVeg;

  /// Remote image URL. Rendered with a branded placeholder until the image
  /// pipeline (CDN + cached network images) lands.
  final String imageUrl;

  /// Optional offer copy, e.g. "50% OFF up to ₹100". Null when no promo.
  final String? promoText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Restaurant && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
