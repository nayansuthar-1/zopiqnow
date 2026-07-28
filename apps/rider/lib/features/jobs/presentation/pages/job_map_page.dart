import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_map/zopiq_map.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/launcher.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';

/// The job, on a map, inside the app.
///
/// **Why this exists.** Navigate used to fire a `geo:` intent and hand the rider
/// to whatever maps app the phone had. That answers "take me there" and loses
/// the job: the rider leaves Zopiqnow, and the address, the pay, the cash to
/// collect and the button they came back to press are all behind an app switch.
/// This keeps the map and the job on the same screen.
///
/// **What it is not.** It is not turn-by-turn navigation — no voice prompts, no
/// re-routing, no lane guidance, because none of that is a map, it is a
/// navigation SDK. So the handoff survives as a button: a rider who wants a
/// co-pilot presses "Open in Maps" and gets the one they already trust, with
/// their own traffic settings in it.
///
/// MapLibre's own location puck shows where the rider is, so there is no second
/// position stream to run here — the renderer reads the location this app
/// already has permission for, and follows it natively. That is smoother than
/// anything Dart could drive, because the camera never waits on a frame.
class JobMapPage extends ConsumerWidget {
  const JobMapPage({required this.job, super.key});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;

    return Scaffold(
      appBar: AppBar(
        title: Text(job.isCarrying ? 'To the customer' : 'To the restaurant'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ZopiqMapView(
              encodedPolyline: job.routePolyline,
              pins: _pins,
              // The rider's own position, tracked and compass-oriented by the
              // renderer. This is the one screen where "where am I" is the
              // whole point, so the puck and the follow are both on.
              showMyLocation: true,
            ),
          ),
          _Details(job: job, zc: zc),
        ],
      ),
    );
  }

  /// Both ends of the ride, with the one the rider is heading for in the colour
  /// that means "here".
  ///
  /// The other end is still drawn. A rider carrying food wants to see where they
  /// picked it up as much as where it is going; dropping it would leave a lone
  /// pin with no sense of direction.
  List<ZopiqMapPin> get _pins {
    final bool carrying = job.isCarrying;
    return <ZopiqMapPin>[
      if (job.restaurantLat != null && job.restaurantLng != null)
        ZopiqMapPin(
          id: 'restaurant',
          lat: job.restaurantLat!,
          lng: job.restaurantLng!,
          color: carrying
              ? ZopiqMapPin.colourPickup
              : ZopiqMapPin.colourDrop,
          title: job.restaurantName,
        ),
      if (job.deliverLat != null && job.deliverLng != null)
        ZopiqMapPin(
          id: 'destination',
          lat: job.deliverLat!,
          lng: job.deliverLng!,
          color: carrying
              ? ZopiqMapPin.colourDrop
              : ZopiqMapPin.colourPickup,
          title: job.deliverTo.isEmpty ? 'Delivery address' : job.deliverTo,
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
