import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_map/src/map_markers.dart';
import 'package:zopiq_map/src/polyline_codec.dart';
import 'package:zopiq_map/src/route_progress.dart';

/// A pin on the map, in the app's own terms rather than the SDK's.
///
/// There is no colour here on purpose. A caller says *what a thing is* — a
/// vendor, a customer, a rider — and [ZopiqPinKind] decides how it is drawn, so
/// the same restaurant cannot be orange on one screen and green on another.
@immutable
class ZopiqMapPin {
  const ZopiqMapPin({
    required this.id,
    required this.lat,
    required this.lng,
    required this.kind,
    this.title,
    this.heading,
    this.label,
  });

  /// Stable across rebuilds, and the whole basis of movement: a pin whose [id]
  /// is unchanged but whose position is not is understood to have *moved*, and
  /// is animated there. A pin with a new id is understood to be a new pin, and
  /// simply appears.
  final String id;

  final double lat;
  final double lng;
  final ZopiqPinKind kind;

  /// The info window, shown on tap. Not the same thing as [label], which is
  /// always on screen.
  final String? title;

  /// Degrees clockwise from north, when the reporting phone was moving enough
  /// to know. Null draws a plain disc rather than a chevron pointing
  /// confidently at nothing — a stationary GPS reports no bearing, and guessing
  /// one would be drawing a direction nobody reported.
  final double? heading;

  /// A word or two rendered in a capsule above the pin — "6 min". Kept short on
  /// purpose: this is painted into the marker image, so a long one is a wide
  /// bitmap covering the map it is describing.
  final String? label;

  LatLng get position => LatLng(lat, lng);

  /// What makes two markers the same *picture*. Two pins with the same kind,
  /// bearing and label share one rasterised bitmap.
  String get imageKey => '${kind.name}|$heading|$label';
}

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
/// **The route is drawn in three passes, not one.** A casing under the whole
/// road, then the part already ridden in grey, then the part still to come in
/// full colour. The split point is where the rider actually is, so the line
/// reads as progress rather than as decoration — and when the rider is nowhere
/// near the quoted road, [splitRoute] refuses and the whole thing stays
/// "ahead", which is the honest picture of a route we can no longer vouch for.
///
/// **There is deliberately no traffic colouring.** Ola's Directions response as
/// we call it carries a distance and an overview polyline and no per-segment
/// speeds, so a green-amber-red road would be three colours we made up.
///
/// **The camera is fitted once, then left alone.** A map that re-centres itself
/// whenever the rider moves is a map you cannot read, because it snatches the
/// view back the moment you drag it. [recenterKey] is the seam for a screen
/// that wants to re-fit deliberately, and [followPinId] the opt-in for one that
/// genuinely wants the camera to chase something — offered to the reader as a
/// button they can switch off, never imposed.
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
  /// real one. It also suppresses the controls: a button on a map you cannot
  /// move has nothing to do.
  final bool interactive;

  /// Tapping the map itself. The inline-map-opens-full-screen seam.
  final VoidCallback? onTap;

  /// Keeps the controls and both attributions clear of anything drawn over the
  /// map. Google's logo may not be covered.
  final EdgeInsets padding;

  /// Change this to re-fit the camera to the route. Null means "fit once".
  final Object? recenterKey;

  /// The id of a pin the camera may follow. Supplying one puts a follow button
  /// on the map and starts with it on; the reader can turn it off, and panning
  /// the map by hand turns it off for them — a camera that fights the finger
  /// dragging it is worse than no camera help at all.
  final String? followPinId;

  @override
  State<ZopiqMapView> createState() => _ZopiqMapViewState();
}

