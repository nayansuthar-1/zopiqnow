import 'dart:convert';

import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/features/location/data/datasources/address_datasource.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/repositories/address_repository.dart';

/// Default [AddressRepository]: the saved list from the address service, the
/// selection from local storage.
///
/// It holds both seams because the two have to be kept in step, and this is the
/// only place that can do it — editing the selected address must rewrite the
/// local snapshot, and deleting it must clear it.
class AddressRepositoryImpl implements AddressRepository {
  const AddressRepositoryImpl(this._dataSource, this._store);

  final AddressDataSource _dataSource;
  final KeyValueStore _store;

  static const String _selectedKey = 'zopiq.location.selected_address';

  @override
  Future<List<Address>> savedAddresses() async {
    try {
      return await _dataSource.fetchAddresses();
    } on Object catch (_) {
      throw const AddressBookFailure();
    }
  }

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

  @override
  Future<Address> addAddress({
    required String line1,
    required String city,
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    try {
      return await _dataSource.insertAddress(
        line1: line1,
        city: city,
        latitude: latitude,
        longitude: longitude,
        label: label,
      );
    } on Object catch (_) {
      throw const AddressBookFailure('We couldn\'t save that address.');
    }
  }

  @override
  Future<Address> updateAddress(Address address) async {
    final Address saved;
    try {
      saved = await _dataSource.updateAddress(address);
    } on Object catch (_) {
      throw const AddressBookFailure('We couldn\'t save that address.');
    }

    // The selection is a *copy* of the address, taken when it was picked. Editing
    // the original has to rewrite it, or the Home header goes on rendering the
    // old text — and the next order ships to it.
    if (selectedAddress()?.id == saved.id) await selectAddress(saved);
    return saved;
  }

  @override
  Future<void> deleteAddress(String id) async {
    try {
      await _dataSource.deleteAddress(id);
    } on Object catch (_) {
      throw const AddressBookFailure('We couldn\'t delete that address.');
    }

    // A deleted address must not linger in the header, and must not quietly
    // become the delivery address of the next order.
    if (selectedAddress()?.id == id) await _store.remove(_selectedKey);
  }
}
