import 'package:flutter/foundation.dart';

/// What a person who works here is allowed to be.
///
/// Two, not four (see migration 0024): the owner, and everyone else. The line is
/// drawn around money and around access itself — earnings, settlements, and who
/// may sign in are the owner's; the whole working day belongs to both.
enum StaffRole {
  owner,
  staff;

  /// Anything that is not exactly `owner` is staff — including null, a value the
  /// column cannot hold and a failed read can. Least privilege on the way in: a
  /// screen wrongly hidden is a support call, a screen wrongly shown is a
  /// promise the database will then break in front of the user.
  static StaffRole fromDb(String? value) =>
      value == 'owner' ? StaffRole.owner : StaffRole.staff;

  bool get isOwner => this == StaffRole.owner;
}

/// A signed-in person who works at a restaurant.
///
/// The restaurant is not a preference and not a setting — it is the whole of
/// this user's authority. Every query the app makes is scoped to it by a policy
/// in Postgres, so this object cannot grant access to anything; it exists so the
/// UI can *say* which kitchen it is showing, and so a stream has an id to filter
/// on. Tamper with `restaurantId` and the database returns nothing.
@immutable
class Vendor {
  const Vendor({
    required this.email,
    required this.restaurantId,
    required this.restaurantName,
    required this.acceptingOrders,
    this.role = StaffRole.staff,
  });

  final String email;
  final String restaurantId;
  final String restaurantName;

  /// What this person may do here. Like [restaurantId], it grants nothing — the
  /// 0024 policies and RPCs are what actually refuse a non-owner. It exists so
  /// the app can decline to offer a door the database would slam.
  final StaffRole role;

  /// Whether the kitchen is currently taking orders. The vendor's own switch,
  /// enforced in Postgres by `place_order` — flipping this in memory only
  /// changes what the app *says*; the database is what actually refuses a closed
  /// kitchen's orders.
  final bool acceptingOrders;

  Vendor copyWith({String? restaurantName, bool? acceptingOrders}) => Vendor(
    email: email,
    restaurantId: restaurantId,
    restaurantName: restaurantName ?? this.restaurantName,
    acceptingOrders: acceptingOrders ?? this.acceptingOrders,
    role: role,
  );
}
