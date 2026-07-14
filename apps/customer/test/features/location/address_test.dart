import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/location/data/datasources/address_mock_datasource.dart';
import 'package:zopiqnow/features/location/data/repositories/address_repository_impl.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/pages/address_book_page.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';

import '../../support/fake_auth_datasource.dart';
import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

const AuthUser _user = AuthUser(
  id: 'usr_1',
  email: 'diner@example.com',
  phone: '+919876543210',
);

const Address _gpsAddress = Address(
  id: 'gps',
  line1: 'Jubilee Hills',
  city: 'Hyderabad',
  latitude: 17.4239,
  longitude: 78.4738,
);

const GeoPoint _geocoded = GeoPoint(17.3850, 78.4867);

/// Stands in for GPS + geocoder. Returns [result], or throws [failure].
class FakeDeviceLocationService implements DeviceLocationService {
  FakeDeviceLocationService({this.result, this.failure, this.point});

  final Address? result;
  final LocationFailure? failure;

  /// What a forward geocode of typed text resolves to. Null makes the geocoder
  /// come up empty — the Play-services-less device, or an address it cannot find.
  final GeoPoint? point;

  @override
  Future<Address> currentAddress() async {
    if (failure != null) throw failure!;
    return result!;
  }

  @override
  Future<GeoPoint> coordinatesOf(String query) async {
    if (point == null) throw const AddressNotFound();
    return point!;
  }
}

Widget _app(ProviderContainer container) =>
    UncontrolledProviderScope(container: container, child: const ZopiqApp());

ProviderContainer _container({
  FakeKeyValueStore? keyValueStore,
  DeviceLocationService? locationService,
  AddressMockDataSource? addressDataSource,
  AuthState authState = const AuthSignedOut(),
}) => ProviderContainer(
  overrides: <Override>[
    ...storageOverrides(
      keyValueStore: keyValueStore,
      addressDataSource: addressDataSource,
      authState: authState,
      authDataSource: FakeAuthDataSource(
        signedInAs: authState is AuthSignedIn ? _user : null,
      ),
    ),
    restaurantDataSourceProvider.overrideWithValue(
      const RestaurantMockDataSource(latency: _latency),
    ),
    if (locationService != null)
      deviceLocationServiceProvider.overrideWithValue(locationService),
  ],
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 500));
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

AddressRepositoryImpl _repository(FakeKeyValueStore store) =>
    AddressRepositoryImpl(AddressMockDataSource(), store);

