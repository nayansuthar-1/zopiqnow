/// The prominent disclosure Play requires before the system location dialog.
///
/// **This is a policy requirement, not a nicety.** Google's User Data policy
/// says an app that requests location must first show an in-app disclosure that
/// names the data, says what it is used for, and takes an affirmative action to
/// continue — and that the disclosure may not be the system dialog itself, which
/// says "allow this app to access your location" and nothing about why. The
/// rejection arrives after review rather than at upload, so its absence costs a
/// cycle rather than a re-upload.
///
/// **Why this is not a copy of the customer's.** That app reads a location once,
/// to fill in an address. This one reports a position every thirty metres for
/// the whole of a delivery, into a screen a stranger is watching. A disclosure
/// that did not say so would be accurate about the permission and misleading
/// about the app, and the reviewer checks the claims against the build.
///
/// [ensureLocationDisclosed] is the only entry point, and it is a *gate* rather
/// than a sheet: it answers true when the caller may go on to request the
/// permission. It shows nothing at all unless the system dialog would actually
/// appear.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/app/router.dart' show riderNavigatorKey;

/// Shows the disclosure if — and only if — the system dialog is about to appear.
///
/// Returns true when the caller should go on and call
/// `Geolocator.requestPermission()`. Dismissing the sheet counts as declining —
/// the affirmative action the policy asks for is the "Continue" button and
/// nothing else, so every other way out of the sheet resolves to false.
///
/// **The three states, and why only one of them shows a sheet:**
///
/// * `denied` — the dialog *will* appear. This is the one case the policy is
///   about, and the only one that shows the disclosure.
/// * `deniedForever` — Android will not show the dialog again, so there is
///   nothing to disclose in front of. A sheet here is an argument with a
///   decision the rider has already made.
/// * granted (`always` / `whileInUse`) — nothing to ask for.
///
/// Keying off the permission rather than off a "seen it once" flag is what makes
/// this correct at *both* call sites without either knowing about the other: the
/// second door finds the permission already granted and stays silent.
///
/// [context] is optional because one of the two callers is a provider-driven
/// data class with no element of its own. It falls back to the root navigator.
/// A null context and a null navigator both mean "no UI to show this in", and
/// the honest answer then is to refuse rather than to ask undisclosed.
Future<bool> ensureLocationDisclosed([BuildContext? context]) async {
  final LocationPermission permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.denied) return true;

  final BuildContext? host = context ?? riderNavigatorKey.currentContext;
  if (host == null || !host.mounted) return false;

  final bool? accepted = await showModalBottomSheet<bool>(
    context: host,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(host).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.xl)),
    ),
    builder: (_) => const _RiderLocationDisclosureSheet(),
  );
  return accepted ?? false;
}

class _RiderLocationDisclosureSheet extends StatelessWidget {
  const _RiderLocationDisclosureSheet();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZopiqSpacing.pageGutter,
          0,
          ZopiqSpacing.pageGutter,
          ZopiqSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.navigation_rounded, color: zc.primary, size: 32),
            const SizedBox(height: ZopiqSpacing.md),
            Text('Share your location on deliveries?', style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              'Zopiqnow sends your location to the customer while you are '
              'carrying their order, so they can watch it come to the door, '
              'and uses it to show you the route.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.md),
            // Four claims, and every one is true of this build — which is the
            // point, because the reviewer checks them against the app.
            //
            //  1. Continuous, and said so plainly. `RiderLocationReporter`
            //     streams every 30 m with a 20 s heartbeat.
            //  2. Only while carrying: `setCarrying` starts and stops the
            //     stream, and 0057 refuses a write from a rider with no live
            //     job regardless.
            //  3. No ACCESS_BACKGROUND_LOCATION in the manifest — the stream
            //     survives Google Maps covering the app because of a foreground
            //     service, whose notification the rider can see the whole time.
            //  4. Refusable: declining costs the rider nothing but the dot.
            const _Point(
              icon: Icons.timeline_rounded,
              text: 'Continuously while you carry an order — not between jobs.',
            ),
            const _Point(
              icon: Icons.notifications_active_outlined,
              text:
                  'A notification stays in your shade for as long as it is on, '
                  'so you always know when you are being located.',
            ),
            const _Point(
              icon: Icons.lock_outline_rounded,
              text: 'Never sold, and never shared for advertising.',
            ),
            const _Point(
              icon: Icons.check_circle_outline_rounded,
              text: 'You can say no. You still get jobs and still get paid.',
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: 'Continue',
              icon: Icons.navigation_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            ZopiqButton(
              label: 'Not now',
              variant: ZopiqButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: zc.textMuted),
          const SizedBox(width: ZopiqSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
