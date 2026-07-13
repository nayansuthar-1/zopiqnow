/// The signed-in user. Thin by design: the profile service owns everything
/// beyond identity.
///
/// Tokens are deliberately absent. Supabase's client owns the access/refresh
/// pair and rotates it; a copy in the domain layer would be a second source of
/// truth that goes stale the first time it refreshes.
class AuthUser {
  const AuthUser({required this.id, required this.email, this.phone});

  /// The Supabase user uuid.
  final String id;

  final String email;

  /// E.164, e.g. `+919876543210`. Null until the user gives one: they sign in
  /// with an email, but a rider needs a number to call. Checkout is where we
  /// ask, because that is the first moment it is actually needed.
  final String? phone;

  AuthUser copyWith({String? phone}) =>
      AuthUser(id: id, email: email, phone: phone ?? this.phone);
}
