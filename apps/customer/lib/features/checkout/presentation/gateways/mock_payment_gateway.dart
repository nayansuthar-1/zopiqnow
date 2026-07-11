import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/payment_outcome.dart';
import 'package:zopiqnow/features/checkout/domain/gateways/payment_gateway.dart';

/// Stand-in for Razorpay until the API keys and the backend that creates the
/// payment order exist.
///
/// It draws its own sheet — same shape as the real SDK, which also owns its UI
/// and answers asynchronously — so the whole UPI path (pay, decline, dismiss)
/// is exercisable today. It lives in the presentation layer precisely *because*
/// it draws UI; the real adapter will sit in `data/gateways/` and this file
/// gets deleted.
///
/// It never moves money and says so on the sheet.
class MockPaymentGateway implements PaymentGateway {
  MockPaymentGateway({
    required this.navigatorKey,
    this.latency = const Duration(milliseconds: 900),
  });

  /// How a non-widget gateway reaches a [BuildContext]. The real SDK needs no
  /// such thing — this is the mock paying for its stand-in UI.
  final GlobalKey<NavigatorState> navigatorKey;

  /// The "contacting your bank" pause, so the loading state is real.
  final Duration latency;

  final math.Random _random = math.Random();

  @override
  Future<PaymentOutcome> pay({
    required int amount,
    required String description,
  }) async {
    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) {
      return const PaymentFailed('Payment couldn\'t be started.');
    }

    final PaymentOutcome? outcome = await showModalBottomSheet<PaymentOutcome>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MockPaymentSheet(
        amount: amount,
        description: description,
        latency: latency,
        paymentId: 'pay_mock_${_random.nextInt(0xFFFFFF).toRadixString(16)}',
      ),
    );

    // A drag-dismiss returns null — same as tapping the sheet's close button.
    return outcome ?? const PaymentCancelled();
  }
}

/// The sheet itself: pay, or decline, or dismiss. Pops with the outcome.
class _MockPaymentSheet extends StatefulWidget {
  const _MockPaymentSheet({
    required this.amount,
    required this.description,
    required this.latency,
    required this.paymentId,
  });

  final int amount;
  final String description;
  final Duration latency;
  final String paymentId;

  @override
  State<_MockPaymentSheet> createState() => _MockPaymentSheetState();
}

class _MockPaymentSheetState extends State<_MockPaymentSheet> {
  bool _isProcessing = false;

  Future<void> _settle(PaymentOutcome outcome) async {
    setState(() => _isProcessing = true);
    await Future<void>.delayed(widget.latency);
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZopiqRadii.xl),
        ),
      ),
      padding: EdgeInsets.only(
        left: ZopiqSpacing.lg,
        right: ZopiqSpacing.lg,
        top: ZopiqSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + ZopiqSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.qr_code_rounded, color: zc.primary, size: 22),
                const SizedBox(width: ZopiqSpacing.sm),
                Expanded(child: Text('UPI payment', style: t.titleMedium)),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cancel payment',
                  onPressed: _isProcessing
                      ? null
                      : () => Navigator.of(context).pop(const PaymentCancelled()),
                ),
              ],
            ),
            Text(
              widget.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            Text('₹${widget.amount}', style: t.headlineSmall),
            const SizedBox(height: ZopiqSpacing.lg),
            // The one thing this sheet must never let anyone forget.
            Container(
              padding: const EdgeInsets.all(ZopiqSpacing.md),
              decoration: BoxDecoration(
                color: zc.primary.withValues(alpha: 0.08),
                borderRadius: ZopiqRadii.rMd,
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.science_outlined, size: 20, color: zc.primary),
                  const SizedBox(width: ZopiqSpacing.sm),
                  Expanded(
                    child: Text(
                      'Test gateway. No money moves — the real Razorpay sheet '
                      'takes over once the keys are in.',
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            ZopiqButton(
              label: 'Pay ₹${widget.amount}',
              variant: ZopiqButtonVariant.cta,
              isLoading: _isProcessing,
              onPressed: () => _settle(PaymentSucceeded(widget.paymentId)),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            TextButton(
              onPressed: _isProcessing
                  ? null
                  : () => _settle(
                      const PaymentFailed(
                        'Your payment was declined. Try another method.',
                      ),
                    ),
              child: const Text('Simulate a failed payment'),
            ),
          ],
        ),
      ),
    );
  }
}
