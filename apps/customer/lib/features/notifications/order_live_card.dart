import 'package:flutter/foundation.dart';
import 'package:zopiq_live_card/zopiq_live_card.dart';

/// The live order card: **two** notifications per order, each redrawn in place.
///
/// The thing on the lock screen while food is on its way — a headline, a bar
/// that fills continuously, a countdown beneath it, and artwork on the right.
///
/// **Two cards, not one.** An order used to produce a single notification whose
/// bar crawled the whole way from "placed" to "delivered". It now produces a
/// **prep card** that fills while the kitchen cooks and comes down when the food
/// leaves, and a **delivery card** that starts empty at pickup and fills on the
/// way over. Different ids, different artwork, different windows — see [_idFor].
///
/// **The bar moves on its own.** Migration 0055 stopped sending a position and
/// started sending a pair of instants (`window_start`, `window_end`). The
/// platform side interpolates between them on the device clock and redraws every
/// twenty seconds from a foreground service, so this file is called only when
/// the *order* changes — six or seven times — and the bar still creeps the whole
/// way. Nothing here computes a percentage.
///
/// **Silent, and it vanishes.** A dedicated channel with sound and vibration
/// off, plus `onlyAlertOnce`; a delivered or cancelled order cancels both cards
/// rather than leaving one on the lock screen.
///
/// Drawn from a data-only push (`kind = order_live`), which means this runs in
/// the FCM background isolate as often as in the app's own. See
/// `packages/zopiq_live_card/`.
class OrderLiveCard {
  OrderLiveCard._();

  /// The phases that end an order. Both cards are cancelled, not redrawn.
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
      final String phase = (data['phase'] as String?) ?? '';
      if (_terminal.contains(phase)) {
        await cancel(orderId);
        return true;
      }

      final DateTime? start = _parse(data['window_start']);
      final DateTime? end = _parse(data['window_end']);
      if (start == null || end == null) return true;

      // The handover. A card is only ever taken down by the phase *after* it, so
      // the prep card survives every event of its own phase and disappears the
      // moment the food is on a bike.
      if (phase == 'delivery') {
        await ZopiqLiveCard.cancel(_idFor(orderId, 'prep'));
      }

      await ZopiqLiveCard.show(
        id: _idFor(orderId, phase),
        orderId: orderId,
        title: (data['title'] as String?) ?? 'Your order',
        body: data['body'] as String?,
        phase: phase,
        windowStart: start,
        windowEnd: end,
        progress: int.tryParse('${data['progress']}'),
      );
    } on Object catch (e) {
      debugPrint('Live order card not drawn: $e.');
    }
    return true;
  }

  /// Take both of an order's cards down. Safe on cards that were never posted.
  static Future<void> cancel(String orderId) async {
    await ZopiqLiveCard.cancel(_idFor(orderId, 'prep'));
    await ZopiqLiveCard.cancel(_idFor(orderId, 'delivery'));
  }

  /// FCM flattens every payload value to a string, so `window_start` arrives as
  /// text whatever the column said. Null on anything unparseable — a card with
  /// no window has no bar to draw and is better skipped than shown empty.
  static DateTime? _parse(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse('$value')?.toUtc();
  }

  /// A stable notification id for one of an order's two cards.
  ///
  /// FNV-1a rather than [String.hashCode]: this id has to be identical in the
  /// app's isolate and in the FCM background isolate, and across restarts, or a
  /// card would be posted twice instead of redrawn once. Dart makes no promise
  /// about `hashCode` across those boundaries; this does.
  ///
  /// The two phases live in **bands a million apart** rather than at `n` and
  /// `n + 1`. Adjacent ids would collide across orders — one order's delivery
  /// card landing on another order's prep card — for any pair whose hashes
  /// happen to differ by one, which over 900,000 slots is not a remote
  /// possibility but a birthday problem. The base band also keeps live cards
  /// clear of the ids `PushService` uses for ordinary alerting notifications, so
  /// an "On the way" push can never land on top of the card it belongs to.
  static int _idFor(String orderId, String phase) {
    int hash = 0x811c9dc5;
    for (final int unit in orderId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    final int base = phase == 'delivery' ? 1100000 : 100000;
    return base + (hash % 900000);
  }

  @visibleForTesting
  static int idFor(String orderId, String phase) => _idFor(orderId, phase);
}
