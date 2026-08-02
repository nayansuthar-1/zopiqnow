import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/checkout/domain/entities/payment_outcome.dart';
import 'package:zopiqnow/features/checkout/domain/gateways/payment_gateway.dart';

/// The real gateway: a Razorpay order created on the server, a checkout opened
/// against it, and a signature verified on the way back (launch C2).
///
/// Three round trips, and each one exists for a reason:
///
/// 1. **`razorpay-order`** fixes the amount server-side. Opening checkout with a
///    bare amount — which is what most integrations do — means the phone decides
///    what it pays.
/// 2. **The SDK** owns its own UI, which is why [PaymentGateway] takes no
///    `BuildContext` and hands back an outcome rather than a widget.
/// 3. **`razorpay-verify`** checks Razorpay's HMAC signature. Without it the
///    reference the SDK returns is just a string the server was asked to
///    believe, which is audit PAY-001 exactly.
///
/// **UPI only**, matching what checkout offers since launch C1: the `method` map
/// below turns the rest off, so the Razorpay sheet cannot present a card field
/// the app has decided not to support.
///
/// [fallback] is used **only** when the server answers `configured: false` —
/// that is, when no Razorpay keys are set yet. A network failure is not a
/// fallback, it is a failed payment; silently dropping to a mock because the
/// server was briefly unreachable would be a way to give food away.
class RazorpayPaymentGateway implements PaymentGateway {
  RazorpayPaymentGateway({required this.supabase, required this.fallback});

  final SupabaseClient supabase;

  /// What to do while there are no keys. See the class comment: reached on
  /// `configured: false` and on nothing else.
  final PaymentGateway fallback;

  @override
  Future<PaymentOutcome> pay({
    required int amount,
    required String description,
  }) async {
    final Map<String, dynamic> intent;
    try {
      final FunctionResponse response = await supabase.functions.invoke(
        'razorpay-order',
        body: <String, dynamic>{'amount': amount, 'description': description},
      );
      intent = Map<String, dynamic>.from(response.data as Map<dynamic, dynamic>);
    } on Object {
      return const PaymentFailed(
        'We couldn\'t start the payment. Check your connection and try again.',
      );
    }

    if (intent['configured'] != true) {
      return fallback.pay(amount: amount, description: description);
    }

    final String? keyId = intent['keyId'] as String?;
    final String? orderId = intent['orderId'] as String?;
    if (keyId == null || orderId == null) {
      return const PaymentFailed('We couldn\'t start the payment.');
    }

    final PaymentSuccessResponse? paid = await _openCheckout(
      keyId: keyId,
      orderId: orderId,
      amount: amount,
      description: description,
      onEnded: (PaymentOutcome outcome) => _ended = outcome,
    );

    if (paid == null) return _ended ?? const PaymentCancelled();

    final String? paymentId = paid.paymentId;
    final String? signature = paid.signature;
    if (paymentId == null || signature == null) {
      // Razorpay reported success without the two things that prove it. Money
      // may well have moved, so this must not read like a decline.
      return const PaymentFailed(
        'Your payment went through but we couldn\'t confirm it. '
        'Don\'t pay again — contact support and we\'ll sort it out.',
      );
    }

    return _verify(
      orderId: paid.orderId ?? orderId,
      paymentId: paymentId,
      signature: signature,
    );
  }

  /// Set by the SDK's error handler, read once the sheet has closed. A field
  /// rather than a second completer because exactly one of the two handlers ever
  /// fires per checkout.
  PaymentOutcome? _ended;

  /// Runs the SDK sheet to its end. Returns the success response, or null with
  /// [onEnded] having been given the failure or cancellation.
  Future<PaymentSuccessResponse?> _openCheckout({
    required String keyId,
    required String orderId,
    required int amount,
    required String description,
    required void Function(PaymentOutcome) onEnded,
  }) async {
    final Completer<PaymentSuccessResponse?> done =
        Completer<PaymentSuccessResponse?>();
    final Razorpay razorpay = Razorpay();

    // `_resync` can replay a response the platform held from a previous run, so
    // guard every completion — completing twice throws.
    void finish(PaymentSuccessResponse? success) {
      if (!done.isCompleted) done.complete(success);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      finish(r);
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      // Razorpay does not have a separate "dismissed" event — a closed sheet
      // arrives here with this code. Treating it as a decline would put an
      // error in front of somebody who simply changed their mind.
      onEnded(
        r.code == Razorpay.PAYMENT_CANCELLED
            ? const PaymentCancelled()
            : PaymentFailed(
                r.message?.trim().isNotEmpty == true
                    ? r.message!
                    : 'Your payment was declined. Try again.',
              ),
      );
      finish(null);
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      // No external wallet is enabled below, so this is unreachable in practice.
      // It is handled anyway: an unhandled event would hang the sheet forever.
      onEnded(const PaymentFailed('That payment method isn\'t supported yet.'));
      finish(null);
    });

    try {
      razorpay.open(<String, dynamic>{
        'key': keyId,
        'order_id': orderId,
        // Paise. The server has already fixed this amount against the order id,
        // so the two cannot disagree — Razorpay would reject the mismatch.
        'amount': amount * 100,
        'currency': 'INR',
        'name': 'Zopiq',
        'description': description,
        // UPI only, matching checkout (launch C1).
        'method': <String, dynamic>{
          'upi': true,
          'card': false,
          'netbanking': false,
          'wallet': false,
          'emi': false,
          'paylater': false,
        },
        // Seconds. A sheet left open on a locked phone should not hold a
        // Razorpay order open indefinitely.
        'timeout': 300,
        'retry': <String, dynamic>{'enabled': false},
      });
      return await done.future;
    } finally {
      razorpay.clear();
    }
  }

  Future<PaymentOutcome> _verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final FunctionResponse response = await supabase.functions.invoke(
        'razorpay-verify',
        body: <String, dynamic>{
          'razorpayOrderId': orderId,
          'razorpayPaymentId': paymentId,
          'signature': signature,
        },
      );
      final Map<String, dynamic> result = Map<String, dynamic>.from(
        response.data as Map<dynamic, dynamic>,
      );
      if (result['verified'] == true) return PaymentSucceeded(paymentId);
    } on Object {
      // Falls through to the same message. Whether the server said no or never
      // answered, the customer's position is identical: they have paid and we
      // cannot yet prove it, so the one thing they must not do is pay again.
    }

    return const PaymentFailed(
      'Your payment went through but we couldn\'t confirm it. '
      'Don\'t pay again — contact support and we\'ll sort it out.',
    );
  }
}
