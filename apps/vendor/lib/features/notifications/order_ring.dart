import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// A new order rings the kitchen like a phone call, and keeps ringing until
/// somebody answers it.
///
/// The chime this replaces played once. One ping is exactly what a kitchen in
/// the middle of service does not hear, which is why orders sat unanswered
/// until the accept window ran out. So this is deliberately hard to ignore: the
/// phone's own ringtone, on the **alarm** stream, repeated by the system until
/// the notification is answered, with Accept and Reject on the notification
/// itself.
///
/// Three flags do the work, and the obvious one is not among them:
///
///  * **`FLAG_INSISTENT`** is what "keeps ringing" actually means. Android
///    repeats the sound of a notification carrying this flag until the user
///    interacts with it. There is no Dart-level name for it, so it goes in as a
///    raw bit through [AndroidNotificationDetails.additionalFlags].
///  * **`ongoing: true`** stops it being swiped away. Without it the ring is one
///    flick from silence, and a dismissed order is the failure we started with.
///  * **`AudioAttributesUsage.alarm`** decides *which volume slider applies*. On
///    the notification stream a phone set to vibrate rings silently; on the
///    alarm stream it does not. This is the single most load-bearing line here.
///
/// ⚠️ **The channel id is new on purpose.** An Android 8+ channel's sound and
/// importance are frozen when it is created and cannot be edited afterwards, so
/// the calm `new_orders` channel could never be upgraded in place on a device
/// that already had it — every existing install would keep the old quiet ping.
/// Ringing needs a channel that has never existed before. `new_orders` stays
/// exactly as it was and still carries the ordinary notifications that
/// `send-notification` sends.
class OrderRing {
  OrderRing._();

  /// The ringing channel. Never reuse `new_orders` here — see the class note.
  static const String channelId = 'incoming_orders';
  static const String channelName = 'Incoming orders';

  /// One ring at a time, under a fixed id. Two orders arriving together must not
  /// start two ringtones over each other — the kitchen hears one bell and finds
  /// two tickets on the queue, which is the same thing a phone does with a
  /// second caller.
  static const int _ringId = 909090;

  /// Action ids, echoed back to the response handler in [PushService].
  static const String actionAccept = 'accept_order';
  static const String actionReject = 'reject_order';

  /// `Notification.FLAG_INSISTENT`. The bit that makes Android repeat the sound
  /// until the notification is answered rather than playing it once.
  static final Int32List _insistent = Int32List.fromList(<int>[4]);

  /// Ring, pause, ring — a telephone cadence rather than a buzz, because the
  /// point is for it to read as a call from across a kitchen.
  static final Int64List _cadence =
      Int64List.fromList(<int>[0, 1000, 800, 1000, 800, 1000]);

  /// The device's own ringtone, so it sounds like the thing the vendor already
  /// picks up. Shipping our own audio file would mean a second thing to license
  /// and a sound nobody recognises.
  static const UriAndroidNotificationSound _ringtone =
      UriAndroidNotificationSound('content://settings/system/ringtone');

  /// Talks to [MainActivity] to pin the alarm volume while ringing. Absent in
  /// the FCM background isolate — there is no activity there — so every call
  /// through it is guarded and optional.
  ///
  /// **Android only, and argued for rather than defaulted to.** iOS has no
  /// supported way to move the system volume: `AVAudioSession` has no setter
  /// and `MPVolumeView`'s slider is the only route, which Apple rejects apps
  /// for driving programmatically. Nothing registers this channel on iOS, so
  /// [_setVolumeBoost] takes the same [MissingPluginException] path it takes in
  /// the background isolate and the ring plays at whatever level the phone is
  /// already set to. The ring itself is not Android-only — see the
  /// `DarwinNotificationDetails` below.
  static const MethodChannel _volume = MethodChannel('zopiqnow/vendor_ring');

  static FlutterLocalNotificationsPlugin? _plugin;

  /// True while a ring is up, so [stop] is cheap to call from the several places
  /// that legitimately want to call it on every stream tick.
  static bool _ringing = false;

  static bool get isRinging => _ringing;

  /// The order the vendor answered from the notification tray, if any.
  ///
  /// A [ValueNotifier] rather than a provider because it is written from the
  /// notification response handler, which is a plain callback with no `Ref` and
  /// — for a killed app — not even the same isolate as the widget tree. The
  /// shell listens and puts the queue in front of them.
  static final ValueNotifier<String?> answered = ValueNotifier<String?>(null);

