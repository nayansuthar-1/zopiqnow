import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_map/zopiq_map.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/pages/address_map_page.dart';
import 'package:zopiqnow/features/location/domain/repositories/address_repository.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/location_disclosure.dart';

/// Add or edit one saved address.
///
/// The interesting problem here is not the form, it is the **coordinates**. An
/// address the dispatcher cannot put on a map is not a delivery address, so the
/// table requires a lat/lng — but the customer types words, not points. Three
/// sources, in this order:
///
/// 1. **The point already attached to the typed text.** From GPS ("use my
///    current location"), or from the address being edited. Exact, and reused
///    whenever the text has not changed — re-geocoding "Flat 402, Banjara Hills"
///    would throw away a real GPS fix for the centroid of a whole neighbourhood.
/// 2. **A forward geocode of the typed text**, when the text *has* changed. This
///    is what lets someone save their office address from their sofa; GPS only
///    ever answers "where am I", which is the wrong question for an address book.
/// 3. **Nothing** — and then the form refuses to save, and says why. Guessing a
///    point is how food goes to the wrong end of the city.
class AddressFormPage extends ConsumerStatefulWidget {
  const AddressFormPage({this.existing, super.key});

  /// The address being edited, or null when adding a new one.
  final Address? existing;

  @override
  ConsumerState<AddressFormPage> createState() => _AddressFormPageState();
}

class _AddressFormPageState extends ConsumerState<AddressFormPage> {
  late final TextEditingController _line1;
  late final TextEditingController _city;
  late final TextEditingController _label;
  late final TextEditingController _notes;

  /// The point we hold, and the text it describes. Kept together because the
  /// pair is the whole question: a point is only valid for the text it came from.
  GeoPoint? _point;
  String? _pointText;

