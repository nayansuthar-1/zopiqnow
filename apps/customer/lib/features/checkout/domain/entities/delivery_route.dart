import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A point on the earth, and the smallest thing this file needs.
///
/// Deliberately not `LatLng` from a mapping package — there is no mapping
/// package. The live map is drawn by a `CustomPainter` from these and an encoded
/// path, which is what lets the tracking screen show a road-shaped route without
/// a tile server, an API key in the APK, or a new dependency.
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
    required this.path,
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
      path: decodePolyline(json['route_polyline'] as String?),
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

  /// The road, as Ola drew it, decoded. Empty when the lookup has not come back
  /// yet or never will — the map then joins the two pins with a straight line
  /// and is honest about being a sketch.
  final List<GeoPoint> path;

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

/// Decodes Google's encoded-polyline format, precision 5 — what Ola's Directions
/// API returns as `overview_polyline` and what 0057 stores verbatim.
///
/// Decoded on the device rather than in Postgres for the reason 0057 gives: it
/// is a few hundred bytes as a string and a few thousand as a coordinate array,
/// and the phone drawing it has to walk the points anyway.
///
/// Tolerant by design. A truncated or malformed string yields the points it
/// managed to read and stops — a tracking screen that throws because a third
/// party sent one bad character is a worse outcome than a slightly short line.
List<GeoPoint> decodePolyline(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const <GeoPoint>[];

  final List<GeoPoint> points = <GeoPoint>[];
  int index = 0;
  int lat = 0;
  int lng = 0;

  while (index < encoded.length) {
    final int? dLat = _readValue(encoded, index);
    if (dLat == null) break;
    index = _cursor;
    lat += dLat;

    final int? dLng = _readValue(encoded, index);
    if (dLng == null) break;
    index = _cursor;
    lng += dLng;

    points.add(GeoPoint(lat / 1e5, lng / 1e5));
  }

  return List<GeoPoint>.unmodifiable(points);
}

/// Where [_readValue] stopped. A module-level cursor rather than a record
/// return, so the hot loop above allocates nothing per point.
int _cursor = 0;

/// One zig-zag-encoded varint, or null if the string ran out mid-value.
int? _readValue(String encoded, int start) {
  int index = start;
  int shift = 0;
  int result = 0;
  int byte;

  do {
    if (index >= encoded.length) return null;
    byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20);

  _cursor = index;
  return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
}

/// The rectangle containing every point given, with a little air around it.
///
/// Used to fit the map to its content. The padding is a *fraction* rather than
/// pixels because this runs in degrees, before anything has been projected —
/// and a zero-size box (one point, or two at the same address) is widened to
/// something drawable rather than dividing by zero later.
({double minLat, double maxLat, double minLng, double maxLng}) boundsOf(
  Iterable<GeoPoint> points,
) {
  double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
  for (final GeoPoint p in points) {
    minLat = math.min(minLat, p.lat);
    maxLat = math.max(maxLat, p.lat);
    minLng = math.min(minLng, p.lng);
    maxLng = math.max(maxLng, p.lng);
  }

  // Nothing was given, or everything was the same point.
  if (minLat > maxLat) return (minLat: 0, maxLat: 0, minLng: 0, maxLng: 0);

  const double minSpan = 0.002; // ~200 m, so a short hop still has a map
  final double latPad = math.max((maxLat - minLat) * 0.15, minSpan);
  final double lngPad = math.max((maxLng - minLng) * 0.15, minSpan);

  return (
    minLat: minLat - latPad,
    maxLat: maxLat + latPad,
    minLng: minLng - lngPad,
    maxLng: maxLng + lngPad,
  );
}
