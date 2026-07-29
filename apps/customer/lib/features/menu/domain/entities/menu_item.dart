import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';

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
    this.imageUrl = '',
    this.optionGroups = const <MenuOptionGroup>[],
  });

  final String id;
  final String name;
  final String description;

  /// Price in whole rupees — the cheapest configuration; options add to it.
  final int price;
  final bool isVeg;
  final bool isBestseller;

  /// Optional dish rating (0–5), null when not enough ratings.
  final double? rating;

  /// Remote dish photo. Empty when the vendor never uploaded one — a real and
  /// common case, so the UI falls back rather than treating it as a failure.
  final String imageUrl;

  /// Variant and add-on groups (migration 0048). Empty for a plain dish, which
  /// is most of them — a plain dish is added straight to the cart, a
  /// [isCustomizable] one asks its questions first.
  final List<MenuOptionGroup> optionGroups;

  bool get isCustomizable => optionGroups.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'price': price,
        'is_veg': isVeg,
        'is_bestseller': isBestseller,
        'rating': rating,
        'image_url': imageUrl,
      };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num?)?.toInt() ?? 0,
        isVeg: json['is_veg'] as bool? ?? true,
        isBestseller: json['is_bestseller'] as bool? ?? false,
        rating: (json['rating'] as num?)?.toDouble(),
        imageUrl: json['image_url'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MenuItem && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
