import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Resolves the device's current position to a human-readable [Address].
///
/// An interface, not a static call to `Geolocator`, so the picker can be tested
/// without a platform channel and so the reverse-geocoder can be swapped for
/// Google Geocoding (SAD 14) without touching the UI.
abstract interface class DeviceLocationService {
  /// Throws a [LocationFailure] subtype for every condition the UI must render
  /// differently: service off, permission denied, permanently denied, or no
  /// address for the coordinates.
  Future<Address> currentAddress();
}

sealed class LocationFailure implements Exception {
  const LocationFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Location services are switched off device-wide. Actionable: open settings.
class LocationServiceDisabled extends LocationFailure {
  const LocationServiceDisabled([
    super.message = 'Turn on location services to detect your address.',
  ]);
}

class LocationPermissionDenied extends LocationFailure {
  const LocationPermissionDenied([
    super.message = 'Allow location access to detect your address.',
  ]);
}

/// Denied with "don't ask again". The system dialog will never appear again, so
/// the only path forward is app settings — the UI must say so, not re-prompt.
class LocationPermissionDeniedForever extends LocationFailure {
  const LocationPermissionDeniedForever([
    super.message = 'Location is blocked. Enable it in app settings.',
  ]);
}

/// Coordinates resolved, but no street address came back — the geocoder is
/// missing (a device with no Play services) or the point is in the sea.
class AddressNotFound extends LocationFailure {
  const AddressNotFound([
    super.message = 'We couldn\'t find an address here. Pick one manually.',
  ]);
}
