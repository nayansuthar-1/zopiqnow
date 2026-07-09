import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/location/data/repositories/address_repository_impl.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';

import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

const Address _gpsAddress = Address(
  id: 'gps',
  line1: 'Jubilee Hills',
  city: 'Hyderabad',
  latitude: 17.4239,
  longitude: 78.4738,
);

/// Stands in for GPS + geocoder. Returns [result], or throws [failure].
class FakeDeviceLocationService implements DeviceLocationService {
  FakeDeviceLocationService({this.result, this.failure});

  final Address? result;
  final LocationFailure? failure;

  @override
  Future<Address> currentAddress() async {
    if (failure != null) throw failure!;
    return result!;
  }
}

Widget _app(ProviderContainer container) =>
    UncontrolledProviderScope(container: container, child: const ZopiqApp());

ProviderContainer _container({
  FakeKeyValueStore? keyValueStore,
  DeviceLocationService? locationService,
}) => ProviderContainer(
  overrides: <Override>[
    ...storageOverrides(keyValueStore: keyValueStore),
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

void main() {
  group('AddressRepositoryImpl', () {
    test('has no selection on a first run', () {
      expect(
        AddressRepositoryImpl(FakeKeyValueStore()).selectedAddress(),
        isNull,
      );
    });

    test('a selected address survives a restart', () async {
      final FakeKeyValueStore store = FakeKeyValueStore();
      await AddressRepositoryImpl(store).selectAddress(_gpsAddress);

      // A fresh repository over the same store — i.e. the next app launch.
      final Address? restored = AddressRepositoryImpl(store).selectedAddress();
      expect(restored?.line1, 'Jubilee Hills');
      expect(restored?.latitude, closeTo(17.4239, 0.0001));
    });

    test('a corrupt stored address is ignored, not thrown', () {
      final FakeKeyValueStore store = FakeKeyValueStore(<String, String>{
        'zopiq.location.selected_address': '{"broken":true}',
      });
      expect(AddressRepositoryImpl(store).selectedAddress(), isNull);
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
      await AddressRepositoryImpl(store).selectAddress(_gpsAddress);

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
      await AddressRepositoryImpl(store).selectAddress(_gpsAddress);

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
}
