import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
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

/// A single order out of the already-loaded history.
///
/// The detail screen is opened *from* the list, so the order is in memory and
/// re-fetching it by id would be a second round trip for bytes we hold. Null
/// when the history has not loaded — a cold deep link to `/orders/ZPQ-1042` —
/// and the screen sends the user to the list rather than inventing a receipt.
final AutoDisposeProviderFamily<CustomerOrder?, String> orderByIdProvider =
    Provider.autoDispose.family<CustomerOrder?, String>((Ref ref, String id) {
      final List<CustomerOrder>? orders = ref.watch(ordersProvider).valueOrNull;
      if (orders == null) return null;
      for (final CustomerOrder o in orders) {
        if (o.id == id) return o;
      }
      return null;
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
