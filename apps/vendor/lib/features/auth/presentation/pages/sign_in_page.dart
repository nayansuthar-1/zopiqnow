import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_legal/zopiq_legal.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/providers/consent_recorder.dart';
import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/features/auth/data/vendor_auth_datasource.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// Sign in with the address ops onboarded the restaurant with — by emailed code,
/// or with the Google account of the same address.
///
/// **Still no password**, and that part of the original reasoning stands: a
/// restaurant account is an *address ops wrote into a table*, and a password
/// would be a second secret to lose on a device shared by a whole kitchen.
///
/// Google was added because the emailed code has one failure the kitchen cannot
/// work around — it depends on mail arriving. Slow delivery, a rate limit, a
/// tablet with no mail client configured, and there is no way in at all. Google
/// proves the same address without the round trip. It grants nothing extra:
/// `restaurant_staff` is still the only thing that says who works here, and both
/// routes are checked against it.
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
    // Start the Google plugin now, while the user is still reading the screen.
    // It used to happen on the first press instead, and the round trip is slow
    // enough to see: the button spun with no account sheet behind it, which
    // reads as "not ready yet". Not awaited and it cannot throw — the button
    // stays pressable either way, and a real attempt reports a real error.
    unawaited(
      ref.read(vendorAuthControllerProvider.notifier).prepareGoogleSignIn(),
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
      setState(
        () => _error = 'Enter the email your restaurant signed up with.',
      );
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(vendorAuthControllerProvider.notifier).sendEmailOtp(email);
      if (mounted) widget.onOtpSent(email);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'We couldn\'t send the code. Please try again.',
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
      await ref.read(vendorAuthControllerProvider.notifier).signInWithGoogle();
      // No navigation on success: signing in changes the auth state, and the
      // shell above this screen is what decides where that lands — including on
      // the "you don't work here" screen, which is not a failure to report.
    } on VendorGoogleCancelled {
      // Somebody closed the account sheet. Saying anything about it would be
      // arguing with a decision they just made.
    } on VendorAuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      // Scrollable since the consent box arrived, and the two `Spacer`s that
      // used to centre this column are gone with it — a Spacer needs a bounded
      // height and a scroll view offers none. The screen now carries an input,
      // a two-line tick box, three buttons and a divider; with the keyboard up
      // on a short tablet that is taller than the viewport, and an unscrollable
      // Column does not clip there, it throws a layout overflow and paints the
      // yellow-and-black stripes over the sign-in screen.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: ZopiqSpacing.xxl),
              Icon(Icons.storefront_rounded, size: 56, color: zc.primary),
              const SizedBox(height: ZopiqSpacing.lg),
              Text('Zopiqnow for restaurants', style: t.headlineSmall),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Sign in with the email your restaurant is registered with.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Restaurant email',
                  errorText: _error,
                ),
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: ZopiqSpacing.md),
              // Above both buttons, because it gates both. A restaurant signs
              // an SLA and a verification policy by trading here; this is where
              // they are told so, before the first order rather than after it.
              LegalConsentCheckbox(
                value: _accepted,
                enabled: !_sending,
                onChanged: (bool next) {
                  setState(() => _accepted = next);
                  // Carried out of this screen: the sign-in it authorises
                  // finishes on the OTP screen.
                  ref.read(pendingConsentProvider.notifier).state = next;
                },
                onOpenDocument: (String slug) => context.pushNamed(
                  Routes.legalDocument,
                  pathParameters: <String, String>{'slug': slug},
                ),
              ),
              const SizedBox(height: ZopiqSpacing.md),
              ZopiqButton(
                label: 'Send code',
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
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ),
                  Expanded(child: Divider(color: zc.divider)),
                ],
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              // The same restaurant_staff row decides both routes, so this is a
              // second door into one house rather than a second key.
              ZopiqButton(
                label: 'Continue with Google',
                icon: Icons.account_circle_outlined,
                variant: ZopiqButtonVariant.outline,
                onPressed: _sending || !_accepted ? null : _google,
              ),
              const SizedBox(height: ZopiqSpacing.md),
              // The rest of the corpus, reachable before signing in — the
              // handbook and the SLA are exactly what somebody deciding whether
              // to list their kitchen here wants to read.
              Center(
                child: TextButton(
                  onPressed: () => context.pushNamed(Routes.legal),
                  child: Text(
                    'All legal documents',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
