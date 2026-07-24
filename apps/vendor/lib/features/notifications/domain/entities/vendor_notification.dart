import 'package:flutter/foundation.dart';

/// What kind of alert a row is. [newOrder] and [settlement] are written by
/// triggers (0021, 0047); [system] is the home any other source lands in — an
/// unknown wire value degrades to it rather than crashing an older build.
enum NotificationKind {
  newOrder,
  settlement,
  system;

  static NotificationKind fromWire(String wire) => switch (wire) {
    'new_order' => newOrder,
    'settlement' => settlement,
    _ => system,
  };
}

/// One line in the kitchen's inbox — a thing that happened, and whether it has
/// been seen. Read-only in the app: the content is the database's (a trigger
/// writes it), and the only thing the vendor changes is [readAt], through an RPC.
@immutable
class VendorNotification {
  const VendorNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body,
    this.orderId,
    this.readAt,
  });

  final int id;
  final NotificationKind kind;
  final String title;
  final String? body;

  /// The order a tap opens the queue for, if this is about one.
  final String? orderId;

  final DateTime createdAt;

  /// Null until the kitchen has seen it.
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory VendorNotification.fromJson(Map<String, dynamic> json) =>
      VendorNotification(
        id: (json['id'] as num).toInt(),
        kind: NotificationKind.fromWire(json['kind'] as String),
        title: json['title'] as String,
        body: json['body'] as String?,
        orderId: json['order_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );
}
