import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_invoice.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_message.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_refund.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_review.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
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

/// The order still on its way, or null when nothing is running.
///
/// Newest wins, because [ordersProvider] is newest-first and somebody with two
/// orders open cares about the one they just placed. Only one is surfaced: this
/// drives a single nav pill, and a pill cannot point at two places.
///
/// Derived rather than fetched — it is a read of a list the app already loads,
/// so it costs nothing and cannot disagree with the history screen about which
/// orders are live. `isOpen` is the entity's own word for it, so this and the
/// order card can never draw different conclusions.
///
/// Null while the history is still loading or has failed. A nav bar is the wrong
/// place to report either: the pill simply stays as the cart until an answer
/// arrives.
final AutoDisposeProvider<CustomerOrder?> liveOrderProvider =
    Provider.autoDispose<CustomerOrder?>((Ref ref) {
      final List<CustomerOrder>? orders = ref.watch(ordersProvider).valueOrNull;
      if (orders == null) return null;
      for (final CustomerOrder order in orders) {
        if (order.status.isOpen) return order;
      }
      return null;
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

/// The map's fixed parts: two pins, the road between them, and the live ETA.
///
/// Fetched rather than streamed, and refetched whenever the *status* stream
/// moves — which is exactly when the arrival time can have been recomputed
/// (0057 re-estimates on every status and delivery-state change). One round trip
/// per real event beats a socket held open on a row that changes twice an hour.
///
/// Null is a real answer and the screen draws no map for it: an order with no
/// delivery coordinates, or a mock one.
final AutoDisposeFutureProviderFamily<DeliveryRoute?, String>
orderRouteProvider =
    FutureProvider.autoDispose.family<DeliveryRoute?, String>((
      Ref ref,
      String orderId,
    ) {
      ref.watch(orderStatusProvider(orderId));
      return ref.watch(orderRepositoryProvider).getRoute(orderId);
    });

/// Where the rider is, live.
///
/// Keyed by the carrier rather than the order because that is what the socket
/// filters on — see [OrderRider.carrierKey], which is a subscription filter and
/// not a credential. The screen only asks once it has a rider, which is also the
/// only window the policy behind it will answer in.
///
/// Never in an error state: a map without a dot is a map, and a tracking screen
/// that goes red because a socket hiccuped is the one thing this must not do.
final AutoDisposeStreamProviderFamily<RiderPosition?, String>
riderPositionProvider =
    StreamProvider.autoDispose.family<RiderPosition?, String>((
      Ref ref,
      String carrierKey,
    ) {
      return ref
          .watch(orderRepositoryProvider)
          .watchRiderPosition(carrierKey)
          .handleError((Object _) {});
    });

/// The thread with the rider, live.
///
/// Streamed rather than fetched, unlike everything else on this screen: a reply
/// arriving while the customer is looking at the sheet is the entire point of a
/// chat. Errors are swallowed to an empty list — a thread that goes red because
/// a socket hiccuped would look like the rider had vanished.
final AutoDisposeStreamProviderFamily<List<OrderMessage>, String>
orderMessagesProvider =
    StreamProvider.autoDispose.family<List<OrderMessage>, String>((
      Ref ref,
      String orderId,
    ) {
      return ref
          .watch(orderRepositoryProvider)
          .watchMessages(orderId)
          .handleError((Object _) {});
    });

/// The sentences this customer may send, as 0061 words them.
///
/// Not keyed by order: the list is the same for every order a customer has, and
/// it is a constant on the server. Auto-disposed, so it is one round trip per
/// time the sheet is opened rather than one per message.
final AutoDisposeFutureProvider<List<CannedMessage>> messageMenuProvider =
    FutureProvider.autoDispose<List<CannedMessage>>(
      (Ref ref) => ref.watch(orderRepositoryProvider).getMessageMenu(),
    );

/// Sends one canned line, and reports what the order service said if it refused.
///
/// State is whether a send is in flight — the same shape as
/// [OrderCancelController], and for the same reason. Returns the refusal rather
/// than throwing it: "There is nobody on this order to message right now." is
/// the answer when the rider handed the food over a moment ago, and it is the
/// most useful sentence on the screen.
class OrderMessageController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<String?> send({required String orderId, required String code}) async {
    if (state) return null;
    state = true;
    try {
      await ref
          .read(orderRepositoryProvider)
          .sendMessage(orderId: orderId, code: code);
      return null;
    } on OrderMessageFailure catch (failure) {
      return failure.message;
    } finally {
      state = false;
    }
  }

  /// Marks the rider's lines seen. Fire-and-forget by design — see
  /// [OrderRepository.markMessagesRead], which never throws.
  Future<void> markRead(String orderId) =>
      ref.read(orderRepositoryProvider).markMessagesRead(orderId);
}

final NotifierProvider<OrderMessageController, bool>
orderMessageControllerProvider =
    NotifierProvider<OrderMessageController, bool>(OrderMessageController.new);

/// Whether this order can be rated, and whether there is a rider to rate.
///
/// Never in an error state: the repository swallows to [OrderReviewState.none],
/// which is also what an order that is still cooking answers. A receipt does not
/// break because a rating prompt could not be asked about.
final AutoDisposeFutureProviderFamily<OrderReviewState, String>
orderReviewStateProvider =
    FutureProvider.autoDispose.family<OrderReviewState, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(orderRepositoryProvider).getReviewState(orderId);
    });

