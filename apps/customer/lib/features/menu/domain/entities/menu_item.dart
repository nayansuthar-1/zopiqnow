import 'package:flutter/foundation.dart';

/// A single orderable dish on a restaurant's menu. Pure domain entity.
@immutable
class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.isVeg,
    this.isBestseller = false,
    this.rating,
  });

  final String id;
  final String name;
  final String description;

  /// Price in whole rupees.
  final int price;
  final bool isVeg;
  final bool isBestseller;

  /// Optional dish rating (0–5), null when not enough ratings.
  final double? rating;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MenuItem && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
