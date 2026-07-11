import 'package:flutter/foundation.dart';

/// What a payment gateway answers with — the three endings Razorpay's SDK has:
/// paid, declined, or the customer closed the sheet.
///
/// Cancellation is not a failure: it gets no error message, because the
/// customer already knows what they did.
@immutable
sealed class PaymentOutcome {
  const PaymentOutcome();
}

/// The gateway captured the payment. [paymentId] is the gateway's own
/// reference (Razorpay's `pay_…`), which the backend verifies in Step 7.
@immutable
final class PaymentSucceeded extends PaymentOutcome {
  const PaymentSucceeded(this.paymentId);

  final String paymentId;
}

/// The gateway declined. [message] is written for the customer.
@immutable
final class PaymentFailed extends PaymentOutcome {
  const PaymentFailed(this.message);

  final String message;
}

/// The customer dismissed the payment sheet.
@immutable
final class PaymentCancelled extends PaymentOutcome {
  const PaymentCancelled();
}
