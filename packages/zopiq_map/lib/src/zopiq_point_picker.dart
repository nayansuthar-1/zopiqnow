import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_map/src/map_style.dart';

/// A map you choose a point on, rather than one you read a journey off.
///
/// [ZopiqMapView] answers "where is this order"; this answers "where is your
/// door". They are separate widgets on purpose — the tracking map's whole design
/// is a camera that fits a route and then leaves the reader alone, and a picker
/// is the opposite: the camera *is* the input, and every gesture is the point
/// changing.
///
/// **The pin does not move; the map does.** The marker is a widget pinned to the
/// centre of the stack rather than a `Marker` on the map, which is what every
/// delivery app does and for a good reason: a marker you drag is a small target
/// under the fingertip that is covering it, while a fixed crosshair lets the
/// whole screen be the handle. It also costs no bitmap rasterisation, so the pin
/// is on screen in the first frame.
///
/// **Reported on idle, not on move.** [onPointChanged] fires when the camera
/// settles, because the caller reverse-geocodes the answer and firing per frame
/// would be a geocoder request per frame. The centre is tracked continuously all
/// the same, so a caller that wants to grey out its confirm button while the map
/// is in motion can watch [onMoveStarted].
class ZopiqPointPicker extends StatefulWidget {
  const ZopiqPointPicker({
    required this.initialLat,
    required this.initialLng,
    required this.onPointChanged,
    this.onMoveStarted,
    this.initialZoom = 16.5,
    this.showMyLocation = false,
    super.key,
  });

  /// Where the map opens. The caller's best guess — the address being edited,
  /// the last GPS fix, or the centre of the town we deliver to.
  final double initialLat;
  final double initialLng;

  /// The centre, each time the camera comes to rest.
  final void Function(double lat, double lng) onPointChanged;

  /// The camera started moving, so whatever was last reported is now stale.
  final VoidCallback? onMoveStarted;

  /// Close enough to pick a building rather than a neighbourhood.
  final double initialZoom;

  /// Google's blue dot, for a picker opened with permission already granted.
  final bool showMyLocation;

  @override
  State<ZopiqPointPicker> createState() => ZopiqPointPickerState();
}

class ZopiqPointPickerState extends State<ZopiqPointPicker> {
  GoogleMapController? _controller;
  late LatLng _centre = LatLng(widget.initialLat, widget.initialLng);

  /// Whether the map is in motion, which lifts the pin off its shadow.
  bool _moving = false;

  /// Moves the camera to [lat]/[lng] — the seam for a picker whose owner has
  /// just resolved a position some other way ("use my current location", or a
  /// place search) and wants the map to agree with it.
  Future<void> moveTo(double lat, double lng) async {
    final GoogleMapController? controller = _controller;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(lat, lng), widget.initialZoom),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(widget.initialLat, widget.initialLng),
            zoom: widget.initialZoom,
          ),
          mapType: MapType.normal,
          // The same quiet ground every other map in the app is drawn on.
          style: zopiqMapStyle,
          myLocationEnabled: widget.showMyLocation,
          myLocationButtonEnabled: widget.showMyLocation,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          // Nothing to tilt or rotate towards on a picker, and both gestures
          // only make the centre harder to place.
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          onMapCreated: (GoogleMapController c) => _controller = c,
          onCameraMoveStarted: () {
            if (!_moving) setState(() => _moving = true);
            widget.onMoveStarted?.call();
          },
          onCameraMove: (CameraPosition p) => _centre = p.target,
          onCameraIdle: () {
            if (_moving) setState(() => _moving = false);
            widget.onPointChanged(_centre.latitude, _centre.longitude);
          },
        ),

        // The pin, dead centre and above the map. `IgnorePointer` so it is
        // scenery: a pin that swallowed taps would be a dead spot in the middle
        // of the one control on the screen.
        IgnorePointer(
          child: Padding(
            // The pin's point is at its bottom, so the *image* sits half its own
            // height above the centre for its tip to land on it.
            padding: const EdgeInsets.only(bottom: _pinHeight),
            child: _Pin(colour: zc.primary, lifted: _moving),
          ),
        ),
      ],
    );
  }
}

const double _pinHeight = 42;

/// The centre pin, and the shadow that says whether the map is moving.
class _Pin extends StatelessWidget {
  const _Pin({required this.colour, required this.lifted});

  final Color colour;

  /// Raised while the map is in motion — the same trick a dragged card plays,
  /// and the only feedback that the point under the pin is not settled yet.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedSlide(
          duration: ZopiqDurations.fast,
          curve: ZopiqCurves.enter,
          offset: Offset(0, lifted ? -0.16 : 0),
          child: Icon(
            Icons.location_on_rounded,
            size: _pinHeight,
            color: colour,
            shadows: const <Shadow>[
              Shadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
        ),
        // The point on the ground the pin is naming, which stays put while the
        // pin above it lifts.
        AnimatedScale(
          duration: ZopiqDurations.fast,
          scale: lifted ? 0.6 : 1,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
