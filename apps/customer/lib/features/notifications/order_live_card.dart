import 'package:flutter/foundation.dart';
import 'package:zopiq_live_card/zopiq_live_card.dart';

/// The live order card: one notification per running order, redrawn in place.
///
/// The thing on the lock screen while food is on its way — a headline, a
/// **segmented delivery tracker** with a milestone at each step, the brand mark,
/// and "Arriving in 18 min" along the top.
///
/// **One notification per order, updated in place.** The id is derived from the
/// order id, so the eight events an order emits redraw a single card rather than
/// stacking eight. **Silent after the first**: a dedicated channel with sound and
/// vibration off, plus `onlyAlertOnce`. **It vanishes** — a delivered or
/// cancelled order cancels its card rather than leaving it on the lock screen.
///
/// Drawn from a data-only push (`kind = order_live`, migration 0052), which
/// means this runs in the FCM background isolate as often as in the app's own.
///
/// **What changed in Tier 2.** Tier 1 drew this with `flutter_local_notifications`
/// and got a plain unbroken progress bar, because that is the only shape the
/// package exposes. The drawing now lives in [ZopiqLiveCard] — an in-repo,
/// Android-only plugin — which paints a segmented tracker on every Android from
/// the version 10 floor up, and on Android 16 hands the job to the platform's own
/// `Notification.ProgressStyle` to earn the status-bar chip. This file is
/// unchanged in every other respect: same ids, same channel, same ladder, same
/// rules. See `packages/zopiq_live_card/`.
class OrderLiveCard {
  OrderLiveCard._();

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
      await ZopiqLiveCard.show(
        id: idFor(orderId),
        orderId: orderId,
        title: (data['title'] as String?) ?? 'Your order',
        body: data['body'] as String?,
        subText: _subText(stage, data['eta_at'] as String?),
        progress: int.tryParse('${data['progress']}') ?? 0,
      );
    } on Object catch (e) {
      debugPrint('Live order card not drawn: $e.');
    }
    return true;
  }

  /// Take the card down. Used on a terminal stage, and safe on an order that
  /// never had one.
  static Future<void> cancel(String orderId) =>
      ZopiqLiveCard.cancel(idFor(orderId));

  /// The line along the top of the card.
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
}
