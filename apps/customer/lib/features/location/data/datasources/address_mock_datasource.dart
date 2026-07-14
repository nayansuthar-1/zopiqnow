import 'package:zopiqnow/features/location/data/datasources/address_datasource.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// In-memory address book — the tests' data source.
///
/// The two seeded addresses used to live in `AddressRepositoryImpl` as compile-
/// time constants, which meant *every account in the app shared them*. They are
/// fixtures, and this is where fixtures belong; the app itself now reads
/// [AddressSupabaseDataSource], where an address book is per-user and can
/// actually be added to.
class AddressMockDataSource implements AddressDataSource {
  AddressMockDataSource({
    this.latency = Duration.zero,
    List<Address>? seed,
  }) : _addresses = <Address>[...(seed ?? _seeded)];

  final Duration latency;
  final List<Address> _addresses;

  int _nextId = 0;

  /// Real Hyderabad points, so a distance calculation over them gets a sane
  /// answer rather than a null island.
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
  Future<List<Address>> fetchAddresses() async {
    await Future<void>.delayed(latency);
    return List<Address>.unmodifiable(_addresses);
  }

  @override
  Future<Address> insertAddress({
    required String line1,
    required String city,
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    await Future<void>.delayed(latency);
    // The id comes from the service, never from the caller — same as Postgres,
    // where it is a `gen_random_uuid()` default.
    final Address saved = Address(
      id: 'addr_${++_nextId}',
      label: label,
      line1: line1,
      city: city,
      latitude: latitude,
      longitude: longitude,
    );
    _addresses.add(saved);
    return saved;
  }

  @override
  Future<Address> updateAddress(Address address) async {
    await Future<void>.delayed(latency);
    final int i = _addresses.indexWhere((Address a) => a.id == address.id);
    if (i == -1) throw StateError('No such address: ${address.id}');
    _addresses[i] = address;
    return address;
  }

  @override
  Future<void> deleteAddress(String id) async {
    await Future<void>.delayed(latency);
    _addresses.removeWhere((Address a) => a.id == id);
  }
}
