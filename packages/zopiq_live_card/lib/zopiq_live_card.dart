import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// The live order card, drawn by the platform.
///
/// A thin wrapper over one method channel. Everything interesting is on the
/// other side of it — see `LiveCardNotification.java` for why the card is built
/// two different ways, `LiveCardSpec.java` for how two instants become a bar
/// position, and `LiveCardService.java` for what moves it between pushes.
///
/// Safe to call from the FCM background isolate: the plugin is registered on
/// every engine in the process, including the one `firebase_messaging` creates
/// to run a message that arrived with the app killed.
class ZopiqLiveCard {
  ZopiqLiveCard._();

  static const MethodChannel _channel = MethodChannel(
    'com.siteonlab.zopiq_live_card',
  );

  /// Android only, and not a placeholder for anything.
  ///
  /// iOS has no notification that looks like this; the equivalent is a Live
  /// Activity, which is a Swift widget extension rather than a notification —
  /// P1 Tier 3, a different feature wearing the same screenshot.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Post or redraw the card, and keep it ticking. Reusing an [id] redraws in
  /// place.
  ///
  /// [windowStart] and [windowEnd] are the two instants the bar sweeps between
  /// — the whole reason it can fill continuously. The platform side interpolates
  /// against them on its own clock and redraws every twenty seconds, so this
  /// need only be called when the *order* changes, not when the bar should move.
  /// Both must be UTC.
  ///
  /// [phase] is `prep` or `delivery`, and decides the artwork and the wording.
  ///
  /// [progress] overrides the clock when non-null, and is the seam for real
  /// distance-driven progress later (B3). Leave it null and the window governs.
  static Future<void> show({
    required int id,
    required String orderId,
    required String title,
    required String phase,
    required DateTime windowStart,
    required DateTime windowEnd,
    String? body,
    int? progress,
  }) {
    if (!isSupported) return Future<void>.value();
    return _channel.invokeMethod<void>('show', <String, dynamic>{
      'id': id,
      'orderId': orderId,
      'title': title,
      'body': body,
      'phase': phase,
      'windowStart': windowStart.toUtc().millisecondsSinceEpoch,
      'windowEnd': windowEnd.toUtc().millisecondsSinceEpoch,
      // -1 is "no override" on the other side; null over the channel would have
      // to be unboxed there anyway.
      'progress': progress ?? -1,
    });
  }

  /// Take the card down. Safe on an id that never had one.
  static Future<void> cancel(int id) {
    if (!isSupported) return Future<void>.value();
    return _channel.invokeMethod<void>('cancel', <String, dynamic>{'id': id});
  }

  /// The order a tap on the card asked to open while the app was **not**
  /// running, or null. Returns it once and forgets it.
  ///
  /// Separate from [listenForTaps] because a cold start has no listener yet:
  /// the tap happens, Android starts the process, and the whole app boots
  /// before any Dart code exists to be called back.
  static Future<String?> consumeLaunchOrderId() {
    if (!isSupported) return Future<String?>.value();
    return _channel.invokeMethod<String>('consumeLaunchOrderId');
  }

  /// Taps that arrive while the app is already running.
  static void listenForTaps(void Function(String orderId) onTap) {
    if (!isSupported) return;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'onOrderTapped') return null;
      final String? orderId = call.arguments as String?;
      if (orderId != null && orderId.isNotEmpty) onTap(orderId);
      return null;
    });
  }
}
