import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The wake: getting a new job to a rider who isn't looking at the app.
///
/// The mirror of the vendor's `PushService`, minus the local new-order chime.
/// It brings Firebase up, makes the `jobs` channel and asks permission,
/// registers this device's token against the signed-in rider
/// (`register_device_token`, audience-aware since 0047), and draws a foreground
/// message the OS would otherwise swallow. The Edge Function `send-notification`
/// is what actually *sends*; this is only the ear. Once it is live the board can
/// stop polling every 20s (see ZOMATO_PARITY.md B0/B3).
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

    await _initLocalNotifications();

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
    messaging.onTokenRefresh.listen(_registerToken);

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
    await _local.initialize(
      const InitializationSettings(android: android),
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
        params: <String, dynamic>{
          'p_token': token,
          'p_platform': 'android',
          // Stated, not inferred — see 0060. A rider who is also staff of a
          // restaurant would otherwise have had this phone filed as a
          // restaurant device.
          'p_audience': 'rider',
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
      ),
    );
  }
}

/// Runs in its own isolate when a message arrives with the app killed or
/// backgrounded. Android posts a *notification* message to the tray on its own;
/// this exists so a *data* message still has an entry point, and so the plugin
/// stops warning that none is registered. Top-level and annotated, as
/// firebase_messaging requires.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Intentionally minimal: the tray notification is Android's to draw here.
}
