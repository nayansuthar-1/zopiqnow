import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where an error goes when nobody is watching (launch C3, audit OBS-001).
///
/// **The bug this exists for was not a crash.** On 29 July migration 0078 put a
/// `where`-less `update` into `place_order`; Supabase's `pg_safeupdate` raised
/// SQLSTATE 21000 for every real customer and for nobody testing through `psql`.
/// The app caught it, showed "We couldn't place your order", and wrote the real
/// error precisely nowhere. **Nobody could order anything for three days**, and
/// the only reason it was found at all is that somebody happened to try.
///
/// A crash reporter that only reports crashes would not have caught that, which
/// is why [recordHandled] exists and is used on the paths that swallow a failure
/// to keep the UI polite. The rule: if the customer is shown a friendly sentence
/// instead of the truth, the truth goes here.
///
/// **Attached before Firebase is up, on purpose.** [attach] is the first thing
/// `main` does — it costs nothing and it means an error thrown during startup is
/// captured rather than lost to a race. Firebase does not come up until after
/// the first frame (see `PushService.start` for why), so anything reported in
/// that window is held in [_pending] and flushed by [enable].
abstract final class CrashReporter {
  /// Set once Crashlytics can actually be written to.
  static bool _ready = false;

  /// Errors raised before [enable] finished. Bounded: if something is throwing
  /// in a loop at startup, the first few tell the whole story and an unbounded
  /// list would be a second bug on top of the first.
  static final List<_PendingError> _pending = <_PendingError>[];
  static const int _maxPending = 20;

  /// Route Flutter's two global error hooks here. Call first in `main`.
  ///
  /// `runZonedGuarded` is deliberately not used: since Flutter 3.3
  /// `PlatformDispatcher.onError` catches everything the zone would, without
  /// wrapping `runApp` in a closure that makes every stack trace longer.
  static void attach() {
    final FlutterExceptionHandler? presentError = FlutterError.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      // Still print it. A developer watching the console should not have to open
      // a web dashboard to see the exception they just caused.
      presentError?.call(details);
      _record(details.exception, details.stack, fatal: true);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _record(error, stack, fatal: true);
      // True: handled. Returning false re-throws it to the platform, which on
      // Android is a process kill — the app would die of the very error we are
      // trying to survive long enough to report.
      return true;
    };
  }

  /// Bring Crashlytics up and flush anything [attach] caught in the meantime.
  ///
  /// Guarded end to end, exactly like `PushService.start`: a device with no
  /// Google Play services, a missing `google-services.json`, a network that is
  /// not there — none of them is a reason for the app to fail to start. Crash
  /// reporting simply stays inert, and says so in the log.
  static Future<void> enable() async {
    try {
      // Idempotent — returns the existing app when `PushService` got there
      // first. Called here too so crash reporting does not depend on push
      // having succeeded; they fail for different reasons.
      await Firebase.initializeApp();

      // Off in debug. A developer's own broken widget is not a production
      // incident, and a dashboard full of them is a dashboard nobody reads.
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );

      _ready = true;

      // Flushed before anything else can throw. These are startup errors — the
      // most valuable ones there are — and letting a later hiccup strand them in
      // the buffer would defeat the whole point of having buffered them.
      for (final _PendingError held in _pending) {
        await FirebaseCrashlytics.instance.recordError(
          held.error,
          held.stack,
          fatal: held.fatal,
          reason: held.reason,
        );
      }
      _pending.clear();

      // Tie reports to an account here rather than in the sign-in flow, because
      // there are three ways into a session (a fresh sign-in, a restored one,
      // and a token refresh) and only one of them is a screen anybody would
      // think to edit. Subscribing covers all three, and sign-out as well.
      final SupabaseClient client = Supabase.instance.client;
      await identify(client.auth.currentUser?.id);
      client.auth.onAuthStateChange.listen(
        (AuthState state) => unawaited(identify(state.session?.user.id)),
      );
    } on Object catch (e) {
      debugPrint('Crash reporting disabled: $e');
    }
  }

  /// An error the app caught and handled — the customer saw a polite sentence,
  /// and this is the sentence's true cause.
  ///
  /// [reason] should say what the app was trying to do, because the exception
  /// alone rarely does: "place_order" is worth more in a report than
  /// `PostgrestException(code: 21000)` on its own.
  static void recordHandled(
    Object error,
    StackTrace? stack, {
    required String reason,
  }) => _record(error, stack, fatal: false, reason: reason);

  /// Ties reports to an account, so a customer who phones in can be found.
  ///
  /// The Supabase user id and nothing else — not their email, name or number.
  /// It is already the id every one of their rows is keyed by, and it is
  /// meaningless to anyone without access to the database.
  static Future<void> identify(String? userId) async {
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');
    } on Object catch (e) {
      debugPrint('Crash reporting: could not set user ($e).');
    }
  }

  static void _record(
    Object error,
    StackTrace? stack, {
    required bool fatal,
    String? reason,
  }) {
    if (!_ready) {
      if (_pending.length < _maxPending) {
        _pending.add(_PendingError(error, stack, fatal, reason));
      }
      return;
    }
    // Not awaited: an error report must never sit on the path of whatever the
    // app was doing when it failed. Crashlytics queues to disk and sends later.
    //
    // The `catchError` is not defensive habit, it is a loop breaker. An
    // unhandled rejection here would surface through
    // `PlatformDispatcher.onError` — which is this very method — and a reporter
    // that reports its own failure to report is an infinite one.
    unawaited(
      FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: fatal, reason: reason)
          .catchError(
            (Object e) => debugPrint('Crash reporting: report failed ($e).'),
          ),
    );
  }
}

@immutable
class _PendingError {
  const _PendingError(this.error, this.stack, this.fatal, this.reason);

  final Object error;
  final StackTrace? stack;
  final bool fatal;
  final String? reason;
}
