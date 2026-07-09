import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/features/location/data/repositories/address_repository_impl.dart';
import 'package:zopiqnow/features/location/data/services/geolocator_location_service.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/repositories/address_repository.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';

final Provider<AddressRepository> addressRepositoryProvider =
    Provider<AddressRepository>(
      (Ref ref) => AddressRepositoryImpl(ref.watch(keyValueStoreProvider)),
    );

/// Overridden in tests with a fake — the real one talks to GPS.
final Provider<DeviceLocationService> deviceLocationServiceProvider =
    Provider<DeviceLocationService>((Ref ref) => GeolocatorLocationService());

final Provider<List<Address>> savedAddressesProvider = Provider<List<Address>>(
  (Ref ref) => ref.watch(addressRepositoryProvider).savedAddresses(),
);

/// The delivery address shown in the Home header.
///
/// Null until the user picks one — Home renders "Set delivery location" rather
/// than inventing a default. Guessing a city is worse than asking.
class SelectedAddressController extends Notifier<Address?> {
  @override
  Address? build() => ref.watch(addressRepositoryProvider).selectedAddress();

  Future<void> select(Address address) async {
    await ref.read(addressRepositoryProvider).selectAddress(address);
    state = address;
  }

  /// Resolves GPS → address and selects it.
  ///
  /// Throws [LocationFailure]; the picker renders the message. Deliberately not
  /// an `AsyncValue` on this provider: a failed detect must leave the previously
  /// selected address on screen, not blank the header.
  Future<void> useCurrentLocation() async {
    final Address address = await ref
        .read(deviceLocationServiceProvider)
        .currentAddress();
    await select(address);
  }
}

final NotifierProvider<SelectedAddressController, Address?>
selectedAddressProvider = NotifierProvider<SelectedAddressController, Address?>(
  SelectedAddressController.new,
);
