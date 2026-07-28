import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_map/src/map_markers.dart';
import 'package:zopiq_map/src/polyline_codec.dart';

/// A pin on the map, in the app's own terms rather than the SDK's.
@immutable
class ZopiqMapPin {
  const ZopiqMapPin({
    required this.id,
    required this.lat,
    required this.lng,
    required this.color,
    this.kind = ZopiqPinKind.place,
    this.title,
  });

  /// Stable across rebuilds, and the whole basis of movement: a pin whose [id]
  /// is unchanged but whose position is not is understood to have *moved*, and
  /// is animated there. A pin with a new id is understood to be a new pin, and
  /// simply appears.
  final String id;

  final double lat;
  final double lng;
  final Color color;
  final ZopiqPinKind kind;
  final String? title;

  /// Where the food is picked up. Brand orange, because the restaurant is the
  /// one place on this map that is a Zopiqnow thing.
  static const Color colourPickup = ZopiqPalette.primary;

  /// Where it is going. Deliberately not orange and not red: it has to be told
  /// apart from the pickup at a glance on a small map, and red on a map means
  /// "problem" everywhere else in this app.
  static const Color colourDrop = ZopiqPalette.veg;

  /// The rider. A cool colour against two warm ones, so the moving thing is
  /// never confused with the fixed ones.
  static const Color colourRider = Color(0xFF1B6FE0);

  LatLng get position => LatLng(lat, lng);
}

/// What a pin is a picture of. See [MapMarkers.rider] for why a vehicle is not
/// drawn with the same shape as an address.
enum ZopiqPinKind { place, rider }

/// What the map is showing underneath the route.
enum ZopiqMapLayer {
  map(MapType.normal, 'Map', Icons.map_outlined),
  satellite(MapType.hybrid, 'Satellite', Icons.satellite_alt),
  terrain(MapType.terrain, 'Terrain', Icons.terrain);

  const ZopiqMapLayer(this.type, this.label, this.icon);

  final MapType type;
  final String label;
  final IconData icon;
}

/// The map, once, for both apps.
///
/// **Google draws the ground; Ola draws the road.** The basemap, its satellite
/// imagery and its terrain come from Google. The route on top is measured by
/// Ola (migrations 0046/0057/0059) and the rider's position arrives over
/// Supabase realtime. The two vendors agree on the encoded-polyline format,
/// which is the only reason a route measured by one can be laid over the other.
///
/// **Why not Ola's own tiles, which we had working.** Ola throttles its tiles
/// product to twenty requests a minute, account-wide across styles, tiles and
/// glyphs. One vector map screen needs forty to eighty, so the basemap went
/// blank on first load and stayed blank while panning. Google's mobile map
/// loads are unmetered, so that ceiling does not exist. Ola's satellite also
/// stops at zoom 14, which is a picture of fields where a rider needs a picture
/// of a gate.
///
/// **Attribution is a licence condition, not decoration.** Google permits a
/// third party's route on their map and requires the UI to name whose route it
/// is. That is [_RoutingCredit], and it is why it may not be quietly deleted.
///
/// **The camera is fitted once, then left alone.** A map that re-centres itself
/// whenever the rider moves is a map you cannot read, because it snatches the
/// view back the moment you drag it. [recenterKey] is the seam for a screen
/// that wants to re-fit deliberately, and [followPinId] the opt-in for one that
/// genuinely wants the camera to chase something.
class ZopiqMapView extends StatefulWidget {
  const ZopiqMapView({
    this.encodedPolyline,
    this.pins = const <ZopiqMapPin>[],
    this.showLayerSwitcher = true,
    this.showMyLocation = false,
    this.interactive = true,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.recenterKey,
    this.followPinId,
    super.key,
  });

  /// The route, as the encoded polyline Ola returned and migration 0046 stored.
  /// Null draws a map framed on the pins alone — the right picture for a job
  /// whose route lookup has not come back yet.
  final String? encodedPolyline;

  final List<ZopiqMapPin> pins;

  /// The Map / Satellite / Terrain control. Off for a small map that is a
  /// glance rather than a screen.
  final bool showLayerSwitcher;

  /// Google's own blue dot. The rider's map wants it; the customer's does not —
  /// the customer's own position is not what that screen is about, and asking
  /// for it would raise a location prompt on a screen with no use for one.
  final bool showMyLocation;

  /// Whether the map may be panned, zoomed, rotated and tilted.
  ///
  /// Off for a map embedded in a scrolling page, and not as a matter of taste:
  /// a map that claims drags inside a `ListView` steals the scroll, and one
  /// that does not claim them is a map whose pan does nothing. Neither is a
  /// good answer, so a small map is a still view with an [onTap] that opens the
  /// real one.
  final bool interactive;

  /// Tapping the map itself. The inline-map-opens-full-screen seam.
  final VoidCallback? onTap;

  /// Keeps the controls and both attributions clear of anything drawn over the
  /// map. Google's logo may not be covered.
  final EdgeInsets padding;

  /// Change this to re-fit the camera to the route. Null means "fit once".
  final Object? recenterKey;