void main() {
  group('AddressRepositoryImpl', () {
    test('has no selection on a first run', () {
      expect(_repository(FakeKeyValueStore()).selectedAddress(), isNull);
    });

    test('a selected address survives a restart', () async {
      final FakeKeyValueStore store = FakeKeyValueStore();
      await _repository(store).selectAddress(_gpsAddress);

      // A fresh repository over the same store — i.e. the next app launch.
      final Address? restored = _repository(store).selectedAddress();
      expect(restored?.line1, 'Jubilee Hills');
      expect(restored?.latitude, closeTo(17.4239, 0.0001));
    });

    test('a corrupt stored address is ignored, not thrown', () {
      final FakeKeyValueStore store = FakeKeyValueStore(<String, String>{
        'zopiq.location.selected_address': '{"broken":true}',
      });
      expect(_repository(store).selectedAddress(), isNull);
    });

    test('shortDisplay omits the comma when the geocoder returns no city', () {
      const Address noCity = Address(
        id: 'gps',
        line1: 'Current location',
        city: '',
        latitude: 0,
        longitude: 0,
      );
      expect(noCity.shortDisplay, 'Current location');
    });

    test('editing the selected address rewrites what the header renders',
        () async {
      final FakeKeyValueStore store = FakeKeyValueStore();
      final AddressMockDataSource source = AddressMockDataSource();
      final AddressRepositoryImpl repository = AddressRepositoryImpl(
        source,
        store,
      );

      final List<Address> saved = await repository.savedAddresses();
      await repository.selectAddress(saved.first); // "Home", Banjara Hills

      await repository.updateAddress(
        Address(
          id: saved.first.id,
          label: 'Home',
          line1: 'Road No. 12, Banjara Hills',
          city: 'Hyderabad',
          latitude: 17.41,
          longitude: 78.44,
        ),
      );

      // The stored selection is a copy. If the edit did not rewrite it, the
      // header would keep showing the old text — and the next order would ship
      // to it.
      expect(
        repository.selectedAddress()?.line1,
        'Road No. 12, Banjara Hills',
      );
    });

    test('deleting the selected address clears the selection', () async {
      final FakeKeyValueStore store = FakeKeyValueStore();
      final AddressRepositoryImpl repository = AddressRepositoryImpl(
        AddressMockDataSource(),
        store,
      );

      final List<Address> saved = await repository.savedAddresses();
      await repository.selectAddress(saved.first);
      await repository.deleteAddress(saved.first.id);

      // Not merely absent from the list: gone from the header too. A deleted
      // address must not quietly become the next order's delivery address.
      expect(repository.selectedAddress(), isNull);
      expect(await repository.savedAddresses(), hasLength(1));
    });

    test('deleting an address the user is not delivering to leaves the '
        'selection alone', () async {
      final FakeKeyValueStore store = FakeKeyValueStore();
      final AddressRepositoryImpl repository = AddressRepositoryImpl(
        AddressMockDataSource(),
        store,
      );

      final List<Address> saved = await repository.savedAddresses();
      await repository.selectAddress(saved.first); // Home
      await repository.deleteAddress(saved.last.id); // Work

      expect(repository.selectedAddress()?.label, 'Home');
    });
  });

  group('Home header', () {
    testWidgets('prompts for a location when none is selected', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);

      expect(find.text('Set delivery location'), findsOneWidget);
      // The old hardcoded value must be gone for good.
      expect(find.text('Banjara Hills, Hyderabad'), findsNothing);
    });

    testWidgets('shows the persisted address on launch', (
      WidgetTester tester,
    ) async {
      final FakeKeyValueStore store = FakeKeyValueStore();
      await _repository(store).selectAddress(_gpsAddress);

      final ProviderContainer container = _container(keyValueStore: store);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);

      expect(find.text('Jubilee Hills, Hyderabad'), findsOneWidget);
    });
  });

  group('address picker', () {
    testWidgets('picking a saved address updates the header', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);

      await tester.tap(find.text('Set delivery location'));
      await _settle(tester);

      expect(find.text('Select delivery location'), findsOneWidget);
      await tester.tap(find.text('Work'));
      await _settle(tester);

      expect(find.text('HITEC City, Hyderabad'), findsOneWidget);
    });

    testWidgets('"use my current location" resolves GPS into the header', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = _container(
        locationService: FakeDeviceLocationService(result: _gpsAddress),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await tester.tap(find.text('Set delivery location'));
      await _settle(tester);

      await tester.tap(find.text('Use my current location'));
      await _settle(tester);

      expect(find.text('Jubilee Hills, Hyderabad'), findsOneWidget);
    });

    testWidgets('a denied permission shows the reason and keeps the sheet open', (
      WidgetTester tester,
    ) async {
      final FakeKeyValueStore store = FakeKeyValueStore();
      await _repository(store).selectAddress(_gpsAddress);

      final ProviderContainer container = _container(
        keyValueStore: store,
        locationService: FakeDeviceLocationService(
          failure: const LocationPermissionDeniedForever(),
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await tester.tap(find.text('Jubilee Hills, Hyderabad'));
      await _settle(tester);

      await tester.tap(find.text('Use my current location'));
      await _settle(tester);

      expect(
        find.text('Location is blocked. Enable it in app settings.'),
        findsOneWidget,
      );
      // The previously selected address is untouched — a failed detect must not
      // blank the header.
      expect(container.read(selectedAddressProvider)?.line1, 'Jubilee Hills');
    });
  });

  group('address book', () {
    /// Home → profile → "Address book".
    Future<void> openBook(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.person_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Address book'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressBookPage), findsOneWidget);
    }

    testWidgets('lists the account\'s saved addresses', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container(
        authState: const AuthSignedIn(_user),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await openBook(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Banjara Hills, Hyderabad'), findsOneWidget);
    });

    testWidgets('a typed address is geocoded and saved', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container(
        authState: const AuthSignedIn(_user),
        // No GPS was used, so the point can only come from a forward geocode of
        // what was typed — which is what lets someone save their office address
        // from their sofa.
        locationService: FakeDeviceLocationService(point: _geocoded),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await openBook(tester);

      await tester.tap(find.text('Add address'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Flat / building / street'),
        'Flat 402, Cyber Towers',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'City'),
        'Hyderabad',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Save as (optional)'),
        'Office',
      );
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();

      // Back on the book, with the new address on it.
      expect(find.byType(AddressBookPage), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('Flat 402, Cyber Towers, Hyderabad'), findsOneWidget);

      final List<Address> saved = await container.read(
        savedAddressesProvider.future,
      );
      final Address office = saved.firstWhere((Address a) => a.label == 'Office');
      expect(office.latitude, closeTo(17.3850, 0.0001));
    });

    testWidgets('an address the geocoder cannot place is refused, not saved '
        'without a point', (WidgetTester tester) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container(
        authState: const AuthSignedIn(_user),
        // The geocoder finds nothing — a device with no Play services, or text
        // that matches no place.
        locationService: FakeDeviceLocationService(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await openBook(tester);

      await tester.tap(find.text('Add address'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Flat / building / street'),
        'Somewhere unfindable',
      );
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();

      // Still on the form, told why. Guessing a point is how food goes to the
      // wrong end of the city.
      expect(
        find.textContaining('couldn\'t place that address'),
        findsOneWidget,
      );
      expect(await container.read(savedAddressesProvider.future), hasLength(2));
    });

    testWidgets('deleting an address asks first, then removes it', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container(
        authState: const AuthSignedIn(_user),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await openBook(tester);

      await tester.tap(find.byTooltip('Delete address').first);
      await tester.pumpAndSettle();

      expect(find.text('Delete this address?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsNothing);
      expect(find.text('Work'), findsOneWidget);
    });
  });
}
