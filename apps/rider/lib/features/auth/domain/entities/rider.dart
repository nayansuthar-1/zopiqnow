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
    this.rating = 0,
    this.ratingCount = 0,
  });

  final String email;
  final String name;
  final String phone;

  /// What customers have made of this rider's deliveries (migration 0062).
  ///
  /// Recomputed by a trigger from the reviews underneath it — no app writes it,
  /// including this one. A rating a client could set is not a rating.
  final double rating;

  /// How many customers rated a delivery. Zero means **not rated yet**, which
  /// the profile shows as a dash rather than as 0.0 — a new partner has no
  /// score, not the worst possible one.
  final int ratingCount;

  bool get isRated => ratingCount > 0;
}
