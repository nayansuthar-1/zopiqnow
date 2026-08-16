import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/notifications/order_ring.dart';

/// The wake: getting a new order to a kitchen that isn't looking at the app.
///
/// Deliberately a plain object, started once from `main`, not a widget or a
/// provider — it speaks to platform channels (Firebase, the OS notification
/// tray) that don't exist under `flutter test`, so keeping it out of the widget
/// tree keeps the tests honest and this off their critical path.
///
/// It does four things, in order: brings Firebase up, makes a channel and asks
/// permission, registers this device's token against the signed-in restaurant
/// (0020), and renders a foreground message the OS would otherwise swallow. The
/// backend (an Edge Function) is what actually *sends*; this is only the ear.
class PushService {
  PushService._();

  static const String _channelId = 'new_orders';
  static const String _channelName = 'New orders';

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Bring the whole thing up. Guarded end to end: a device with no Google
  /// Play services, a missing config, a denied permission — none of these is a
  /// reason for the app to fail to start. The kitchen can still work the queue
  /// on screen; it just won't be rung.
  static Future<void> start() async {
    try {
      await Firebase.initializeApp();
    } on Object catch (e) {
      // No Firebase, no push. The app is a worklist first and a pager second.
      debugPrint('Push disabled: Firebase failed to initialize ($e).');
      return;
    }

    // The channels exist after this, so the in-app alarm has somewhere to ring.
    // `OrderRing` refuses to ring until it has been handed the plugin here,
    // which is also what keeps notifications off the test path: tests never
    // call `start()`, so they never reach a binding that `flutter test` lacks.
    await _initLocalNotifications();

    // A ring left over from a previous run is a phone that starts ringing for
    // an order somebody dealt with an hour ago. `ongoing` notifications survive
    // the process that posted them, so clearing on start is not paranoia.
    await OrderRing.stop();

    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    // On Android 13+ this raises the POST_NOTIFICATIONS prompt; on older
    // Androids it is a no-op that returns authorized.
    await messaging.requestPermission();

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    // A message that arrives while the app is foregrounded is *not* posted to the
    // tray by Android — we have to draw it ourselves, or a busy kitchen looking
    // at the menu never sees the order that just came in.
    FirebaseMessaging.onMessage.listen(_showForeground);

    // The token can change (reinstall, restore, periodic refresh); each new one
    // has to be re-registered or the sender rings a dead address.
    messaging.onTokenRefresh.listen(_registerToken);

    // Register now if already signed in, and follow the session from here on:
    // a device only belongs to the kitchen whose staff is signed into it.
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
      // isolate. Without it, Accept and Reject on a ring the app did not draw
      // itself would silence the phone and tell this app nothing.
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationTap,
    );

