import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as service_dialog;

import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';

/// GPS via `geolocator`, reverse-geocode via Android's **native** `Geocoder`
/// (`geocoding`). No Maps API key, no billing — Google Places autocomplete
/// arrives with the backend (SAD 14).
///
/// **Why a second location plugin.** [requestService] — and nothing else — comes
/// from the `location` package, aliased `service_dialog` so no reader has to
/// wonder which library a call belongs to. geolocator cannot switch location
/// services on; the furthest it goes is `openLocationSettings()`, which throws
/// the customer out to Android Settings, and being ejected from the app is where
/// a location prompt gets abandoned. `location` wraps the Play Services dialog
/// that flips the setting in place.
///
/// Every *coordinate* still comes from geolocator. The two plugins are kept from
/// disagreeing about where the device is by never asking the second one.
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
  Future<bool> needsPermissionPrompt() async {
    // `denied` is "not decided yet", which is the only state where the system
    // dialog still appears. `deniedForever` never shows it again, and the two
    // granted states have no reason to. `unableToDetermine` is the unknown case
    // and is treated as a prompt: an extra disclosure costs a tap, a missing one
    // costs a review cycle.
    final LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine;
  }

  @override
  Future<LocationReadiness> readiness() async {
    // Services first, and the order is not arbitrary: with location switched off
    // device-wide, a granted permission buys nothing, and asking the customer to
    // re-grant a permission they already gave would be the wrong instruction.
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadiness.serviceOff;
    }

    final LocationPermission permission = await Geolocator.checkPermission();
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationReadiness.ready,
      LocationPermission.deniedForever => LocationReadiness.permissionBlocked,
      // `unableToDetermine` is the unknown case, treated as "not granted" — the
      // same call `currentAddress` makes. Without a positive grant we must not
      // touch the GPS, and offering the ask is the recoverable answer.
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationReadiness.permissionDenied,
    };
  }

  @override
  Future<ServiceRequestOutcome> requestService() async {
    final service_dialog.Location location = service_dialog.Location();
    try {
      if (await location.serviceEnabled()) return ServiceRequestOutcome.enabled;
      return await location.requestService()
          ? ServiceRequestOutcome.enabled
          : ServiceRequestOutcome.declined;
    } on Object {
      // iOS has no in-app way to turn location services on, and an Android
      // build without Play Services has no dialog to show either — both surface
      // as a throw from the platform channel. Neither is worth an error message,
      // but both mean the caller must offer the settings screen instead of
      // treating this as a refusal.
      return ServiceRequestOutcome.unavailable;
    }
  }

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

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

    return _toAddress(
      places.first,
      id: 'gps',
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  @override
  Future<GeoPoint> coordinatesOf(String query) async {
    // Same capability check as the reverse path, and the same reason: a device
    // with no Play services has no Geocoder at all, and calling it there throws
    // rather than returning empty (Rule 1.1).
    if (!await _geocoding.isPresent()) throw const AddressNotFound();

    final List<Location> matches = await _geocoding.locationFromAddress(query);
    if (matches.isEmpty) throw const AddressNotFound();

    // The first match. The geocoder ranks by relevance and we have no map for
    // the customer to disambiguate on — offering them a list of five points they
    // cannot see would be a worse lie than taking the best guess and letting
    // them correct the text.
    final Location best = matches.first;
    return GeoPoint(best.latitude, best.longitude);
  }

  @override
  Future<Address> addressAt(GeoPoint point) async {
    // The same capability check the other two make: no Play services means no
    // Geocoder, and calling it there throws rather than returning empty.
    if (!await _geocoding.isPresent()) throw const AddressNotFound();

    final List<Placemark> places = await _geocoding.placemarkFromCoordinates(
      point.latitude,
      point.longitude,
    );
    if (places.isEmpty) throw const AddressNotFound();

    return _toAddress(
      places.first,
      // 'manual:' — the same id the search path mints, and for the same reason:
      // it marks a place the customer chose rather than one they saved, and the
      // coordinates keep two different choices from colliding.
      id: 'manual:${point.latitude},${point.longitude}',
      latitude: point.latitude,
      longitude: point.longitude,
    );
  }

  @override
  Future<List<Address>> searchPlaces(String query, {int limit = 5}) async {
    final String text = query.trim();
    if (text.isEmpty) return const <Address>[];
    // No Geocoder on this device (no Play services). Nothing to search with, and
    // an empty list is the honest answer — the sheet says "no matches" and the
    // saved addresses above it still work.
    if (!await _geocoding.isPresent()) return const <Address>[];

    final List<Location> matches;
    try {
      matches = await _geocoding.locationFromAddress(text);
    } on Object {
      // The native Geocoder throws on half-typed text as readily as it returns
      // nothing. Both mean the same thing to somebody still typing.
      return const <Address>[];
    }

    final List<Address> places = <Address>[];
    for (final Location match in matches.take(limit)) {
      final List<Placemark> named;
      try {
        named = await _geocoding.placemarkFromCoordinates(
          match.latitude,
          match.longitude,
        );
      } on Object {
        continue;
      }
      if (named.isEmpty) continue;

      places.add(
        _toAddress(
          named.first,
          // The id is what tells the rest of the app this is a picked place and
          // not a saved one — the same trick the GPS path plays with 'gps'.
          // Coordinates make it unique, so two searches for different places
          // cannot collide in the selected-address store.
          id: 'manual:${match.latitude},${match.longitude}',
          latitude: match.latitude,
          longitude: match.longitude,
        ),
      );
    }
    return places;
  }

  /// A named place from a placemark and the point it was resolved at.
  ///
  /// The point comes in rather than being read off a [Position], because the two
  /// callers hold different things: the GPS path has a fix, and the search path
  /// has a geocoder match. Both have a latitude and a longitude, which is all
  /// this ever wanted.
  static Address _toAddress(
    Placemark p, {
    required String id,
    required double latitude,
    required double longitude,
  }) {
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
      id: id,
      line1: line1,
      city: city,
      latitude: latitude,
      longitude: longitude,
    );
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final String? c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }
}
