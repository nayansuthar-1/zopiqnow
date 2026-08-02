import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zopiq_live_card/zopiq_live_card.dart';

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
    // First, and deliberately ahead of Firebase: a tap on the live card has to
    // land on the tracking screen even on a device where push never came up at
    // all. The card is drawn by `zopiq_live_card` since Tier 2, so its taps
    // arrive on that plugin's channel rather than through `_onLocalTap`.
    await _adoptLiveCardTaps();

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

  /// Two entry points, because a tap has two shapes: one for an app that was
  /// already running, and one for a tap that started the process from dead. The
  /// second cannot be a callback — there is no Dart alive to call — so the
  /// platform parks the order id and this drains it.
  static Future<void> _adoptLiveCardTaps() async {
    ZopiqLiveCard.listenForTaps((String orderId) {
      pendingOrderId.value = orderId;
    });

    final String? launched = await ZopiqLiveCard.consumeLaunchOrderId();
    if (launched != null && launched.isNotEmpty) pendingOrderId.value = launched;
  }

  static Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    // iOS asks for its own permission through this plugin as well as through
    // `firebase_messaging`, and asking twice would show the system dialog twice.
    // All three request flags are false here: `messaging.requestPermission()`
    // below is the one place this app asks, on both platforms, and the OS
    // remembers the answer for whichever caller comes second.
    const DarwinInitializationSettings darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // A tap on an alerting notification this app drew while it was dead: the OS
    // starts us and hands the response over here rather than through the
    // callback above. (The live card's own taps go through `_adoptLiveCardTaps`.)
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
          // The real platform, not the constant `'android'` this sent until
          // iOS existed. `device_tokens.platform` has accepted `'ios'` since
          // 0020 and the column is what `send-notification` reads to decide
          // whether a payload needs an APNs block — so a mislabelled iPhone is
          // not cosmetic, it is a push that arrives shaped for the wrong OS.
          'p_platform': Platform.isIOS ? 'ios' : 'android',
          // This is the customer app, and it says so rather than letting the
          // database work it out. Until 0060 the audience was inferred from the
          // signed-in *person*, so a customer who also happened to be staff of
          // a restaurant had this phone filed as a restaurant device: customer
          // pushes went to a bucket it was not in, and it quietly received that
          // restaurant's order traffic instead. A token belongs to an app, and
          // only the app knows which one it is.
          'p_audience': 'customer',
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
        // iOS has no channels — importance and sound are decided per
        // notification, here, rather than once when a channel is created.
        // Without this block the call still succeeds and draws nothing at all.
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBanner: true,
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
