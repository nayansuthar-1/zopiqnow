/// Shared value formatters, so six screens don't grow six copies.
///
/// Order-relative age and the `12 Jul · 7:42 PM` date live with the queue in
/// `orders_providers.dart` — they are the queue's own vocabulary. What belongs
/// here is what *every* money-showing screen needs: rupees, grouped the way an
/// Indian reader expects them.
library;

/// `₹1,240`, `₹12,34,567`, `-₹90`. Whole rupees, grouped in the Indian system
/// (last three digits, then twos) rather than the thousands grouping `intl`
/// would give — and by hand, because `intl` is not a dependency this app has.
String formatRupees(int amount) {
  final bool negative = amount < 0;
  final String digits = amount.abs().toString();

  final String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final String last3 = digits.substring(digits.length - 3);
    String rest = digits.substring(0, digits.length - 3);
    final List<String> groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    grouped = '${groups.join(',')},$last3';
  }

  return '${negative ? '-' : ''}₹$grouped';
}
