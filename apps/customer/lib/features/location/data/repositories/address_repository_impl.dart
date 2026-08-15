import 'dart:convert';

import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/features/location/data/datasources/address_datasource.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/entities/delivery_area.dart';
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

  /// Picking an address also settles which town it orders from (0126).
  ///
  /// Resolved **here**, and not wherever the catalogue is read, for two reasons.
  /// It is the one funnel every caller already goes through — the picker sheet,
  /// the map, "use my current location", and the re-select that follows an edit —
  /// so the town cannot be forgotten on one path. And it is written into the same
  /// JSON blob as the address itself, in one atomic write, so the stored town can
  /// never belong to a different door than the stored coordinates.
  ///
  /// A failed resolve stores the address with a null town rather than refusing
  /// the selection: choosing where to deliver must work on a bad connection, and
  /// null means "ask the server again", which is what the feed then does.
  @override
  Future<void> selectAddress(Address address) async {
    String? areaId;
    try {
      areaId = (await _dataSource.checkDeliveryArea(
        latitude: address.latitude,
        longitude: address.longitude,
      )).areaId;
    } on Object catch (_) {
      areaId = null;
    }
    await _store.setString(
      _selectedKey,
      jsonEncode(address.withServiceArea(areaId).toJson()),
    );
  }

  @override
  Future<Address> addAddress({
    required String line1,
    required String city,
    required double latitude,
    required double longitude,
    String? label,
    String? deliveryNotes,
  }) async {
    try {
      return await _dataSource.insertAddress(
        line1: line1,
        city: city,
        latitude: latitude,
        longitude: longitude,
        label: label,
        deliveryNotes: deliveryNotes,
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

  /// Fails **open**, unlike every other method here.
  ///
  /// The others throw [AddressBookFailure] and the screen shows it. This one
  /// cannot: it stands between a customer and the Pay button, and a dropped
  /// request would otherwise read as "we do not deliver to you" to somebody
  /// standing in Sadri. The boundary is enforced by a trigger on `orders`
  /// regardless of what this returns, so the cost of answering yes on a network
  /// error is a refusal one step later with the money not yet taken — and the
  /// cost of answering no is turning away an order we could have delivered.
  @override
  Future<DeliveryAreaVerdict> deliveryArea({
    required double latitude,
    required double longitude,
  }) async {
    try {
      return await _dataSource.checkDeliveryArea(
        latitude: latitude,
        longitude: longitude,
      );
    } on Object catch (_) {
      // `areaId` stays null, which is "not known" and not a town. Failing open
      // on *whether* we deliver is a considered risk the trigger covers; failing
      // open on *which town* would put another town's kitchens on the feed, and
      // there is no honest guess to make.
      return const DeliveryAreaVerdict(
        serviceable: true,
        headline: 'We deliver here',
        detail: "You're inside our delivery area.",
      );
    }
  }
}
