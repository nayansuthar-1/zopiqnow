import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls the visibility of the bottom navigation bar.
/// Used by HomePage to hide the bar when scrolling down.
final StateProvider<bool> bottomNavVisibilityProvider = StateProvider<bool>((Ref ref) => true);

/// Runs [show] — a modal sheet or dialog — with the shell's bottom pills slid
/// out of the way, then puts them back.
///
/// A bottom sheet and the pills occupy the same corner of the screen, so a sheet
/// opens *over* them: the Cart pill ends up floating on top of the sheet's
/// content, and on the taller sheets it lands on a button. Sliding them away is
/// the same animation scrolling already triggers, so the sheet appears to push
/// them down rather than cover them.
///
/// Restores only if they were showing to begin with. Arriving here from a
/// scrolled-down feed means they were already hidden, and putting them back on
/// dismiss would make closing a sheet scroll the page's furniture back into view.
Future<void> withBottomNavHidden(
  WidgetRef ref,
  Future<void> Function() show,
) async {
  final bool wasVisible = ref.read(bottomNavVisibilityProvider);
  ref.read(bottomNavVisibilityProvider.notifier).state = false;
  try {
    await show();
  } finally {
    // `finally`, so a sheet that throws on its way out does not leave the app
    // permanently without a navigation bar.
    if (wasVisible) {
      ref.read(bottomNavVisibilityProvider.notifier).state = true;
    }
  }
}
