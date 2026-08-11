import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/location/domain/services/device_location_service.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/location_disclosure.dart';

/// Clears whatever stands between a tap on "use my current location" and the
/// GPS, asking for each thing in the order the OS will enforce it.
///
/// **Why this exists.** Three screens detect a location — the startup gate, the
/// address picker, and the location-off sheet — and each used to `try` the
/// detect and print whatever [LocationFailure] came back. That reads as the app
/// refusing: "Turn on location services to detect your address" is a true
/// sentence and a dead end, because the thing it describes is one dialog away
/// and the screen offers no way to open it. Asking first turns each of those
/// sentences into the action it was describing.
///
/// Returns true when the caller should go ahead and detect. False is always an
/// answer the customer gave — they dismissed the GPS dialog, declined the
/// disclosure, or left the settings screen — so a false must be met with
/// silence, not an error. They did not fail to give us a location.
Future<bool> ensureLocationReady(BuildContext context, WidgetRef ref) async {
  final DeviceLocationService service = ref.read(deviceLocationServiceProvider);

  LocationReadiness state = await service.readiness();

  // Services first: with location switched off device-wide a granted permission
  // buys nothing, and "allow location access" would be the wrong instruction.
  if (state == LocationReadiness.serviceOff) {
    final ServiceRequestOutcome outcome = await service.requestService();
    if (!context.mounted) return false;

    switch (outcome) {
      case ServiceRequestOutcome.declined:
        // They saw the dialog and said no. Respect it in silence.
        return false;

      case ServiceRequestOutcome.unavailable:
        // No dialog could be shown, so the customer has refused nothing — they
        // pressed a button and watched it do nothing. Offer the manual route.
        await _showSettingsDialog(
          context,
          title: 'Turn on location',
          body: 'We couldn\'t open the location switch from here. You can turn '
              'it on in your device settings, or pick your address by hand.',
          onOpen: service.openLocationSettings,
        );
        return false;

      case ServiceRequestOutcome.enabled:
        break;
    }

    // Re-read rather than assume. The dialog reporting success says the customer
    // agreed, not that the setting has landed.
    state = await service.readiness();
    if (state == LocationReadiness.serviceOff) return false;
  }

  switch (state) {
    case LocationReadiness.ready:
      return true;

    case LocationReadiness.permissionDenied:
      // Play's prominent disclosure, immediately before the system dialog and at
      // no other time. The system ask itself happens inside `currentAddress`.
      if (!context.mounted) return false;
      return showLocationDisclosure(context);

    case LocationReadiness.permissionBlocked:
      if (!context.mounted) return false;
      await _showSettingsDialog(
        context,
        title: 'Location is turned off for Zopiq',
        body: 'You\'ve blocked location access, so we can\'t ask again from '
            'here. Turn it on in app settings, or pick your address by hand.',
        onOpen: service.openAppSettings,
      );
      // Even if they went to settings and granted it, the OS has not handed the
      // grant back to this process yet. The next tap will find it.
      return false;

    case LocationReadiness.serviceOff:
      // Handled above; still off means the customer declined.
      return false;
  }
}

/// The last resort, for the two cases with no in-app fix: location denied with
/// "don't ask again", and a device that cannot show the turn-on dialog at all.
///
/// Both end the same way — a switch that only the OS settings can flip — so both
/// get the same shape: say plainly what happened, and offer the one door that is
/// left rather than a "try again" that cannot work.
Future<void> _showSettingsDialog(
  BuildContext context, {
  required String title,
  required String body,
  required Future<void> Function() onOpen,
}) async {
  final bool? open = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );

  if (open ?? false) await onOpen();
}

/// Whether location is unavailable right now — what the startup sheet keys on.
///
/// Anything but [LocationReadiness.ready] counts, including a permission that
/// has merely never been asked for. That is the state the sheet is *for*: a
/// customer who has not yet said yes is exactly who it is offering to ask.
Future<bool> isLocationOff(WidgetRef ref) async =>
    await ref.read(deviceLocationServiceProvider).readiness() !=
    LocationReadiness.ready;

/// The muted red the "off" states are drawn in — a status colour, not a brand
/// one, which is why it comes from the palette's non-veg red rather than
/// anything in the Swiggy-orange ramp.
Color locationOffColor(BuildContext context) => context.zc.nonVeg;
