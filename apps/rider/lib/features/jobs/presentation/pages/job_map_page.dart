import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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
/// **Where the rider themselves is drawn.** Google's own blue dot, not a scooter
/// marker. The scooter is how a rider looks to *someone else* — it is what the
/// customer's tracking map shows, fed by the positions [RiderLocationReporter]
/// writes. On this screen the rider is not being tracked, they are holding the
/// phone, and the platform dot is the better answer for it: it is driven by
/// fused location natively, so it has heading and an accuracy circle and moves
/// without waiting on a Dart frame. Drawing a scooter here as well would put two
/// markers on the map for one person.
///
/// **Why this asks for permission.** [RiderLocationReporter] only requests
/// location when the rider starts *carrying*, which is the right moment for a
/// permission dialog but leaves this screen with no dot for a rider who has
/// merely opened a job. So the page asks on the way in. A refusal costs nothing
/// but the dot — the route, both ends and "Open in Maps" all still work.
class JobMapPage extends ConsumerStatefulWidget {
  const JobMapPage({required this.job, super.key});

  final Job job;

  @override
  ConsumerState<JobMapPage> createState() => _JobMapPageState();
}

class _JobMapPageState extends ConsumerState<JobMapPage> {
  bool _located = false;

  Job get job => widget.job;

  @override
  void initState() {
    super.initState();
    unawaited(_askForLocation());
  }

  /// Enables the blue dot only once Android has actually granted the
  /// permission. Turning it on before that logs a security exception and shows
  /// nothing, which looks like a broken map rather than an unanswered dialog.
  Future<void> _askForLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final bool granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (granted && mounted) setState(() => _located = true);
    } on Object {
      // A phone with location off, or a rider who said no. The map is still a
      // map; it just does not know where they are.
    }
  }

  @override
  Widget build(BuildContext context) {
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
              showMyLocation: _located,
            ),
          ),
          _Details(job: job, zc: zc),
        ],
      ),
    );
  }

  /// Both ends of the ride.
  ///
  /// They used to swap colours to mark which end the rider was heading for.
  /// They do not any more, because the icons now say what each place *is* — a
  /// storefront and a person — and that is the more useful fact. Which one is
  /// next is already on the screen twice over: in the app bar and in the
  /// address under the map.
  ///
  /// Both ends stay drawn either way. A rider carrying food wants to see where
  /// they picked it up as much as where it is going; dropping one would leave a
  /// lone pin with no sense of direction.
  List<ZopiqMapPin> get _pins => <ZopiqMapPin>[
    if (job.restaurantLat != null && job.restaurantLng != null)
      ZopiqMapPin(
        id: 'restaurant',
        lat: job.restaurantLat!,
        lng: job.restaurantLng!,
        kind: ZopiqPinKind.vendor,
        title: job.restaurantName,
      ),
    if (job.deliverLat != null && job.deliverLng != null)
      ZopiqMapPin(
        id: 'destination',
        lat: job.deliverLat!,
        lng: job.deliverLng!,
        kind: ZopiqPinKind.customer,
        title: job.deliverTo.isEmpty ? 'Delivery address' : job.deliverTo,
      ),
  ];
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
