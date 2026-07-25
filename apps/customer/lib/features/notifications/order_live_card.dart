import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The live order card: one notification per running order, redrawn in place.
///
/// The thing on the lock screen while food is on its way — a headline, a
/// progress bar, the brand mark, and "Arriving in 18 min" along the top. It is a
/// plain Android notification, which is the whole point: every field it uses
/// exists on API 24, so the card works on the Android 10 floor with no new
/// dependency and no `targetSdk` bump.
///
/// **One notification per order, updated in place.** The id is derived from the
/// order id, so the eight events an order emits redraw a single card rather than
/// stacking eight. **Silent after the first**: a dedicated channel with sound and
/// vibration off, plus `onlyAlertOnce`. **It vanishes** — a delivered or
/// cancelled order cancels its card rather than leaving it on the lock screen.
///
/// Drawn from a data-only push (`kind = order_live`, migration 0052), which
/// means this runs in the FCM background isolate as often as in the app's own.
/// That is why it owns its plugin instance and initialises it lazily: statics do
/// not cross isolates, so [PushService]'s copy is not available here.
class OrderLiveCard {
  OrderLiveCard._();

  static const String channelId = 'order_live';
  static const String _channelName = 'Live order tracking';

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// Swiggy orange, as `ZopiqPalette.primary` — repeated as a literal rather
  /// than imported because this code runs in the background isolate, where the
  /// design system's theme machinery has no business being woken up.
  static const Color _brand = Color(0xFFFC8019);

  /// The stages that end an order. Their card is cancelled, not redrawn.
  static const Set<String> _terminal = <String>{'delivered', 'ended'};

  /// Handle one push payload. Returns false if it was not a live-card tick, so
  /// the caller can fall through to its ordinary handling.
  ///
  /// Never throws: a malformed payload is a card that does not redraw, which is
  /// a great deal better than a background isolate that crashes.
  static Future<bool> handle(Map<String, dynamic> data) async {
    if (data['kind'] != 'order_live') return false;

    final String? orderId = data['order_id'] as String?;
    if (orderId == null || orderId.isEmpty) return true;

    try {
      final String stage = (data['stage'] as String?) ?? '';
      if (_terminal.contains(stage)) {
        await cancel(orderId);
        return true;
      }
      await _show(orderId: orderId, stage: stage, data: data);
    } on Object catch (e) {
      debugPrint('Live order card not drawn: $e.');
    }
    return true;
  }

  /// Take the card down. Used on a terminal stage, and safe on an order that
  /// never had one.
  static Future<void> cancel(String orderId) async {
    await _ensureReady();
    await _local.cancel(idFor(orderId));
  }

  static Future<void> _show({
    required String orderId,
    required String stage,
    required Map<String, dynamic> data,
  }) async {
    await _ensureReady();

    final int progress = int.tryParse('${data['progress']}') ?? 0;
    final String title = (data['title'] as String?) ?? 'Your order';
    final String? body = data['body'] as String?;

    await _local.show(
      idFor(orderId),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelName,
          channelDescription: 'The live card while an order is on its way.',
          // DEFAULT, not HIGH: the card must never peek over what the customer
          // is doing. The alerting half of an order's news is `order_updates`,
          // and it still buzzes exactly five times per order (0047).
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          // Sits in the shade for the life of the order and does not disappear
          // when tapped — tapping opens the tracking screen, it does not mean
          // "I'm done with this".
          ongoing: true,
          autoCancel: false,
          // Six redraws, one alert. Without this every status change would make
          // its own noise on a channel that is supposed to be silent.
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          showProgress: true,
          maxProgress: 100,
          progress: progress.clamp(0, 100),
          subText: _subText(stage, data['eta_at'] as String?),
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          color: _brand,
          colorized: true,
          category: AndroidNotificationCategory.progress,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: orderId,
    );
  }

  /// The orange line along the top of the card.
  ///
  /// Counted down against a fixed deadline the server sent (`eta_at`), not
  /// against a minutes-remaining number computed when the push was built. That
  /// is what keeps Rule 3 — the deadline never moves, so the count can only ever
  /// fall, and the number on the lock screen never walks backwards.
  static String? _subText(String stage, String? etaAt) {
    if (stage == 'at_door') return 'At your door';
    if (etaAt == null) return null;

    final DateTime? eta = DateTime.tryParse(etaAt);
    if (eta == null) return null;

    final int minutes = eta.difference(DateTime.now().toUtc()).inMinutes;
    return minutes > 0 ? 'Arriving in $minutes min' : 'Arriving any moment';
  }

  /// A stable notification id for an order, in a band of its own.
  ///
  /// FNV-1a rather than [String.hashCode]: this id has to be identical in the
  /// app's isolate and in the FCM background isolate, and across restarts, or
  /// the card would be posted twice instead of redrawn once. Dart makes no
  /// promise about `hashCode` across those boundaries; this does.
  ///
  /// The `100000 +` keeps live cards clear of the ids [PushService] uses for
  /// ordinary alerting notifications, so an "On the way" push can never land on
  /// top of the card it belongs to.
  @visibleForTesting
  static int idFor(String orderId) {
    int hash = 0x811c9dc5;
    for (final int unit in orderId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return 100000 + (hash % 900000);
  }

  /// The channel, and the plugin behind it. Cheap to call repeatedly; the first
  /// call in each isolate does the work.
  static Future<void> _ensureReady() async {
    if (_ready) return;

    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(const InitializationSettings(android: android));

    // Sound and vibration are off on the channel itself, not only on each
    // notification: the channel is what the customer sees in system settings,
    // and it should read as the silent tracker it is.
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      _channelName,
      description: 'The live card while an order is on its way.',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    _ready = true;
  }
}
