import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/data/vendor_order_datasource.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<VendorOrderDataSource> vendorOrderDataSourceProvider =
    Provider<VendorOrderDataSource>(
      (Ref ref) => const VendorOrderSupabaseDataSource(),
    );

/// Every order at this restaurant, live.
///
/// Empty when nobody is signed in — not an error, and not a stream that throws:
/// the router will not show this screen to a signed-out user anyway, and a
/// provider that explodes during sign-out is a provider that explodes during a
/// perfectly ordinary sign-out.
final StreamProvider<List<VendorOrder>> ordersProvider =
    StreamProvider<List<VendorOrder>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        return Stream<List<VendorOrder>>.value(<VendorOrder>[]);
      }

      return ref
          .watch(vendorOrderDataSourceProvider)
          .watchOrders(vendor.restaurantId);
    });

/// The queue: what the kitchen still has to do, oldest first.
///
/// Derived, not a second subscription. The stream already carries every order at
/// the restaurant, and an order leaving the queue is the *same event* as an order
/// being delivered — one socket, two readings.
final Provider<List<VendorOrder>> queueProvider = Provider<List<VendorOrder>>((
  Ref ref,
) {
  final List<VendorOrder> orders =
      ref.watch(ordersProvider).valueOrNull ?? <VendorOrder>[];
  return orders
      .where((VendorOrder o) => o.status.isOpen)
      .toList(growable: false);
});

/// The book: orders that are finished — delivered or cancelled — newest first.
///
/// The other reading of the same stream `queueProvider` filters. The queue is
/// oldest-first because a queue starves its oldest ticket; history is
/// newest-first because the thing you just did is the thing you look up.
final Provider<List<VendorOrder>> orderHistoryProvider =
    Provider<List<VendorOrder>>((Ref ref) {
      final List<VendorOrder> orders =
          ref.watch(ordersProvider).valueOrNull ?? <VendorOrder>[];
      final List<VendorOrder> past = orders
          .where((VendorOrder o) => !o.status.isOpen)
          .toList();
      past.sort((VendorOrder a, VendorOrder b) => b.placedAt.compareTo(a.placedAt));
      return past;
    });

/// Orders that need someone to look up *right now* — the new ones. What the
/// count badge counts.
final Provider<int> newOrderCountProvider = Provider<int>((Ref ref) {
  return ref
      .watch(queueProvider)
      .where((VendorOrder o) => o.status == OrderStatus.placed)
      .length;
});

/// The lines of one order. Cached per id and never refetched: `place_order`
/// writes them once and nothing can change them.
final AutoDisposeFutureProviderFamily<List<OrderLine>, String>
orderLinesProvider = FutureProvider.autoDispose.family<List<OrderLine>, String>(
  (Ref ref, String orderId) {
    // Held for the session rather than dropped the moment a ticket scrolls
    // out of view — a kitchen scrolls up and down the same queue all evening,
    // and refetching immutable lines on every pass is a request per scroll.
    ref.keepAlive();
    return ref.watch(vendorOrderDataSourceProvider).fetchLines(orderId);
  },
);

/// Which orders have a status change in flight, so only *that* ticket's button
/// spins. A single bool would light up every button in the kitchen.
class OrderActionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  bool isBusy(String orderId) => state.contains(orderId);

  /// Moves the order on. Returns null on success, or the reason it was refused —
  /// which the caller shows on the ticket.
  ///
  /// The new status is *not* written into local state on success. It arrives on
  /// the stream, because the database is what decides what an order's status is
  /// and this app is a subscriber to that fact like any other. Writing it here
  /// too would mean two sources of truth that agree almost always — and the
  /// "almost" is a ticket that says "Preparing" in a kitchen where the order was
  /// actually cancelled.
  Future<String?> move(
    VendorOrder order,
    OrderStatus to, {
    String? reason,
    int? prepMinutes,
  }) async {
    if (state.contains(order.id)) return null;
    state = <String>{...state, order.id};
    try {
      await ref
          .read(vendorOrderDataSourceProvider)
          .setStatus(
            orderId: order.id,
            status: to,
            reason: reason,
            prepMinutes: prepMinutes,
          );
      return null;
    } on OrderStatusFailure catch (failure) {
      return failure.message;
    } on Object {
      return 'We couldn\'t update that order. Please try again.';
    } finally {
      state = <String>{...state}..remove(order.id);
    }
  }
}

final NotifierProvider<OrderActionController, Set<String>>
orderActionControllerProvider =
    NotifierProvider<OrderActionController, Set<String>>(
      OrderActionController.new,
    );

/// A ticket's age, recomputed on a slow tick.
///
/// The kitchen is judged on how long a ticket has been sitting there, so "4 min"
/// has to become "5 min" without anyone touching the screen. Once every 30
/// seconds — a clock that ticked every second would rebuild the whole queue
/// sixty times a minute to change one digit twice.
///
/// Auto-disposed, which is not a detail: a `Stream.periodic` never completes, so
/// a plain provider would leave a timer ticking for the life of the process —
/// including on the sign-in screen, where there are no tickets to age.
final AutoDisposeStreamProvider<DateTime> clockProvider =
    StreamProvider.autoDispose<DateTime>((Ref ref) {
      return Stream<DateTime>.periodic(
        const Duration(seconds: 30),
        (_) => DateTime.now(),
      );
    });

/// `4 min`, `1 hr 12 min`. What a ticket's age reads as.
String formatAge(Duration age) {
  final int minutes = age.inMinutes;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min';

  final int hours = age.inHours;
  final int rest = minutes - hours * 60;
  return rest == 0 ? '$hours hr' : '$hours hr $rest min';
}

/// `12 Jul · 7:42 PM`. A finished order is looked up by *when* it happened, not
/// how long ago — the queue's relative age stops being the useful reading once
/// an order is off the queue. Formatted by hand rather than reaching for `intl`,
/// which is not a dependency this app has (Rule 4).
String formatOrderDate(DateTime when) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final int hour12 = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final String minute = when.minute.toString().padLeft(2, '0');
  final String meridiem = when.hour < 12 ? 'AM' : 'PM';
  return '${when.day} ${months[when.month - 1]} · $hour12:$minute $meridiem';
}
