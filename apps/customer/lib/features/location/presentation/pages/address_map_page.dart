import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_map/zopiq_map.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/location_prompt.dart';

/// Where the pin opens when the caller has nothing better to offer.
///
/// Falna — the first town we deliver to — rather than the middle of the country.
/// A picker that opens on an empty map 600km from the customer is a picker they
/// have to pan across a state to use.
const double _fallbackLat = 25.2380;
const double _fallbackLng = 73.2360;

/// Drop a pin on the map and get the address standing under it.
///
/// The form could already turn *words* into a point, and GPS could turn *here*
/// into one. Neither covers the ordinary case of a customer who is not at the
/// address, whose lane has no name the geocoder knows, and who can nonetheless
/// see their own roof. This is that third way in, and it is the one every
/// delivery app leads with.
///
/// Returns the chosen [Address] to whoever pushed it, or null if they backed
/// out. The address carries a `manual:` id, so nothing downstream mistakes it
/// for a row in the address book.
Future<Address?> showAddressMapPicker(
  BuildContext context, {
  GeoPoint? initial,
}) {
  return Navigator.of(context).push<Address>(
    MaterialPageRoute<Address>(
      fullscreenDialog: true,
      builder: (_) => AddressMapPage(initial: initial),
    ),
  );
}

class AddressMapPage extends ConsumerStatefulWidget {
  const AddressMapPage({this.initial, super.key});

  /// Where to open. The address being edited, or the one already selected.
  final GeoPoint? initial;

  @override
  ConsumerState<AddressMapPage> createState() => _AddressMapPageState();
}

class _AddressMapPageState extends ConsumerState<AddressMapPage> {
  final GlobalKey<ZopiqPointPickerState> _picker =
      GlobalKey<ZopiqPointPickerState>();

  /// The point under the pin, and the place we resolved it to.
  late double _lat;
  late double _lng;
  Address? _resolved;

  /// True from the moment the map starts moving until its address comes back.
  bool _resolving = false;
  String? _error;
  bool _locating = false;

  /// Guards against an older reverse-geocode landing after a newer one.
  ///
  /// The map settles, we ask, the customer drags again before the answer
  /// arrives — two requests in flight, and the network decides which returns
  /// last. Without this the label can end up naming a point the pin left.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final GeoPoint? initial = widget.initial;
    _lat = initial?.latitude ?? _fallbackLat;
    _lng = initial?.longitude ?? _fallbackLng;
  }

  Future<void> _resolve(double lat, double lng) async {
    _lat = lat;
    _lng = lng;
    final int mine = ++_request;
    setState(() {
      _resolving = true;
      _error = null;
    });

    try {
      final Address found = await ref
          .read(deviceLocationServiceProvider)
          .addressAt(GeoPoint(lat, lng));
      if (!mounted || mine != _request) return;
      setState(() {
        _resolved = found;
        _resolving = false;
      });
    } on LocationFailure catch (failure) {
      if (!mounted || mine != _request) return;
      setState(() {
        // The point is still perfectly usable — we simply cannot name it. The
        // confirm button stays live and the coordinates go through, because a
        // rider can be sent to a pin the geocoder has no word for.
        _resolved = null;
        _error = failure.message;
        _resolving = false;
      });
    }
  }

  Future<void> _jumpToCurrentLocation() async {
    if (!await ensureLocationReady(context, ref)) return;
    if (!mounted) return;

    setState(() => _locating = true);
    try {
      final Address here = await ref
          .read(deviceLocationServiceProvider)
          .currentAddress();
      if (!mounted) return;
      // Moving the camera is enough: the picker reports its new centre on idle
      // and that runs the reverse-geocode through the ordinary path.
      await _picker.currentState?.moveTo(here.latitude, here.longitude);
    } on LocationFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Hands back the pin, named if we could name it.
  void _confirm() {
    final Address? resolved = _resolved;
    Navigator.of(context).pop(
      resolved ??
          // No name came back. The point is the answer that matters — the form
          // this returns to has text fields for the rest, and refusing to hand
          // back a perfectly good coordinate because the geocoder was quiet
          // would be the picker failing at its one job.
          Address(
            id: 'manual:$_lat,$_lng',
            line1: '',
            city: '',
            latitude: _lat,
            longitude: _lng,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Set delivery location')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                ZopiqPointPicker(
                  key: _picker,
                  initialLat: _lat,
                  initialLng: _lng,
                  onMoveStarted: () {
                    if (!_resolving) setState(() => _resolving = true);
                  },
                  onPointChanged: (double lat, double lng) =>
                      unawaited(_resolve(lat, lng)),
                ),
                // The instruction, over the map rather than under it, because
                // it describes the gesture the map is asking for.
                const Positioned(
                  top: ZopiqSpacing.md,
                  left: ZopiqSpacing.md,
                  right: ZopiqSpacing.md,
                  child: _Hint(text: 'Move the map to place the pin'),
                ),
                Positioned(
                  right: ZopiqSpacing.md,
                  bottom: ZopiqSpacing.md,
                  child: _LocateButton(
                    busy: _locating,
                    onPressed: () => unawaited(_jumpToCurrentLocation()),
                  ),
                ),
              ],
            ),
          ),

          // What is under the pin, and the way out.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'DELIVERING TO',
                    style: t.labelSmall?.copyWith(color: zc.textMuted),
                  ),
                  const SizedBox(height: ZopiqSpacing.xs),
                  // A fixed height, so the sheet does not jump every time a
                  // longer or shorter street name comes back.
                  SizedBox(
                    height: 44,
                    child: _PinLabel(
                      resolving: _resolving,
                      resolved: _resolved,
                      error: _error,
                    ),
                  ),
                  const SizedBox(height: ZopiqSpacing.md),
                  ZopiqButton(
                    label: 'Confirm location',
                    variant: ZopiqButtonVariant.cta,
                    expand: true,
                    // Live even when nothing could be named: the coordinates
                    // are the point of this screen. Held only while the map is
                    // actually in motion, where "here" has no settled meaning.
                    onPressed: _resolving ? null : _confirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The address under the pin — resolving, resolved, or unnameable.
class _PinLabel extends StatelessWidget {
  const _PinLabel({
    required this.resolving,
    required this.resolved,
    required this.error,
  });

  final bool resolving;
  final Address? resolved;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    if (resolving) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Finding this place…',
          style: t.bodyMedium?.copyWith(color: zc.textMuted),
        ),
      );
    }

    final Address? address = resolved;
    if (address == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          error ?? 'Drop the pin and add the details yourself.',
          style: t.bodySmall?.copyWith(color: zc.textMuted),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          address.line1,
          style: t.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (address.city.isNotEmpty)
          Text(
            address.city,
            style: t.bodySmall?.copyWith(color: zc.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: ZopiqRadii.rPill,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.md,
            vertical: ZopiqSpacing.xs,
          ),
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Use my current location',
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.my_location_rounded, color: zc.primary),
      ),
    );
  }
}
