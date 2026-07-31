/// What the platform will tell a rider about their own papers (0080).
///
/// Deliberately thin. The database holds a licence number, an Aadhaar number and
/// four document paths; `my_kyc` returns none of them and this object has
/// nowhere to put them. A rider knowing their licence is on file is the point —
/// a copy of their Aadhaar number sitting in an app's memory on a phone that
/// gets lost is a liability we can simply decline to create.
class RiderKyc {
  const RiderKyc({
    required this.status,
    required this.blockedReason,
    required this.daysToExpiry,
    required this.nothingFiled,
  });

  factory RiderKyc.fromJson(Map<String, dynamic> json) => RiderKyc(
    status: json['status'] as String? ?? 'pending',
    blockedReason: json['blocked_reason'] as String?,
    daysToExpiry: (json['days_to_expiry'] as num?)?.toInt(),
    nothingFiled: json['documents_needed'] as bool? ?? true,
  );

  /// `pending`, `verified` or `rejected` — what an admin last decided.
  final String status;

  /// Why they cannot take deliveries, in a sentence written for them, or null
  /// when nothing is stopping them.
  ///
  /// Not derivable from [status]: a rider verified in March whose insurance
  /// lapsed last night is still `verified` and is still blocked.
  final String? blockedReason;

  /// Days until the *sooner* of the licence and the insurance runs out. Negative
  /// once one has. Null for a bicycle, which has neither.
  final int? daysToExpiry;

  /// Nothing has been filed for this rider at all — they are waiting on somebody
  /// at Zopiqnow to enter their documents, not on a decision.
  final bool nothingFiled;

  bool get canWork => blockedReason == null;

  /// A fortnight's notice. Long enough to renew a policy in India without
  /// hurrying, short enough that the warning still reads as one.
  bool get expiringSoon =>
      canWork && daysToExpiry != null && daysToExpiry! <= 14;
}
