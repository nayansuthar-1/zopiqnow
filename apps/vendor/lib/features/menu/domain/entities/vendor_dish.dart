import 'package:flutter/foundation.dart';

/// A dish on the vendor's own menu.
///
/// Not the customer's `MenuItem`. The customer sees a dish to order — a price, a
/// photo, a rating it earned. The vendor sees a dish to *manage*: the same name
/// and price, plus the one thing the customer never sees, which is whether it is
/// available at all. `rating` is not here because a kitchen does not set its own
/// rating. `imageUrl` *is* here now — photo upload landed with Cloudinary
/// (PM §6's CDN) — and it holds the delivery URL, never the image itself.
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
    this.isBestseller = false,
    this.imageUrl = '',
    this.originalPrice,
    this.unavailableReason = '',
    this.prepMinutes,
    this.serveFromMinutes,
    this.serveToMinutes,
  });

  /// A dish being created, before the database has given it an id. `saveDish`
  /// treats an empty id as "insert", a present one as "update".
  const VendorDish.draft({
    this.name = '',
    this.description = '',
    this.price = 0,
    this.isVeg = true,
    this.category = '',
    this.imageUrl = '',
  }) : id = '',
       isAvailable = true,
       isBestseller = false,
       originalPrice = null,
       unavailableReason = '',
       prepMinutes = null,
       serveFromMinutes = null,
       serveToMinutes = null;

  final String id;
  final String name;
  final String description;

  /// The dish photo's Cloudinary URL, or '' when there is none — the same empty
  /// string the customer menu reads as "no photo, draw the fallback".
  final String imageUrl;

  /// Price in whole rupees. The check constraint refuses anything <= 0.
  final int price;

  /// A higher, struck-through number shown beside [price]. Null when there is
  /// none, which is most dishes.
  ///
  /// **Display only.** `place_order` prices every line off [price] and has no
  /// idea this column exists (migration 0068 says so on the line that does the
  /// arithmetic). Nothing here computes it from [price] either — the vendor
  /// types it, because a "was" price nobody ever charged is a misleading price
  /// claim and the number has to be theirs.
  final int? originalPrice;

  final bool isVeg;

  /// The menu section this dish sits under — "Recommended", "Biryanis". Free
  /// text the vendor types, deliberately: the sections are their merchandising,
  /// not a fixed taxonomy we impose.
  final String category;

  /// Whether a customer can order it right now. The daily driver of this whole
  /// screen: a dish sells out, the kitchen flips this, and it vanishes from the
  /// customer menu without anyone touching the price or deleting anything.
  final bool isAvailable;

  /// Why it is off — "Paneer is over", "Tandoor is down". Kitchen-facing only:
  /// an unavailable dish is already invisible to customers, so this is the note
  /// the *next* shift reads, not an apology to a diner. '' when unstated.
  final String unavailableReason;

  /// Whether the kitchen has flagged this as a bestseller. Shown to customers as
  /// a badge (the `is_bestseller` column has existed since 0002 and the customer
  /// menu already renders it) — this is the vendor finally getting to set it.
  final bool isBestseller;

  /// How long this dish takes to cook, in minutes. Null when the kitchen has not
  /// said — most dishes — and the prep-time sheet falls back to its own presets.
  final int? prepMinutes;

  /// The daily window this dish is served in, as minutes since midnight IST.
  /// Both null (the common case) means all day. A [serveToMinutes] *earlier*
  /// than [serveFromMinutes] crosses midnight, exactly as a restaurant's own
  /// hours have since migration 0036.
  final int? serveFromMinutes;
  final int? serveToMinutes;

  bool get isNew => id.isEmpty;

  /// Whether this dish is sold only during part of the day.
  bool get hasServingWindow =>
      serveFromMinutes != null && serveToMinutes != null;

  /// True when a serving window runs past midnight — worth saying out loud in
  /// the UI, because "22:00 – 02:00" on one row reads like a typo until it is.
  bool get windowCrossesMidnight =>
      hasServingWindow && serveToMinutes! < serveFromMinutes!;

  VendorDish copyWith({
    String? name,
    String? description,
    int? price,
    bool? isVeg,
    String? category,
    bool? isAvailable,
    bool? isBestseller,
    String? imageUrl,
    String? unavailableReason,
    // Nullable fields need a way to be cleared, and `null` already means "leave
    // it alone" in a copyWith. So each takes an explicit `clear` flag rather
    // than a sentinel value — the vendor removing a serving window is a real
    // edit, not an absent one.
    int? originalPrice,
    bool clearOriginalPrice = false,
    int? prepMinutes,
    bool clearPrepMinutes = false,
    int? serveFromMinutes,
    int? serveToMinutes,
    bool clearServingWindow = false,
  }) => VendorDish(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    price: price ?? this.price,
    isVeg: isVeg ?? this.isVeg,
    category: category ?? this.category,
    isAvailable: isAvailable ?? this.isAvailable,
    isBestseller: isBestseller ?? this.isBestseller,
    imageUrl: imageUrl ?? this.imageUrl,
    unavailableReason: unavailableReason ?? this.unavailableReason,
    originalPrice: clearOriginalPrice
        ? null
        : (originalPrice ?? this.originalPrice),
    prepMinutes: clearPrepMinutes ? null : (prepMinutes ?? this.prepMinutes),
    serveFromMinutes: clearServingWindow
        ? null
        : (serveFromMinutes ?? this.serveFromMinutes),
    serveToMinutes: clearServingWindow
        ? null
        : (serveToMinutes ?? this.serveToMinutes),
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
  const VendorMenuSection({
    required this.title,
    required this.dishes,
    this.isAvailable = true,
  });

  final String title;
  final List<VendorDish> dishes;

  /// Whether the whole section is on the customer menu. A section switched off
  /// hides all its dishes at once without touching each dish's own sold-out
  /// state — the `category_available` column (migration 0016), which every row
  /// of the section shares.
  final bool isAvailable;
}
