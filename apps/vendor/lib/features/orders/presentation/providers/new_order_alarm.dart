import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/notifications/push_service.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

/// Rings the kitchen when a new order lands while someone has the app open.
///
/// The push notification (0020) wakes a *closed* app; this is its counterpart for
/// an *open* one. The realtime order stream is already here, so a new ticket is a
/// known event the instant it arrives — no server round trip — and the answer is
/// a buzz and a chime, the two cues a busy kitchen notices without watching the
/// screen.
///
/// The one thing it must never do is ring for orders that were already on the
/// queue when it woke up: a kitchen reopening the app to nine waiting tickets does
/// not want nine alarms. So the batch it first sees is *adopted* silently; only
/// ids that appear after that are new.
///
/// Auto-disposed with the shell that keeps it alive, which is the whole point —
/// the shell exists only while signed in, so signing out drops the alarm and the
/// next sign-in rebuilds it fresh: a different restaurant's backlog is adopted,
/// not rung.
class NewOrderAlarm extends AutoDisposeNotifier<int> {
  /// The placed-order ids already accounted for. Null until the first batch is
  /// seen — which is how "we just woke up, adopt everything" is told apart from
  /// "the queue is genuinely empty".
  Set<String>? _known;

  @override
  int build() {
    // Seed from whatever is already loaded, so the *next order* — not the next
    // batch — is the first thing that rings. If the stream is still loading, the
    // listener below adopts its first emission instead.
    _known = _placedIds(ref.read(ordersProvider).valueOrNull);

    ref.listen<AsyncValue<List<VendorOrder>>>(ordersProvider, (
      AsyncValue<List<VendorOrder>>? _,
      AsyncValue<List<VendorOrder>> next,
    ) {
      final List<VendorOrder>? orders = next.valueOrNull;
      if (orders == null) return;

      final Set<String> placed = _placedIds(orders)!;
      final Set<String>? known = _known;
      _known = placed;

      if (known == null) return; // first sight — adopt, do not ring
      if (placed.difference(known).isEmpty) return; // nothing new arrived

      state++;
      _ring();
    });

    return 0;
  }

  static Set<String>? _placedIds(List<VendorOrder>? orders) {
    if (orders == null) return null;
    return orders
        .where((VendorOrder o) => o.status == OrderStatus.placed)
        .map((VendorOrder o) => o.id)
        .toSet();
  }

  void _ring() {
    // Fire-and-forget: the alarm is a courtesy, not a step the queue waits on.
    // The haptic fires even where notifications are denied; the chime carries the
    // sound, off the same high-importance channel a pushed order rings.
    HapticFeedback.heavyImpact();
    PushService.chimeNewOrder();
  }
}

/// Kept alive by the shell (watch its `.notifier`), so it runs for the whole
/// signed-in session without rebuilding anything when it fires.
final AutoDisposeNotifierProvider<NewOrderAlarm, int> newOrderAlarmProvider =
    AutoDisposeNotifierProvider<NewOrderAlarm, int>(NewOrderAlarm.new);