  /// The id of a pin the camera should stay with as it moves. Null leaves the
  /// camera under the reader's control, which is the default for a reason.
  final String? followPinId;

  @override
  State<ZopiqMapView> createState() => _ZopiqMapViewState();
}

class _ZopiqMapViewState extends State<ZopiqMapView>
    with SingleTickerProviderStateMixin {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  ZopiqMapLayer _layer = ZopiqMapLayer.map;

  /// Marker bitmaps, keyed by [_imageName]. Empty until the first async load
  /// lands, which is why [_markers] falls back to Google's own pin: a map that
  /// showed nothing for a frame would flicker on every rebuild.
  final Map<String, BitmapDescriptor> _icons = <String, BitmapDescriptor>{};

  /// Where a pin currently is on screen, which is not where it was last
  /// reported while it is gliding between the two.
  final Map<String, LatLng> _drawnAt = <String, LatLng>{};
  final Map<String, _Move> _moving = <String, _Move>{};

  bool _fitted = false;

  /// Roughly the interval between two rider fixes, so a pin finishes its glide
  /// about when the next one arrives and the dot never appears to stall.
  late final AnimationController _mover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..addListener(_onMoveTick);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_loadIcons()));
  }

  @override
  void dispose() {
    _mover.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ZopiqMapView old) {
    super.didUpdateWidget(old);

    if (widget.recenterKey != null && widget.recenterKey != old.recenterKey) {
      unawaited(_fit());
    }
    if (!_samePins(old.pins, widget.pins)) {
      _startMoves(old.pins);
      unawaited(_loadIcons());
    }
  }

  static bool _samePins(List<ZopiqMapPin> a, List<ZopiqMapPin> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].lat != b[i].lat ||
          a[i].lng != b[i].lng ||
          a[i].color != b[i].color) {
        return false;
      }
    }
    return true;
  }

  static String _imageName(ZopiqMapPin pin) =>
      '${pin.kind.name}-${pin.color.toARGB32()}';

  /// Rasterises any marker bitmap this map needs and does not yet have.
  Future<void> _loadIcons() async {
    if (!mounted) return;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    bool added = false;

    for (final ZopiqMapPin pin in widget.pins) {
      final String name = _imageName(pin);
      if (_icons.containsKey(name)) continue;
      final Uint8List bytes = switch (pin.kind) {
        ZopiqPinKind.place => await MapMarkers.pin(
          color: pin.color,
          pixelRatio: dpr,
        ),
        ZopiqPinKind.rider => await MapMarkers.rider(
          color: pin.color,
          pixelRatio: dpr,
        ),
      };
      _icons[name] = BytesMapBitmap(bytes, imagePixelRatio: dpr);
      added = true;
    }

    if (added && mounted) setState(() {});
  }

  /// Anything that kept its id but changed position is animated to the new one.
  void _startMoves(List<ZopiqMapPin> previous) {
    final Map<String, LatLng> before = <String, LatLng>{
      for (final ZopiqMapPin p in previous) p.id: p.position,
    };
    bool animate = false;

    for (final ZopiqMapPin pin in widget.pins) {
      final LatLng? from = _drawnAt[pin.id] ?? before[pin.id];
      if (from == null) continue;
      if (from.latitude == pin.lat && from.longitude == pin.lng) continue;
      // It moved. Glide it rather than teleport it — a dot that jumps every few
      // seconds reads as a glitch, not as a vehicle.
      _moving[pin.id] = _Move(from: from, to: pin.position, pin: pin);
      animate = true;
    }

    if (animate) {
      _mover.reset();
      unawaited(_mover.forward());
    }
  }

  void _onMoveTick() {
    if (_moving.isEmpty || !mounted) return;

    final double t = Curves.easeOut.transform(_mover.value);
    for (final MapEntry<String, _Move> e in _moving.entries) {
      _drawnAt[e.key] = e.value.at(t);
    }

    final LatLng? follow = widget.followPinId == null
        ? null
        : _drawnAt[widget.followPinId];
    if (follow != null && _controller.isCompleted) {
      unawaited(
        _controller.future.then(
          (GoogleMapController c) => c.moveCamera(CameraUpdate.newLatLng(follow)),
        ),
      );
    }

    setState(() {});
    if (_mover.value == 1) _moving.clear();
  }

  /// Every point that has to be visible, so a rider who has wandered off the
  /// quoted route is still in frame rather than off the edge of it.
  List<LatLng> get _framed => <LatLng>[
    ...decodePolyline(widget.encodedPolyline),
    ...widget.pins.map((ZopiqMapPin p) => p.position),
  ];

  Future<void> _fit() async {
    final List<LatLng> points = _framed;
    if (points.isEmpty) return;
    final GoogleMapController controller = await _controller.future;
    // 48pt of air, so a pin at the edge of the route is not half off the screen.
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(boundsOf(points), 48),
    );
  }

  Set<Marker> get _markers => widget.pins.map((ZopiqMapPin pin) {
    final LatLng at = _drawnAt[pin.id] ?? pin.position;
    return Marker(
      markerId: MarkerId(pin.id),
      position: at,
      icon: _icons[_imageName(pin)] ?? BitmapDescriptor.defaultMarker,
      // A teardrop points at its place, so it is anchored at its tip. A rider's
      // disc *is* its place, so it is anchored at its middle.
      anchor: pin.kind == ZopiqPinKind.place
          ? const Offset(0.5, 1)
          : const Offset(0.5, 0.5),
      infoWindow: pin.title == null
          ? InfoWindow.noText
          : InfoWindow(title: pin.title),
    );
  }).toSet();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final List<LatLng> road = decodePolyline(widget.encodedPolyline);
    final List<LatLng> points = _framed;

    return Stack(
      children: <Widget>[
        GoogleMap(
          initialCameraPosition: CameraPosition(
            // Somewhere sensible for the moment before the fit lands. India's
            // centre, so a failed fit is never the middle of the ocean.
            target: points.isEmpty ? const LatLng(21.13, 82.79) : points.first,
            zoom: 13,
          ),
          mapType: _layer.type,
          padding: widget.padding,
          myLocationEnabled: widget.showMyLocation,
          myLocationButtonEnabled: widget.showMyLocation && widget.interactive,
          // The stock zoom buttons are redundant beside pinch-to-zoom and they
          // crowd a small map; the gestures they duplicate stay on.
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: widget.interactive,
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          rotateGesturesEnabled: widget.interactive,
          tiltGesturesEnabled: widget.interactive,
          onTap: widget.onTap == null ? null : (LatLng _) => widget.onTap!(),
          polylines: road.length < 2
              ? const <Polyline>{}
              : <Polyline>{
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: road,
                    color: ZopiqPalette.primary,
                    width: 6,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                  ),
                },
          markers: _markers,
          onMapCreated: (GoogleMapController controller) {
            if (!_controller.isCompleted) _controller.complete(controller);
            if (!_fitted) {
              _fitted = true;
              unawaited(_fit());
            }
          },
        ),
        if (widget.showLayerSwitcher)
          Positioned(
            top: widget.padding.top + ZopiqSpacing.sm,
            right: widget.padding.right + ZopiqSpacing.sm,
            child: _LayerSwitcher(
              current: _layer,
              zc: zc,
              onChanged: (ZopiqMapLayer layer) =>
                  setState(() => _layer = layer),
            ),
          ),
        // Only when there is actually a third party's route on the map.
        if (road.length >= 2)
          Positioned(
            right: widget.padding.right + ZopiqSpacing.sm,
            bottom: widget.padding.bottom + ZopiqSpacing.sm,
            child: const _RoutingCredit(),
          ),
      ],
    );
  }
}

