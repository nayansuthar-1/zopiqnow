import 'package:flutter/foundation.dart';

/// Whether this order can be reviewed, and whether there is a rider to rate.
///
/// Read from `order_review_state` rather than worked out here. "Delivered, mine,
/// and inside the window" is three rules the database already owns (migration
/// 0062), and a second copy on a phone is a copy that goes stale on the day the
/// window changes — or on a phone whose clock is wrong.
@immutable
class OrderReviewState {
  const OrderReviewState({
    required this.canReview,
    required this.hasRider,
    this.riderName,
  });

  /// Nothing to review: the order is not delivered, is not this customer's, or
  /// the fortnight has passed.
  static const OrderReviewState none = OrderReviewState(
    canReview: false,
    hasRider: false,
  );

  factory OrderReviewState.fromJson(Map<String, dynamic> json) {
    return OrderReviewState(
      canReview: json['can_review'] as bool? ?? false,
      hasRider: json['has_rider'] as bool? ?? false,
      riderName: json['rider_name'] as String?,
    );
  }

  final bool canReview;

  /// False when nobody carried the order — a pickup, or a delivery whose row
  /// never landed. The sheet then rates the food alone rather than showing a
  /// second row of stars with nobody behind them.
  final bool hasRider;

  final String? riderName;
}

/// What this customer said about one order.
@immutable
class OrderReview {
  const OrderReview({
    required this.foodRating,
    required this.createdAt,
    required this.editableUntil,
    this.riderRating,
    this.comment,
  });

  factory OrderReview.fromJson(Map<String, dynamic> json) {
    return OrderReview(
      foodRating: (json['food_rating'] as num).toInt(),
      riderRating: (json['rider_rating'] as num?)?.toInt(),
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      editableUntil: DateTime.parse(
        json['editable_until'] as String,
      ).toLocal(),
    );
  }

  final int foodRating;
  final int? riderRating;
  final String? comment;
  final DateTime createdAt;

  /// After this, the row itself refuses to change (0062). The screen greys the
  /// button from this timestamp; it is not the enforcement, only the warning.
  final DateTime editableUntil;

  bool get isEditable => DateTime.now().isBefore(editableUntil);
}
