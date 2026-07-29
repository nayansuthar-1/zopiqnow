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
    this.acceptingOrders = true,
    this.pauseReason = '',
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

  /// Whether the kitchen is currently taking orders. The vendor's own switch
  /// (`restaurants.accepting_orders`). When false the card is greyed and the
  /// menu's ADD buttons are disabled — but the real refusal is `place_order`'s,
  /// so a stale cart cannot slip past a client that thinks the kitchen is open.
  ///
  /// Defaults to true: a restaurant that has never touched the switch is open,
  /// and every mock fixture predates it.
  final bool acceptingOrders;

  /// The kitchen's own words for why it paused — "Short on staff". Shown in
  /// place of the generic "not taking orders" when there is one, and '' when the
  /// kitchen is open or paused without explaining. Postgres clears it on reopen
  /// (migration 0068), so it can never outlive the pause it belonged to.
  final String pauseReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Restaurant && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