class _ZopiqMapViewState extends State<ZopiqMapView>
    with SingleTickerProviderStateMixin {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  ZopiqMapLayer _layer = ZopiqMapLayer.map;

  /// Marker images, keyed by [ZopiqMapPin.imageKey].
  final Map<String, _PinImage> _images = <String, _PinImage>{};

  /// The last image actually drawn for a given pin *id*.
  ///
  /// A rider's bearing changes with every fix, and each new bearing is a new
  /// bitmap that has to be rasterised off the frame. Without this the marker
  /// would fall back to the SDK's default red pin for the frame or two that
  /// takes, so a moving scooter would flicker red every few seconds. Holding
  /// the previous image means the worst case is a chevron one fix out of date.
  final Map<String, _PinImage> _lastDrawn = <String, _PinImage>{};

  /// Where a pin currently is on screen, which is not where it was last
  /// reported while it is gliding between the two.
  final Map<String, LatLng> _drawnAt = <String, LatLng>{};
  final Map<String, _Move> _moving = <String, _Move>{};

  /// Whether the camera is currently chasing [ZopiqMapView.followPinId].
  late bool _follow = widget.followPinId != null;

  /// Where the finger currently on the map first landed.
  ///
  /// Following has to stop the moment the reader takes the camera back, and the
  /// SDK is no help here: `onCameraMoveStarted` fires for *our own*
  /// `moveCamera` as readily as for a drag, so following would switch itself
  /// off on its first tick. The finger is the only unambiguous signal, so the
  /// map watches for one directly.
  Offset? _touchStart;

  /// How many times the opening fit has been attempted.
  ///
  /// **Why more than once.** `newLatLngBounds` needs the platform view to know
  /// its own size, and at `onMapCreated` it does not yet — the fit lands, but
  /// against the wrong viewport, and the result is a route framed slightly too
  /// tight with a pin clipped off the edge. The first `onCameraIdle` is the
  /// earliest moment the map is laid out and settled, so the fit is repeated
  /// there and then never again, which leaves the camera to the reader.
  int _fitAttempts = 0;
  static const int _maxFitAttempts = 2;

  /// Roughly the interval between two rider fixes, so a pin finishes its glide
  /// about when the next one arrives and the dot never appears to stall.
  late final AnimationController _mover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..addListener(_onMoveTick);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_loadImages()),
    );
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
      unawaited(_loadImages());
    }
  }

  static bool _samePins(List<ZopiqMapPin> a, List<ZopiqMapPin> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].lat != b[i].lat ||
          a[i].lng != b[i].lng ||
          a[i].imageKey != b[i].imageKey) {
        return false;
      }
    }
    return true;
  }

  /// Rasterises any marker image this map needs and does not yet have.
  Future<void> _loadImages() async {
    if (!mounted) return;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    bool added = false;

    for (final ZopiqMapPin pin in widget.pins) {
      _PinImage? image = _images[pin.imageKey];
      if (image == null) {
        final MarkerBitmap drawn = await MapMarkers.forPin(
          pin.kind,
          pixelRatio: dpr,
          heading: pin.heading,
          label: pin.label,
        );
        image = _PinImage(
          icon: BytesMapBitmap(drawn.bytes, imagePixelRatio: dpr),
          anchor: drawn.anchor,
        );
        _images[pin.imageKey] = image;
        added = true;
      }
      // Held per id, not per image, so the next bearing has something to draw
      // while it rasterises.
      if (_lastDrawn[pin.id] != image) {
        _lastDrawn[pin.id] = image;
        added = true;
      }
    }

    // Only the images the current pins use are kept. Each one holds a native
    // bitmap behind its descriptor, and a rider whose bearing and countdown
    // both move on every fix would otherwise leave one stranded here every
    // twenty seconds for the whole ride. Nothing is lost by dropping them: the
    // bytes are still in MapMarkers' cache, and `_lastDrawn` separately holds
    // the one image per pin the next frame might still need to fall back to.
    final Set<String> inUse = <String>{
      for (final ZopiqMapPin pin in widget.pins) pin.imageKey,
    };
    _images.removeWhere((String key, _PinImage _) => !inUse.contains(key));

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

    final LatLng? follow = !_follow || widget.followPinId == null
        ? null
        : _drawnAt[widget.followPinId];
    if (follow != null && _controller.isCompleted) {
      unawaited(
        _controller.future.then(
          (GoogleMapController c) =>
              c.moveCamera(CameraUpdate.newLatLng(follow)),
        ),
      );
    }

    setState(() {});
    if (_mover.value == 1) _moving.clear();
  }

  /// Where a pin is being drawn right now — mid-glide, not where it was last
  /// reported.
  LatLng _positionOf(ZopiqMapPin pin) => _drawnAt[pin.id] ?? pin.position;

  /// The moving one, if this map has one.
  ZopiqMapPin? get _rider {
    for (final ZopiqMapPin pin in widget.pins) {
      if (pin.kind == ZopiqPinKind.rider) return pin;
    }
    return null;
  }

  /// Every point that has to be visible, so a rider who has wandered off the
  /// quoted route is still in frame rather than off the edge of it.
  List<LatLng> get _framed => <LatLng>[
    ...decodePolyline(widget.encodedPolyline),
    ...widget.pins.map((ZopiqMapPin p) => p.position),
  ];

  /// The opening fit, at most [_maxFitAttempts] times and never after.
  void _openingFit() {
    if (_fitAttempts >= _maxFitAttempts) return;
    _fitAttempts++;
    unawaited(_fit());
  }

  Future<void> _fit() async {
    final List<LatLng> points = _framed;
    if (points.isEmpty) return;
    final GoogleMapController controller = await _controller.future;
    // 48pt of air, so a pin at the edge of the route is not half off the screen.
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(boundsOf(points), 48),
    );
  }

  /// Turns following on and jumps to the pin, or turns it off and leaves the
  /// camera exactly where it is.
  Future<void> _toggleFollow() async {
    final String? id = widget.followPinId;
    if (id == null) return;

    setState(() => _follow = !_follow);
    if (!_follow) return;

    for (final ZopiqMapPin pin in widget.pins) {
      if (pin.id != id) continue;
      final GoogleMapController controller = await _controller.future;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(_positionOf(pin), 16),
      );
      return;
    }
  }

  Set<Marker> get _markers => widget.pins.map((ZopiqMapPin pin) {
    final _PinImage? image = _images[pin.imageKey] ?? _lastDrawn[pin.id];
    return Marker(
      markerId: MarkerId(pin.id),
      position: _positionOf(pin),
      icon: image?.icon ?? BitmapDescriptor.defaultMarker,
      anchor: image?.anchor ?? const Offset(0.5, 1),
      // The moving marker sits over the fixed ones, so a rider at the door is
      // not hidden underneath it.
      zIndexInt: pin.kind == ZopiqPinKind.rider ? 2 : 1,
      infoWindow: pin.title == null
          ? InfoWindow.noText
          : InfoWindow(title: pin.title),
    );
  }).toSet();

  /// The road: a casing under everything, then behind-the-rider, then ahead.
  Set<Polyline> _road(List<LatLng> road) {
    if (road.length < 2) return const <Polyline>{};

    final ZopiqMapPin? rider = _rider;
    final RouteProgress? progress = rider == null
        ? null
        : splitRoute(road, _positionOf(rider));

    return <Polyline>{
      // A dark outline under the whole road. Without it an orange line over
      // satellite imagery of an orange rooftop is invisible, and over a pale
      // basemap it has no edge at all.
      Polyline(
        polylineId: const PolylineId('route-casing'),
        points: road,
        color: const Color(0xFF1C2230).withValues(alpha: 0.45),
        width: 11,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
      if (progress != null && progress.travelled.length >= 2)
        Polyline(
          polylineId: const PolylineId('route-travelled'),
          points: progress.travelled,
          color: ZopiqPalette.textMuted,
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.buttCap,
          jointType: JointType.round,
          zIndex: 1,
        ),
      Polyline(
        polylineId: const PolylineId('route'),
        points: progress?.remaining ?? road,
        color: ZopiqPalette.primary,
        width: 6,
        startCap: Cap.buttCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 2,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final List<LatLng> road = decodePolyline(widget.encodedPolyline);
    final List<LatLng> points = _framed;
    final bool canFollow = widget.interactive && widget.followPinId != null;

    return Stack(
      children: <Widget>[
        Listener(
          onPointerDown: (PointerDownEvent e) => _touchStart = e.position,
          onPointerUp: (PointerUpEvent _) => _touchStart = null,
          // A drag, not a tap. Twelve logical pixels is about Flutter's own
          // slop, so tapping a pin to read its label does not silently stop the
          // camera following the rider.
          onPointerMove: (PointerMoveEvent e) {
            final Offset? start = _touchStart;
            if (!_follow || start == null) return;
            if ((e.position - start).distance < 12) return;
            setState(() => _follow = false);
          },
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              // Somewhere sensible for the moment before the fit lands. India's
              // centre, so a failed fit is never the middle of the ocean.
              target: points.isEmpty
                  ? const LatLng(21.13, 82.79)
                  : points.first,
              zoom: 13,
            ),
            mapType: _layer.type,
            padding: widget.padding,
            myLocationEnabled: widget.showMyLocation,
            myLocationButtonEnabled:
                widget.showMyLocation && widget.interactive,
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
            polylines: _road(road),
            markers: _markers,
            onMapCreated: (GoogleMapController controller) {
              if (!_controller.isCompleted) _controller.complete(controller);
              _openingFit();
            },
            // The second and last opening fit — see [_fitAttempts]. Guarded, so
            // once the route has been framed this stops firing and a reader who
            // pans away keeps the view they chose.
            onCameraIdle: _openingFit,
          ),
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
        Positioned(
          right: widget.padding.right + ZopiqSpacing.sm,
          bottom: widget.padding.bottom + ZopiqSpacing.sm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (canFollow)
                _MapButton(
                  icon: _follow ? Icons.navigation : Icons.navigation_outlined,
                  tooltip: _follow ? 'Stop following' : 'Follow your rider',
                  colour: _follow ? zc.primary : zc.textMuted,
                  onPressed: _toggleFollow,
                ),
              if (widget.interactive && points.isNotEmpty) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.xs),
                _MapButton(
                  icon: Icons.fullscreen,
                  tooltip: 'Show the whole route',
                  colour: zc.textMuted,
                  onPressed: _fit,
                ),
              ],
              // Only when there is actually a third party's route on the map.
              if (road.length >= 2) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.xs),
                const _RoutingCredit(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A rasterised marker, ready for the SDK.
///
/// The [BitmapDescriptor] is built once when the bytes are and then held,
/// because a fresh one on every frame is a fresh object on every frame: the
/// SDK diffs markers by equality, so rebuilding the descriptor in `build`
/// would make every marker look changed on every tick and push a full marker
/// update across the platform channel sixty times a second.
@immutable
class _PinImage {
  const _PinImage({required this.icon, required this.anchor});

  final BitmapDescriptor icon;
  final Offset anchor;
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

/// One round control over the map, sized so a thumb can hit it.
class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.colour,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color colour;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
        onPressed: () => unawaited(onPressed()),
        icon: Icon(icon, color: colour),
      ),
    );
  }
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
          style: TextStyle(color: Colors.white, fontSize: 10, height: 1.4),
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
