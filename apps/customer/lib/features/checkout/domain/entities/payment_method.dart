/// How the customer pays for an order.
///
/// [upi] is the only method checkout offers, and since migration 0084 the only
/// one the database will accept on a new order (launch C1). It settles through
/// Razorpay, whose adapter and server-side signature check both exist (launch
/// C2) — until the merchant keys are configured the server reports as much and
/// the adapter falls back to the mock, which moves no money and says so.
///
/// [cod] is kept because **cash orders already exist**. The vendor collects on
/// them, the rider's cash ledger balances against them and their invoices say
/// what happened. It is history this enum has to be able to read, not a choice
/// anybody can still make.
enum PaymentMethod { cod, upi }
