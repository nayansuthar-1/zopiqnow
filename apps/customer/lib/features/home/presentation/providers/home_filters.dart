import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// Ordering applied to the Home restaurant list.
enum HomeSort {
  relevance('Relevance'),
  rating('Rating: high to low'),
  deliveryTime('Delivery time'),
  costLowToHigh('Cost: low to high'),
  costHighToLow('Cost: high to low');

  const HomeSort(this.label);

  final String label;
}

/// The chip-row selection: a set of toggles plus one sort order.
///
/// Owns [apply] so the filtering rules live next to the state they read, and
/// can be unit-tested without a widget tree.
@immutable
class HomeFilters {
  const HomeFilters({
    this.fastDelivery = false,
    this.ratingAbove4 = false,
    this.pureVeg = false,
    this.greatOffers = false,
    this.sort = HomeSort.relevance,
  });

  final bool fastDelivery;
  final bool ratingAbove4;
  final bool pureVeg;
  final bool greatOffers;
  final HomeSort sort;

  /// A restaurant arriving within this many minutes counts as "fast delivery".
  ///
  /// Forty, raised from thirty when this started measuring the arrival instead
  /// of the kitchen's share of it. Thirty was calibrated against prep times
  /// alone; adding the ride pushed every kitchen in Sadri past it and the chip
  /// returned an empty feed. Forty draws the line where it was actually meant
  /// to go — a normal kitchen close by passes, a slow one or a far one does not.
  static const int _fastDeliveryMinutes = 40;

  bool get hasActiveToggle =>
      fastDelivery || ratingAbove4 || pureVeg || greatOffers;

  HomeFilters copyWith({
    bool? fastDelivery,
    bool? ratingAbove4,
    bool? pureVeg,
    bool? greatOffers,
    HomeSort? sort,
  }) {
    return HomeFilters(
      fastDelivery: fastDelivery ?? this.fastDelivery,
      ratingAbove4: ratingAbove4 ?? this.ratingAbove4,
      pureVeg: pureVeg ?? this.pureVeg,
      greatOffers: greatOffers ?? this.greatOffers,
      sort: sort ?? this.sort,
    );
  }

  /// Filters then sorts [restaurants]. Never mutates the input list.
  List<Restaurant> apply(List<Restaurant> restaurants) {
    final List<Restaurant> result = restaurants.where((Restaurant r) {
      // The arrival, not the kitchen's share of it. Filtering on the latter kept
      // a four-kilometre kitchen with a quick cook under "fast delivery" while
      // its own card said forty minutes.
      if (fastDelivery && r.deliveryEta.minutes > _fastDeliveryMinutes) {
        return false;
      }
      if (ratingAbove4 && r.rating < 4.0) return false;
      if (pureVeg && !r.isVeg) return false;
      if (greatOffers && r.promoText == null) return false;
      return true;
    }).toList();

    switch (sort) {
      case HomeSort.relevance:
        break; // Server order is the relevance order.
      case HomeSort.rating:
        result.sort(
          (Restaurant a, Restaurant b) => b.rating.compareTo(a.rating),
        );
      case HomeSort.deliveryTime:
        result.sort(
          (Restaurant a, Restaurant b) =>
              a.deliveryEta.minutes.compareTo(b.deliveryEta.minutes),
        );
      case HomeSort.costLowToHigh:
        result.sort(
          (Restaurant a, Restaurant b) =>
              a.priceForTwo.compareTo(b.priceForTwo),
        );
      case HomeSort.costHighToLow:
        result.sort(
          (Restaurant a, Restaurant b) =>
              b.priceForTwo.compareTo(a.priceForTwo),
        );
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HomeFilters &&
          other.fastDelivery == fastDelivery &&
          other.ratingAbove4 == ratingAbove4 &&
          other.pureVeg == pureVeg &&
          other.greatOffers == greatOffers &&
          other.sort == sort);

  @override
  int get hashCode =>
      Object.hash(fastDelivery, ratingAbove4, pureVeg, greatOffers, sort);
}
