import 'package:flutter/foundation.dart';

/// A signed-in delivery partner.
///
/// Unlike the vendor's `Vendor`, there is no restaurant here and that absence is
/// the whole platform-fleet decision made concrete: a rider is not attached to a
/// kitchen, they are a Zopiqnow partner who can take a job from any of them.
///
/// This object grants nothing. Every row a rider can reach is decided by
/// `delivery_partner_email()` in Postgres (migration 0025); this exists so the
/// app can greet someone by name.
@immutable
class Rider {
  const Rider({
    required this.email,
    required this.name,
    required this.phone,
  });

  final String email;
  final String name;
  final String phone;
}
