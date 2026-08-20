import 'dart:io' show Platform;

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
/// backgrounded. Android posts a *notification* message to the tray on its own;
/// this exists so a *data* message still has an entry point, and so the plugin
/// stops warning that none is registered. Top-level and annotated, as
/// firebase_messaging requires.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Intentionally minimal: the tray notification is Android's to draw here.
}
