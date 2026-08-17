import 'package:flutter/foundation.dart';

/// What kind of alert a row is. A rider hears about jobs appearing, payouts
/// being sent, and their account being switched on or off; an unknown wire value
/// degrades to [system] rather than crashing an older build (the reason 0047
/// keeps `kind` a tolerant check, not an enum the client must know in full).
enum RiderNotificationKind {
  /// A job the dispatcher picked *this* rider for, with a countdown on it
  /// (0056). Distinct from [jobAvailable] because the two are different events:
  /// one is a question addressed to a person and expires, the other is a notice
  /// to a room. Telling them apart by reading the body is how an app eventually
  /// gets it wrong.
  jobOffer,
  jobAvailable,
  jobCancelled,

  /// The customer on a live job said something (0061). Its own kind rather than
  /// [system] because it is the only row here that somebody is waiting on an
  /// answer to.
  message,
  payout,
  account,

  /// The rider did something that will cost them if it continues — today, only
  /// accepting a delivery and not collecting it (0130). Its own kind and not
  /// [system] for the same reason [message] is: this is the one row in the
  /// inbox the rider is expected to act on rather than note, and a warning that
  /// looks like a notice is a warning nobody reads.
  warning,
  system;

  static RiderNotificationKind fromWire(String wire) => switch (wire) {
    'job_offer' => jobOffer,
    'job_available' => jobAvailable,
    'job_cancelled' => jobCancelled,
    'message' => message,
    'payout' => payout,
    'account' => account,
    'warning' => warning,
    _ => system,
  };
}

/// One line in the rider's inbox. Read-only in the app: a database trigger
/// (0047) writes the content; the only thing the app changes is [readAt],
/// through an RPC.
@immutable
class RiderNotification {
  const RiderNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body,
    this.readAt,
  });

  final int id;
  final RiderNotificationKind kind;
  final String title;
  final String? body;
  final DateTime createdAt;

  /// Null until the rider has seen it.
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory RiderNotification.fromJson(Map<String, dynamic> json) =>
      RiderNotification(
        id: (json['id'] as num).toInt(),
        kind: RiderNotificationKind.fromWire(json['kind'] as String),
        title: json['title'] as String,
        body: json['body'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );
}
