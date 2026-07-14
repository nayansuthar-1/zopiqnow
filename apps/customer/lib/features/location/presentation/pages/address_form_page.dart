import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/repositories/address_repository.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';

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
    super.dispose();
  }

  static String _query(String line1, String city) => '$line1, $city';

  Future<void> _useCurrentLocation() async {
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(borderRadius: ZopiqRadii.rMd),
      ),
    );
  }
}