    // The channel a new-order notification lands on. Must match the id named in
    // the manifest's default-channel meta-data, or Android 8+ drops it silently.
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'A customer has placed a new order.',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // The loud one, alongside it rather than instead of it. `new_orders` still
    // carries everything `send-notification` sends; only a *new order* rings.
    await OrderRing.install(_local);
  }

  /// The vendor answered the ring — from the tray, or by tapping the body.
  ///
  /// Both actions do the same two things: stop the noise, and remember which
  /// order it was so the app can open on the queue rather than wherever the
  /// vendor last happened to be. The accept and reject themselves stay in the
  /// app, because each needs something the notification cannot ask for — a prep
  /// time, or a reason — and a one-tap accept that invents a prep time is a
  /// promise the kitchen never made.
  static void _onNotificationResponse(NotificationResponse response) {
    OrderRing.stop();
    final String? orderId = response.payload;
    if (orderId != null && orderId.isNotEmpty) {
      OrderRing.answered.value = orderId;
    }
  }

  /// Register only if there is a signed-in session; the RPC is scoped to staff,
  /// so a token with no session behind it would be refused anyway.
  ///
  /// The iOS branch is not defensive padding. FCM cannot mint a token until
  /// APNs has answered `registerForRemoteNotifications` with a device token,
  /// and asked before that, `getToken()` does not wait or return null — it
  /// **throws** ("APNS token has not been set yet"). At cold start that is the
  /// ordinary case: AppDelegate's registration is asynchronous and `main`
  /// reaches here within milliseconds of it. The throw would escape `start()`,
  /// and since `main` awaits `start()` *before* `runApp`, it would take the
  /// launch with it — a blank app, over a notification token.
  ///
  /// So iOS asks APNs first and simply leaves if the answer has not arrived.
  /// Nothing is lost by leaving: `onTokenRefresh` above fires when the token is
  /// first minted, and that is the path a first launch actually registers on.
  static Future<void> _syncTokenToSession() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      if (Platform.isIOS &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        return;
      }
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } on Object catch (e) {
      debugPrint('Could not read push token: $e.');
    }
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
          // Stated, not inferred — see 0060.
          'p_audience': 'restaurant',
          // This build draws its own new-order notification, so it can be sent
          // a data-only message and ring (0128). Builds that predate the ring
          // do not send this at all and default to false, which is what keeps
          // `send-order-push` including a notification block for them — a
          // data-only message to an older install shows nothing while killed.
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
  /// also the reason the ring lives in a **plugin package** rather than in this
  /// app's own Kotlin: only plugins land in `GeneratedPluginRegistrant`, so
  /// anything written in `android/app` simply does not exist on this path.
  static Future<void> prepareBackgroundIsolate() async {
    DartPluginRegistrant.ensureInitialized();
    await _initLocalNotifications();
  }

  /// True when this message is the "a customer just ordered" wake, as opposed
  /// to any of the ordinary notifications `send-notification` sends.
  static bool _isNewOrder(RemoteMessage message) =>
      message.data['kind'] == 'new_order';

  /// Ring for a new-order message. Shared by the foreground listener and the
  /// background isolate, because a woken kitchen and an open one should sound
  /// identical — the vendor cannot tell which state the app was in, and should
  /// not have to.
  static Future<void> _ringForOrder(RemoteMessage message) async {
    final String? orderId = message.data['order_id'] as String?;
    if (orderId == null || orderId.isEmpty) return;
    await OrderRing.ring(
      orderId: orderId,
      body: (message.data['body'] as String?) ??
          'A customer just placed an order.',
      ringFor: _windowLeft(message.data['accept_deadline'] as String?),
    );
  }

  /// How long is left to answer. The server sends the order's `accept_deadline`
  /// (0051); a message that sat in a Doze queue for four minutes should ring for
  /// the one that remains, not for a fresh five.
  static Duration _windowLeft(String? deadline) {
    const Duration fallback = Duration(minutes: 5);
    if (deadline == null) return fallback;
    final DateTime? at = DateTime.tryParse(deadline);
    if (at == null) return fallback;
    final Duration left = at.difference(DateTime.now().toUtc());
    // Clamped at both ends: never longer than the window the database allows,
    // and never a negative duration, which would post and cancel in one frame.
    return left <= Duration.zero
        ? Duration.zero
        : (left > fallback ? fallback : left);
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    if (_isNewOrder(message)) {
      await _ringForOrder(message);
      return;
    }
    final RemoteNotification? n = message.notification;
    if (n == null) return;
    await _local.show(
      n.hashCode,
      n.title ?? 'New order',
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
/// `send-order-push` sends **data only**, Android posts nothing, and this
/// handler owns the whole notification — which is the only way the ring can
/// have the flags, the alarm-stream sound and the Accept/Reject actions.
///
/// ⚠️ Nothing `start()` did has happened in this isolate. It is a fresh Dart
/// VM with no plugin registrations, no channel, no initialize. Hence the
/// two lines of setup before anything is shown; skip them and `show` throws.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  if (message.data['kind'] != 'new_order') return;
  await PushService.prepareBackgroundIsolate();
  await PushService._ringForOrder(message);
}

/// Answering the ring while the app is killed lands here — a separate isolate
/// again, and a separate entry point from [_onBackgroundMessage].
///
/// All it can usefully do is stop the noise. Tapping an action with
/// `showsUserInterface: true` also launches the app, and the launched app's own
/// `start()` clears any leftover ring and picks the order up off the realtime
/// stream, so the accept or reject happens there with the full ticket in view.
@pragma('vm:entry-point')
void onBackgroundNotificationTap(NotificationResponse response) {
  OrderRing.stop();
}
