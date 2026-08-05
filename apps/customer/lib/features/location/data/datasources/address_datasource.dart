import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/entities/delivery_area.dart';

/// The address-book contract, implemented by the mock and by Supabase.
///
/// No user id anywhere. `auth.uid()` says whose addresses these are, through the
/// row-level policies on `addresses` — a client that could name the owner could
/// read, or write, someone else's home address.
abstract interface class AddressDataSource {
  Future<List<Address>> fetchAddresses();

  /// Returns the address with the id the server assigned.
  Future<Address> insertAddress({
    required String line1,
    required String city,
    required double latitude,
    required double longitude,
    String? label,
    String? deliveryNotes,
  });

  Future<Address> updateAddress(Address address);

  Future<void> deleteAddress(String id);

  /// Whether we deliver to a point, with the wording to show if we do not.
  ///
  /// Asked before the gateway runs, never after: an order refused at insert is
  /// a customer who has already paid. See [DeliveryAreaVerdict].
  Future<DeliveryAreaVerdict> checkDeliveryArea({
    required double latitude,
    required double longitude,
  });
}
