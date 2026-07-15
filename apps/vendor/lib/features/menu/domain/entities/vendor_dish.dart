import 'package:flutter/foundation.dart';

/// A dish on the vendor's own menu.
///
/// Not the customer's `MenuItem`. The customer sees a dish to order — a price, a
/// photo, a rating it earned. The vendor sees a dish to *manage*: the same name
/// and price, plus the one thing the customer never sees, which is whether it is
/// available at all. `rating` is not here because a kitchen does not set its own
/// rating, and `imageUrl` is not here because there is no way to change one yet —
/// photo upload needs a CDN this project does not have (PM_CHECKLIST §6).
@immutable
class VendorDish {
  const VendorDish({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.isVeg,
    required this.category,
    required this.isAvailable,
  });

  /// A dish being created, before the database has given it an id. `saveDish`
  /// treats an empty id as "insert", a present one as "update".
  const VendorDish.draft({
    this.name = '',
    this.description = '',
    this.price = 0,
    this.isVeg = true,
    this.category = '',
  }) : id = '',
       isAvailable = true;

  final String id;
  final String name;
  final String description;

  /// Price in whole rupees. The check constraint refuses anything <= 0.
  final int price;
  final bool isVeg;

  /// The menu section this dish sits under — "Recommended", "Biryanis". Free
  /// text the vendor types, deliberately: the sections are their merchandising,
  /// not a fixed taxonomy we impose.
  final String category;

  /// Whether a customer can order it right now. The daily driver of this whole
  /// screen: a dish sells out, the kitchen flips this, and it vanishes from the
  /// customer menu without anyone touching the price or deleting anything.
  final bool isAvailable;

  bool get isNew => id.isEmpty;

  VendorDish copyWith({
    String? name,
    String? description,
    int? price,
    bool? isVeg,
    String? category,
    bool? isAvailable,
  }) => VendorDish(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    price: price ?? this.price,
    isVeg: isVeg ?? this.isVeg,
    category: category ?? this.category,
    isAvailable: isAvailable ?? this.isAvailable,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is VendorDish && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// One named section of the menu, in the vendor's own order.
///
/// The screen renders sections; Postgres stores a flat list with a rank per row.
/// The grouping happens in the data layer, the same way the customer's menu does
/// it, so no widget above has to understand `category_rank`.
@immutable
class VendorMenuSection {
  const VendorMenuSection({required this.title, required this.dishes});

  final String title;
  final List<VendorDish> dishes;
}
