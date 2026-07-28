import 'dart:async';
// MapLibre takes control margins as a `Point`, and does not re-export the one
// it means.
import 'dart:math' show Point;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_map/src/map_markers.dart';
import 'package:zopiq_map/src/ola_maps.dart';
import 'package:zopiq_map/src/polyline_codec.dart';

/// A pin on the map, in the app's own terms rather than the renderer's.
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

/// The map, once, for both apps.
///
/// **What this replaced.** Until now these screens showed a photograph: a
/// finished PNG from Ola's static API with the road and pins already drawn on
/// it. It was a real map, but a picture of one — it could not pan, zoom, rotate
/// or switch layers, and every change of any kind meant a round trip for a new
/// image. This is the same data from the same vendor, rendered live on the
/// device by MapLibre, which is the engine Ola's own SDK is built on.
///
/// **The camera is fitted once, then left alone.** A map that re-centres itself
/// whenever the rider moves is a map you cannot read, because it snatches the
/// view back the moment you drag it. So the route is framed on first load and
/// on nothing else. [recenterKey] is the seam for a screen that wants to re-fit
/// deliberately, and [followPinId] is the opt-in for one that genuinely wants
/// the camera to chase something.
///
/// **Switching layers does not disturb the view.** MapLibre discards every
/// annotation when a style is swapped, so the route and the pins are rebuilt on
/// each style load — but the camera is not re-fitted, because someone who has
/// zoomed into a junction and then tapped Satellite wants that junction from
/// above, not the whole city again.
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

  /// The Map / Satellite control. Off for a small map that is a glance rather
  /// than a screen.
  final bool showLayerSwitcher;

  /// MapLibre's own location puck, tracked natively.
  ///
  /// The rider's map wants it; the customer's does not — the customer's own
  /// position is not what that screen is about, and asking for it would raise a
  /// location prompt on a screen with no use for one.
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

  /// Keeps the attribution and the controls clear of anything drawn over the
  /// map. Ola's attribution may not be covered.
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
  MapLibreMapController? _controller;
  ZopiqMapLayer _layer = ZopiqMapLayer.map;

  final Map<String, Symbol> _symbols = <String, Symbol>{};
  Line? _route;

  /// Fitting happens on the first style load only — see the class comment.
  bool _fitted = false;

  /// Where each pin was and where it is going, for the pins currently moving.
  final Map<String, _Move> _moving = <String, _Move>{};

  /// Roughly the interval between two rider fixes, so a pin finishes its glide
  /// about when the next one arrives and the dot never appears to stall.
  late final AnimationController _mover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..addListener(_onMoveTick);

  /// The platform channel is a real cost per call, and a symbol update at the
  /// display's full rate would put 120 of them a second on it for no visible
  /// benefit. 30 a second is smooth to the eye and an eighth of the traffic.
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

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
    if (widget.encodedPolyline != old.encodedPolyline) {
      unawaited(_syncRoute());
    }
    if (!_samePins(old.pins, widget.pins)) {
      unawaited(_syncPins(previous: old.pins));
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

  /// Every point that has to be visible, so a rider who has wandered off the
  /// quoted route is still in frame rather than off the edge of it.
  List<LatLng> get _framed => <LatLng>[
    ...decodePolyline(widget.encodedPolyline),
    ...widget.pins.map((ZopiqMapPin p) => p.position),
  ];

  Future<void> _fit() async {
    final MapLibreMapController? controller = _controller;
    final List<LatLng> points = _framed;
    if (controller == null || points.isEmpty) return;

    // 48pt of air, plus whatever the screen has drawn over the map, so a pin at
    // the edge of the route is never half under a sheet.
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        boundsOf(points),
        left: widget.padding.left + 48,
        top: widget.padding.top + 48,
        right: widget.padding.right + 48,
        bottom: widget.padding.bottom + 48,
      ),
    );
  }

  /// A style swap throws away every annotation, so this runs on each style load
  /// and not only the first.
  Future<void> _onStyleLoaded() async {
    final MapLibreMapController? controller = _controller;
    if (controller == null) return;

    _symbols.clear();
    _route = null;

    await _registerImages(controller);
    await _syncRoute();
    await _syncPins();

    // Overlapping pins stay drawn. The default hides a symbol that collides
    // with another, which at a shared pickup point would silently delete the
    // restaurant from the map.
    await controller.setSymbolIconAllowOverlap(true);

    if (!_fitted) {
      _fitted = true;
      await _fit();
    }
  }

  /// Every marker bitmap this map could need, registered under a name the
  /// symbol layer can refer to.
  Future<void> _registerImages(MapLibreMapController controller) async {
    // Reached from style- and pin-change callbacks, both of which can land after
    // the screen has been popped. Reading `context` then would throw.
    if (!mounted) return;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final Set<String> done = <String>{};

    for (final ZopiqMapPin pin in widget.pins) {
      final String name = _imageName(pin);
      if (!done.add(name)) continue;
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
      await controller.addImage(name, bytes);
    }
  }

  static String _imageName(ZopiqMapPin pin) =>
      '${pin.kind.name}-${pin.color.toARGB32()}';

  Future<void> _syncRoute() async {
    final MapLibreMapController? controller = _controller;
    if (controller == null) return;

    final List<LatLng> road = decodePolyline(widget.encodedPolyline);
    final Line? existing = _route;

    if (road.length < 2) {
      if (existing != null) {
        await controller.removeLine(existing);
        _route = null;
      }
      return;
    }

    final LineOptions options = LineOptions(
      geometry: road,
      lineColor: _hex(ZopiqPalette.primary),
      lineWidth: 5,
      lineOpacity: 1,
      lineJoin: 'round',
    );

    if (existing == null) {
      _route = await controller.addLine(options);
    } else {
      await controller.updateLine(existing, options);
    }
  }

  /// Adds what is new, removes what is gone, and animates what has moved.
  Future<void> _syncPins({List<ZopiqMapPin> previous = const <ZopiqMapPin>[]}) async {
    final MapLibreMapController? controller = _controller;
    if (controller == null) return;

    final Map<String, ZopiqMapPin> wanted = <String, ZopiqMapPin>{
      for (final ZopiqMapPin p in widget.pins) p.id: p,
    };

    for (final String id in _symbols.keys.toList()) {
      if (wanted.containsKey(id)) continue;
      final Symbol? gone = _symbols.remove(id);
      _moving.remove(id);
      if (gone != null) await controller.removeSymbol(gone);
    }

    await _registerImages(controller);

    final Map<String, LatLng> before = <String, LatLng>{
      for (final ZopiqMapPin p in previous) p.id: p.position,
    };
    bool animate = false;

    for (final ZopiqMapPin pin in widget.pins) {
      final Symbol? existing = _symbols[pin.id];

      if (existing == null) {
        _symbols[pin.id] = await controller.addSymbol(_optionsFor(pin, pin.position));
        continue;
      }

      final LatLng? from = before[pin.id];
      if (from != null && (from.latitude != pin.lat || from.longitude != pin.lng)) {
        // It moved. Glide it rather than teleport it — a dot that jumps every
        // few seconds reads as a glitch, not as a vehicle.
        _moving[pin.id] = _Move(from: from, to: pin.position, pin: pin);
        animate = true;
      } else {
        await controller.updateSymbol(existing, _optionsFor(pin, pin.position));
      }
    }

    if (animate) {
      _mover.reset();
      unawaited(_mover.forward());
    }
  }

  SymbolOptions _optionsFor(ZopiqMapPin pin, LatLng at) => SymbolOptions(
    geometry: at,
    iconImage: _imageName(pin),
    iconSize: 1,
    // A teardrop points at its place, so it is anchored at its tip. A rider's
    // disc *is* its place, so it is anchored at its middle.
    iconAnchor: pin.kind == ZopiqPinKind.place ? 'bottom' : 'center',
  );

  void _onMoveTick() {
    final MapLibreMapController? controller = _controller;
    if (controller == null || _moving.isEmpty) return;

    final DateTime now = DateTime.now();
    final bool last = _mover.value == 1;
    if (!last && now.difference(_lastTick).inMilliseconds < 33) return;
    _lastTick = now;

    final double t = Curves.easeOut.transform(_mover.value);

    for (final MapEntry<String, _Move> entry in _moving.entries) {
      final Symbol? symbol = _symbols[entry.key];
      if (symbol == null) continue;
      final LatLng at = entry.value.at(t);
      unawaited(controller.updateSymbol(symbol, _optionsFor(entry.value.pin, at)));

      if (entry.key == widget.followPinId) {
        unawaited(controller.moveCamera(CameraUpdate.newLatLng(at)));
      }
    }

    if (last) _moving.clear();
  }

  /// MapLibre's annotation options take a colour as a CSS string, not a [Color].
  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final List<LatLng> points = _framed;

    // Without a key MapLibre would draw an empty grey rectangle and log the 401
    // where nobody is looking. Say it on the screen instead.
    if (!OlaMaps.isConfigured) return _MissingKey(zc: zc);

    return Stack(
      children: <Widget>[
        MapLibreMap(
          styleString: OlaMaps.urlFor(_layer, dark: dark),
          initialCameraPosition: CameraPosition(
            // Somewhere sensible for the moment before the fit lands. India's
            // centre, so a failed fit is never the middle of the ocean.
            target: points.isEmpty ? const LatLng(21.13, 82.79) : points.first,
            zoom: 13,
          ),
          myLocationEnabled: widget.showMyLocation,
          myLocationTrackingMode: widget.showMyLocation
              ? MyLocationTrackingMode.tracking
              : MyLocationTrackingMode.none,
          // Must follow `myLocationEnabled`: MapLibre asserts that any mode
          // other than `normal` has the location layer switched on, so a
          // hard-coded `compass` crashes every map that does not show a puck —
          // which is both of the customer's.
          myLocationRenderMode: widget.showMyLocation
              ? MyLocationRenderMode.compass
              : MyLocationRenderMode.normal,
          compassEnabled: widget.interactive,
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          rotateGesturesEnabled: widget.interactive,
          tiltGesturesEnabled: widget.interactive,
          // Annotation dragging, not map dragging. Nothing here is draggable.
          dragEnabled: false,
          // Ola's attribution is a condition of using the tiles. It is kept
          // clear of whatever the screen has drawn over the map.
          attributionButtonMargins: Point<num>(
            8 + widget.padding.right,
            8 + widget.padding.bottom,
          ),
          onMapCreated: (MapLibreMapController controller) =>
              _controller = controller,
          onStyleLoadedCallback: () => unawaited(_onStyleLoaded()),
          onMapClick: widget.onTap == null
              ? null
              : (Point<double> _, LatLng _) => widget.onTap!(),
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
      ],
    );
  }
}

/// What a map looks like when the build forgot its key.
///
/// Addressed to whoever is holding the phone, which during development is a
/// developer and in production should be nobody: a release built without the
/// define is a release with no maps, and this is how that announces itself
/// rather than looking like a slow network.
class _MissingKey extends StatelessWidget {
  const _MissingKey({required this.zc});

  final ZopiqColors zc;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.map_outlined, color: zc.textMuted),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Map unavailable',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: zc.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
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

/// Map / Satellite, as a menu behind one button.
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

  static const Map<ZopiqMapLayer, IconData> _icons = <ZopiqMapLayer, IconData>{
    ZopiqMapLayer.map: Icons.map_outlined,
    ZopiqMapLayer.satellite: Icons.satellite_alt,
  };

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
                      _icons[layer],
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
          child: Icon(_icons[current], size: 20, color: zc.primary),
        ),
      ),
    );
  }
}
