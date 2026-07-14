import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// What the app shows for the one moment it genuinely does not know who you are:
/// between launch and the Keystore handing back a session.
///
/// It is not a loading screen for the queue — the queue has its own. It exists
/// so the router has something to render during `AuthUnknown` instead of
/// guessing, and guessing wrong means throwing a signed-in kitchen back to the
/// login screen every time they open the app.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.storefront_rounded, size: 56, color: zc.primary),
            const SizedBox(height: ZopiqSpacing.lg),
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
