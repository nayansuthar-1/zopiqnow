/// The signed-in user. Thin by design: the profile service owns everything
/// beyond identity.
class AuthUser {
  const AuthUser({required this.id, required this.phone});

  final String id;

  /// E.164, e.g. `+919876543210`.
  final String phone;

  /// The national part, for display: `+919876543210` → `98765 43210`.
  String get displayPhone {
    final String national = phone.startsWith('+91')
        ? phone.substring(3)
        : phone;
    if (national.length != 10) return phone;
    return '${national.substring(0, 5)} ${national.substring(5)}';
  }
}

/// Access + refresh pair (SAD 9.2). The access token is a short-lived JWT; the
/// refresh token is opaque and rotating. Refresh-on-401 arrives with the Dio
/// interceptor in Step 7 — today nothing calls an authenticated endpoint.
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// What gets persisted to the secure store: identity + credentials.
class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final AuthUser user;
  final AuthTokens tokens;
}
