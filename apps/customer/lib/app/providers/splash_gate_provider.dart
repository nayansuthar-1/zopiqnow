import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the brand animation runs — the length of [SplashPage]'s timeline,
/// and nothing else's.
///
/// A provider rather than a constant for one reason: widget tests drive a cold
/// start on nearly every case, and a suite that waits out a second and a half of
/// brand on each of them is a suite that stops being run. Override it to
/// [Duration.zero] and the gate below opens on the first frame.
final Provider<Duration> splashHoldProvider = Provider<Duration>(
  (Ref ref) => const Duration(milliseconds: 1650),
);

/// The longest the gate will stay shut without the animation reporting in.
///
/// See [SplashGate] for what this is protecting against. It is deliberately far
/// longer than the animation: it is the answer to "the splash never played",
/// not to "the splash is playing", and a failsafe that can fire *during* a
/// normal launch is not a failsafe, it is the bug this class just fixed.
const Duration _failsafe = Duration(seconds: 8);

/// Whether the brand animation has finished and the router may move on.
///
/// Closed by [SplashPage] when its timeline completes, because that is the only
/// clock that knows. It used to be a timer of the same length as the animation,
/// started when this provider was first read — and those turned out to be two
/// different moments. The router builds `_AuthRefreshListenable`, which listens
/// to this provider and so starts it, roughly 700ms before [SplashPage] mounts
/// and begins animating. Two thirds of the hold was spent before the first
/// frame of the animation, and the tagline was cut off at t=0.58 of 1.0 — the
/// words never appeared.
///
/// The timer survives as a failsafe rather than as the mechanism. The original
/// worry stands and is worth restating: a gate only a widget can close is a gate
/// that stays shut forever when that widget is disposed mid-animation, or never
/// mounted at all, and the customer is left on an orange screen with no way off.
/// So both exist — the animation opens it in the ordinary case, and [_failsafe]
/// guarantees it opens regardless.
class SplashGate extends Notifier<bool> {
  @override
  bool build() {
    final Duration hold = ref.watch(splashHoldProvider);
    if (hold == Duration.zero) return true;

    final Timer timer = Timer(_failsafe, open);
    ref.onDispose(timer.cancel);
    return false;
  }

  /// Lets the router move on. Idempotent, so the failsafe firing after the
  /// animation has already opened the gate is a no-op rather than a second
  /// notification and a second redirect.
  void open() {
    if (!state) state = true;
  }
}

final NotifierProvider<SplashGate, bool> splashGateProvider =
    NotifierProvider<SplashGate, bool>(SplashGate.new);
