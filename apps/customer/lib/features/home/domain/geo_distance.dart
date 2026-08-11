import 'dart:math' as math;

/// Great-circle distance between two points, in kilometres.
///
/// A deliberate port of the database's `delivery_distance_km` (migration 0043),
/// down to the `least(1, …)` guard and the two-decimal rounding, so a customer
/// reading "1.2 km" on a restaurant card and a rider being paid for 1.2 km are
/// reading the same number rather than two implementations of the same idea.
///
/// **Null in, null out**, which is the other thing that function is careful
/// about: a missing coordinate is *unknown* distance, not zero distance. Every
/// caller has to decide what to render for "unknown", and none of them may
/// render it as 0.0 — that was the bug this file exists to fix.
///
/// Straight-line, not road. The road figure needs Ola and a round trip per
/// restaurant; a feed of twenty cards cannot pay for that, and "as the crow
/// flies" is the right precision for deciding whether somewhere is nearby.
double? distanceKmBetween({
  required double? fromLat,
  required double? fromLng,
  required double? toLat,
  required double? toLng,
}) {
  if (fromLat == null || fromLng == null || toLat == null || toLng == null) {
    return null;
  }

  const double earthRadiusKm = 6371;

  final double dLat = _radians(toLat - fromLat);
  final double dLng = _radians(toLng - fromLng);

  final double h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(fromLat)) *
          math.cos(_radians(toLat)) *
          math.pow(math.sin(dLng / 2), 2);

  // Floating point can push this a hair past 1.0 for two points that are the
  // same place, and `asin` of that is NaN rather than zero.
  final double angle = 2 * math.asin(math.min(1, math.sqrt(h)));

  return double.parse((earthRadiusKm * angle).toStringAsFixed(2));
}

double _radians(double degrees) => degrees * math.pi / 180;
