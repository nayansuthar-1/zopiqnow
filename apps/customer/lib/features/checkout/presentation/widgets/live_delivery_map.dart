import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/map_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';

/// The rider, on the road, moving — on an actual map.
///
/// **What changed, and why.** This used to be a hand-painted picture: the real
/// road decoded from Ola's polyline, drawn over a faint grid, with no streets
/// and no landmarks behind it. The reasoning was sound at the time — Ola's key
/// is referer-restricted and belongs in Vault, not in an APK, and a tile
/// renderer is a dependency the version freeze does not allow.
///
/// Neither of those had to mean *no map*. The key stays on the server and the
/// `ola-static` Edge Function returns a finished picture with our road and our
/// pins already on it, which needs no key on the device and no new dependency.
/// So the grid is gone and there are streets behind the route now.
///
/// **Everything is drawn by one renderer.** The road, both ends and the rider
/// are all Ola's marks in Ola's projection. There is no overlay, so there is no
/// second coordinate system that can drift a few pixels out of step and put the
/// rider in a field beside the road.
///
/// **What it still never does.** It does not draw a rider before there is one,
/// and it does not keep drawing one whose position has gone stale (see
/// [RiderPosition.isStale]). A dot that keeps gliding after the rider's phone
/// died is the single most convincing lie a tracking screen can tell.
class LiveDeliveryMap extends ConsumerWidget {
  const LiveDeliveryMap({
    required this.route,
    required this.rider,
    super.key,
  });

  final DeliveryRoute route;

  /// Who is carrying it, or null while nobody is. Supplies the subscription key
  /// and the label under the dot — and its absence is what makes this a map of
  /// the ride ahead rather than of a ride in progress.
  final OrderRider? rider;

  static const double _height = 220;

  /// The kitchen end, in near-black: a fixed point, and deliberately not the
  /// brand colour, which the road and the destination already use.
  static const Color _pinRestaurant = Color(0xFF282C3F);

  /// The rider, in the one colour on this map that is neither the road nor
  /// either end of it.
  static const Color _pinRider = Color(0xFF1D6FE0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!route.isMappable) return const SizedBox.shrink();

    final String? token = ref.watch(mapAuthTokenProvider);
    if (token == null) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final String? key = rider?.carrierKey;

    final RiderPosition? position = key == null
        ? null
        : ref.watch(riderPositionProvider(key)).valueOrNull;

    // A fix older than two minutes is drawn as nothing rather than as a rider.
    final RiderPosition? live =
        position != null && !position.isStale(DateTime.now()) ? position : null;

    final GeoPoint destination = route.destination!;

    return ClipRRect(
      borderRadius: ZopiqRadii.rMd,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: ZopiqStaticMap(
          endpoint: ref.watch(mapEndpointProvider),
          authToken: token,
          encodedPolyline: route.encodedPath,
          markers: <ZopiqMapMarker>[
            if (route.restaurant != null)
              ZopiqMapMarker(
                lat: route.restaurant!.lat,
                lng: route.restaurant!.lng,
                color: _pinRestaurant,
              ),
            ZopiqMapMarker(
              lat: destination.lat,
              lng: destination.lng,
              color: ZopiqPalette.primary,
            ),
            // Last, so it is the pin drawn on top where the rider is close
            // enough to the door for the two to overlap.
            if (live != null)
              ZopiqMapMarker(
                lat: live.point.lat,
                lng: live.point.lng,
                color: _pinRider,
              ),
          ],
          caption: _captionFor(position: position, live: live, zc: zc),
        ),
      ),
    );
  }

  /// A line along the bottom, for the times there is no rider on the map. Said
  /// plainly rather than hidden — the customer can see the pin is missing, and
  /// not saying why is worse than saying this.
  Widget? _captionFor({
    required RiderPosition? position,
    required RiderPosition? live,
    required ZopiqColors zc,
  }) {
    if (live != null) return null;
    return _Caption(
      text: position != null
          ? 'Live location paused — reconnecting'
          : rider == null
          ? 'The route your order will take'
          : 'Waiting for ${rider!.name}\'s location',
      color: zc.textMuted,
    );
  }
}

/// A one-line strip along the bottom of the map, for the times there is no pin.
class _Caption extends StatelessWidget {
  const _Caption({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.xs,
      ),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}
