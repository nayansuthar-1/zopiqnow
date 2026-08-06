import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

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
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
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
              const SizedBox(height: ZopiqSpacing.lg),
              ZopiqButton(
                label: 'Send code',
                variant: ZopiqButtonVariant.cta,
                isLoading: _sending,
                onPressed: _send,
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
                onPressed: _sending ? null : _google,
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
