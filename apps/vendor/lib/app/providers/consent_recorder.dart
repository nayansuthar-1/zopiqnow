import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:zopiq_legal/zopiq_legal.dart';

import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// Set true by the tick box on the sign-in screen, and by nothing else.
///
/// Consent is given one route before it can be recorded — the tick happens on
/// the sign-in screen, where there is no user id, and the sign-in that produces
/// one finishes on the OTP screen. This carries the fact across that gap.
///
/// Without it the recorder below could only see "somebody became signed in",
/// and that is also what a *restored session* looks like on a cold start:
/// `AuthUnknown` to `AuthSignedIn`, the same transition. Recording on that
/// would write an acceptance for a kitchen that has never seen a tick box.
final StateProvider<bool> pendingConsentProvider = StateProvider<bool>(
  (Ref ref) => false,
);

/// Turns the tick on the sign-in screen into a row on the server.
///
/// [AuthNotStaff] is deliberately not recorded against. Somebody whose email is
/// not on `restaurant_staff` agreed to the terms and then turned out not to work
/// here; there is no restaurant account for the acceptance to belong to.
final Provider<void> consentRecorderProvider = Provider<void>((Ref ref) {
  ref.listen<VendorAuthState>(vendorAuthControllerProvider, (
    VendorAuthState? was,
    VendorAuthState now,
  ) {
    if (now is! AuthSignedIn || was is AuthSignedIn) return;
    if (!ref.read(pendingConsentProvider)) return;

    // Cleared before the write. The write is idempotent server-side, so a lost
    // one costs a record; a flag left set costs a *false* record on whatever
    // the next sign-in happens to be.
    ref.read(pendingConsentProvider.notifier).state = false;
    recordPolicyConsent(Supabase.instance.client, surface: 'vendor');
  });
});
