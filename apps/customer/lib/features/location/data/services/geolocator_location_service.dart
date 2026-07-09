import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';

/// GPS via `geolocator`, reverse-geocode via Android's **native** `Geocoder`
/// (`geocoding`). No Maps API key, no billing — Google Places autocomplete
/// arrives with the backend (SAD 14).
class GeolocatorLocationService implements DeviceLocationService {
  GeolocatorLocationService({Geocoding? geocoding})
    : _geocoding = geocoding ?? Geocoding();

  final Geocoding _geocoding;

  /// `medium` (PRIORITY_BALANCED_POWER_ACCURACY), not `best`. A delivery
  /// address is a building, not a doorstep: block-level accuracy is enough and
  /// it spares the GPS radio on the 3GB-RAM floor device (Rule 1.8).
  static const LocationSettings _settings = LocationSettings(
    accuracy: LocationAccuracy.medium,
    timeLimit: Duration(seconds: 15),
  );

  @override
  Future<Address> currentAddress() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabled();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      // `unableToDetermine` is the web/unknown case. Treated as denied: without
      // a positive grant we must not touch the GPS.
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        throw const LocationPermissionDenied();
      case LocationPermission.deniedForever:
        throw const LocationPermissionDeniedForever();
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }

    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: _settings,
    );

    // Rule 1.1 capability check: Android devices without Play services ship no
    // Geocoder, and calling it there throws rather than returning empty. We
    // still have coordinates, so this degrades instead of failing outright.
    if (!await _geocoding.isPresent()) throw const AddressNotFound();

    final List<Placemark> places = await _geocoding.placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    if (places.isEmpty) throw const AddressNotFound();

    return _toAddress(places.first, position);
  }

  static Address _toAddress(Placemark p, Position position) {
    // Indian addresses put the neighbourhood in `subLocality` ("Banjara Hills")
    // and the city in `locality` ("Hyderabad"). Fall back down the hierarchy
    // rather than render an empty line.
    final String line1 =
        _firstNonEmpty(<String?>[
          p.subLocality,
          p.thoroughfare,
          p.name,
          p.locality,
        ]) ??
        'Current location';
    final String city =
        _firstNonEmpty(<String?>[
          p.locality,
          p.subAdministrativeArea,
          p.administrativeArea,
        ]) ??
        '';

    return Address(
      id: 'gps',
      line1: line1,
      city: city,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final String? c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }
}
