import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// Resend cooldown (SAD 9.3). Supabase rate-limits sends server-side, so the UI
/// should never let the user hit it.
///
/// **45, not 30, because 30 was shorter than the limit it exists to stay under.**
/// The project's `smtp_max_frequency` is 45 seconds — the minimum gap Supabase
/// allows between two mails to the *same* address — so at 30 the button went
/// live fifteen seconds early and the resend it invited came back refused. The
/// comment above was true as an intent and false as a number.
///
/// If that setting is ever changed, change this with it: it is the one number
/// here that is not ours to choose.
const Duration otpResendCooldown = Duration(seconds: 45);

/// The same idea for SMS, and **this one is ours to choose.**
///
/// Supabase's `sms_max_frequency` is 5 seconds, so unlike the email figure above
/// this is not a server minimum being mirrored — 30 is a product decision, and
/// the reason it is not 5 is that every resend costs real money at MSG91 and a
/// button that can be hammered six times a minute is a button that will be.
const Duration smsOtpResendCooldown = Duration(seconds: 30);

/// Verifies the code. Navigation on success is *not* this screen's job: the
/// router's redirect watches auth state and sends the user to wherever they were
/// originally headed. Popping from here as well would race that redirect.
class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({this.email, this.phone, super.key})
    : assert(
        (email == null) != (phone == null),
        'Exactly one of email or phone. A code belongs to one address, and a '
        'screen that held both would have to guess which one to verify against '
        '- and GoTrue answers "invalid code" for a perfectly good code checked '
        'against the wrong channel.',
      );

  /// The address the code was mailed to, when this is the email flow.
  final String? email;

  /// The E.164 number the code was texted to, when this is the SMS flow.
  final String? phone;

  /// Where the code went, as the customer should read it back.
  String get destination => email ?? phone!;

  bool get isPhone => phone != null;

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _timer;
  int _secondsLeft = 0;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(
      () => _secondsLeft = widget.isPhone
          ? smsOtpResendCooldown.inSeconds
          : otpResendCooldown.inSeconds,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    if (_verifying || _controller.text.length != 6) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final AuthController auth = ref.read(authControllerProvider.notifier);
      if (widget.isPhone) {
        await auth.verifyPhoneOtp(
          phone: widget.phone!,
          code: _controller.text,
        );
      } else {
        await auth.verifyEmailOtp(
          email: widget.email!,
          code: _controller.text,
        );
      }
      // No navigation here — see the class doc.
    } on AuthFailure catch (failure) {
      _fail(failure.message);
    } on Object catch (error) {
      // Anything that is not an [AuthFailure] is a bug, not a wrong code — a
      // Keystore that will not write, a plugin that is not there. It still has
      // to release the button: a spinner that never stops is the one outcome
      // the user cannot recover from (Rule 1.6). Debug builds name it, because
      // the alternative is guessing from a screenshot.
      _fail(kDebugMode ? '$error' : 'Something went wrong. Try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _verifying = false;
    });
    _controller.clear();
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      final AuthController auth = ref.read(authControllerProvider.notifier);
      if (widget.isPhone) {
        await auth.sendPhoneOtp(widget.phone!);
      } else {
        await auth.sendEmailOtp(widget.email!);
      }
      _startCooldown();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
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
              Text(
                widget.isPhone ? 'Check your messages' : 'Check your inbox',
                style: t.headlineSmall,
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Enter the 6-digit code sent to ${widget.destination}',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: t.headlineSmall?.copyWith(letterSpacing: 12),
                autofillHints: const <String>[AutofillHints.oneTimeCode],
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (String value) {
                  setState(() => _error = null);
                  if (value.length == 6) _verify();
                },
                decoration: InputDecoration(
                  counterText: '',
                  errorText: _error,
                  border: const OutlineInputBorder(
                    borderRadius: ZopiqRadii.rMd,
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              ZopiqButton(
                label: 'Verify',
                variant: ZopiqButtonVariant.cta,
                isLoading: _verifying,
                expand: true,
                onPressed: _verify,
              ),
              const SizedBox(height: ZopiqSpacing.md),
              Center(
                child: _secondsLeft > 0
                    ? Text(
                        'Resend code in ${_secondsLeft}s',
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      )
                    : TextButton(
                        onPressed: _resend,
                        child: const Text('Resend code'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