  bool _detecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Address? existing = widget.existing;
    _line1 = TextEditingController(text: existing?.line1 ?? '');
    _city = TextEditingController(text: existing?.city ?? '');
    _label = TextEditingController(text: existing?.label ?? '');
    _notes = TextEditingController(text: existing?.deliveryNotes ?? '');
    if (existing != null) {
      _point = GeoPoint(existing.latitude, existing.longitude);
      _pointText = _query(existing.line1, existing.city);
    }
  }

  @override
  void dispose() {
    _line1.dispose();
    _city.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String _query(String line1, String city) => '$line1, $city';

  Future<void> _useCurrentLocation() async {
    // See the picker sheet: Play's prominent disclosure goes immediately before
    // the system dialog, and declining is silent.
    if (await ref.read(deviceLocationServiceProvider).needsPermissionPrompt()) {
      if (!mounted) return;
      if (!await showLocationDisclosure(context)) return;
    }
    if (!mounted) return;

    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      final Address found = await ref
          .read(deviceLocationServiceProvider)
          .currentAddress();
      if (!mounted) return;
      setState(() {
        _line1.text = found.line1;
        _city.text = found.city;
        _point = GeoPoint(found.latitude, found.longitude);
        _pointText = _query(found.line1, found.city);
        _detecting = false;
      });
    } on LocationFailure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.message;
          _detecting = false;
        });
      }
    }
  }

  /// Source 1b — the map.
  ///
  /// Between "here" and "these words" there was a gap: a customer who is not
  /// standing at the address, whose lane the geocoder has never heard of, and
  /// who can see their own roof on a map. The pin closes it, and it is the
  /// strongest of the three sources — the customer looked at the ground and
  /// pointed at it.
  ///
  /// The text fields are filled from the pin only where the pin has something
  /// to say and the field is empty or came from an earlier pin. Typed words are
  /// never overwritten: somebody who wrote "Flat 402, blue gate" and then
  /// adjusted the pin means both, and replacing their flat number with a street
  /// name would throw away the half only they know.
  Future<void> _pickOnMap() async {
    final Address? picked = await showAddressMapPicker(context, initial: _point);
    if (picked == null || !mounted) return;

    setState(() {
      _error = null;
      if (picked.line1.isNotEmpty && _line1.text.trim().isEmpty) {
        _line1.text = picked.line1;
      }
      if (picked.city.isNotEmpty) _city.text = picked.city;
      _point = GeoPoint(picked.latitude, picked.longitude);
      // The pin is now the authority for these words, whatever they say — so
      // `_resolvePoint` keeps it instead of re-geocoding the text over the top.
      _pointText = _query(_line1.text.trim(), _city.text.trim());
    });
  }

  /// Source 1, then source 2, then give up (source 3).
  Future<GeoPoint?> _resolvePoint(String line1, String city) async {
    final String text = _query(line1, city);
    if (_point != null && _pointText == text) return _point;

    try {
      return await ref.read(deviceLocationServiceProvider).coordinatesOf(text);
    } on LocationFailure {
      // The geocoder is missing or matched nothing. A stale point is still a
      // point in roughly the right place — better than refusing to save an
      // address whose *text* the rider can read perfectly well.
      return _point;
    }
  }

  Future<void> _save() async {
    final String line1 = _line1.text.trim();
    final String city = _city.text.trim();
    final String label = _label.text.trim();
    final String notes = _notes.text.trim();

    if (line1.isEmpty) {
      setState(() => _error = 'Add the flat, building, or street.');
      return;
    }

    setState(() => _error = null);

    final GeoPoint? point = await _resolvePoint(line1, city);
    if (!mounted) return;
    if (point == null) {
      setState(
        () => _error =
            'We couldn\'t place that address on the map. Try "Use my current '
            'location", or add the city.',
      );
      return;
    }

    final AddressBookController book = ref.read(
      addressBookControllerProvider.notifier,
    );
    try {
      final Address? existing = widget.existing;
      if (existing == null) {
        await book.add(
          line1: line1,
          city: city,
          latitude: point.latitude,
          longitude: point.longitude,
          label: label.isEmpty ? null : label,
          deliveryNotes: notes.isEmpty ? null : notes,
        );
      } else {
        await book.update(
          Address(
            id: existing.id,
            label: label.isEmpty ? null : label,
            line1: line1,
            city: city,
            latitude: point.latitude,
            longitude: point.longitude,
            deliveryNotes: notes.isEmpty ? null : notes,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on AddressBookFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool saving = ref.watch(addressBookControllerProvider);
    final bool isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit address' : 'Add address'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
        children: <Widget>[
          // The point, before the words. It is the part of this form the
          // customer cannot type and the part the rider actually needs.
          _MapCard(point: _point, onTap: _pickOnMap),
          const SizedBox(height: ZopiqSpacing.md),
          ZopiqButton(
            label: 'Use my current location',
            icon: Icons.my_location_rounded,
            variant: ZopiqButtonVariant.outline,
            isLoading: _detecting,
            onPressed: _useCurrentLocation,
          ),
          const SizedBox(height: ZopiqSpacing.lg),

          _Field(
            controller: _line1,
            label: 'Flat / building / street',
            hint: 'Flat 402, Cyber Towers',
            autofocus: !isEdit,
          ),
          const SizedBox(height: ZopiqSpacing.md),
          _Field(
            controller: _city,
            label: 'City',
            hint: 'Hyderabad',
          ),
          const SizedBox(height: ZopiqSpacing.md),
          _Field(
            controller: _label,
            label: 'Save as (optional)',
            hint: 'Home, Work, Mum\'s place',
          ),
          const SizedBox(height: ZopiqSpacing.md),
          // Typed once and reused on every order to this door — checkout
          // prefills it and still lets tonight's order say something different.
          // Capped where the column is (0061): a note a rider does not read at
          // the gate is worse than no note.
          _Field(
            controller: _notes,
            label: 'Note for the rider (optional)',
            hint: 'Gate 2, blue building. Ring twice.',
            maxLength: 160,
            capitalizeSentences: true,
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.md),
            Text(_error!, style: t.bodySmall?.copyWith(color: zc.nonVeg)),
          ],

          const SizedBox(height: ZopiqSpacing.xl),
          ZopiqButton(
            label: isEdit ? 'Save changes' : 'Save address',
            variant: ZopiqButtonVariant.cta,
            isLoading: saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// The pin, shown as a small still map, or an invitation to place one.
///
/// Not interactive: a map that claimed drags inside this `ListView` would eat
/// the scroll, which is the same reason [ZopiqMapView] has an `interactive`
/// flag at all. It is a picture and a button — the real map is the full screen
/// this opens.
class _MapCard extends StatelessWidget {
  const _MapCard({required this.point, required this.onTap});

  final GeoPoint? point;
  final Future<void> Function() onTap;

  static const double _height = 140;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final GeoPoint? p = point;

    return SizedBox(
      height: _height,
      child: Material(
        color: zc.primary.withValues(alpha: 0.06),
        borderRadius: ZopiqRadii.rLg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(onTap()),
          child: p == null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.map_outlined, color: zc.primary),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Text(
                      'Set location on map',
                      style: t.titleSmall?.copyWith(color: zc.primary),
                    ),
                  ],
                )
              : Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ZopiqMapView(
                        interactive: false,
                        pins: <ZopiqMapPin>[
                          ZopiqMapPin(
                            id: 'address',
                            lat: p.latitude,
                            lng: p.longitude,
                            kind: ZopiqPinKind.customer,
                          ),
                        ],
                      ),
                    ),
                    // The whole card is the button, so the map must not take
                    // the tap that opens the real one.
                    Positioned.fill(
                      child: InkWell(onTap: () => unawaited(onTap())),
                    ),
                    Positioned(
                      right: ZopiqSpacing.sm,
                      top: ZopiqSpacing.sm,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: ZopiqRadii.rPill,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZopiqSpacing.sm,
                            vertical: 4,
                          ),
                          child: Text(
                            'Change',
                            style: t.labelMedium?.copyWith(color: zc.primary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.autofocus = false,
    this.maxLength,
    this.capitalizeSentences = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool autofocus;

  /// Set only on the rider note, where the column has a limit (0061) and the
  /// counter is the honest way to show it.
  final int? maxLength;

  /// A note is a sentence; an address line is a set of proper nouns.
  final bool capitalizeSentences;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLength: maxLength,
      maxLines: capitalizeSentences ? 2 : 1,
      textCapitalization: capitalizeSentences
          ? TextCapitalization.sentences
          : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(borderRadius: ZopiqRadii.rMd),
      ),
    );
  }
}
