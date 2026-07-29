import 'package:flutter/foundation.dart';

/// One line of the thread between a customer and the rider carrying their order
/// (migration 0061).
///
/// Note that [body] is stored on the row rather than derived from [code]: the
/// code is what was chosen, the body is what was *said*. Rewording a canned line
/// next month must not rewrite a conversation that already happened.
@immutable
class OrderMessage {
  const OrderMessage({
    required this.id,
    required this.isMine,
    required this.body,
    required this.sentAt,
    required this.isRead,
  });

  /// Which side wrote it, resolved at parse time from the wire's `customer` /
  /// `rider`. The widget only ever asks "mine or theirs?", and the two apps that
  /// render this thread answer it from opposite sides — so the answer belongs
  /// here rather than in the bubble.
  factory OrderMessage.fromJson(Map<String, dynamic> json) => OrderMessage(
    id: (json['id'] as num).toInt(),
    isMine: json['sender'] == 'customer',
    body: json['body'] as String,
    sentAt: DateTime.parse(json['created_at'] as String).toLocal(),
    isRead: json['read_at'] != null,
  );

  final int id;
  final bool isMine;
  final String body;
  final DateTime sentAt;

  /// Whether the *other* side has opened the thread since this arrived. Only
  /// meaningful on a line they sent — a message of my own is read by definition.
  final bool isRead;
}

/// One sentence the customer is allowed to send, as the database offers it.
///
/// The list is fetched rather than hard-coded, and that is the point: 0061 owns
/// the wording, so what the button says is exactly what will be stored. Two
/// copies of the list would be two lists, and the day they drift is the day
/// somebody taps "Leave it at the door" and sends "Thank you!".
@immutable
class CannedMessage {
  const CannedMessage({required this.code, required this.body});

  factory CannedMessage.fromJson(Map<String, dynamic> json) => CannedMessage(
    code: json['code'] as String,
    body: json['body'] as String,
  );

  final String code;
  final String body;
}
