import 'dart:convert';

import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/repositories/address_repository.dart';

class AddressRepositoryImpl implements AddressRepository {
  const AddressRepositoryImpl(this._store);

  final KeyValueStore _store;

  static const String _selectedKey = 'zopiq.location.selected_address';

  /// Stand-in for the user's saved addresses until the profile service exists.
  /// Coordinates are real Hyderabad points, so a distance calculation built on
  /// them in Step 6 gets a sane answer rather than a null island.
  static const List<Address> _seeded = <Address>[
    Address(
      id: 'home',
      label: 'Home',
      line1: 'Banjara Hills',
      city: 'Hyderabad',
      latitude: 17.4126,
      longitude: 78.4482,
    ),
    Address(
      id: 'work',
      label: 'Work',
      line1: 'HITEC City',
      city: 'Hyderabad',
      latitude: 17.4435,
      longitude: 78.3772,
    ),
  ];

  @override
  List<Address> savedAddresses() => _seeded;

  @override
  Address? selectedAddress() {
    final String? raw = _store.getString(_selectedKey);
    if (raw == null) return null;
    try {
      return Address.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Written by an older build with a different shape. Forget it rather than
      // crash Home on launch; the picker will ask again.
      return null;
    }
  }

  @override
  Future<void> selectAddress(Address address) =>
      _store.setString(_selectedKey, jsonEncode(address.toJson()));
}
