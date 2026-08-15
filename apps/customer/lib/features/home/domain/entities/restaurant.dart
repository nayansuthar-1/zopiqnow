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
    required this.isVeg,
    required this.imageUrl,
    this.distanceKm,
    this.latitude,
    this.longitude,
    this.serviceAreaId,
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

  /// How far this kitchen is from the delivery address, or null when we cannot
  /// say — no address chosen yet, or a restaurant with no coordinates on file.
  ///
  /// **Not read from the database.** `restaurants.distance_km` is a typed-in
  /// number that has always defaulted to 0, which is why every real restaurant
  /// on the platform rendered "0.0 km" from any address, including one in the
  /// next town. This is computed in `home_providers.dart` from [latitude] /
  /// [longitude] and the selected address.
  ///
  /// Nullable on purpose, and the same call the database's own
  /// `delivery_distance_km` makes: a missing coordinate is *unknown* distance,
  /// which is a different fact from zero and must not collapse into it. The UI
  /// omits the figure rather than inventing one.
  final double? distanceKm;

  /// Where the kitchen actually is (migration 0042). Null on rows whose owner
  /// has not been placed on the map yet.
  final double? latitude;
  final double? longitude;

  /// Which town's catalogue this kitchen belongs to (migration 0126) — `sadri`,
  /// `falna`. Derived in Postgres from [latitude]/[longitude], never typed in.
  ///
  /// A kitchen is only ever offered to a customer whose delivery address is in
  /// the same town, and `orders_within_service_area` refuses the order outright
  /// if one gets through anyway. Null on a restaurant outside every service
  /// area, which RLS already hides from the catalogue.
  final String? serviceAreaId;

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

  /// The same kitchen, measured from somewhere.
  ///
  /// A copy rather than a mutation because the entity is immutable, and the feed
  /// re-derives every distance whenever the delivery address changes — the same
  /// restaurant is 0.4 km from home and 11 km from the office.
  Restaurant withDistance(double? km) => Restaurant(
    id: id,
    name: name,
    cuisines: cuisines,
    rating: rating,
    ratingCount: ratingCount,
    etaMinutes: etaMinutes,
    priceForTwo: priceForTwo,
    isVeg: isVeg,
    imageUrl: imageUrl,
    distanceKm: km,
    latitude: latitude,
    longitude: longitude,
    serviceAreaId: serviceAreaId,
    promoText: promoText,
    acceptingOrders: acceptingOrders,
    pauseReason: pauseReason,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Restaurant && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
