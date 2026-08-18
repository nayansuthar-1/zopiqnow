import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:zopiq_legal/zopiq_legal.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// Set true by the tick box on the sign-in screen, and by nothing else.
///
/// It exists because consent is given one route before it can be recorded: the
/// tick happens on the sign-in screen, where there is no user id, and the
/// sign-in that produces one finishes on the OTP screen. This carries the fact
/// across that gap.
///
/// **It is not a convenience.** Without it the recorder below could only see
/// "somebody became signed in", and that is also what a *restored session*
/// looks like on a cold start — `AuthUnknown` to `AuthSignedIn`, the same
/// transition. Recording on that would write an acceptance for a customer who
/// has never seen a tick box, which is worse than having no record at all: a
/// consent ledger that contains consent nobody gave is evidence of the opposite
/// of what it claims.
final StateProvider<bool> pendingConsentProvider = StateProvider<bool>(
  (Ref ref) => false,
);

/// Turns the tick on the sign-in screen into a row on the server.
///
/// Watched once, at the app root. Living here rather than on a screen is what
/// makes it cover all three paths: Google finishes on the sign-in screen, but
/// email and SMS finish on the OTP screen one route later, and a recorder on
/// either screen would miss whichever paths end on the other.
final Provider<void> consentRecorderProvider = Provider<void>((Ref ref) {
  ref.listen<AuthState>(authControllerProvider, (
    AuthState? was,
    AuthState now,
  ) {
    if (now is! AuthSignedIn || was is AuthSignedIn) return;
    if (!ref.read(pendingConsentProvider)) return;

    // Cleared before the write, not after. The write is idempotent server-side,
    // so a lost one costs a record; a flag left set costs a *false* record on
    // whatever the next sign-in happens to be.
    ref.read(pendingConsentProvider.notifier).state = false;
    recordPolicyConsent(Supabase.instance.client, surface: 'customer');
  });
});
