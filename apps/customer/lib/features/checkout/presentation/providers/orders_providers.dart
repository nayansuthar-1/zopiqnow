import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';

/// The signed-in customer's order history, newest first.
///
/// Watches the auth state, so signing out and back in as someone else refetches
/// instead of serving the previous account's receipts out of the cache. Auto-
/// disposed: history is worth a round trip on open and not worth holding for a
/// session.
final AutoDisposeFutureProvider<List<CustomerOrder>> ordersProvider =
    FutureProvider.autoDispose<List<CustomerOrder>>((Ref ref) {
      ref.watch(authControllerProvider);
      return ref.watch(orderRepositoryProvider).getOrders();
    });

/// A single order, fetched by id.
///
/// It used to be a lookup into the already-loaded history, on the reasoning that
/// the detail screen is only ever opened *from* the list. That stopped being
/// true the moment the confirmation screen grew a "Track this order" button:
/// checkout does not load anyone's history, so the lookup would miss and the
/// customer would be told their brand-new order does not exist. So it fetches —
/// one row, by primary key, behind the same policy — and a cold deep link to
/// `/orders/ZPQ-1042` now works for the same reason.
///
/// Null is a real answer: no such order, or not this customer's. The screen says
/// so. A *failure* to ask throws [OrdersLoadFailure], and the screen offers a
/// retry — telling someone their order is gone because a socket hiccuped is the
/// one thing this must never do.
final AutoDisposeFutureProviderFamily<CustomerOrder?, String> orderByIdProvider =
    FutureProvider.autoDispose.family<CustomerOrder?, String>((
      Ref ref,
      String id,
    ) {
      ref.watch(authControllerProvider);
      return ref.watch(orderRepositoryProvider).getOrder(id);
    });

/// The order's status, live.
///
/// Only ever watched for an order that is still open — a delivered receipt has
/// nothing left to report, and a subscription to it is a socket held open for an
/// event that will never come.
final AutoDisposeStreamProviderFamily<OrderStatus, String> orderStatusProvider =
    StreamProvider.autoDispose.family<OrderStatus, String>((
      Ref ref,
      String id,
    ) {
      return ref.watch(orderRepositoryProvider).watchOrderStatus(id);
    });

/// Who is carrying the order.
///
/// Fetched, not streamed. `deliveries` is readable by the customer only while
/// the order is out for delivery, and Realtime rides that same policy — so a
/// subscription opened a minute earlier would be a socket held open for a row
/// it is not yet allowed to see. Instead the *status* is already live, and the
/// card asks this question when the status answers "out for delivery".
///
/// Never in an error state: the repository returns null rather than throwing,
/// because a missing name is not worth a broken tracking screen.
final AutoDisposeFutureProviderFamily<OrderRider?, String> orderRiderProvider =
    FutureProvider.autoDispose.family<OrderRider?, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(orderRepositoryProvider).getRider(orderId);
    });

/// The four digits to read out at the door (0049).
///
/// Same shape as [orderRiderProvider], and asked at the same moment — the
/// screen only wants it once the food is on its way. Null while there is
/// nothing to confirm, which is also what a failed read looks like: the code
/// simply is not on screen, and the rider's own app will say why.
final AutoDisposeFutureProviderFamily<String?, String> deliveryCodeProvider =
    FutureProvider.autoDispose.family<String?, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(orderRepositoryProvider).getDeliveryCode(orderId);
    });

/// What a reorder actually managed to put in the cart.
///
/// [unavailable] is not an error: a dish sells out, a vendor delists it, and the
/// honest thing is to load what is still there and say what is missing. Only an
/// order where *nothing* survives has nothing to show for itself.
@immutable
class ReorderOutcome {
  const ReorderOutcome({required this.added, required this.unavailable});

  final int added;
  final int unavailable;

  bool get isEmpty => added == 0;
}

/// Rebuilds the cart from a past order.
///
/// The order's own prices are deliberately *not* reused. Its lines are resolved
/// against today's menu by id, so the customer is quoted what the dish costs now
/// — and `place_order` prices it again server-side regardless. A cart restored
/// from a three-month-old receipt would otherwise promise last quarter's prices.
///
/// State is whether a reorder is in flight, which is what the button renders.
class ReorderController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<ReorderOutcome> reorder(CustomerOrder order) async {
    state = true;
    try {
      final List<MenuCategory> menu = await ref
          .read(menuRepositoryProvider)
          .getMenu(order.restaurantId);

      final Map<String, MenuItem> available = <String, MenuItem>{
        for (final MenuCategory c in menu)
          for (final MenuItem i in c.items) i.id: i,
      };

      final List<CartLine> lines = <CartLine>[];
      int unavailable = 0;
      for (final OrderLine line in order.lines) {
        final MenuItem? item = available[line.menuItemId];
        if (item == null) {
          unavailable++;
        } else {
          lines.add(CartLine(item: item, quantity: line.quantity));
        }
      }

      // An empty cart is not "a cart with nothing in it" here — it is a failed
      // reorder, and replaceWith would silently wipe the cart the customer
      // already had. Leave it alone and let the caller say so.
      if (lines.isNotEmpty) {
        ref
            .read(cartProvider.notifier)
            .replaceWith(
              restaurantId: order.restaurantId,
              restaurantName: order.restaurantName,
              lines: lines,
            );
      }

      return ReorderOutcome(added: lines.length, unavailable: unavailable);
    } finally {
      state = false;
    }
  }
}

final NotifierProvider<ReorderController, bool> reorderControllerProvider =
    NotifierProvider<ReorderController, bool>(ReorderController.new);
