/// How the customer pays for an order.
///
/// [upi] means **prepaid**, not UPI. It is the only value the database accepts
/// on a new order since migration 0084 (launch C1) and the only one checkout
/// writes, but the *instrument* behind it is whatever the merchant account has
/// enabled — a card today, UPI once activation lands. Checkout stopped
/// filtering Razorpay's methods when a UPI-only filter over a card-only account
/// produced an empty sheet; which one was used is recorded on
/// `payment_intents.instrument` (0139), and nothing in any of the three apps
/// branches on it. `RazorpayPaymentGateway` carries the full reasoning.
///
/// [cod] is kept because **cash orders already exist**. The vendor collects on
/// them, the rider's cash ledger balances against them and their invoices say
/// what happened. It is history this enum has to be able to read, not a choice
/// anybody can still make.
enum PaymentMethod { cod, upi }
