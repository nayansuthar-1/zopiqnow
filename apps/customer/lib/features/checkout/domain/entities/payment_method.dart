/// How the customer pays for an order.
///
/// [cod] is the only method the mock order service can settle. Online payment
/// ([upi]) needs the Razorpay SDK — a new dependency awaiting an approved
/// change request — and a backend to create the payment order, so the checkout
/// screen shows it disabled rather than pretending.
enum PaymentMethod { cod, upi }
