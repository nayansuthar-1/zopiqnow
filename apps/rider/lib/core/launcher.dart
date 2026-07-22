import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Handing the rider off to another app — the map, and the dialler.
///
/// An interface with a provider, not a bare top-level function, for one blunt
/// reason: `url_launcher` talks over a platform channel, and a widget test has
/// no platform on the other end. Every test overrides this with a fake and
/// asserts on the URL that *would* have been opened, which is the only part
/// this app is responsible for anyway. Whether the phone has a maps app
/// installed is not our bug to test.
abstract interface class Launcher {
  /// Opens the map at a point, or at an address when there is no point.
  Future<bool> navigate({double? lat, double? lng, required String label});

  /// Opens the dialler with the number filled in.
  Future<bool> dial(String phone);
}

class UrlLauncher implements Launcher {
  const UrlLauncher();

  /// A `geo:` URI rather than a Google Maps or Ola Maps https link.
  ///
  /// `geo:` is the Android standard: it opens whatever the rider has set as
  /// their maps app, which on this fleet will be whatever they already trust and
  /// already have their traffic settings in. Hard-coding a vendor's https link
  /// would override that choice for no benefit to them.
  ///
  /// The `q=` is not redundant with the coordinates before it. `geo:lat,lng`
  /// alone centres the map at a point and drops no pin; `?q=lat,lng(Label)` is
  /// what puts a named marker there, which is what a rider needs to press
  /// "directions" against.
  @override
  Future<bool> navigate({
    double? lat,
    double? lng,
    required String label,
  }) async {
    final Uri uri = (lat != null && lng != null)
        ? Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})')
        // No coordinates on file — the kitchen has no map location (0042). A
        // text search is worse than a pin and much better than nothing.
        : Uri.parse('geo:0,0?q=${Uri.encodeComponent(label)}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// `tel:` opens the dialler with the number ready, and does **not** place the
  /// call. Deliberate: dialling outright needs the CALL_PHONE permission, and a
  /// permission prompt to save one tap is a bad trade — especially on a button
  /// somebody might brush with a glove.
  @override
  Future<bool> dial(String phone) {
    // Spaces and dashes are fine in a `tel:` URI but '+' is not: it means a
    // space in a query string. Percent-encoding the whole thing keeps the
    // country code intact.
    return launchUrl(Uri.parse('tel:${Uri.encodeComponent(phone)}'));
  }
}

final Provider<Launcher> launcherProvider = Provider<Launcher>(
  (Ref ref) => const UrlLauncher(),
);
