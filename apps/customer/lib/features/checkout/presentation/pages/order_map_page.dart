import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_map/zopiq_map.dart';
import 'package:zopiq_ui/zopiq_ui.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_ad.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_ad_page.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/explore_puck.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart'
    show formatClockTime;
import 'package:zopiqnow/features/checkout/presentation/widgets/order_map_pins.dart';

/// The tracking map, full screen: pan, zoom, rotate.
///
/// The card on the order screen is a glance — gestures off, because a map that
/// claims drags inside a scrolling page steals the scroll. This is where the
/// map becomes a map. Reached by tapping that card.
///
/// **Why the arrival bar is under the map rather than floating over it.** It is
/// the one thing on this screen that is always worth reading, and a panel
/// floating over a map is a panel covering the part of the route nearest the
/// door. Below the map it costs a strip of height once instead of hiding the
/// destination for the whole ride.
class OrderMapPage extends ConsumerWidget {
  const OrderMapPage({
    required this.route,
    required this.rider,
    required this.orderId,
    super.key,
  });

  final DeliveryRoute route;
  final OrderRider? rider;

  /// Carried for the ad puck alone — it is what keeps one order's view from
  /// being counted twice (0125).
  final String orderId;

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
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ZopiqMapView(
                  encodedPolyline: route.encodedPath,
                  liveEncodedPolyline: route.livePath,
                  pins: orderMapPins(route: route, live: live),
                  // The customer's own position is not what this screen is
                  // about, and asking for it would raise a location prompt with
                  // nothing behind it.
                  showMyLocation: false,
                  // Offered only while there is something to follow. The button
                  // starts on and the first drag turns it off — see ZopiqMapView.
                  followPinId: live == null ? null : 'rider',
                ),
                // Bottom-right, above the arrival bar. The left half of a map is
                // where the route usually runs and the top-right is where
                // ZopiqMapView puts its own controls.
                Positioned(
                  right: ZopiqSpacing.md,
                  bottom: ZopiqSpacing.md,
                  child: ExplorePuck(
                    orderId: orderId,
                    onOpen: (OrderAd ad) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            OrderAdPage(ad: ad, orderId: orderId),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _ArrivalBar(route: route, live: live),
        ],
      ),
    );
  }
}

/// When it gets here, how far it has to come, and — when there is one — the
/// reason the first of those moved.
class _ArrivalBar extends StatelessWidget {
  const _ArrivalBar({required this.route, required this.live});

  final DeliveryRoute route;
  final RiderPosition? live;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    etaLabel(route.etaAt, DateTime.now()),
                    style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: zc.primary,
                    ),
                  ),
                  const SizedBox(width: ZopiqSpacing.sm),
                  Expanded(
                    child: Padding(
                      // Sits on the big number's baseline rather than its box,
                      // so the two read as one line.
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        <String>[
                          'Arriving by ${formatClockTime(route.etaAt)}',
                          if (route.routeKm != null)
                            '${route.routeKm!.toStringAsFixed(1)} km',
                        ].join('  ·  '),
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
              // B3's rule, made visible here as well as on the order card: an
              // arrival time that moved later never does so silently.
              if (route.etaReason != null) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  route.etaReason!,
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
              // Said plainly rather than left to a missing pin. The customer
              // can already see there is no scooter; not saying why is worse
              // than saying it.
              if (live == null) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  'Waiting for your rider\'s location',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
