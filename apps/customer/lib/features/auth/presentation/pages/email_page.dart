import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  const EmailPage({
    required this.onOtpSent,
    required this.onSignedIn,
    required this.onCancel,
    super.key,
  });

  /// Called with the address once the code is on its way.
  final void Function(String email) onOtpSent;

  /// Called when Google has signed the user in and this screen is done.
  ///
  /// The email path never needs this: sending a code navigates to the OTP screen,
  /// and *that* `go` is what turns an imperatively pushed login back into a
  /// declarative one the redirect can move. Google has no second step, so
  /// nothing rewrites the stack — and go_router does not re-run `redirect` on a
  /// pushed route. Without this callback the user picks an account, watches
  /// nothing happen, and discovers they are signed in only after pressing back.
  final VoidCallback onSignedIn;

  /// Backs out of the sign-in. This screen is reached by `go`, not `push`, so
  /// there is nothing on the stack to pop and Flutter draws no back arrow —
  /// without this, a user who tapped "Sign in" by accident would be trapped.
  final VoidCallback onCancel;

  @override
  ConsumerState<EmailPage> createState() => _EmailPageState();
}

class _EmailPageState extends ConsumerState<EmailPage> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  bool _googleBusy = false;
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

  Future<void> _signInWithGoogle() async {
    if (_googleBusy || _sending) return;
    setState(() {
      _googleBusy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
      // [onSignedIn] `go`es, which is a declarative navigation — so it leaves
      // this screen behind even when the guard *pushed* it here, which the
      // redirect on its own cannot do. Where to go is still the router's call,
      // not this screen's: it holds `?from=`.
      if (mounted) widget.onSignedIn();
    } on GoogleSignInCancelled {
      // They closed the sheet. They know they closed the sheet.
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onCancel,
        ),
      ),
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
              OutlinedButton.icon(
                onPressed: _sending ? null : _signInWithGoogle,
                icon: _googleBusy
                    // Sized to the icon it replaces, so the label does not
                    // shift sideways when the spinner appears.
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : SvgPicture.asset(
                        'assets/icons_zopiq/google_g.svg',
                        width: 20,
                        height: 20,
                      ),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(color: zc.divider),
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZopiqRadii.rMd,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
