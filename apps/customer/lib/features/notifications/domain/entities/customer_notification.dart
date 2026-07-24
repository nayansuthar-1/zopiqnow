import 'package:flutter/foundation.dart';

/// What kind of alert a row is. A customer only ever receives order updates and
/// the occasional system notice today; an unknown wire value degrades to
/// [system] rather than crashing an older build (the reason 0047 keeps `kind` a
/// tolerant check, not an enum the client must know in full).
enum CustomerNotificationKind {
  orderUpdate,
  system;

  static CustomerNotificationKind fromWire(String wire) => switch (wire) {
    'order_update' => orderUpdate,
    _ => system,
  };
}

/// One line in the customer's inbox — something that happened to an order, and
/// whether it has been seen. Read-only in the app: a database trigger (0047)
/// writes the content; the only thing the app changes is [readAt], through an
/// RPC.
@immutable
class CustomerNotification {
  const CustomerNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body,
    this.orderId,
    this.readAt,
  });

  final int id;
  final CustomerNotificationKind kind;
  final String title;
  final String? body;

  /// The order a tap opens, if this is about one.
  final String? orderId;

  final DateTime createdAt;

  /// Null until the customer has seen it.
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory CustomerNotification.fromJson(Map<String, dynamic> json) =>
      CustomerNotification(
        id: (json['id'] as num).toInt(),
        kind: CustomerNotificationKind.fromWire(json['kind'] as String),
        title: json['title'] as String,
        body: json['body'] as String?,
        orderId: json['order_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );
}