/// One pin's journey between two fixes.
@immutable
class _Move {
  const _Move({required this.from, required this.to, required this.pin});

  final LatLng from;
  final LatLng to;
  final ZopiqMapPin pin;

  /// Straight-line interpolation, which is the honest choice: we know where the
  /// rider was and where they are, and inventing a curve between the two would
  /// be drawing a path nobody reported taking.
  LatLng at(double t) => LatLng(
    from.latitude + (to.latitude - from.latitude) * t,
    from.longitude + (to.longitude - from.longitude) * t,
  );
}

/// "Routing by Ola Maps".
///
/// **Do not remove this.** Google's Maps Platform terms allow a third party's
/// route to be drawn on a Google map on the condition that the interface says
/// whose route it is. Deleting this label does not simplify the map, it breaks
/// the terms the basemap is served under.
///
/// It sits bottom-right because Google's own logo sits bottom-left and the same
/// terms forbid obscuring it.
class _RoutingCredit extends StatelessWidget {
  const _RoutingCredit();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: ZopiqRadii.rSm,
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          'Routing by Ola Maps',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// Map / Satellite / Terrain, as a menu behind one button.
///
/// A button rather than chips across the top: this sits over the map, and
/// anything permanently over a map is map the person cannot see. It is the
/// shape Google Maps itself uses, so nobody has to be taught it.
class _LayerSwitcher extends StatelessWidget {
  const _LayerSwitcher({
    required this.current,
    required this.zc,
    required this.onChanged,
  });

  final ZopiqMapLayer current;
  final ZopiqColors zc;
  final ValueChanged<ZopiqMapLayer> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      borderRadius: ZopiqRadii.rMd,
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<ZopiqMapLayer>(
        tooltip: 'Map layers',
        initialValue: current,
        onSelected: onChanged,
        itemBuilder: (BuildContext context) => ZopiqMapLayer.values
            .map(
              (ZopiqMapLayer layer) => PopupMenuItem<ZopiqMapLayer>(
                value: layer,
                child: Row(
                  children: <Widget>[
                    Icon(
                      layer.icon,
                      size: 18,
                      color: layer == current ? zc.primary : zc.textMuted,
                    ),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Text(layer.label),
                  ],
                ),
              ),
            )
            .toList(),
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.sm),
          child: Icon(current.icon, size: 20, color: zc.primary),
        ),
      ),
    );
  }
}
