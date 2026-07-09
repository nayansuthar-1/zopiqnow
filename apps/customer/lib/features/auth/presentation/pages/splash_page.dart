import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Shown only while the session is being read out of the Keystore (SAD 24.1,
/// "Splash → session restore"). Usually one or two frames.
///
/// It exists so the router never has to guess: redirecting on [AuthUnknown]
/// would bounce a signed-in user to the login screen on every cold start.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: CircularProgressIndicator(color: context.zc.primary)),
    );
  }
}
