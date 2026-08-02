import 'package:zopiqnow/features/checkout/domain/entities/payment_outcome.dart';
import 'package:zopiqnow/features/checkout/domain/gateways/payment_gateway.dart';

/// The gateway a release build gets when there are no Razorpay keys and nobody
/// has explicitly asked for the mock (launch C2).
///
/// **Why a refusal is the safe default.** The mock invents a reference and the
/// server, until `payment_settings.require_verified_payment` is flipped, takes
/// any reference it is given (0085). A production build carrying the mock is
/// therefore free food for anyone who installs it — and a payment screen that
/// moves no money is a Play policy problem on its own account, quite apart from
/// the cost.
///
/// So the mock is not something a release build can reach by accident. It has to
/// be asked for:
///
///     flutter build appbundle --dart-define=ALLOW_MOCK_PAYMENTS=true
///
/// Testing tracks are built with that flag. The production build is not, and no
/// amount of forgetting can turn it on.
///
/// Debug builds keep the mock unconditionally — that is what makes the whole
/// flow exercisable without keys, and a debug build is not on anybody's phone.
class LockedPaymentGateway implements PaymentGateway {
  const LockedPaymentGateway();

  @override
  Future<PaymentOutcome> pay({
    required int amount,
    required String description,
  }) async => const PaymentFailed(
    'Payments aren\'t available in this build yet. Please try again shortly.',
  );
}
