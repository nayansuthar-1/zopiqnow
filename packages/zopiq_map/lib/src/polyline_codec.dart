import 'package:maplibre_gl/maplibre_gl.dart';

/// Decodes the encoded-polyline format, precision 5 — what Ola's Directions API
/// returns as `overview_polyline` and what migration 0046 stores verbatim.
///
/// Ola measures the road and MapLibre draws it. The format is the interchange
/// between the two, and it is not Ola's invention: it is the same scheme Google
/// published, which is why a route stored once can be rendered by anything.
///
/// Tolerant by design. A truncated or malformed string yields the points it
/// managed to read and stops — a tracking screen that throws because a third
/// party sent one bad character is a worse outcome than a slightly short line.
List<LatLng> decodePolyline(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const <LatLng>[];

  final List<LatLng> points = <LatLng>[];
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

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }

  return List<LatLng>.unmodifiable(points);
}

/// Where [_readValue] stopped. A library-level cursor rather than a record
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

/// The smallest rectangle containing every point given.
///
/// The camera needs one of these to frame a route. A single point, or two at
/// the same address, would give a zero-area box that `newLatLngBounds` cannot
/// resolve to a zoom level, so it is widened by about a hundred metres — enough
/// to be a valid box, small enough that the camera still lands where it was
/// asked to.
LatLngBounds boundsOf(Iterable<LatLng> points) {
  double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
  for (final LatLng p in points) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }

  const double minSpan = 0.001; // ~110 m
  if (maxLat - minLat < minSpan) {
    final double mid = (maxLat + minLat) / 2;
    minLat = mid - minSpan / 2;
    maxLat = mid + minSpan / 2;
  }
  if (maxLng - minLng < minSpan) {
    final double mid = (maxLng + minLng) / 2;
    minLng = mid - minSpan / 2;
    maxLng = mid + minSpan / 2;
  }

  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}
