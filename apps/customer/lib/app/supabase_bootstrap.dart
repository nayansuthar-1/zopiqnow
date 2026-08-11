import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/app/env.dart';
import 'package:zopiqnow/core/storage/secure_store.dart';
import 'package:zopiqnow/core/storage/supabase_secure_local_storage.dart';

/// Brings Supabase up *beside* the first frame rather than in front of it.
///
/// `Supabase.initialize` reads the persisted session out of the Keystore, and on
/// a phone's first launch after install that is not cheap: 3.4s measured on a
/// CPH2263, against roughly 0.2s on every launch after, because the first call
/// is the one that makes the keyset. Awaiting it in `main` put all of that
/// between the process starting and `runApp`, which is the one window in which
/// nothing can be drawn — so the splash it was meant to play behind could not
/// exist yet, and the customer watched the launch window's flat orange for six
/// seconds instead.
///
/// It is therefore *started* before `runApp` and *awaited* after. The work is
/// the same length; it now happens while the brand animation is on screen.
///
/// Started before `runApp` and not after, deliberately: the first frame is built
/// during a warm-up frame that can run while `main` is still suspended, so a
/// bootstrap kicked off below `runApp` would race the widget that waits on it.
/// By the time any widget exists, [ready] is already a real future.
abstract final class SupabaseBootstrap {
  static Future<void>? _started;

  /// Completes when `Supabase.instance` is safe to touch.
  ///
  /// Resolves immediately when [start] was never called. That is the widget
  /// tests' case: they bind fakes over the data sources and never stand a real
  /// client up, and they must not hang waiting for one.
  static Future<void> get ready => _started ?? Future<void>.value();

  /// Idempotent — the second caller gets the first call's future, never a second
  /// `initialize`, which throws.
  static Future<void> start(SecureStore secureStore) =>
      _started ??= _initialize(secureStore);

  static Future<void> _initialize(SecureStore secureStore) async {
    // Sets up the Postgres client (and, later, the realtime socket for order
    // tracking). It does not open a connection here — the first query does.
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SupabaseSecureLocalStorage(secureStore),
      ),
    );
  }
}
