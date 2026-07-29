import 'package:zopiq_map/zopiq_map.dart';

import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';

/// The three pins an order's map can carry, built once and used by both the
/// glance on the order screen and the full-screen map behind it.
///
/// Shared so the two cannot disagree — a tap that opened a map with different
/// pins on it would read as a bug even though both were "correct".
///
/// The rider is last, so it is the marker on top where a rider close to the door
/// overlaps the destination.
List<ZopiqMapPin> orderMapPins({
  required DeliveryRoute route,
  required RiderPosition? live,
  DateTime? now,
}) {
  final GeoPoint? destination = route.destination;
  final GeoPoint? restaurant = route.restaurant;

  return <ZopiqMapPin>[
    if (restaurant != null)
      ZopiqMapPin(
        id: 'restaurant',
        lat: restaurant.lat,
        lng: restaurant.lng,
        kind: ZopiqPinKind.vendor,
        title: route.restaurantName,
      ),
    if (destination != null)
      ZopiqMapPin(
        id: 'destination',
        lat: destination.lat,
        lng: destination.lng,
        kind: ZopiqPinKind.customer,
        title: route.deliverTo.isEmpty ? 'Delivery address' : route.deliverTo,
      ),
    if (live != null)
      ZopiqMapPin(
        id: 'rider',
        lat: live.point.lat,
        lng: live.point.lng,
        // A vehicle, not an address — so a scooter on a disc, and so it keeps
        // its identity across fixes and is animated between them.
        kind: ZopiqPinKind.rider,
        title: 'Your delivery partner',
        // Which way they are actually pointing. Null on a stationary phone,
        // which draws a plain disc rather than a chevron aimed at a guess.
        heading: live.heading,
        // The one number the customer opened this screen for, put on the thing
        // they are already watching.
        label: etaLabel(route.etaAt, now ?? DateTime.now()),
      ),
  ];
}

/// "6 min", for the capsule above the rider.
///
/// Two words at the outside, because this is painted *into* the marker image: a
/// longer string is a wider bitmap sitting over the map it is meant to
/// annotate.
///
/// A promise that has already passed is not shown as a negative number and not
/// quietly dropped either. The rider is visibly still on the road, and "Due now"
/// is what that is — anything else would be the map arguing with itself.
String etaLabel(DateTime etaAt, DateTime now) {
  final int minutes = etaAt.difference(now).inMinutes;
  return minutes < 1 ? 'Due now' : '$minutes min';
}
