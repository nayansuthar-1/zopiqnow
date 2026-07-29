import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The road, cut in two at the point the rider has actually reached.
///
/// The half behind them is drawn muted and the half ahead in full colour, which
/// is the one thing a tracking map can say about progress without inventing
/// anything: both halves come from the road Ola measured and the position the
/// rider's own phone reported, and the cut is simply where those two meet.
@immutable
class RouteProgress {
  const RouteProgress({required this.travelled, required this.remaining});

  /// Kitchen → rider. May be a single point at the very start of the ride.
  final List<LatLng> travelled;

  /// Rider → door.
  final List<LatLng> remaining;
}

/// How far off the quoted road a rider may stray and still be understood as
/// being *on* it.
///
/// A rider who has taken a different street entirely has not "made progress
/// along this route" — there is no honest point on it to cut at, and snapping
/// them to the nearest bit of a road they are not on would draw a confident
/// line through a journey nobody took. Past this, [splitRoute] gives up and the
/// caller draws the whole route as still ahead, which is the truth: we know the
/// road we quoted and we know where the rider is, and right now those disagree.
const double _corridorMetres = 250;

/// Splits [road] at the point on it nearest to [at], or null when [at] is off
/// the route by more than [_corridorMetres] — or when there is no route to
/// speak of.
///
/// Nearest-point-on-polyline, in metres rather than degrees: a degree of
/// longitude is a different distance from a degree of latitude everywhere
/// except the equator, so comparing raw coordinate deltas would bias every
/// projection east-west. One cosine at the rider's latitude fixes that, and
/// over a city the flat-earth approximation it leaves is worth a fraction of a
/// percent — far below the accuracy of the GPS fix being projected.
RouteProgress? splitRoute(List<LatLng> road, LatLng at) {
  if (road.length < 2) return null;

  const double metresPerLat = 111320;
  final double metresPerLng =
      metresPerLat * math.cos(at.latitude * math.pi / 180);

  double bestSquared = double.infinity;
  int bestIndex = 0;
  LatLng bestPoint = road.first;

  for (int i = 0; i < road.length - 1; i++) {
    final LatLng a = road[i];
    final LatLng b = road[i + 1];

    // The segment, and the rider, as metres from `a`.
    final double bx = (b.longitude - a.longitude) * metresPerLng;
    final double by = (b.latitude - a.latitude) * metresPerLat;
    final double px = (at.longitude - a.longitude) * metresPerLng;
    final double py = (at.latitude - a.latitude) * metresPerLat;

    // How far along the segment the foot of the perpendicular falls, clamped
    // so a rider past either end projects onto that end rather than onto an
    // imagined continuation of the segment.
    final double lengthSquared = bx * bx + by * by;
    final double t = lengthSquared == 0
        ? 0
        : ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);

    final double dx = px - bx * t;
    final double dy = py - by * t;
    final double squared = dx * dx + dy * dy;

    if (squared >= bestSquared) continue;

    bestSquared = squared;
    bestIndex = i;
    bestPoint = LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  if (math.sqrt(bestSquared) > _corridorMetres) return null;

  // The cut point belongs to both halves, so the two lines meet under the
  // rider instead of leaving a gap the width of one segment.
  return RouteProgress(
    travelled: <LatLng>[...road.sublist(0, bestIndex + 1), bestPoint],
    remaining: <LatLng>[bestPoint, ...road.sublist(bestIndex + 1)],
  );
}
