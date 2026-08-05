import 'package:flutter/foundation.dart';

/// A point on the earth, and the smallest thing this file needs.
///
/// Deliberately not `LatLng` from a mapping package — there is no mapping
/// package.
///
/// This used to say the map "arrives as a finished picture from the
/// `ola-static` Edge Function". It has not since B3: `zopiq_map` paints the map
/// on the device and makes no network request at all, which is why there is
/// still no tile renderer, no key in the APK and no new dependency. The
/// function outlived its caller, and staying deployed is how it turned into
/// audit API-002 — it is retired now.
///
/// These are the points the painter is given.
@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// Both ends of the ride, the road between them, and when the food is due.
///
/// Comes from `order_route` (migration 0057) — one call, scoped by Postgres to
/// an order that belongs to the caller. The rider's *position* is deliberately
/// not in here: it arrives over Realtime, because it changes every few seconds
/// and everything else on this object does not.
@immutable
class DeliveryRoute {
  const DeliveryRoute({
    required this.restaurantName,
    required this.restaurant,
    required this.deliverTo,
    required this.destination,
    required this.encodedPath,
    required this.livePath,
    required this.routeKm,
    required this.etaAt,
    required this.etaReason,
  });

  factory DeliveryRoute.fromJson(Map<String, dynamic> json) {
    final double? rLat = (json['restaurant_lat'] as num?)?.toDouble();
    final double? rLng = (json['restaurant_lng'] as num?)?.toDouble();
    final double? dLat = (json['deliver_lat'] as num?)?.toDouble();
    final double? dLng = (json['deliver_lng'] as num?)?.toDouble();

    return DeliveryRoute(
      restaurantName: json['restaurant_name'] as String? ?? 'Restaurant',
      restaurant: rLat == null || rLng == null ? null : GeoPoint(rLat, rLng),
      deliverTo: json['deliver_to'] as String? ?? '',
      destination: dLat == null || dLng == null ? null : GeoPoint(dLat, dLng),
      encodedPath: json['route_polyline'] as String?,
      livePath: json['live_polyline'] as String?,
      routeKm: (json['route_km'] as num?)?.toDouble(),
      etaAt: DateTime.parse(json['eta_at'] as String).toLocal(),
      etaReason: json['eta_reason'] as String?,
    );
  }

  final String restaurantName;

  /// Null for a kitchen with no coordinates on file (0042). The map then has one
  /// pin instead of two rather than drawing the restaurant at the equator.
  final GeoPoint? restaurant;

  final String deliverTo;
  final GeoPoint? destination;

  /// The same road, still encoded, exactly as Ola returned it and 0057 stored
  /// it. Passed through untouched: the renderer that draws it decodes the same
  /// format Ola encoded, so decoding it here to send it somewhere else would be
  /// a round trip that can only lose precision.
  ///
  /// Null when the route lookup has not come back yet or never will. The map is
  /// then framed on the two pins with no road between them, which is honest —
  /// we do not know the road yet.
  final String? encodedPath;

  /// The road from where the rider actually was to the door, fetched when they
  /// were found to be off [encodedPath] by more than 250 m (0103) — a diversion,
  /// a one-way, a closure, or simply a better road than the one quoted an hour
  /// ago.
  ///
  /// Null in the ordinary case, which is a rider following the route. Null too
  /// when the last one is more than fifteen minutes old: the server withholds a
  /// stale live road rather than letting the map draw a street the rider left
  /// long ago.
  final String? livePath;

  final double? routeKm;

  /// When the food is due, as an absolute instant. Recomputed server-side from
  /// the rider's position (0057) and — the rule B3 set — only ever moved later
  /// together with [etaReason].
  final DateTime etaAt;

  /// Why the arrival time slipped, in the words the platform recorded. Null on
  /// an order running to time, which is what the card checks: the line exists
  /// only when there is something to admit.
  final String? etaReason;

  /// Whether there is enough here to draw anything at all.
  bool get isMappable => destination != null;
}

/// Where the rider is, right now.
///
/// One row out of `rider_locations`, delivered over Realtime and readable only
/// by the customer whose food is on that bike, for the minutes it is on it
/// (0057). There is no history behind it — the platform keeps the latest fix
/// and nothing else.
@immutable
class RiderPosition {
  const RiderPosition({
    required this.point,
    required this.heading,
    required this.updatedAt,
  });

  factory RiderPosition.fromJson(Map<String, dynamic> json) => RiderPosition(
    point: GeoPoint(
      (json['lat'] as num).toDouble(),
      (json['lng'] as num).toDouble(),
    ),
    heading: (json['heading'] as num?)?.toDouble(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final GeoPoint point;

  /// Degrees clockwise from north, and null when the phone would not say — a
  /// stationary device reports no bearing. The marker is then a plain dot
  /// rather than an arrow pointing confidently at nothing.
  final double? heading;

  final DateTime updatedAt;

  /// A fix this old is not worth drawing as "live". The rider's phone reports
  /// every twenty seconds at the outside (0057), so two minutes of silence means
  /// a dead battery, a tunnel, or a killed app — and a dot that keeps sitting
  /// there is a lie the customer will believe.
  bool isStale(DateTime now) =>
      now.difference(updatedAt) > const Duration(minutes: 2);
}
