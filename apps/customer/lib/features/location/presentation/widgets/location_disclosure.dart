import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The prominent disclosure Play requires before the system location dialog.
///
/// **This is a policy requirement, not a nicety.** Google's User Data policy says
/// an app that requests location must first show an in-app disclosure that names
/// the data, says what it is used for, and takes an affirmative action to
/// continue — and that the disclosure may not be the system dialog itself, since
/// that dialog says "allow this app to access your location" and nothing about
/// why. Listings are rejected for its absence, and the rejection arrives after
/// review rather than at upload.
///
/// It is shown only when the system dialog would actually appear — see
/// `DeviceLocationService.needsPermissionPrompt`. Showing it to somebody who has
/// already granted (or permanently denied) is a second sheet in front of a
/// decision they have made, which is the kind of thing that trains people to tap
/// through disclosures without reading them.
///
/// Returns true when the customer chose to continue. Dismissing counts as
/// declining, which is why the caller must treat false as "say nothing and stop"
/// rather than as an error: they did not fail to give us a location, they
/// declined to, and an error message would be an argument with their answer.
Future<bool> showLocationDisclosure(BuildContext context) async {
  final bool? accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.xl)),
    ),
    builder: (_) => const _LocationDisclosureSheet(),
  );
  return accepted ?? false;
}

class _LocationDisclosureSheet extends StatelessWidget {
  const _LocationDisclosureSheet();

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
            Icon(Icons.my_location_rounded, color: zc.primary, size: 32),
            const SizedBox(height: ZopiqSpacing.md),
            Text('Use your location?', style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              'Zopiqnow uses your device location to fill in your delivery '
              'address and to show the restaurants that deliver to you.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.md),
            // The three claims Play's reviewer looks for, and each of them is
            // true of this build: foreground only (no ACCESS_BACKGROUND_LOCATION
            // in the manifest), never sold or shared (the privacy policy says so
            // and the data-safety form has to match), and refusable (typing an
            // address by hand reaches every screen the GPS path does).
            const _Point(
              icon: Icons.visibility_outlined,
              text: 'Only while the app is open — never in the background.',
            ),
            const _Point(
              icon: Icons.lock_outline_rounded,
              text: 'Never sold, and never shared for advertising.',
            ),
            const _Point(
              icon: Icons.edit_outlined,
              text: 'You can skip this and type your address instead.',
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: 'Continue',
              icon: Icons.my_location_rounded,
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
