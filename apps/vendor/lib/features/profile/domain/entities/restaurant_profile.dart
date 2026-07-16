import 'package:flutter/foundation.dart';

/// The restaurant's public face, as the kitchen may edit it.
///
/// These are the fields that render on the *customer* app — the name on the
/// card, the cuisines under it, the cost for two, the pure-veg badge, the offer
/// line, the prep time. Editing one here changes what a customer sees there,
/// because both apps read the one `restaurants` row.
///
/// `rating` and `ratingCount` are here to *show*, not to set: a rating is earned
/// by customers, and `update_restaurant_profile` cannot touch it.
@immutable
class RestaurantProfile {
  const RestaurantProfile({
    required this.name,
    required this.cuisines,
    required this.priceForTwo,
    required this.isVeg,
    required this.promoText,
    required this.etaMinutes,
    required this.imageUrl,
    required this.rating,
    required this.ratingCount,
  });

  final String name;
  final List<String> cuisines;
  final int priceForTwo;
  final bool isVeg;
  final String? promoText;
  final int etaMinutes;

  /// The cover photo's Cloudinary URL, or '' when there is none.
  final String imageUrl;

  /// Read-only. Earned, not typed.
  final double rating;
  final int ratingCount;
}
