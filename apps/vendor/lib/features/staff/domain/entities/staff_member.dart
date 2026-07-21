import 'package:flutter/foundation.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';

/// One person on a restaurant's roster.
///
/// Keyed by email and not by a user id, because that is how `restaurant_staff`
/// has been keyed since 0009: ops grants access to an address days before
/// anyone at that address has ever opened the app and been issued an id. A
/// member who has never signed in is a perfectly ordinary row here.
@immutable
class StaffMember {
  const StaffMember({
    required this.email,
    required this.role,
    required this.createdAt,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    email: json['email'] as String,
    role: StaffRole.fromDb(json['role'] as String?),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String email;
  final StaffRole role;

  /// When they were added to the roster — not when they last signed in, which
  /// this app has no way to know.
  final DateTime createdAt;
}
