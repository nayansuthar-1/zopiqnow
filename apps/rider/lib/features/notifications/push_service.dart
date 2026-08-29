import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_rider/features/notifications/offer_ring.dart';

/// The wake: getting a new job to a rider who isn't looking at the app.
///
/// The mirror of the vendor's `PushService`, and since 0148 that includes the
/// ring. It brings Firebase up, makes the `jobs` channel and asks permission,
/// registers this device's token against the signed-in rider
/// (`register_device_token`, audience-aware since 0047), and draws a foreground
/// message the OS would otherwise swallow. The Edge Function `send-notification`
/// is what actually *sends*; this is only the ear.
///
/// A plain object started once from `main`, not a widget or provider — it speaks
/// to platform channels (Firebase, the OS tray) that don't exist under
/// `flutter test`, so keeping it out of the widget tree keeps the tests honest.
class PushService {
  PushService._();

  static const String _channelId = 'jobs';
  static const String _channelName = 'New jobs';

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Bring the whole thing up. Guarded end to end: a device with no Google Play
  /// services, a missing config, a denied permission — none of these is a reason
  /// for the app to fail to start. Push just stays inert.
  static Future<void> start() async {
    try {
      await Firebase.initializeApp();
    } on Object catch (e) {
      // No Firebase, no push. The rider can still pull the board by hand.
      debugPrint('Push disabled: Firebase failed to initialize ($e).');
      return;
    }

    // The channels exist after this, so the ring has somewhere to sound.
    // `OfferRing` refuses to ring until it has been handed the plugin here.
    await _initLocalNotifications();

    // A ring left over from a previous run is a phone that starts ringing for
    // an offer that expired an hour ago. `ongoing` notifications survive the
    // process that posted them, so clearing on start is not paranoia.
    await OfferRing.stop();

    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    // On Android 13+ this raises the POST_NOTIFICATIONS prompt; on older
    // Androids it is a no-op that returns authorized.
    await messaging.requestPermission();

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    // A message that arrives while the app is foregrounded is *not* posted to the
    // tray by Android — we draw it ourselves or the rider never sees it.
    FirebaseMessaging.onMessage.listen(_showForeground);

    // The token can change (reinstall, restore, periodic refresh); each new one
    // has to be re-registered or the sender rings a dead address.
    //
    // Through the same session gate as `_syncTokenToSession`, and not straight
    // into `_registerToken`: the RPC is scoped to `auth.uid()` and *raises*
    // without one ("Please sign in before registering for notifications"),
    // which `_registerToken` then swallows into a `debugPrint` nobody reads on
    // a released build. A fresh install mints its token before anyone has
    // signed in, so that was the common case, not the rare one. Skipping here
    // costs nothing — signing in fires `signedIn`, which registers.
    messaging.onTokenRefresh.listen((String token) {
      if (Supabase.instance.client.auth.currentSession == null) return;
      _registerToken(token);
    });

    // Register now if already signed in, and follow the session from here on:
    // a device only belongs to the rider signed into it.
    await _syncTokenToSession();
    Supabase.instance.client.auth.onAuthStateChange.listen((AuthState s) {
      switch (s.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
          _syncTokenToSession();
        case AuthChangeEvent.signedOut:
          _unregisterCurrentToken();
        default:
          break;
      }
    });
  }

