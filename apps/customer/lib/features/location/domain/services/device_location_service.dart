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

  /// Forward-geocodes typed text ("Banjara Hills, Hyderabad") to a point.
  ///
  /// This is what lets a customer save their office address from their sofa. GPS
  /// only ever answers "where am I", which is the wrong question for an address
  /// book — the one address you cannot add that way is the one you are not
  /// standing in.
  ///
  /// Throws [AddressNotFound] when the geocoder is missing (a device with no
  /// Play services) or the text matches nothing.
  Future<GeoPoint> coordinatesOf(String query);

  /// Typed text → a short list of named, selectable places.
  ///
  /// [coordinatesOf] answers "where is that text" with a bare point, which is
  /// all the address *form* needs — the customer already typed the words, so
  /// there is nothing to show them back. A search list is the other case: the
  /// customer is choosing, and a row reading `17.4239, 78.4738` is not a choice
  /// anyone can make. So each match is reverse-geocoded back into a name.
  ///
  /// Returns empty rather than throwing when nothing matches. A search that
  /// finds nothing is a normal thing for a search to do, and half-typed text
  /// finds nothing constantly.
  Future<List<Address>> searchPlaces(String query, {int limit = 5});

  /// Whether calling [currentAddress] would put the *system* location dialog on
  /// screen.
  ///
  /// Exists so the UI can show Play's required prominent disclosure immediately
  /// before that dialog and at no other time. Granted and permanently-denied
  /// both answer false: one needs no explanation and the other will never see
  /// the dialog again, so a disclosure in front of either is a sheet arguing
  /// with a decision the customer has already made.
  Future<bool> needsPermissionPrompt();

  /// What, if anything, is standing between us and a location right now.
  ///
  /// Asked *before* doing anything, so the UI can lead with the fix rather than
  /// attempt a detect and report a failure. [currentAddress] still throws for
  /// each of these — it is the authority — but "why can't we?" and "we tried and
  /// couldn't" are different questions, and only the first one can be answered
  /// without touching the GPS.
  Future<LocationReadiness> readiness();

  /// Asks the OS to switch location services on **without leaving the app**.
  ///
  /// On Android this is the Play Services dialog — "Turn on location? / NO,
  /// YES" — which flips the setting in place.
  ///
  /// Three outcomes and not a bool, because "the customer said no" and "this
  /// device cannot ask" must not be handled the same way. The first is an answer
  /// and deserves silence; the second is the app failing to do the thing its
  /// button offered, and deserves a way forward. Collapsing them is how you ship
  /// a button that visibly does nothing.
  Future<ServiceRequestOutcome> requestService();

  /// Opens the device's location settings — the fallback when the in-place
  /// dialog is not available (an Android build with no Play Services, or iOS,
  /// where no app may change the setting).
  Future<void> openLocationSettings();

  /// Opens this app's OS settings page — the only route left once location has
  /// been denied with "don't ask again", since the system dialog will not appear
  /// again no matter how many times we ask.
  Future<void> openAppSettings();
}

/// What came of asking the OS to turn location services on.
enum ServiceRequestOutcome {
  /// Services are on now.
  enabled,

  /// The dialog appeared and the customer said no. An answer, not a failure.
  declined,

  /// No dialog could be shown at all — no Play Services on this device, or the
  /// plugin never attached. The customer has not refused anything; they tapped a
  /// button and nothing happened, so the UI owes them the manual route.
  unavailable,
}

/// Why a location is or is not available, without having tried to take one.
enum LocationReadiness {
  /// Services on and permission granted — [DeviceLocationService.currentAddress]
  /// would go straight to the GPS.
  ready,

  /// Location is switched off for the whole device. Fixable in place with
  /// [DeviceLocationService.requestService].
  serviceOff,

  /// Not granted, but never permanently refused — the system dialog will still
  /// appear, so the disclosure comes first and then the ask.
  permissionDenied,

  /// Denied with "don't ask again". No dialog will ever appear again; the only
  /// way through is [DeviceLocationService.openAppSettings].
  permissionBlocked,
}

/// A latitude/longitude pair. Not an [Address]: this is the answer to "where is
/// that text", and the text is already in hand.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
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
