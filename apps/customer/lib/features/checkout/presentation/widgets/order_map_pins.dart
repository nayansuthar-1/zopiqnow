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
}) {
  final GeoPoint? destination = route.destination;
  final GeoPoint? restaurant = route.restaurant;

  return <ZopiqMapPin>[
    if (restaurant != null)
      ZopiqMapPin(
        id: 'restaurant',
        lat: restaurant.lat,
        lng: restaurant.lng,
        color: ZopiqMapPin.colourPickup,
        title: route.restaurantName,
      ),
    if (destination != null)
      ZopiqMapPin(
        id: 'destination',
        lat: destination.lat,
        lng: destination.lng,
        color: ZopiqMapPin.colourDrop,
        title: route.deliverTo.isEmpty ? 'Delivery address' : route.deliverTo,
      ),
    if (live != null)
      ZopiqMapPin(
        id: 'rider',
        lat: live.point.lat,
        lng: live.point.lng,
        color: ZopiqMapPin.colourRider,
        // A vehicle, not an address — so a disc, and so it keeps its identity
        // across fixes and is animated between them rather than redrawn.
        kind: ZopiqPinKind.rider,
        title: 'Your delivery partner',
      ),
  ];
}
