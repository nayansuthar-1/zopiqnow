import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/launcher.dart';
import 'package:zopiq_rider/core/map_providers.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';

/// Where this rider is, right now, for the map they are looking at.
///
/// `autoDispose`, and that is the whole point of it being a provider: the GPS
/// stream starts when the map opens and stops when it closes. The reporter that
/// feeds the customer's tracking screen is a separate thing with a separate
/// lifetime (it runs whenever the rider is carrying, map or no map) — this one
/// exists only to draw a dot.
///
/// Errors are swallowed to null. Airplane mode, a denied permission, a phone
/// with no fix yet: all of them mean "no dot", none of them mean "no map".
final AutoDisposeStreamProvider<Position?> riderSelfPositionProvider =
    StreamProvider.autoDispose<Position?>((Ref ref) async* {
      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        yield null;
        return;
      }
      yield* Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Thirty metres, the same filter the reporter uses. Below that is GPS
          // noise on a parked bike, and every fix through it is a new picture
          // fetched from the server.
          distanceFilter: 30,
        ),
      ).handleError((Object _) {});
    });

/// The job, on a map, inside the app.
///
/// **Why this exists.** Navigate used to fire a `geo:` intent and hand the rider
/// to whatever maps app the phone had. That answers "take me there" and loses
/// the job: the rider leaves Zopiqnow, and the address, the pay, the cash to
/// collect and the button they came back to press are all behind an app switch.
/// This keeps the map and the job on the same screen.
///
/// **What it is not.** It is not turn-by-turn navigation — there are no voice
/// prompts, no re-routing and no lane guidance, because none of that is a map
/// widget, it is a navigation SDK. So the handoff survives as a button: a rider
/// who wants a co-pilot presses "Open in Maps" and gets the one they already
/// trust, with their own traffic settings in it.
///
/// The picture itself comes from `ola-static` — see [ZopiqStaticMap] for why it
/// is a picture and not tiles.
class JobMapPage extends ConsumerWidget {
  const JobMapPage({required this.job, super.key});

  final Job job;

  /// The kitchen end, in near-black.
  static const Color _pinRestaurant = Color(0xFF282C3F);

  /// The rider's own position, in the one colour that is neither the road nor
  /// either end of it.
  static const Color _pinSelf = Color(0xFF1D6FE0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final String? token = ref.watch(mapAuthTokenProvider);
    final Position? self = ref.watch(riderSelfPositionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(job.isCarrying ? 'To the customer' : 'To the restaurant'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: token == null
                ? const SizedBox.shrink()
                : ZopiqStaticMap(
                    endpoint: ref.watch(mapEndpointProvider),
                    authToken: token,
                    encodedPolyline: job.routePolyline,
                    markers: _markers(self),
                  ),
          ),
          _Details(job: job, zc: zc),
        ],
      ),
    );
  }

  /// Both ends of the ride and the rider, in draw order — the target last, so it
  /// is the pin on top wherever two of them overlap.
  ///
  /// The end the rider is *not* heading for is still drawn. A rider carrying
  /// food wants to see where they picked it up as much as where it is going;
  /// dropping it would leave a lone pin with no sense of direction.
  List<ZopiqMapMarker> _markers(Position? self) {
    final bool carrying = job.isCarrying;
    return <ZopiqMapMarker>[
      if (self != null)
        ZopiqMapMarker(
          lat: self.latitude,
          lng: self.longitude,
          color: _pinSelf,
        ),
      if (job.restaurantLat != null && job.restaurantLng != null)
        ZopiqMapMarker(
          lat: job.restaurantLat!,
          lng: job.restaurantLng!,
          color: carrying ? _pinRestaurant : ZopiqPalette.primary,
        ),
      if (job.deliverLat != null && job.deliverLng != null)
        ZopiqMapMarker(
          lat: job.deliverLat!,
          lng: job.deliverLng!,
          color: carrying ? ZopiqPalette.primary : _pinRestaurant,
        ),
    ];
  }
}

/// Everything under the map: where this is going, how far, and the way out to a
/// real navigator.
class _Details extends ConsumerWidget {
  const _Details({required this.job, required this.zc});

  final Job job;
  final ZopiqColors zc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              job.targetLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (job.distanceKm != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xxs),
              Text(
                '${job.distanceKm!.toStringAsFixed(1)} km · ₹${job.riderPay}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: zc.textMuted),
              ),
            ],
            const SizedBox(height: ZopiqSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openExternal(context, ref),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZopiqRadii.rMd,
                  ),
                ),
                icon: RiderSvgIcon(
                  type: RiderSvgType.navigationPin,
                  size: 18,
                  color: zc.primary,
                ),
                label: Text(
                  'Open in Maps',
                  style: TextStyle(color: zc.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The escape hatch. A `geo:` URI rather than any vendor's https link, for the
  /// reason [UrlLauncher.navigate] gives: it opens whatever the rider has
  /// already chosen and already has their traffic settings in.
  Future<void> _openExternal(BuildContext context, WidgetRef ref) async {
    final bool ok = await ref
        .read(launcherProvider)
        .navigate(
          lat: job.targetLat,
          lng: job.targetLng,
          label: job.targetLabel,
        );
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('No maps app could open that address.')),
      );
  }
}
