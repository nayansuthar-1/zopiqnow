import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_legal/zopiq_legal.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/consent_recorder.dart';
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

/// **SMS sign-in is built, wired, and switched off. See G16.**
///
/// Off because nothing would arrive: India delivers no transactional SMS until
/// DLT registration clears — entity, header and approved template — and the
/// project's Send SMS hook is not enabled either. Left drawn, the mobile field
/// would be the first thing a customer sees, take the focus, own the orange
/// button, and fail; email would be the smaller control underneath that they
/// have to notice. That is a worse sign-in screen than the one this app shipped
/// with, which is the only test that matters here.
///
/// A constant rather than a `--dart-define`, deliberately: a build-time flag is
/// a thing to remember on every build, and the failure mode of forgetting it is
/// shipping the broken screen — the exact outcome this exists to prevent. It
/// stops being a decision the day it is deleted.
///
/// **Flip to true when a code reaches a real handset**, and nothing else needs
/// touching: the datasource, the OTP screen and the router already carry the
/// phone path in full.
const bool smsSignInEnabled = false;

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

  /// The consent gate. Starts false and is never pre-ticked — a box that
  /// arrives ticked is not consent, it is a notice with a checkbox drawn on it,
  /// and every regulator that has looked at the pattern has said so.
  bool _accepted = false;

  String? _error;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    // Start the Google plugin now, while the user is still reading the screen.
    // It used to happen on the first press instead, and the round trip is slow
    // enough to see: the button spun with no account sheet behind it, which
    // reads as "not ready yet". Not awaited and it cannot throw — the button
    // stays pressable either way, and a real attempt reports a real error.
    unawaited(ref.read(authControllerProvider.notifier).prepareGoogleSignIn());
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Both halves of "can this button be pressed": the field has to be plausible
  /// *and* the terms have to have been accepted. Kept as two getters and
  /// combined at each button, so the disabled state is one expression rather
  /// than three places that could disagree about what enables a sign-in.
  bool get _isValid => isPlausibleEmail(_controller.text);

  bool get _isPhoneValid => isPlausibleIndianMobile(_phoneController.text);

  /// Any one of the three paths in flight locks the other two. They all end in
  /// the same place, and two codes racing to the same screen is a customer
  /// typing the one that arrived first into a screen expecting the other.
  bool get _busy => _sending || _sendingSms || _googleBusy;

  /// The gate, restated in code at the top of every path that creates an
  /// account. The disabled buttons are the visible half; this is the half that
  /// still holds if a keyboard's "done" key, an autofill, or a future edit to
  /// this screen finds a way past them.
  bool get _gateOpen => _accepted;

  Future<void> _submitPhone() async {
    if (!_isPhoneValid || _busy || !_gateOpen) return;
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
    if (!_isValid || _busy || !_gateOpen) return;
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
    if (_busy || !_gateOpen) return;
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

  /// The gate itself. One instance, referenced from whichever of the two
  /// placements below is live, so the two configurations of this screen cannot
  /// end up with two subtly different consent boxes.
  Widget get _consent => LegalConsentCheckbox(
    value: _accepted,
    // Locked while a sign-in is in flight: un-ticking the box underneath a
    // request that was sent on the strength of it would leave the screen
    // claiming consent was refused while the account is being created.
    enabled: !_busy,
    onChanged: (bool next) {
      setState(() => _accepted = next);
      // Carried out of this screen, because the sign-in it authorises finishes
      // on the OTP screen — one route after this widget is gone.
      ref.read(pendingConsentProvider.notifier).state = next;
    },
    onOpenDocument: (String slug) => context.pushNamed(
      Routes.legalDocument,
      pathParameters: <String, String>{'slug': slug},
    ),
  );

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
              Text(
                smsSignInEnabled
                    ? 'Enter your mobile number'
                    : 'Enter your email',
                style: t.headlineSmall,
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                smsSignInEnabled
                    ? 'We\'ll text you a 6-digit verification code.'
                    : 'We\'ll send you a 6-digit verification code.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              // Above the SMS block when it is drawn, because the block ends in
              // a button and the gate has to be above every button on the
              // screen, not only the last one. With SMS off the copy below the
              // email field is the first button, and the box sits there instead.
              if (smsSignInEnabled) ...<Widget>[
                _consent,
                const SizedBox(height: ZopiqSpacing.md),
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
                  onPressed: _isPhoneValid && !_busy && _gateOpen
                      ? _submitPhone
                      : null,
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
              ],
              TextField(
                controller: _controller,
                // Only when the mobile field is not there to take it. Two
                // autofocused fields on one screen is a race, and the keyboard
                // lands on whichever widget happened to build second.
                autofocus: !smsSignInEnabled,
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
              // The gate, when the SMS block above is not there to carry it.
              if (!smsSignInEnabled) ...<Widget>[
                _consent,
                const SizedBox(height: ZopiqSpacing.md),
              ],
              ZopiqButton(
                label: smsSignInEnabled ? 'Continue with email' : 'Continue',
                // Secondary only while the mobile path is above it: two
                // CTA-orange buttons on one screen means neither is the call to
                // action. With SMS off this is the primary path again, and it
                // gets the primary button back.
                variant: smsSignInEnabled
                    ? ZopiqButtonVariant.outline
                    : ZopiqButtonVariant.cta,
                isLoading: _sending,
                expand: true,
                onPressed: _isValid && !_busy && _gateOpen ? _submit : null,
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
                onPressed: _busy || !_gateOpen ? null : _signInWithGoogle,
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
              const SizedBox(height: ZopiqSpacing.lg),

              // Where the rest of the corpus lives. Two documents gate the
              // sign-in; the other nineteen are reference material, and burying
              // them behind an account somebody cannot yet create would put the
              // refund policy out of reach of exactly the person deciding
              // whether to sign up.
              Center(
                child: TextButton(
                  onPressed: () => context.pushNamed(Routes.legal),
                  child: Text(
                    'All legal documents',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
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
