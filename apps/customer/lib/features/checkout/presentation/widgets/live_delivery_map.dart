import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_map/zopiq_map.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_ad.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_ad_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_map_page.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/corner_puck.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/explore_puck.dart';
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
///
/// **It has a second face** (0125). While a campaign is live, the corner carries
/// an Explore puck, and tapping it turns this slot over to the ad with a Map
/// puck to turn it back. The swap happens in place rather than pushing a screen,
/// because at this size the ad is the same glance the map was — a full screen of
/// somebody else's artwork is what tapping the *ad* is for.
class LiveDeliveryMap extends ConsumerStatefulWidget {
  const LiveDeliveryMap({
    required this.route,
    required this.rider,
    required this.orderId,
    super.key,
  });

  final DeliveryRoute route;

  /// Who is carrying it, or null while nobody is. Supplies the subscription key
  /// and the label under the pin — and its absence is what makes this a map of
  /// the ride ahead rather than of a ride in progress.
  final OrderRider? rider;

  final String orderId;

  @override
  ConsumerState<LiveDeliveryMap> createState() => _LiveDeliveryMapState();
}

class _LiveDeliveryMapState extends ConsumerState<LiveDeliveryMap> {
  /// The ad currently filling the slot, or null while the map does.
  ///
  /// Held as the ad rather than a bool so the face cannot outlive the campaign
  /// that put it there.
  OrderAd? _showing;

  static const double _height = 220;

  @override
  Widget build(BuildContext context) {
    final DeliveryRoute route = widget.route;
    final OrderRider? rider = widget.rider;
    if (!route.isMappable) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final String? key = rider?.carrierKey;

    final RiderPosition? position = key == null
        ? null
        : ref.watch(riderPositionProvider(key)).valueOrNull;

    // A fix older than two minutes is drawn as nothing rather than as a rider.
    final RiderPosition? live =
        position != null && !position.isStale(DateTime.now()) ? position : null;

    final OrderAd? ad = _showing;

    return ClipRRect(
      borderRadius: ZopiqRadii.rMd,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (ad != null)
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        OrderAdPage(ad: ad, orderId: widget.orderId),
                  ),
                ),
                child: ZopiqNetworkImage(
                  url: ad.imageUrl,
                  // Cover here and contain full screen, on purpose: this is a
                  // 220-high band cut out of a tall banner, and letterboxing it
                  // would show more grey than artwork.
                  fallback: ColoredBox(color: zc.divider),
                ),
              )
            else
              ZopiqMapView(
                encodedPolyline: route.encodedPath,
                liveEncodedPolyline: route.livePath,
                pins: orderMapPins(route: route, live: live),
                // A glance, not a map you drive: gestures off so the page can
                // still be scrolled, and no layer switcher because a control
                // that small over a map this small is mostly map you cannot see.
                interactive: false,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => OrderMapPage(
                      route: route,
                      rider: rider,
                      orderId: widget.orderId,
                    ),
                  ),
                ),
              ),

            if (ad == null && live == null)
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
                      : 'Waiting for ${rider.name}\'s location',
                  color: zc.textMuted,
                ),
              ),

            Positioned(
              right: ZopiqSpacing.sm,
              bottom: ZopiqSpacing.sm,
              child: ad == null
                  ? ExplorePuck(
                      orderId: widget.orderId,
                      onOpen: (OrderAd opened) =>
                          setState(() => _showing = opened),
                    )
                  : CornerPuck(
                      label: 'MAP',
                      icon: Icons.map_rounded,
                      onTap: () => setState(() => _showing = null),
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
