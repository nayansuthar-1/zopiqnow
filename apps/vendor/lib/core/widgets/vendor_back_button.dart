import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The back arrow for the three screens that draw their own header instead of
/// an [AppBar] — Analytics, Payments and the restaurant Profile.
///
/// Those three are pushed over the More hub, so there has always been something
/// to go back *to*; there was simply nothing on screen to press. Android lent
/// them its system Back and hid the omission. iOS has none, so each was a room
/// with the door painted on.
///
/// Renders nothing when there is nothing to pop, so a screen that ever becomes a
/// tab root does not grow a dead arrow.
class VendorBackButton extends StatelessWidget {
  const VendorBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.canPop()) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        // Negative visual density pulls the arrow's optical edge back to the
        // page gutter, so the header title below still lines up with the cards.
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        alignment: Alignment.centerLeft,
        icon: Icon(Icons.arrow_back_rounded, color: context.zc.textStrong),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: context.pop,
      ),
    );
  }
}
