import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// The customer's address book, plus which address is currently selected.
///
/// Two different kinds of state, deliberately behind one contract because the UI
/// treats them as one thing:
///
/// * **The saved list is the account's.** It lives in Postgres, scoped to
///   `auth.uid()`, and follows the customer to a new phone.
/// * **The selection is the device's.** Which address *this* phone is ordering
///   to is not a fact about the account — the same customer can be at home on
///   one device and at the office on another — so it stays in local storage and
///   needs no network to read on launch.
abstract interface class AddressRepository {
  /// The signed-in customer's saved addresses. Empty when signed out: an address
  /// book belongs to an account, and having none is not an error.
  ///
  /// Throws [AddressBookFailure] on a transport error.
  Future<List<Address>> savedAddresses();

  /// The address the user last chose on this device, or null on a first run.
  /// Local and synchronous — the Home header must render on the first frame.
  Address? selectedAddress();

  Future<void> selectAddress(Address address);

  /// Saves a new address and returns it with the id the server assigned.
  ///
  /// Coordinates are required, not optional: an address the dispatcher cannot
  /// put on a map is not a delivery address. The caller resolves them (GPS, or a
  /// forward geocode of what was typed) before it gets here.
  Future<Address> addAddress({
    required String line1,
    required String city,
    required double latitude,
    required double longitude,
    String? label,
  });

  /// Edits a saved address. If it is the one selected on this device, the
  /// selection is updated too — otherwise the Home header would go on showing
  /// the old text until the user happened to pick it again.
  Future<Address> updateAddress(Address address);

  /// Deletes a saved address. If it was selected, the selection is cleared: an
  /// address the customer has deleted must not stay in the header, and must not
  /// quietly become the delivery address of the next order.
  ///
  /// Past orders are unaffected — an order stores the address it shipped to.
  Future<void> deleteAddress(String id);
}

/// Domain-level failure for reading or writing the address book.
class AddressBookFailure implements Exception {
  const AddressBookFailure([
    this.message = 'We couldn\'t reach your saved addresses. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'AddressBookFailure: $message';
}