/// What this customer already said about the order, or null.
final AutoDisposeFutureProviderFamily<OrderReview?, String> myOrderReviewProvider =
    FutureProvider.autoDispose.family<OrderReview?, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(orderRepositoryProvider).getMyReview(orderId);
    });

/// Money going back on this order (0077), oldest first.
///
/// Empty for almost every order, and the widget renders nothing when it is —
/// including while the read is in flight, so a receipt does not jump.
final AutoDisposeFutureProviderFamily<List<OrderRefund>, String>
orderRefundsProvider =
    FutureProvider.autoDispose.family<List<OrderRefund>, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(orderRepositoryProvider).getRefunds(orderId);
    });

/// What this customer has already reported about the order (0095), newest
/// first.
///
/// Empty for almost every order, like the refunds above, and the widget renders
/// nothing when it is. Watched rather than read once so that raising a complaint
/// can invalidate it and the receipt updates itself.
final AutoDisposeFutureProviderFamily<List<OrderIssue>, String>
orderIssuesProvider =
    FutureProvider.autoDispose.family<List<OrderIssue>, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(orderRepositoryProvider).getIssues(orderId);
    });

/// The tax invoice for a delivered order (0063).
///
/// Left in its error state on purpose, unlike everything else on this screen:
/// the document *is* the screen. "An invoice is issued once your order has been
/// delivered." is the answer, and an empty page pretending otherwise is not.
final AutoDisposeFutureProviderFamily<OrderInvoice, String> orderInvoiceProvider =
    FutureProvider.autoDispose.family<OrderInvoice, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(orderRepositoryProvider).getInvoice(orderId);
    });

/// Saves a rating, and reports what the review service said if it refused.
///
/// State is whether a save is in flight — the same shape as
/// [OrderCancelController], and for the same reason. Returns the refusal rather
/// than throwing it: "This review can no longer be changed." is the answer when
/// the hour ran out while the sheet was open, and it is the only useful sentence
/// on screen at that moment. Null means the rating is in.
class OrderReviewController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<String?> submit({
    required String orderId,
    required int foodRating,
    int? riderRating,
    String? comment,
  }) async {
    if (state) return null;
    state = true;
    try {
      await ref
          .read(orderRepositoryProvider)
          .submitReview(
            orderId: orderId,
            foodRating: foodRating,
            riderRating: riderRating,
            comment: comment,
          );
      // Both of these read the row this just wrote. The state matters as much
      // as the review: an edit that lands on the last minute of the window has
      // to come back with a button that is already gone.
      ref.invalidate(myOrderReviewProvider(orderId));
      ref.invalidate(orderReviewStateProvider(orderId));
      return null;
    } on OrderReviewFailure catch (failure) {
      ref.invalidate(myOrderReviewProvider(orderId));
      return failure.message;
    } finally {
      state = false;
    }
  }
}

final NotifierProvider<OrderReviewController, bool>
orderReviewControllerProvider =
    NotifierProvider<OrderReviewController, bool>(OrderReviewController.new);

/// Calls an order off, and reports what the order service said if it refused.
///
/// State is whether a cancellation is in flight, which is what the button
/// renders — the same shape as [ReorderController], and for the same reason.
///
/// Returns the refusal rather than throwing it. The sentence is the answer the
/// screen shows ("The kitchen has already started cooking this order."), not an
/// exception to be caught somewhere and turned into "something went wrong".
/// Null means the order is cancelled.
class OrderCancelController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<String?> cancel(String orderId, {String? reason}) async {
    state = true;
    try {
      await ref
          .read(orderRepositoryProvider)
          .cancelOrder(orderId: orderId, reason: reason);
      // The order row changed under both of these. The status stream will bring
      // the tracking card along on its own, but the *receipt* — and the reason
      // printed on it — was fetched once and is now stale.
      ref.invalidate(orderByIdProvider(orderId));
      ref.invalidate(ordersProvider);
      return null;
    } on OrderCancelFailure catch (failure) {
      // The order moved while the sheet was open — someone in the kitchen tapped
      // Start a half-second before this did. Refetch, so the screen agrees with
      // the sentence it is about to show.
      ref.invalidate(orderByIdProvider(orderId));
      return failure.message;
    } finally {
      state = false;
    }
  }
}

final NotifierProvider<OrderCancelController, bool>
orderCancelControllerProvider =
    NotifierProvider<OrderCancelController, bool>(OrderCancelController.new);

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
