/// How a customer describes themselves. Optional, and `other` is a real answer
/// rather than a bucket — nobody is required to fill this in at all.
enum Gender {
  male('Male'),
  female('Female'),
  other('Other');

  const Gender(this.label);

  final String label;

  /// Parses the stored wire value. Null on anything unrecognised, so a value
  /// written by a future build cannot crash an older one.
  static Gender? fromWire(String? wire) {
    for (final Gender g in Gender.values) {
      if (g.name == wire) return g;
    }
    return null;
  }
}

/// The signed-in user, identity *and* profile.
///
/// These were two objects until 2026-07-30: this one, and a `CustomerProfile`
/// held in an in-memory `StateNotifier` seeded with 'Zopiq user'. They are one
/// object now because they were always one row — every field below lives in the
/// same `auth.users.raw_user_meta_data`, and [phone] has lived there since
/// checkout first asked for it. Two objects over one row is a disagreement
/// waiting to happen, and the field it would have happened on first is the
/// number the rider calls.
///
/// Tokens are deliberately absent. Supabase's client owns the access/refresh
/// pair and rotates it; a copy in the domain layer would be a second source of
/// truth that goes stale the first time it refreshes.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.phone,
    this.fullName,
    this.avatarUrl,
    this.dateOfBirth,
    this.gender,
  });

  /// The Supabase user uuid.
  final String id;

  final String email;

  /// E.164, e.g. `+919876543210`. Null until the user gives one: they sign in
  /// with an email, but a rider needs a number to call. Checkout is where we
  /// first ask, because that is the first moment it is actually needed; Account
  /// is where they can change it afterwards.
  final String? phone;

  /// What they call themselves. Null when they have never said and no provider
  /// told us — the UI asks rather than inventing 'Zopiq user'.
  final String? fullName;

  /// A Cloudinary URL they uploaded, or the picture Google gave us at sign-in.
  /// Null means draw their initial.
  final String? avatarUrl;

  /// Date only; the time component is meaningless and never read.
  final DateTime? dateOfBirth;

  final Gender? gender;

  /// The one-word name to greet somebody by. Falls back to the local part of
  /// their email, which is not their name but *is* recognisably theirs — and
  /// then to nothing, which the caller renders as an invitation to set one.
  String? get firstName {
    final String? full = fullName?.trim();
    if (full != null && full.isNotEmpty) return full.split(' ').first;
    final String local = email.split('@').first.trim();
    return local.isEmpty ? null : local;
  }

  /// The letter drawn on the avatar when there is no photo.
  String get initial {
    final String? source = fullName?.trim().isNotEmpty ?? false
        ? fullName!.trim()
        : (email.trim().isEmpty ? null : email.trim());
    return source == null ? '?' : source.substring(0, 1).toUpperCase();
  }

  AuthUser copyWith({
    String? phone,
    String? fullName,
    String? avatarUrl,
    DateTime? dateOfBirth,
    Gender? gender,
  }) => AuthUser(
    id: id,
    email: email,
    phone: phone ?? this.phone,
    fullName: fullName ?? this.fullName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    gender: gender ?? this.gender,
  );
}
