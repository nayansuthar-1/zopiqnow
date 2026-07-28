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
    this.carrierKey,
  });

  /// The delivery's `partner_email`, used as the filter on the live-position
  /// subscription (0057) and **never rendered**.
  ///
  /// It sits on this object rather than costing a second round trip because
  /// `fetchRider` already reads the delivery row it comes from. That it is
  /// readable at all is 0039: a customer may see their own live delivery. It is
  /// not permission to see anything — the policy on `rider_locations` decides
  /// that, and would return nothing for a key belonging to somebody else's
  /// rider.
  final String? carrierKey;

  /// The rider has said they are outside (0049). The one fact on this screen
  /// worth interrupting somebody for, and the moment the delivery code matters.
  final bool isAtDoor;

  final String name;
  final String phone;

  /// `bike`, `scooter` or `bicycle` — the wire values the schema allows.
  final String vehicle;
}
