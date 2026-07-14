import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// Sign in with the address ops onboarded the restaurant with.
///
/// No Google sign-in and no password. A restaurant account is an *address that
/// ops wrote into a table*, and the only thing worth proving is that whoever is
/// holding the tablet can read mail sent to it. A password would be a second
/// secret to lose, on a device shared by a whole kitchen.
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
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
