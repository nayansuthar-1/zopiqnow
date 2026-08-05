import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import 'package:zopiq_rider/core/widgets/location_disclosure.dart';
import 'package:zopiq_rider/features/jobs/data/jobs_datasource.dart';

/// Sends this rider's position to the platform while — and only while — they are
/// carrying something.
///
/// **What decides whether it runs.** Not this class. It is started and stopped
/// by [RiderLocationReporter.setCarrying], which the app drives off the rider's
/// own live jobs, and the database refuses a write from a rider with nothing
/// live regardless (0057). Two gates, and neither is a permission dialog: a
/// rider who declines location still gets jobs, still gets paid, and simply
/// does not appear on the customer's map.
///
/// **The budget: a moving rider is never more than three seconds stale on the
/// customer's screen.** That number is the whole design of this class, and it is
/// spent like this — a fix asked for every [_interval] (2 s), one RPC of a
/// couple of hundred milliseconds, and Realtime's own hop to the phone watching.
/// The customer's map then glides the pin over 1.2 s rather than teleporting it,
/// which is inside the same budget because the glide *starts* on arrival.
///
/// **What this replaced, and why it could not hit that.** The stream used to be
/// filtered to 30 m with a 20-second tick beneath it. Thirty metres is 5 s at
/// 20 km/h, 11 s at 10 km/h, and *never* for a rider walking the last stretch to
/// a gate — so the tick was the real reporting rate, and the customer's dot was
/// routinely twenty seconds behind a rider they could already hear outside.
///
/// **Why quiet-when-parked survived the change.** A rider stopped at a light has
/// not moved, and writes saying so are writes that change nothing and wake a
/// socket in somebody's kitchen. That was `distanceFilter`'s job and it is now
/// [_send]'s: a fix within [_stillMetres] of the last one sent is dropped unless
/// [_stillInterval] has passed. So the fast path is fast for the only thing the
/// customer can see — *movement* — and a parked bike still costs four writes a
/// minute rather than thirty.
///
/// **Why a foreground service** (audit RID-001). Navigate hands the rider to
/// Google Maps, which comes up over this app — and a `whileInUse` app that is no
/// longer in use gets its location throttled to a few fixes an hour, or on
/// Android 10+ to none. The designed happy path was therefore also the path that
/// froze the customer's map for the whole journey. The foreground notification
/// is what buys the stream the right to keep running; the rider sees it in their
/// shade for as long as they are carrying and never after.
class RiderLocationReporter {
  RiderLocationReporter(this._jobs);

  final JobsDataSource _jobs;

  StreamSubscription<Position>? _stream;
  bool _carrying = false;

  /// No distance filter at all. The platform is asked for every fix it has and
  /// [_send] decides what is worth a write — because a filter set in metres is a
  /// filter whose *time* behaviour depends on how fast the rider happens to be
  /// going, which is exactly the thing the three-second budget cannot leave to
  /// chance.
  static const int _metres = 0;

  /// How often Android is asked for a fix. iOS has no equivalent knob and
  /// delivers roughly this rate on its own for [ActivityType.automotiveNavigation]
  /// with no distance filter.
  static const Duration _interval = Duration(seconds: 2);

  /// Movement smaller than this, between one fix and the next sent, is GPS noise
  /// on a stationary bike rather than a rider going anywhere.
  static const double _stillMetres = 10;

  /// How often a rider who is *not* moving still reports. It exists so the row's
  /// `updated_at` stays fresh — a position older than two minutes is drawn as no
  /// rider at all on the customer's side, and a bike parked outside a kitchen
  /// for ten minutes must not read as a rider who has vanished.
  static const Duration _stillInterval = Duration(seconds: 15);

  /// The watchdog. Not the reporting rate any more — with no distance filter the
  /// stream cannot simply go quiet, so this fires only when the stream has
  /// genuinely stopped delivering (GPS lost indoors, the OS throttling us
  /// despite the foreground service) and covers it by asking for a fix directly.
  ///
  /// Deliberately longer than [_stillInterval]: a *working* stream writes at
  /// least that often even from a parked bike, so silence past this is the
  /// stream being broken rather than the rider being still. Set them equal and
  /// this would fire on jitter and buy a GPS fix nobody needed.
  static const Duration _watchdog = Duration(seconds: 20);

  Timer? _tick;

  /// The last position actually written, and when. Both null until the first
  /// send of a shift, which is why the first fix is never suppressed.
  Position? _sent;
  DateTime? _sentAt;

  /// Called whenever the rider's set of live jobs changes. Idempotent — passing
  /// the same value twice does nothing, which matters because the provider that
  /// drives it rebuilds on every list refresh.
  Future<void> setCarrying(bool carrying) async {
    if (carrying == _carrying) return;
    _carrying = carrying;
    if (carrying) {
      await _start();
    } else {
      await stop();
    }
  }

  Future<void> _start() async {
    if (!await _permitted()) return;
    // The rider may have stopped carrying while the permission dialog was open.
    if (!_carrying) return;

    await _stream?.cancel();
    _stream =
        Geolocator.getPositionStream(
          locationSettings: _settings(),
        ).listen(
          _send,
          // A GPS stream that errors — airplane mode, a revoked permission
          // mid-shift — must not take the app down with it. The map stops
          // updating; nothing else changes.
          onError: (Object _) {},
        );

    _tick?.cancel();
    _tick = Timer.periodic(_watchdog, (_) async {
      if (!_carrying) return;
      // The stream is the reporting path. This only steps in when it has
      // stopped delivering — otherwise it would double every write a moving
      // rider already makes.
      final DateTime? at = _sentAt;
      if (at != null && DateTime.now().difference(at) < _watchdog) return;
      try {
        _send(await _current());
      } on Object {
        // Same reasoning as onError above.
      }
    });
  }

