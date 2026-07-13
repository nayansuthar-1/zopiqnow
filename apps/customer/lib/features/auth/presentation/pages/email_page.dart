import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// Good enough to catch a typo, not a validator. The only authority on whether
/// an address exists is whether the code arrives in its inbox.
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isPlausibleEmail(String value) => _emailPattern.hasMatch(value.trim());

/// Sign in / sign up — one screen, because an email OTP makes no distinction:
/// an unknown address is created, a known one is signed in.
class EmailPage extends ConsumerStatefulWidget {
  const EmailPage({required this.onOtpSent, super.key});

  /// Called with the address once the code is on its way.
  final void Function(String email) onOtpSent;

  @override
  ConsumerState<EmailPage> createState() => _EmailPageState();
}

class _EmailPageState extends ConsumerState<EmailPage> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isValid => isPlausibleEmail(_controller.text);

  Future<void> _submit() async {
    if (!_isValid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final String email = _controller.text.trim();
    try {
      await ref.read(authControllerProvider.notifier).sendEmailOtp(email);
      if (mounted) widget.onOtpSent(email);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _sending = false);
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
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Enter your email', style: t.headlineSmall),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'We\'ll send you a 6-digit verification code.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const <String>[AutofillHints.email],
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  errorText: _error,
                  border: const OutlineInputBorder(
                    borderRadius: ZopiqRadii.rMd,
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              ZopiqButton(
                label: 'Continue',
                variant: ZopiqButtonVariant.cta,
                isLoading: _sending,
                expand: true,
                onPressed: _isValid ? _submit : null,
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
              // Disabled rather than absent, and it says why: the Google Cloud
              // OAuth clients do not exist yet, so a tap could only fail. Same
              // honesty as the UPI tile at checkout.
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZopiqRadii.rMd,
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Center(
                child: Text(
                  'Google sign-in arrives with the OAuth setup.',
                  style: t.labelSmall?.copyWith(color: zc.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