  static Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    // All three request flags false: `messaging.requestPermission()` is the one
    // place this app asks, on both platforms. Leaving them true would show the
    // system dialog a second time.
    const DarwinInitializationSettings darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      // Answering the ring from a killed app runs here instead, in its own
      // isolate. Without it, tapping a ring the app did not draw itself would
      // silence the phone and tell this app nothing.
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationTap,
    );

    // The channel a new-job notification lands on. Must match the id named in
    // the manifest's default-channel meta-data, or Android 8+ drops it.
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'A delivery is ready to claim.',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // The loud one, alongside it rather than instead of it. `jobs` still carries
    // everything else `send-notification` sends a rider; only an *offer* rings.
    await OfferRing.install(_local);
  }

  /// The rider answered the ring — from the tray, or by tapping the body.
  ///
  /// It does two things: stop the noise, and remember which order it was so the
  /// app can open on the Jobs tab rather than wherever the rider last happened
  /// to be. Accepting stays in the app, because accepting is now a call that can
  /// come back "somebody was closer" (0148) and a tray action has nowhere to put
  /// that sentence.
  static void _onNotificationResponse(NotificationResponse response) {
    OfferRing.stop();
    final String? orderId = response.payload;
    if (orderId != null && orderId.isNotEmpty) {
      OfferRing.answered.value = orderId;
    }
  }

  /// Register only if there is a signed-in session; the RPC is scoped to the
  /// caller, so a token with no session behind it would be refused anyway.
  ///
  /// The iOS branch is not defensive padding. FCM cannot mint a token until
  /// APNs has answered `registerForRemoteNotifications` with a device token,
  /// and asked before that, `getToken()` does not wait or return null — it
  /// **throws** ("APNS token has not been set yet"). At cold start that is the
  /// ordinary case: AppDelegate's registration is asynchronous and this runs
  /// within a second of it. So iOS must ask APNs first.
  ///
  /// It has to *wait* for the answer rather than leave, and that is the fix for
  /// 25 Android tokens against zero iOS ones. Leaving was justified by
  /// `onTokenRefresh` picking the device up later, and it does not: that stream
  /// fires when the FCM token is minted or rotated, which on every launch after
  /// the first has already happened. The other two paths do not cover it either
  /// — a *restored* session emits `initialSession`, not `signedIn`, and
  /// `tokenRefreshed` waits for the JWT's hourly roll. So a single lost race at
  /// launch meant the device never registered again, silently, for the life of
  /// the install.
  ///
  /// Waiting is safe here in a way it would not have been before: `main` calls
  /// `start()` *after* `runApp` and after Supabase is up, so this is behind a
  /// painted screen and costs no launch time.
  static Future<void> _syncTokenToSession() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      if (Platform.isIOS && await _awaitApnsToken() == null) return;
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } on Object catch (e) {
      debugPrint('Could not read push token: $e.');
    }
  }

  /// The APNs token once Apple has answered, or null if it never does.
  ///
  /// Ten seconds, because this is bounded by a real answer rather than a guess:
  /// a device that is going to register does so in well under a second, and one
  /// that is not — no network, permission refused at the OS level — would not
  /// answer if we waited all day. Returning null then is the honest outcome and
  /// leaves push inert, exactly as before; what changed is that the ordinary
  /// cold-start case no longer looks like that one.
  static Future<String?> _awaitApnsToken() async {
    for (int attempt = 0; attempt < 20; attempt++) {
      final String? apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null) return apns;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  static Future<void> _registerToken(String token) async {
    try {
      await Supabase.instance.client.rpc<void>(
        'register_device_token',
        params: <String, dynamic>{
          'p_token': token,
          // The real platform, not the constant this sent until iOS existed.
          // `device_tokens.platform` has accepted `'ios'` since 0020, and it is
          // what `send-notification` reads to decide whether a payload needs an
          // APNs block.
          'p_platform': Platform.isIOS ? 'ios' : 'android',
          // Stated, not inferred — see 0060. A rider who is also staff of a
          // restaurant would otherwise have had this phone filed as a
          // restaurant device.
          'p_audience': 'rider',
          // This build draws its own job-offer notification, so it can be sent
          // a data-only message and ring (0148). The column is generic; 0128
          // named it after the kitchen's use because it was the only one.
          // Builds that predate the ring do not send this at all and default to
          // false, which is what keeps `send-notification` including a
          // notification block for them — a data-only message to an older
          // install shows nothing while killed.
          //
          // ⚠️ A device that reports false gets the quiet ping and nothing else,
          // so a phone that is not ringing is worth checking here before the
          // sender is blamed: `select rings_new_orders from device_tokens`.
          'p_rings_new_orders': true,
        },
      );
    } on Object catch (e) {
      debugPrint('Could not register push token: $e.');
    }
  }

  static Future<void> _unregisterCurrentToken() async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client.rpc<void>(
        'unregister_device_token',
        params: <String, dynamic>{'p_token': token},
      );
    } on Object catch (e) {
      debugPrint('Could not unregister push token: $e.');
    }
  }

  /// Bring the notification plugin up inside the FCM background isolate.
  ///
  /// A background isolate starts with nothing registered — [Firebase] handed it
  /// a message and that is all. `DartPluginRegistrant.ensureInitialized()` is
  /// what makes `flutter_local_notifications` reachable at all here, and it is
  /// also why the alarm-volume boost in [OfferRing] is optional: that one lives
  /// in `android/app`, which never reaches a background isolate.
  static Future<void> prepareBackgroundIsolate() async {
    DartPluginRegistrant.ensureInitialized();
    await _initLocalNotifications();
  }

  /// True when this message is the "this job is yours for fifteen seconds" wake,
  /// as opposed to any of the ordinary notifications `send-notification` sends.
  static bool _isJobOffer(RemoteMessage message) =>
      message.data['kind'] == 'job_offer';

  /// Ring for an offer. Shared by the foreground listener and the background
  /// isolate, because a woken rider and one already holding the phone should
  /// hear the same thing — they cannot tell which state the app was in, and
  /// should not have to.
  static Future<void> _ringForOffer(RemoteMessage message) async {
    final String? orderId = message.data['order_id'] as String?;
    if (orderId == null || orderId.isEmpty) return;
    await OfferRing.ring(
      orderId: orderId,
      // The server's title carries the fee — "New delivery — ₹58". Worth
      // sounding for; worth reading before unlocking anything.
      title: (message.data['title'] as String?) ?? 'New delivery',
      body: (message.data['body'] as String?) ?? 'A delivery is offered to you.',
      ringFor: _windowLeft(message.data['expires_at'] as String?),
    );
  }

  /// How long is left of this rider's exclusive window. The server sends the
  /// offer's `expires_at` (0097); a message that sat in a Doze queue for twelve
  /// seconds should ring for the three that remain, not for a fresh fifteen.
  static Duration _windowLeft(String? expiresAt) {
    // What the offer window is today (0148 shipped 15s, tunable in
    // `dispatch_settings`). Used only when the payload carries no deadline at
    // all, which is an older sender rather than a normal case.
    const Duration fallback = Duration(seconds: 15);
    // A ceiling the payload cannot argue with, so a wrong clock or a malformed
    // instant cannot pin the alarm stream open.
    const Duration ceiling = Duration(minutes: 1);
    if (expiresAt == null) return fallback;
    final DateTime? at = DateTime.tryParse(expiresAt);
    if (at == null) return fallback;
    final Duration left = at.difference(DateTime.now().toUtc());
    return left <= Duration.zero
        ? Duration.zero
        : (left > ceiling ? ceiling : left);
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    if (_isJobOffer(message)) {
      await _ringForOffer(message);
      return;
    }
    final RemoteNotification? n = message.notification;
    if (n == null) return;
    await _local.show(
      n.hashCode,
      n.title ?? 'New delivery',
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        // iOS has no channels — importance and sound are decided per
        // notification rather than once when a channel is created. Without this
        // block the call succeeds and draws nothing.
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBanner: true,
        ),
      ),
    );
  }
}

