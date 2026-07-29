import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's dialler with [phone] filled in.
///
/// Deliberately not the rider app's `Launcher` interface with a provider behind
/// it: that abstraction exists so a widget test can assert on the URL that would
/// have been opened, and this app does not carry those tests. A free function is
/// what the two call buttons actually need.
///
/// `tel:` opens the keypad and does **not** place the call. That is the whole
/// design: dialling outright needs the `CALL_PHONE` permission, and a permission
/// prompt to save one tap is a bad trade — especially on a screen somebody opens
/// to check where their food is.
///
/// Returns false when nothing on the device can dial, which is a real case on a
/// tablet and the reason the caller shows a sentence instead of assuming.
Future<bool> dialNumber(String phone) {
  // Spaces and dashes are fine in a `tel:` URI but '+' is not: it means a space
  // in a query string. Percent-encoding the whole thing keeps a country code
  // intact. Same reasoning as the rider app's `UrlLauncher.dial`.
  return launchUrl(Uri.parse('tel:${Uri.encodeComponent(phone)}'));
}
