import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/location/data/datasources/address_datasource.dart';
import 'package:zopiqnow/features/location/data/datasources/address_supabase_datasource.dart';
import 'package:zopiqnow/features/location/data/repositories/address_repository_impl.dart';
import 'package:zopiqnow/features/location/data/services/geolocator_location_service.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/entities/delivery_area.dart';
import 'package:zopiqnow/features/location/domain/repositories/address_repository.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';

/// Data source binding — Postgres, as of Step 7. Tests override it with
/// `AddressMockDataSource`, which carries the seeded Home/Work fixtures the
/// repository used to hand to every account in the app.
final Provider<AddressDataSource> addressDataSourceProvider =
    Provider<AddressDataSource>((Ref ref) => const AddressSupabaseDataSource());

final Provider<AddressRepository> addressRepositoryProvider =
    Provider<AddressRepository>(
      (Ref ref) => AddressRepositoryImpl(
        ref.watch(addressDataSourceProvider),
        ref.watch(keyValueStoreProvider),
      ),
    );

/// Overridden in tests with a fake — the real one talks to GPS.
final Provider<DeviceLocationService> deviceLocationServiceProvider =
    Provider<DeviceLocationService>((Ref ref) => GeolocatorLocationService());

/// Do we deliver to this point? (Migration 0098.)
///
/// Keyed on the coordinates rather than the address, so re-selecting the same
/// place does not re-ask and two addresses in the same courtyard share one
/// answer. A Dart record gives that structural equality for free.
///
/// `autoDispose` because the answer is only interesting while a screen is asking
/// — and because a widened radius should reach a customer who reopens checkout,
/// not be cached for the life of the process.
final AutoDisposeFutureProviderFamily<DeliveryAreaVerdict,
        ({double lat, double lng})>
    deliveryAreaProvider =
    FutureProvider.autoDispose
        .family<DeliveryAreaVerdict, ({double lat, double lng})>(
          (Ref ref, ({double lat, double lng}) point) => ref
              .watch(addressRepositoryProvider)
              .deliveryArea(latitude: point.lat, longitude: point.lng),
        );

/// Which town the customer is ordering from — `sadri`, `falna` (0126).
///
/// Null means **we do not know yet**, and every reader has to treat it as such:
/// no address chosen, an address outside every service area, or a resolve that
/// has not landed. It is never a town in its own right, which is why the catalog
/// providers refuse to fetch on null rather than fetching everything.
///
/// Two sources, in order. The selection carries its own town, written when the
/// address was picked, so the usual case is synchronous and survives a dead
/// connection — which matters, because the feed is served from disk in exactly
/// that state and would otherwise be filtered by nothing. The live check is the
/// fallback for a snapshot written by a build that predates the column.
final Provider<String?> currentAreaIdProvider = Provider<String?>((Ref ref) {
  final Address? address = ref.watch(selectedAddressProvider);
  if (address == null) return null;

  final String? stored = address.serviceAreaId;
  if (stored != null) return stored;

  return ref
      .watch(
        deliveryAreaProvider((lat: address.latitude, lng: address.longitude)),
      )
      .valueOrNull
      ?.areaId;
});

/// The signed-in customer's saved addresses.
///
/// Async now that the list is the account's rather than two constants everyone
/// shared. It watches the auth state, so signing in loads *your* addresses and
/// signing out empties the list instead of leaving the last account's home
/// address on screen.
final AutoDisposeFutureProvider<List<Address>> savedAddressesProvider =
    FutureProvider.autoDispose<List<Address>>((Ref ref) {
      ref.watch(authControllerProvider);
      return ref.watch(addressRepositoryProvider).savedAddresses();
    });

/// The delivery address shown in the Home header.
///
/// Null until the user picks one — Home renders "Set delivery location" rather
/// than inventing a default. Guessing a city is worse than asking.
///
/// Still synchronous, and still local: this is the *device's* choice of where to
/// deliver, and the header has to render it on the first frame without waiting
/// on a network call.
class SelectedAddressController extends Notifier<Address?> {
  @override
  Address? build() => ref.watch(addressRepositoryProvider).selectedAddress();

  Future<void> select(Address address) async {
    await ref.read(addressRepositoryProvider).selectAddress(address);
    state = address;
  }

  /// Re-reads the local selection after the address book has changed it: an edit
  /// rewrites the stored snapshot, and a delete clears it.
  void resyncFromStore() =>
      state = ref.read(addressRepositoryProvider).selectedAddress();

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

/// Writes to the address book: add, edit, delete.
///
/// State is whether a write is in flight — what the form's button renders. Reads
/// stay on [savedAddressesProvider], which every write invalidates: the server's
/// list is the truth, and re-fetching it is cheaper than keeping a second copy
/// of it correct.
class AddressBookController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<Address> add({
    required String line1,
    required String city,
    required double latitude,
    required double longitude,
    String? label,
    String? deliveryNotes,
  }) => _write(
    () => ref
        .read(addressRepositoryProvider)
        .addAddress(
          line1: line1,
          city: city,
          latitude: latitude,
          longitude: longitude,
          label: label,
          deliveryNotes: deliveryNotes,
        ),
  );

  Future<Address> update(Address address) =>
      _write(() => ref.read(addressRepositoryProvider).updateAddress(address));

  Future<void> delete(String id) =>
      _write(() => ref.read(addressRepositoryProvider).deleteAddress(id));

  /// Every write ends the same way: refresh the list, then re-read the local
  /// selection, because editing or deleting the selected address changes it.
  Future<T> _write<T>(Future<T> Function() action) async {
    state = true;
    try {
      final T result = await action();
      ref.invalidate(savedAddressesProvider);
      ref.read(selectedAddressProvider.notifier).resyncFromStore();
      return result;
    } finally {
      state = false;
    }
  }
}

final NotifierProvider<AddressBookController, bool>
addressBookControllerProvider =
    NotifierProvider<AddressBookController, bool>(AddressBookController.new);
