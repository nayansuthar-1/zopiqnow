import 'package:flutter/foundation.dart';

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
  });

  final String email;
  final String restaurantId;
  final String restaurantName;
}