/// Runs in its own isolate when a message arrives with the app killed or
/// backgrounded. Top-level and annotated, as firebase_messaging requires.
///
/// This is where the ring for a closed app is drawn, and it has to be drawn
/// here: a message carrying an FCM `notification` block is posted by Android
/// itself, and Android will not set `FLAG_INSISTENT` on our behalf. So
/// `send-notification` sends a `job_offer` **data only** (0148), Android posts
/// nothing, and this handler owns the whole notification — which is the only way
/// the ring can have the flags and the alarm-stream sound.
///
/// Everything else still falls through to Android, which draws the tray entry
/// from the message's own `notification` block exactly as it always has.
///
/// ⚠️ Nothing `start()` did has happened in this isolate. It is a fresh Dart VM
/// with no plugin registrations, no channel, no initialize. Hence the two lines
/// of setup before anything is shown; skip them and `show` throws.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  if (message.data['kind'] != 'job_offer') return;
  await PushService.prepareBackgroundIsolate();
  await PushService._ringForOffer(message);
}

/// Answering the ring while the app is killed lands here — a separate isolate
/// again, and a separate entry point from [_onBackgroundMessage].
///
/// All it can usefully do is stop the noise. Tapping the notification also
/// launches the app, and the launched app's own `start()` clears any leftover
/// ring and picks the offer up off the realtime stream, so accepting happens
/// there with the whole job in view.
@pragma('vm:entry-point')
void onBackgroundNotificationTap(NotificationResponse response) {
  OfferRing.stop();
}
