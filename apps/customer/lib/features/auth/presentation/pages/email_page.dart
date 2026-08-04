import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// Good enough to catch a typo, not a validator. The only authority on whether
/// an address exists is whether the code arrives in its inbox.
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isPlausibleEmail(String value) => _emailPattern.hasMatch(value.trim());

/// India only, which is what the listing ships to (D2). Ten digits, and the
/// first is 6-9 because no Indian mobile number begins with anything else —
/// catching that here saves a customer an SMS that was never going to arrive
/// and saves us the paise it would have cost to not deliver it.
final RegExp _indianMobilePattern = RegExp(r'^[6-9]\d{9}$');

bool isPlausibleIndianMobile(String value) =>
    _indianMobilePattern.hasMatch(value.trim());

/// The country code the number is sent with. Not a picker: one country, and a
/// picker would be a control that can only be set wrong.
const String _dialCode = '+91';

/// Sign in / sign up — one screen, because an email OTP makes no distinction:
/// an unknown address is created, a known one is signed in.
class EmailPage extends ConsumerStatefulWidget {
  const EmailPage({
    required this.onOtpSent,
    required this.onSmsOtpSent,
    required this.onSignedIn,
    required this.onCancel,
    super.key,
  });

  /// Called with the address once the code is on its way.
  final void Function(String email) onOtpSent;

  /// The same, for the SMS path, with the number in E.164 (`+91…`) — the form
  /// GoTrue stores and the form the OTP screen has to verify against.
  final void Function(String phone) onSmsOtpSent;

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
  final TextEditingController _phoneController = TextEditingController();
  bool _sending = false;
  bool _sendingSms = false;
  bool _googleBusy = false;
  String? _error;
  String? _phoneError;

  @override
  void dispose() {
    _controller.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _isValid => isPlausibleEmail(_controller.text);

  bool get _isPhoneValid => isPlausibleIndianMobile(_phoneController.text);

  /// Any one of the three paths in flight locks the other two. They all end in
  /// the same place, and two codes racing to the same screen is a customer
  /// typing the one that arrived first into a screen expecting the other.
  bool get _busy => _sending || _sendingSms || _googleBusy;

  Future<void> _submitPhone() async {
    if (!_isPhoneValid || _busy) return;
    setState(() {
      _sendingSms = true;
      _phoneError = null;
      _error = null;
    });

    final String phone = '$_dialCode${_phoneController.text.trim()}';
    try {
      await ref.read(authControllerProvider.notifier).sendPhoneOtp(phone);
      if (mounted) widget.onSmsOtpSent(phone);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _phoneError = failure.message);
    } finally {
      if (mounted) setState(() => _sendingSms = false);
    }
  }

  Future<void> _submit() async {
    if (!_isValid || _busy) return;
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
    if (_busy) return;
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
      // A SnackBar, not `_error`. `_error` renders as the *email field's*
      // `errorText` — a red line under a box the customer never touched, two
      // controls above the button they actually pressed. It reads as "the app
      // did nothing", which is how a Google sign-in that was failing loudly all
      // along got reported as a screen that simply would not move on.
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
      }
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
      // Scrollable since the mobile field arrived. This screen now carries two
      // inputs, three buttons, two dividers and the consent paragraph; with the
      // keyboard up on a short phone that is taller than the viewport, and an
      // un-scrollable Column does not clip there, it throws a layout overflow
      // and paints the yellow-and-black stripes over the sign-in screen.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Enter your mobile number', style: t.headlineSmall),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'We\'ll text you a 6-digit verification code.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              TextField(
                controller: _phoneController,
                autofocus: true,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                // Digits only, so a customer who pastes "+91 98765 43210" or
                // "098765-43210" is not told their own number is wrong. The
                // formatter strips it to what the pattern actually judges.
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(() => _phoneError = null),
                onSubmitted: (_) => _submitPhone(),
                decoration: InputDecoration(
                  hintText: '98765 43210',
                  counterText: '',
                  errorText: _phoneError,
                  // The country code is shown, not typed. One country ships
                  // (D2), so a picker would be a control that can only be set
                  // wrong, and a customer who types +91 themselves would send
                  // a twelve-digit number to a ten-digit field.
                  prefixText: '$_dialCode  ',
                  prefixStyle: t.bodyLarge,
                  border: const OutlineInputBorder(
                    borderRadius: ZopiqRadii.rMd,
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              ZopiqButton(
                label: 'Continue',
                variant: ZopiqButtonVariant.cta,
                isLoading: _sendingSms,
                expand: true,
                onPressed: _isPhoneValid && !_busy ? _submitPhone : null,
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
              TextField(
                controller: _controller,
                // The mobile field takes the focus now. Two autofocused fields
                // on one screen is a race, and the keyboard lands on whichever
                // widget happened to build second.
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
                label: 'Continue with email',
                // Outlined, because the mobile path above is now the primary
                // one and two CTA-orange buttons on one screen means neither is
                // the call to action.
                variant: ZopiqButtonVariant.outline,
                isLoading: _sending,
                expand: true,
                onPressed: _isValid && !_busy ? _submit : null,
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
                onPressed: _busy ? null : _signInWithGoogle,
                icon: _googleBusy
                    // Sized to the icon it replaces, so the label does not
                    // shift sideways when the spinner appears.
                    ? const ZopiqLoader(size: 20, strokeWidth: 2)
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
              const SizedBox(height: ZopiqSpacing.xl),

              // Consent, at the point of consenting. This screen is where an
              // account is created — an unknown address is signed up, not
              // rejected — so this is the only honest place to say what that
              // agrees to, and both documents are one tap away rather than
              // named and left unfindable.
              Text.rich(
                TextSpan(
                  style: t.bodySmall?.copyWith(color: zc.textMuted, height: 1.4),
                  children: <InlineSpan>[
                    const TextSpan(text: 'By continuing you agree to our '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(color: zc.primary),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => context.pushNamed(
                          Routes.legal,
                          pathParameters: const <String, String>{'doc': 'terms'},
                        ),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(color: zc.primary),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => context.pushNamed(
                          Routes.legal,
                          pathParameters: const <String, String>{
                            'doc': 'privacy',
                          },
                        ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
