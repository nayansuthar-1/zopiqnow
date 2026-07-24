import 'package:flutter/foundation.dart';

/// The person carrying the order, as the customer is allowed to see them.
///
/// Three fields, and no email or id among them: the rider is not an account the
/// customer can look up, they are a name and a number for the length of one
/// delivery. The policy behind this (migration 0039) narrows it further — the
/// row is only readable while the order is actually out for delivery.
@immutable
class OrderRider {
  const OrderRider({
    required this.name,
    required this.phone,
    required this.vehicle,
    this.isAtDoor = false,
  });

  /// The rider has said they are outside (0049). The one fact on this screen
  /// worth interrupting somebody for, and the moment the delivery code matters.
  final bool isAtDoor;

  final String name;
  final String phone;

  /// `bike`, `scooter` or `bicycle` — the wire values the schema allows.
  final String vehicle;
}
