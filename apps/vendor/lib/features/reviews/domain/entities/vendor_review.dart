import 'package:flutter/foundation.dart';

/// One customer's verdict on one order, as `vendor_reviews` hands it over
/// (migration 0062).
///
/// Note what is **not** here: who wrote it. The kitchen gets the order id — so
/// it can look the meal up in its own history — and never the customer's name,
/// id or phone. A vendor that could put a name to a 1★ is a vendor that could
/// ring somebody about it.
@immutable
class VendorReview {
  const VendorReview({
    required this.orderId,
    required this.foodRating,
    required this.createdAt,
    this.riderRating,
    this.comment,
  });

  factory VendorReview.fromJson(Map<String, dynamic> json) => VendorReview(
    orderId: json['order_id'] as String,
    foodRating: (json['food_rating'] as num).toInt(),
    riderRating: (json['rider_rating'] as num?)?.toInt(),
    comment: json['comment'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String orderId;
  final int foodRating;

  /// The delivery's score, which is *not* the kitchen's. Shown beside the food
  /// rating precisely so "the food was cold" can be read next to a 2★ ride
  /// instead of landing on the cook.
  final int? riderRating;

  final String? comment;
  final DateTime createdAt;
}

/// The headline figures at the top of the Reviews room.
///
/// [rating] is the same number the customer sees on the restaurant card — read
/// from the same aggregate, not summed here — because a kitchen being shown a
/// different average from its customers is a support ticket waiting to happen.
@immutable
class VendorReviewSummary {
  const VendorReviewSummary({
    required this.rating,
    required this.ratingCount,
    required this.stars,
  });

  static const VendorReviewSummary empty = VendorReviewSummary(
    rating: 0,
    ratingCount: 0,
    stars: <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0},
  );

  factory VendorReviewSummary.fromJson(Map<String, dynamic> json) =>
      VendorReviewSummary(
        rating: (json['rating'] as num).toDouble(),
        ratingCount: (json['rating_count'] as num).toInt(),
        stars: <int, int>{
          5: (json['five_star'] as num).toInt(),
          4: (json['four_star'] as num).toInt(),
          3: (json['three_star'] as num).toInt(),
          2: (json['two_star'] as num).toInt(),
          1: (json['one_star'] as num).toInt(),
        },
      );

  final double rating;
  final int ratingCount;

  /// How many reviews gave each score, 5 down to 1.
  final Map<int, int> stars;

  bool get isEmpty => ratingCount == 0;
}
