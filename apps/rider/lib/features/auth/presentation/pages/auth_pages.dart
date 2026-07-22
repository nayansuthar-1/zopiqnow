import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/features/auth/data/rider_auth_datasource.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';

/// The window between launch and the Keystore read returning.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Icon(
          Icons.delivery_dining_rounded,
          size: 64,
          color: context.zc.primary,
        ),
      ),
    );
  }
}

/// Sign in with the address ops onboarded the rider with.
///
/// No password, for the reason the vendor app gives: a delivery partner account
/// is *an address someone wrote into a table*, and the only thing worth proving
/// is that whoever is holding the phone can read mail sent to it.
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
      // Supabase's own sentence, not ours. "You can only request this after 54
      // seconds" is something a rider can act on; "please try again" is what
      // they were told while the real problem went unnamed for four phases.
      if (mounted) setState(() => _error = e.message);
    } on Object {
      // Anything that is not the auth service talking — no signal, DNS, a dead
      // socket. There is nothing specific to say, so say the honest general
      // thing and point at the one cause the rider can actually fix.
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
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
              Icon(Icons.delivery_dining_rounded, size: 56, color: zc.primary),
              const SizedBox(height: ZopiqSpacing.lg),
              Text('Zopiqnow for partners', style: t.headlineSmall),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Sign in with the email you were signed up with.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Email',
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
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// The six digits mailed to the rider's address.
///
/// This screen never navigates itself. Verifying moves the auth state and the
/// router's redirect is what leaves — either to the board, or to "you don't ride
/// for us", and this screen neither knows nor cares which.
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

  Future<void> _verify() async {
    final String code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'The code is 6 digits.');
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
      // No navigation here, on purpose. See the class doc.
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
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Enter the code', style: t.headlineSmall),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'We sent it to ${widget.email}.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: '6-digit code',
                  errorText: _error,
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              ZopiqButton(
                label: 'Verify',
                variant: ZopiqButtonVariant.cta,
                isLoading: _verifying,
                onPressed: _verify,
              ),
            ],
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.no_transfer_rounded, size: 56, color: zc.textMuted),
              const SizedBox(height: ZopiqSpacing.lg),
              Text('Not a delivery partner', style: t.titleLarge),
              const SizedBox(height: ZopiqSpacing.sm),
              Text(
                '$email isn\'t signed up to deliver for Zopiqnow. If you think '
                'that\'s wrong, talk to whoever onboarded you.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqButton(
                label: 'Sign out',
                variant: ZopiqButtonVariant.outline,
                expand: false,
                onPressed: () =>
                    ref.read(riderAuthControllerProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