  /// The same intent, expressed twice, because the two platforms buy the right
  /// to keep reporting in completely different currencies.
  ///
  /// Android buys it with a **foreground service**: a visible ongoing
  /// notification, and no background-location grant at all. iOS has no such
  /// thing — it buys the same right with the `location` background mode in
  /// Info.plist and the flag below. Notably *not* with an "Always" grant:
  /// WhenInUse plus the background mode already keeps fixes arriving while
  /// Google Maps is on screen, so the rider's Info.plist asks for no more than
  /// the customer's does. See the note there.
  ///
  /// The two iOS flags that are not optional:
  ///
  /// * `allowBackgroundLocationUpdates` is the switch itself. Without it iOS
  ///   suspends the stream the instant another app covers this one, which is
  ///   RID-001 all over again on a platform that never had the fix.
  /// * `pauseLocationUpdatesAutomatically: false`, because the default is true
  ///   and iOS decides "stopped moving" on its own — a rider waiting ten minutes
  ///   for a kitchen would have the stream paused *and never resumed*, since iOS
  ///   only resumes on significant motion it may not detect on a scooter.
  ///
  /// `showBackgroundLocationIndicator` is the honesty half, and the direct
  /// counterpart of Android's ongoing notification: the status bar stays blue
  /// for exactly as long as we hold the stream. Both platforms tell the rider,
  /// continuously, that they are being located.
  LocationSettings _settings() {
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _metres,
        activityType: ActivityType.automotiveNavigation,
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _metres,
      // The reporting rate, and the first term in the three-second budget.
      // Android treats this as the rate it *aims* for rather than a guarantee —
      // it will deliver slower when the GPS cannot do better, which is why
      // [_watchdog] exists underneath it.
      intervalDuration: _interval,
      // Naming what we are doing and why, in the rider's own notification
      // shade. `setOngoing` because a location share the rider can swipe
      // away while it keeps running is the thing this notification exists
      // to prevent; it clears the moment the stream is cancelled.
      //
      // `enableWakeLock` is what stops the fixes arriving in a burst when
      // the phone next wakes — a partial wake lock held only while
      // carrying, and released with the service. It is why the manifest
      // declares WAKE_LOCK.
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'On a delivery',
        notificationText: 'Sharing your location with the customer',
        notificationChannelName: 'Delivery location',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  Future<Position> _current() => Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );

  Future<void> stop() async {
    await _stream?.cancel();
    _stream = null;
    _tick?.cancel();
    _tick = null;
    // So the next job starts clean. Kept, and the first fix of a shift would be
    // measured against a position from the last one — suppressed if the rider
    // happens to start where they finished, which is exactly what a rider doing
    // two deliveries from the same kitchen does.
    _sent = null;
    _sentAt = null;
  }

  void _send(Position p) {
    if (!_shouldSend(p)) return;
    _sent = p;
    _sentAt = DateTime.now();

    // Fire and forget. A failed write is one missed dot, and the next one is
    // two seconds away — retrying would build a queue of positions that were
    // true a minute ago, which is worse than the gap.
    unawaited(
      _jobs
          .recordLocation(
            lat: p.latitude,
            lng: p.longitude,
            // `heading` is -1 or NaN on a stationary device on some Android
            // builds; null is the honest answer and the column is nullable
            // exactly for it.
            heading: p.heading.isFinite && p.heading >= 0 ? p.heading : null,
            speedKmh: p.speed.isFinite && p.speed >= 0 ? p.speed * 3.6 : null,
          )
          .catchError((Object _) {}),
    );
  }

  /// Whether this fix is worth a write.
  ///
  /// Yes if the rider has moved — that is the case the customer is watching and
  /// it is never delayed. Yes if nothing has been sent for [_stillInterval],
  /// which keeps a parked bike's row from ageing into "no rider". No otherwise,
  /// which is what stops a stationary phone writing thirty times a minute now
  /// that nothing filters the stream by distance.
  bool _shouldSend(Position p) {
    final Position? last = _sent;
    final DateTime? at = _sentAt;
    if (last == null || at == null) return true;
    if (DateTime.now().difference(at) >= _stillInterval) return true;
    return Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          p.latitude,
          p.longitude,
        ) >=
        _stillMetres;
  }

  /// Asks once, at the moment the rider actually starts carrying — not at
  /// launch, and not at sign-in. A permission dialog makes sense to somebody who
  /// has just accepted a delivery and makes none to somebody opening an app for
  /// the first time.
  Future<bool> _permitted() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Play's prominent disclosure, in front of the system dialog. This
        // class has no widget of its own, so the sheet goes up on the root
        // navigator — see `riderNavigatorKey`. Declining returns false and the
        // rider simply does not appear on the customer's map, which is the
        // outcome this class was already written to tolerate.
        if (!await ensureLocationDisclosed()) return false;
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } on Object {
      return false;
    }
  }
}
