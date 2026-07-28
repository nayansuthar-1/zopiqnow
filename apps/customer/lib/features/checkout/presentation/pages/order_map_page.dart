import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_map/zopiq_map.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_map_pins.dart';

/// The tracking map, full screen: pan, zoom, rotate, and the satellite layer.
///
/// The card on the order screen is a glance — gestures off, because a map that
/// claims drags inside a scrolling page steals the scroll. This is where the
/// map becomes a map. Reached by tapping that card.
class OrderMapPage extends ConsumerWidget {
  const OrderMapPage({required this.route, required this.rider, super.key});

  final DeliveryRoute route;
  final OrderRider? rider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? key = rider?.carrierKey;
    final RiderPosition? position = key == null
        ? null
        : ref.watch(riderPositionProvider(key)).valueOrNull;

    final RiderPosition? live =
        position != null && !position.isStale(DateTime.now()) ? position : null;

    return Scaffold(
      appBar: AppBar(title: Text(route.restaurantName)),
      body: ZopiqMapView(
        encodedPolyline: route.encodedPath,
        pins: orderMapPins(route: route, live: live),
        // The customer's own position is not what this screen is about, and
        // asking for it would raise a location prompt with nothing behind it.
        showMyLocation: false,
      ),
    );
  }
}
