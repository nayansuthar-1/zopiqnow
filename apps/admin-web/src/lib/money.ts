/// Rupees, formatted once.
///
/// The console showed money two ways: `₹{n}` on nine screens and
/// `₹${n.toLocaleString('en-IN')}` on two, so the same figure read `₹125000` on
/// All orders and `₹1,25,000` on Settlements. In a console whose four busiest
/// screens are money, that is not a cosmetic difference — a lakh and ten
/// thousand look alike at a glance and only one of them has commas.
///
/// `en-IN` groups the Indian way (1,25,000 — not 125,000), which is the whole
/// reason the locale is named rather than left to the browser.
export function inr(amount: number): string {
  return `₹${amount.toLocaleString('en-IN')}`
}

/// The same figure with its sign spelled out, for ledger columns where a credit
/// and a debit sit in one column and the reader has to tell them apart.
/// U+2212 MINUS, not a hyphen: at 14px a hyphen beside a rupee sign reads as a
/// dash between two numbers.
export function inrSigned(amount: number): string {
  return `${amount < 0 ? '−' : '+'}₹${Math.abs(amount).toLocaleString('en-IN')}`
}
