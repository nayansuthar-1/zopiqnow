import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_map/zopiq_map.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_map_page.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_map_pins.dart';

/// The rider, on the road, moving — on a real map.
///
/// **What this has been through.** It began as a hand-painted picture: the road
/// decoded from Ola's polyline, drawn over a faint grid, with no streets behind
/// it. Then it became a finished PNG from Ola's static API, which put real
/// streets behind the road but could not pan, zoom, or offer a layer. It is now
/// Google's map with Ola's road on it — the two agree on the encoded-polyline
/// format, which is the only reason a route measured by one can be drawn over
/// the other.
///
/// **This one is still a glance, deliberately.** It sits in a scrolling page,
/// and a map that claims drags inside a scrollable steals the scroll. So
/// gestures are off here and a tap opens [OrderMapPage], which is the same map
/// with everything switched on. That is also why the layer switcher is not on
/// this one: a control that small, over a map that small, is mostly map you
/// cannot see.
///
/// **What it never does.** It does not draw a rider before there is one, and it
/// does not keep drawing one whose position has gone stale (see
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
  /// and the label under the pin — and its absence is what makes this a map of
  /// the ride ahead rather than of a ride in progress.
  final OrderRider? rider;

  static const double _height = 220;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!route.isMappable) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final String? key = rider?.carrierKey;

    final RiderPosition? position = key == null
        ? null
        : ref.watch(riderPositionProvider(key)).valueOrNull;

    // A fix older than two minutes is drawn as nothing rather than as a rider.
    final RiderPosition? live =
        position != null && !position.isStale(DateTime.now()) ? position : null;

    return ClipRRect(
      borderRadius: ZopiqRadii.rMd,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ZopiqMapView(
              encodedPolyline: route.encodedPath,
              liveEncodedPolyline: route.livePath,
              pins: orderMapPins(route: route, live: live),
              // A glance, not a map you drive: gestures off so the page can
              // still be scrolled, and no layer switcher because a control that
              // small over a map this small is mostly map you cannot see.
              interactive: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      OrderMapPage(route: route, rider: rider),
                ),
              ),
            ),
            if (live == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Caption(
                  // Said plainly rather than hidden. The customer can see the
                  // pin is missing, and not saying why is worse than saying it.
                  text: position != null
                      ? 'Live location paused — reconnecting'
                      : rider == null
                      ? 'The route your order will take'
                      : 'Waiting for ${rider!.name}\'s location',
                  color: zc.textMuted,
                ),
              ),
          ],
        ),
      ),
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
