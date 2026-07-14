import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/auth/data/vendor_auth_datasource.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// The six digits mailed to the restaurant's address.
///
/// This screen never navigates itself. Verifying moves the auth state, and the
/// router's redirect is what leaves — either to the queue, or to "you're not a
/// partner", and this screen does not know or care which. Signing in and *going
/// somewhere* are different jobs, and a screen that does both is a screen that
/// spins forever the day they disagree.
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
          .read(vendorAuthControllerProvider.notifier)
          .verifyEmailOtp(email: widget.email, code: code);
      // No navigation here, on purpose. See the class doc.
    } on VendorAuthFailure catch (failure) {
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
                'We mailed a 6-digit code to ${widget.email}.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: '6-digit code',
                  errorText: _error,
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              ZopiqButton(
                label: 'Sign in',
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
