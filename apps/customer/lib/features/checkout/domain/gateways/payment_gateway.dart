import 'package:zopiqnow/features/checkout/domain/entities/payment_outcome.dart';

/// The seam between checkout and whoever moves the money.
///
/// Modelled on how Razorpay actually behaves: the gateway owns its own UI, so
/// this takes no [BuildContext] and hands back an outcome, not a widget. The
/// mock gateway draws a stand-in sheet; the real one opens the SDK. Checkout
/// can't tell the difference, which is the point.
///
/// [amount] is in whole rupees, like every other price in the app — converting
/// to paise is the Razorpay adapter's job, not the caller's.
abstract interface class PaymentGateway {
  Future<PaymentOutcome> pay({
    required int amount,
    required String description,
  });
}

/// A declined payment, raised by checkout so the screen can say why. A
/// *cancelled* payment raises nothing — see [PaymentCancelled].
class PaymentFailure implements Exception {
  const PaymentFailure(this.message);

  final String message;

  @override
  String toString() => 'PaymentFailure: $message';
}
