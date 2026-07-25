import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/notifications/order_live_card.dart';

/// The wake: getting an order update to a customer who isn't looking at the app.
///
/// The mirror of the vendor's `PushService`, minus the kitchen's new-order chime
/// (the customer has no equivalent local alarm). It brings Firebase up, makes
/// the `order_updates` channel and asks permission, registers this device's
/// token against the signed-in customer (`register_device_token`, audience-aware
/// since 0047), and draws a foreground message the OS would otherwise swallow.
/// The Edge Function `send-notification` is what actually *sends*; this is the ear.
///
/// A plain object started once from `main`, not a widget or provider — it speaks
/// to platform channels (Firebase, the OS tray) that don't exist under
/// `flutter test`, so keeping it out of the widget tree keeps the tests honest.
class PushService {
  PushService._();

  static const String _channelId = 'order_updates';
  static const String _channelName = 'Order updates';

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// The order a notification tap asked to open, or null.
  ///
  /// A tap can arrive before there is a router to answer it — the app may not be
  /// running at all — so it is parked here and the app drains it when it can.
  /// `ZopiqApp` is the only reader; it navigates and clears.
  static final ValueNotifier<String?> pendingOrderId = ValueNotifier<String?>(
    null,
  );

  /// Bring the whole thing up. Guarded end to end: a device with no Google Play
  /// services, a missing config, a denied permission — none of these is a reason
  /// for the app to fail to start. Push just stays inert.
  static Future<void> start() async {
    try {
      await Firebase.initializeApp();
    } on Object catch (e) {
      // No Firebase, no push. The app works fine; it just won't be woken.
      debugPrint('Push disabled: Firebase failed to initialize ($e).');
      return;
    }

    await _initLocalNotifications();

    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    // On Android 13+ this raises the POST_NOTIFICATIONS prompt; on older
    // Androids it is a no-op that returns authorized.
    await messaging.requestPermission();

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    // A message that arrives while the app is foregrounded is *not* posted to the
    // tray by Android — we draw it ourselves or the customer never sees it.
    FirebaseMessaging.onMessage.listen(_showForeground);

    // Tapping a tray notification the OS drew itself. Two entry points, because
    // Android has two: one for a running app, one for a cold start.
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
    final RemoteMessage? launch = await messaging.getInitialMessage();
    if (launch != null) _openFromMessage(launch);

    // The token can change (reinstall, restore, periodic refresh); each new one
    // has to be re-registered or the sender rings a dead address.
    messaging.onTokenRefresh.listen(_registerToken);

    // Register now if already signed in, and follow the session from here on:
    // a device only belongs to the customer signed into it.
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
    await _local.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // A tap on the live card while the app was dead: the OS starts us and hands
    // the response over here rather than through the callback above.
    final NotificationAppLaunchDetails? launch = await _local
        .getNotificationAppLaunchDetails();
    final NotificationResponse? response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
      _onLocalTap(response);
    }

    // The channel an order-update notification lands on. Must match the id named
    // in the manifest's default-channel meta-data, or Android 8+ drops it.
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Updates on your Zopiqnow orders.',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Register only if there is a signed-in session; the RPC is scoped to the
  /// caller, so a token with no session behind it would be refused anyway.
  static Future<void> _syncTokenToSession() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    final String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerToken(token);
  }

  static Future<void> _registerToken(String token) async {
    try {
      await Supabase.instance.client.rpc<void>(
        'register_device_token',
        params: <String, dynamic>{'p_token': token, 'p_platform': 'android'},
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

  static Future<void> _showForeground(RemoteMessage message) async {
    // A live-card tick carries no notification block and is handled whether the
    // app is foregrounded or not — the card is the same card either way.
    if (await OrderLiveCard.handle(message.data)) return;

    final RemoteNotification? n = message.notification;
    if (n == null) return;
    await _local.show(
      // Masked into the low band: `OrderLiveCard` reserves ids from 100000 up,
      // so an "On the way" alert can never overwrite the card it belongs to.
      n.hashCode & 0xFFFF,
      n.title ?? 'Order update',
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: message.data['order_id'] as String?,
    );
  }

  /// A tap on a notification this app drew itself. The payload is the order id.
  static void _onLocalTap(NotificationResponse response) {
    final String? orderId = response.payload;
    if (orderId != null && orderId.isNotEmpty) pendingOrderId.value = orderId;
  }

  /// A tap on a tray notification Android drew from an FCM `notification` block.
  static void _openFromMessage(RemoteMessage message) {
    final String? orderId = message.data['order_id'] as String?;
    if (orderId != null && orderId.isNotEmpty) pendingOrderId.value = orderId;
  }
}

/// Runs in its own isolate when a message arrives with the app killed or
/// backgrounded. Android posts a *notification* message to the tray on its own;
/// this is where a *data* message is handled — which is to say, where the live
/// order card is drawn for a phone that is asleep in someone's pocket. That is
/// the whole point of the card, so this is no longer a stub. Top-level and
/// annotated, as firebase_messaging requires.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // A fresh isolate: nothing `start()` set up is visible here, so Firebase has
  // to come up again before the plugin channels will answer.
  try {
    await Firebase.initializeApp();
  } on Object catch (e) {
    debugPrint('Background push dropped: Firebase failed to initialize ($e).');
    return;
  }
  // Returns false for an ordinary alerting push, whose tray entry is Android's
  // to draw here — that half stays exactly as it was.
  await OrderLiveCard.handle(message.data);
}
