import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_legal/zopiq_legal.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/app/providers/consent_recorder.dart';
import 'package:zopiq_rider/app/router.dart';
import 'package:zopiq_rider/core/widgets/rider_animations.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/auth/data/rider_auth_datasource.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';

/// The window between launch and the Keystore read returning.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              zc.primary.withValues(alpha: 0.12),
              surfaceColor,
              surfaceColor,
            ],
          ),
        ),
        child: Center(
          child: RiderFadeSlide(
            offsetY: 20,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                RiderPulseBadge(
                  enabled: true,
                  glowColor: zc.primary,
                  child: Container(
                    padding: const EdgeInsets.all(ZopiqSpacing.lg),
                    decoration: BoxDecoration(
                      color: zc.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: RiderSvgIcon(
                      type: RiderSvgType.deliveryBike,
                      size: 56,
                      color: zc.primary,
                    ),
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.lg),
                Text(
                  'ZOPIQNOW',
                  style: t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: zc.primary,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                Text(
                  'Partner Delivery Fleet',
                  style: t.labelLarge?.copyWith(
                    color: zc.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sign in with the address ops onboarded the rider with.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({required this.onOtpSent, super.key});

  final void Function(String email) onOtpSent;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final TextEditingController _email = TextEditingController();
  bool _sending = false;

  /// The consent gate. Never pre-ticked — a box that arrives ticked is not
  /// consent, it is a notice with a checkbox drawn on it.
  bool _accepted = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    // Start the Google plugin now, while the rider is still reading the screen.
    // It used to happen on the first press instead, and the round trip is slow
    // enough to see: the button spun with no account sheet behind it, which
    // reads as "not ready yet". Not awaited and it cannot throw — the button
    // stays pressable either way, and a real attempt reports a real error.
    unawaited(
      ref.read(riderAuthControllerProvider.notifier).prepareGoogleSignIn(),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_accepted) return;

    final String email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter the email you signed up with.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(riderAuthControllerProvider.notifier).sendEmailOtp(email);
      if (mounted) widget.onOtpSent(email);
    } on RiderAuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'We couldn\'t reach Zopiqnow. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _google() async {
    if (!_accepted) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(riderAuthControllerProvider.notifier).signInWithGoogle();
      // No navigation on success: signing in changes the auth state, and the
      // shell above this screen decides where that lands — including on the
      // "you don't ride for us" screen, which is not a failure to report.
    } on RiderGoogleCancelled {
      // The account sheet was closed. Saying anything would be arguing with a
      // decision just made.
    } on RiderAuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'We couldn\'t reach Zopiqnow. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: RiderFadeSlide(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: ZopiqSpacing.xxl),

                // Brand Header Banner
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          zc.primary,
                          zc.primary.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: ZopiqRadii.rXl,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: zc.primary.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: RiderSvgIcon(
                        type: RiderSvgType.deliveryBike,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xl),

                Center(
                  child: Text(
                    'Partner Sign In',
                    style: t.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                Center(
                  child: Text(
                    'Welcome back! Enter your registered rider email to access your active shift.',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: zc.textMuted),
                  ),
                ),

                const SizedBox(height: ZopiqSpacing.xxl),

                // Elevated Input Card
                ZopiqCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'RIDER ACCOUNT EMAIL',
                        style: t.labelSmall?.copyWith(
                          color: zc.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: ZopiqSpacing.sm),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'rider@zopiqnow.com',
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: zc.textMuted,
                          ),
                          errorText: _error,
                          border: OutlineInputBorder(
                            borderRadius: ZopiqRadii.rMd,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                      const SizedBox(height: ZopiqSpacing.md),
                      // Above both buttons, because it gates both. A rider signs
                      // a handbook and a verification policy by working here;
                      // this is where they are told so.
                      LegalConsentCheckbox(
                        value: _accepted,
                        enabled: !_sending,
                        onChanged: (bool next) {
                          setState(() => _accepted = next);
                          // Carried out of this screen: the sign-in it
                          // authorises finishes on the OTP screen.
                          ref.read(pendingConsentProvider.notifier).state = next;
                        },
                        onOpenDocument: (String slug) => context.pushNamed(
                          Routes.legalDocument,
                          pathParameters: <String, String>{'slug': slug},
                        ),
                      ),
                      const SizedBox(height: ZopiqSpacing.md),
                      ZopiqButton(
                        label: 'Send Verification Code',
                        variant: ZopiqButtonVariant.cta,
                        isLoading: _sending,
                        onPressed: _accepted ? _send : null,
                      ),
                      const SizedBox(height: ZopiqSpacing.lg),
                      Row(
                        children: <Widget>[
                          Expanded(child: Divider(color: zc.divider)),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ZopiqSpacing.md,
                            ),
                            child: Text(
                              'or',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: zc.textMuted),
                            ),
                          ),
                          Expanded(child: Divider(color: zc.divider)),
                        ],
                      ),
                      const SizedBox(height: ZopiqSpacing.lg),
                      // The same delivery_partners row decides both routes, so
                      // this is a second door into one house, not a second key.
                      ZopiqButton(
                        label: 'Continue with Google',
                        icon: Icons.account_circle_outlined,
                        variant: ZopiqButtonVariant.outline,
                        onPressed: _sending || !_accepted ? null : _google,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: ZopiqSpacing.lg),

                // The rest of the corpus, reachable before signing in — the
                // handbook and the verification policy are exactly what
                // somebody deciding whether to ride for us wants to read.
                Center(
                  child: TextButton(
                    onPressed: () => context.pushNamed(Routes.legal),
                    child: Text(
                      'All legal documents',
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ),
                ),

                const SizedBox(height: ZopiqSpacing.sm),

                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      RiderSvgIcon(
                        type: RiderSvgType.verifiedShield,
                        size: 16,
                        color: zc.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Secure OTP Passwordless Authentication',
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The six digits mailed to the rider's address.
class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({required this.email, super.key});

  final String email;

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final TextEditingController _code = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify([String? otpCode]) async {
    final String code = otpCode ?? _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'The code must be 6 digits.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref
          .read(riderAuthControllerProvider.notifier)
          .verifyEmailOtp(email: widget.email, code: code);
    } on RiderAuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'We couldn\'t check that code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Code'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: RiderFadeSlide(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: ZopiqSpacing.lg),

                // Icon banner
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(ZopiqSpacing.lg),
                    decoration: BoxDecoration(
                      color: zc.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: RiderSvgIcon(
                      type: RiderSvgType.pickupKey,
                      size: 40,
                      color: zc.primary,
                    ),
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.lg),

                Center(
                  child: Text(
                    'Enter 6-Digit Code',
                    style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: t.bodyMedium?.copyWith(color: zc.textMuted),
                      children: <TextSpan>[
                        const TextSpan(text: 'We sent a verification code to\n'),
                        TextSpan(
                          text: widget.email,
                          style: TextStyle(
                            color: zc.textStrong,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: ZopiqSpacing.xxl),

                // Pin Input Box
                Center(
                  child: RiderPinInput(
                    length: 6,
                    controller: _code,
                    autofocus: true,
                    errorText: _error,
                    onCompleted: (String code) => _verify(code),
                  ),
                ),

                const SizedBox(height: ZopiqSpacing.xl),

                ZopiqButton(
                  label: 'Verify & Access Shift',
                  variant: ZopiqButtonVariant.cta,
                  isLoading: _verifying,
                  onPressed: () => _verify(),
                ),

                const SizedBox(height: ZopiqSpacing.lg),

                Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Use a different email address'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Authenticated, and nobody. Not an error — a screen.
class NotPartnerPage extends ConsumerWidget {
  const NotPartnerPage({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: RiderFadeSlide(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(ZopiqSpacing.xl),
                  decoration: BoxDecoration(
                    color: zc.nonVeg.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: RiderSvgIcon(
                    type: RiderSvgType.verifiedShield,
                    size: 56,
                    color: zc.nonVeg,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xl),
                Text(
                  'Account Not Onboarded',
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: ZopiqSpacing.sm),
                Text(
                  '$email is not registered in the active delivery roster.\n\n'
                  'If you were recently hired as a delivery partner, ask your operations coordinator to activate your email.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: zc.textMuted, height: 1.4),
                ),
                const SizedBox(height: ZopiqSpacing.xxl),
                ZopiqButton(
                  label: 'Sign Out',
                  variant: ZopiqButtonVariant.outline,
                  expand: false,
                  onPressed: () =>
                      ref.read(riderAuthControllerProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
