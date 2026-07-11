/// How the customer pays for an order.
///
/// [upi] currently settles through the mock gateway (no real money moves): the
/// Razorpay keys and the backend that creates the payment order arrive in
/// Step 7, and swapping them in replaces the gateway binding, not this enum.
enum PaymentMethod { cod, upi }
