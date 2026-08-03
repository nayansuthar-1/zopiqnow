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
/// **Why distance and not only time.** A rider stopped at a light for ninety
/// seconds has not moved, and three writes saying so are three writes that
/// change nothing and wake a socket in somebody's kitchen. `distanceFilter`
/// makes the stream itself quiet, and the periodic tick underneath it exists
/// only so a *moving* rider on a straight road still reports at a predictable
/// rate rather than in bursts at corners.
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

  /// Thirty metres. Below that is GPS noise on a parked bike; above it and a
  /// dot on the customer's map moves in visible jumps.
  static const int _metres = 30;

  /// The ceiling on how stale a position may get while the rider is moving
  /// slowly through traffic — the one case `distanceFilter` alone goes quiet on
  /// a rider who is genuinely still making progress.
  static const Duration _heartbeat = Duration(seconds: 20);

  Timer? _tick;

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
    _tick = Timer.periodic(_heartbeat, (_) async {
      if (!_carrying) return;
      try {
        _send(await Geolocator.getLastKnownPosition() ?? await _current());
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
  }

  void _send(Position p) {
    // Fire and forget. A failed write is one missed dot, and the next one is
    // twenty seconds away — retrying would build a queue of positions that were
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
