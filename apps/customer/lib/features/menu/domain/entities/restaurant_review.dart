import 'package:flutter/foundation.dart';

/// One review on a restaurant's public wall, as `restaurant_reviews` hands it
/// over (migration 0062).
///
/// [reviewer] is a **first name and nothing else** — the function derives it and
/// falls back to "Zopiqnow customer" when there is none. What deliberately does
/// not reach this class: the order id, the user id, and the rider's score. A
/// public list keyed by order would let anyone correlate a review with a
/// delivery, and the rider's score is between the rider and us.
@immutable
class RestaurantReview {
  const RestaurantReview({
    required this.reviewer,
    required this.rating,
    required this.createdAt,
    this.comment,
  });

  factory RestaurantReview.fromJson(Map<String, dynamic> json) =>
      RestaurantReview(
        reviewer: json['reviewer'] as String,
        rating: (json['food_rating'] as num).toInt(),
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final String reviewer;
  final int rating;
  final String? comment;
  final DateTime createdAt;
}
