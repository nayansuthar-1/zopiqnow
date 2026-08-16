import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/notifications/order_ring.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

/// Rings the kitchen when a new order lands while someone has the app open.
///
/// The push notification (0020) wakes a *closed* app; this is its counterpart for
/// an *open* one. The realtime order stream is already here, so a new ticket is a
/// known event the instant it arrives — no server round trip.
///
/// What it rings is [OrderRing], the same ringtone a woken app plays, and it
/// keeps ringing until the order is accepted or rejected — a single chime is
/// what a kitchen mid-service does not hear, and unanswered orders were the
/// result. This class owns the *stopping*: it holds the set of orders that
/// arrived while it was awake and have not been answered, and the ring runs for
/// exactly as long as that set is non-empty. Because the set is rebuilt from the
/// stream on every tick, an order answered on another tablet stops this one's
/// phone too, with no extra message.
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

      // Orders that arrived on *this* tick, and everything still waiting for an
      // answer. Intersecting with `placed` is what ends the ring: the moment an
      // order is accepted or rejected it leaves `placed`, so it drops out of
      // here, and when the last one drops out the phone goes quiet.
      final Set<String> arrived = placed.difference(known);
      _unanswered = <String>{..._unanswered, ...arrived}.intersection(placed);

      if (arrived.isNotEmpty) {
        state++;
        _ring(orders);
      } else if (_unanswered.isEmpty) {
        OrderRing.stop();
      }
    });

    ref.onDispose(OrderRing.stop);

    return 0;
  }

  /// New orders that have arrived since this alarm woke up and that nobody has
  /// answered yet. The ring runs for exactly as long as this is non-empty.
  Set<String> _unanswered = <String>{};

  static Set<String>? _placedIds(List<VendorOrder>? orders) {
    if (orders == null) return null;
    return orders
        .where((VendorOrder o) => o.status == OrderStatus.placed)
        .map((VendorOrder o) => o.id)
        .toSet();
  }

  /// Start the ring for the oldest unanswered order.
  ///
  /// Fire-and-forget: the alarm is a courtesy, not a step the queue waits on.
  /// The haptic fires even where notifications are denied.
  ///
  /// The ring is bounded by the *earliest* deadline among the orders waiting,
  /// not the newest one's. Those orders expire in the order they arrived, and
  /// ringing past the point where the first one has already been auto-expired
  /// is ringing about nothing.
  void _ring(List<VendorOrder> orders) {
    HapticFeedback.heavyImpact();

    final List<VendorOrder> waiting = orders
        .where((VendorOrder o) => _unanswered.contains(o.id))
        .toList(growable: false);
    if (waiting.isEmpty) return;

    DateTime? earliest;
    for (final VendorOrder o in waiting) {
      final DateTime? d = o.acceptDeadline;
      if (d != null && (earliest == null || d.isBefore(earliest))) earliest = d;
    }

    OrderRing.ring(
      orderId: waiting.first.id,
      body: waiting.length == 1
          ? 'A customer just placed an order.'
          : '${waiting.length} orders are waiting to be accepted.',
      ringFor: earliest == null
          ? const Duration(minutes: 5)
          : earliest.difference(DateTime.now()),
    );
  }
}

/// Kept alive by the shell (watch its `.notifier`), so it runs for the whole
/// signed-in session without rebuilding anything when it fires.
final AutoDisposeNotifierProvider<NewOrderAlarm, int> newOrderAlarmProvider =
    AutoDisposeNotifierProvider<NewOrderAlarm, int>(NewOrderAlarm.new);