  /// Creates the channel. Safe to call more than once; Android treats a repeat
  /// create of an existing channel as a no-op rather than an edit.
  static Future<void> install(FlutterLocalNotificationsPlugin plugin) async {
    _plugin = plugin;
    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: 'Rings until a new order is accepted or rejected.',
      importance: Importance.max,
      sound: _ringtone,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      vibrationPattern: _cadence,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Start ringing for [orderId].
  ///
  /// [ringFor] bounds it. Ringing genuinely forever is not a kindness to anyone:
  /// an unanswered order is auto-expired at its `accept_deadline` (0051, five
  /// minutes after it was placed), and a phone still ringing for an order the
  /// database has already given up on is noise with nothing behind it. Callers
  /// pass the time actually left on that deadline; the default is the full five
  /// minutes for a caller that does not know.
  static Future<void> ring({
    required String orderId,
    required String body,
    Duration ringFor = const Duration(minutes: 5),
  }) async {
    final FlutterLocalNotificationsPlugin? plugin = _plugin;
    if (plugin == null) return;

    // A deadline that has already passed would be a notification Android
    // cancels the instant it is posted — a flash of sound and nothing else.
    final int ms = ringFor.inMilliseconds;
    if (ms <= 0) return;

    try {
      await plugin.show(
        _ringId,
        'New order',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.max,
            priority: Priority.max,
            // Tells Android this is call-like: it ranks above ordinary
            // notifications and survives more of Do Not Disturb.
            category: AndroidNotificationCategory.call,
            sound: _ringtone,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            vibrationPattern: _cadence,
            // Not swipeable, and it does not clear itself when tapped — only
            // answering it, or the deadline, takes it down.
            ongoing: true,
            autoCancel: false,
            // The opposite of what the name suggests you want: `true` would
            // silence a re-post, and a re-post is how a ring is renewed.
            onlyAlertOnce: false,
            additionalFlags: _insistent,
            timeoutAfter: ms,
            actions: <AndroidNotificationAction>[
              const AndroidNotificationAction(
                actionAccept,
                'Accept',
                showsUserInterface: true,
                cancelNotification: true,
              ),
              const AndroidNotificationAction(
                actionReject,
                'Reject',
                showsUserInterface: true,
                cancelNotification: true,
              ),
            ],
          ),
          // iOS cannot loop a notification sound without Apple's Critical
          // Alerts entitlement, which is granted by application only. Time
          // Sensitive is the loudest thing available unasked: it breaks through
          // a Focus mode. The iOS project still needs the matching capability
          // (see IOS_HANDOVER.md) — until then this degrades to a normal alert.
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBanner: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: orderId,
      );
      _ringing = true;
      await _setVolumeBoost(true);
    } on Object catch (e) {
      debugPrint('Could not ring the new order: $e.');
    }
  }

  /// Stop ringing and hand the volume slider back.
  ///
  /// The cancel is **unconditional**, and deliberately not guarded by
  /// [_ringing]. An `ongoing` notification outlives the process that posted it,
  /// so the one case that matters most — the app was killed mid-ring and has
  /// just been relaunched — is exactly the case where `_ringing` is a fresh
  /// `false` and a guarded stop would leave the phone ringing. Cancelling an id
  /// that is not showing is free.
  static Future<void> stop() async {
    final bool wasRinging = _ringing;
    _ringing = false;
    try {
      await _plugin?.cancel(_ringId);
    } on Object catch (e) {
      debugPrint('Could not cancel the order ring: $e.');
    }
    // Only if we were the ones who raised it. The native side is the authority
    // on what the level was before, and it ignores a restore it did not boost.
    if (wasRinging) await _setVolumeBoost(false);
  }

  /// Pin the alarm stream to maximum while ringing, and put it back afterwards.
  ///
  /// The alarm stream is already the right stream, but a vendor who once turned
  /// their alarm down to a third has a ring at a third — and "full audio" was
  /// the ask. The native side remembers the level it found and restores exactly
  /// that, so this borrows the setting rather than overwriting it.
  ///
  /// Optional by design. In the FCM background isolate there is no activity and
  /// therefore no method channel, which throws [MissingPluginException]; the
  /// ring is still perfectly audible on whatever the alarm volume happens to be,
  /// so that is a shrug, not a failure.
  static Future<void> _setVolumeBoost(bool on) async {
    try {
      await _volume.invokeMethod<void>(on ? 'boost' : 'restore');
    } on MissingPluginException {
      // Background isolate. Expected; see above.
    } on Object catch (e) {
      debugPrint('Could not adjust alarm volume: $e.');
    }
  }
}
