import 'package:zopiqnow/features/location/data/datasources/address_datasource.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/entities/delivery_area.dart';

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
    String? deliveryNotes,
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
      deliveryNotes: deliveryNotes,
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

  /// Always yes, and deliberately so.
  ///
  /// The boundary is a row per town in `service_areas` (0098, 0117) and the
  /// database is the only thing that knows them. A copy of the circles here
  /// would be a second source of truth that goes stale the first time somebody
  /// widens a radius — and the fixtures above are in Hyderabad, so a faithful
  /// mock would refuse every order in every test for a reason no test is about.
  ///
  /// Set [refuseDeliveryArea] to exercise the other branch.
  bool refuseDeliveryArea = false;

  @override
  Future<DeliveryAreaVerdict> checkDeliveryArea({
    required double latitude,
    required double longitude,
  }) async {
    await Future<void>.delayed(latency);
    return refuseDeliveryArea
        ? const DeliveryAreaVerdict(
            serviceable: false,
            headline: "We'll be there soon",
            detail:
                "We're not delivering to this address yet — we're still only "
                'in Falna, Ranakpur and Sadri.',
          )
        : const DeliveryAreaVerdict(
            serviceable: true,
            headline: 'We deliver here',
            detail: "You're inside our delivery area.",
          );
  }
}
