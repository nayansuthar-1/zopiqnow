import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/auth/data/datasources/auth_mock_datasource.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// Resend cooldown (SAD 9.3). Also what the real endpoint rate-limits on, so the
/// UI should never let the user hit it.
const Duration otpResendCooldown = Duration(seconds: 30);

/// Verifies the code. Navigation on success is *not* this screen's job: the
/// router's redirect watches auth state and sends the user to wherever they were
/// originally headed. Popping from here as well would race that redirect.
class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({required this.phone, super.key});

  /// E.164.
  final String phone;

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
    setState(() => _secondsLeft = otpResendCooldown.inSeconds);
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
      await ref
          .read(authControllerProvider.notifier)
          .verifyOtp(phone: widget.phone, code: _controller.text);
      // No navigation here — see the class doc.
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _verifying = false;
      });
      _controller.clear();
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await ref.read(authControllerProvider.notifier).requestOtp(widget.phone);
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
              Text('Verify your number', style: t.headlineSmall),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Enter the 6-digit code sent to ${widget.phone}',
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
              // There is no SMS to read from a mock data source. Rather than
              // leave the screen unusable, say the code out loud — in debug only.
              if (kDebugMode) ...<Widget>[
                const Spacer(),
                Center(
                  child: Text(
                    'Debug: the code is ${AuthMockDataSource.devCode}',
                    style: t.labelSmall?.copyWith(color: zc.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
