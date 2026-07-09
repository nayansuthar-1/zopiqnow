import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Saved addresses + which one is currently selected.
///
/// The saved list is mock today (the real one is per-user, server-side). The
/// *selection* is genuinely local, and stays local even after Step 7 — it is
/// device state, not account state.
abstract interface class AddressRepository {
  List<Address> savedAddresses();

  /// The address the user last chose, or null on a first run.
  Address? selectedAddress();

  Future<void> selectAddress(Address address);
}
