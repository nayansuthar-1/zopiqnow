import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_invoice.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_message.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_refund.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_review.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/restaurant_offer.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Default [OrderRepository]. Names the data source interface, so the mock and
/// Postgres are interchangeable.
class OrderRepositoryImpl implements OrderRepository {
  const OrderRepositoryImpl(this._dataSource);

  final OrderDataSource _dataSource;

  @override
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
    required String restaurantId,
  }) {
    // CouponFailure passes through untouched — it *is* the domain answer.
    return _dataSource.applyCoupon(
      code: code,
      subtotal: subtotal,
      restaurantId: restaurantId,
    );
  }

  @override
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
    required String userPhone,
    String? couponCode,
    String? paymentId,
    String? deliveryNotes,
    String? idempotencyKey,
  }) async {
    try {
      return await _dataSource.placeOrder(
        cart: cart,
        deliveryAddress: deliveryAddress,
        paymentMethod: paymentMethod,
        userPhone: userPhone,
        couponCode: couponCode,
        paymentId: paymentId,
        deliveryNotes: deliveryNotes,
        idempotencyKey: idempotencyKey,
      );
    } on OrderPlacementFailure {
      // Already a domain failure carrying the service's own message — relabelling
      // it as a generic error would throw away the only useful sentence in it.
      rethrow;
    } on CouponFailure catch (failure) {
      // The coupon was valid when applied and is not valid now — the cart moved
      // under it. That is a *placement* failure at this point (the screen has no
      // coupon field to attach an error to any more), but the reason is worth
      // keeping: "Add items worth ₹99 more" tells the customer what to do, and
      // "please try again" tells them nothing.
      throw OrderPlacementFailure(failure.message);
    } on Object catch (_) {
      throw const OrderPlacementFailure();
    }
  }

  @override
  Future<List<CustomerOrder>> getOrders() async {
    try {
      return await _dataSource.fetchOrders();
    } on Object catch (_) {
      // Unlike a missing coupon hint, an empty list here is a *statement* —
      // "you have never ordered" — and the screen renders it as one. A failed
      // fetch must not be able to say that, so it surfaces as an error the user
      // can retry.
      throw const OrdersLoadFailure();
    }
  }

  @override
  Future<CustomerOrder?> getOrder(String orderId) async {
    try {
      return await _dataSource.fetchOrder(orderId);
    } on Object catch (_) {
      // Null already means "you have no such order", which the screen renders
      // as a dead end with a way back to the list. A failed fetch must not be
      // able to say that — it is a retry, not a verdict.
      throw const OrdersLoadFailure();
    }
  }

  @override
  Stream<OrderStatus> watchOrderStatus(String orderId) =>
      // Passed through untouched. A dropped subscription is not a failure the
      // customer needs a sentence about: the order still renders from what was
      // fetched, and the only thing lost is the live-ness.
      _dataSource.watchOrderStatus(orderId);

  @override
  Future<String?> getDeliveryCode(String orderId) async {
    try {
      return await _dataSource.fetchDeliveryCode(orderId);
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<DeliveryRoute?> getRoute(String orderId) async {
    try {
      return await _dataSource.fetchRoute(orderId);
    } on Object catch (_) {
      // Same swallow, same reason as [getRider]: the tracking card is already
      // rendering the order. Failing it over a map would be trading the screen
      // for a picture.
      return null;
    }
  }

  @override
  Stream<RiderPosition?> watchRiderPosition(String carrierKey) =>
      // Passed through untouched, like [watchOrderStatus]. A dropped
      // subscription costs the dot its liveness and nothing else — the map
      // still has its two pins and its road.
      _dataSource.watchRiderPosition(carrierKey);

  @override
  Future<OrderRider?> getRider(String orderId) async {
    try {
      return await _dataSource.fetchRider(orderId);
    } on Object catch (_) {
      // Swallowed on purpose, and the one place in this class where that is the
      // right answer: the tracking card is already rendering the order. Failing
      // it over a name would be trading the screen for a nicety.
      return null;
    }
  }

  @override
  Future<List<CannedMessage>> getMessageMenu() async {
    try {
      return await _dataSource.fetchMessageMenu();
    } on Object catch (_) {
      // Empty is already "the chat has nothing to offer", and the sheet handles
      // it by not opening. A failed read looks the same, which is the honest
      // outcome: without the list there is nothing to tap.
      return const <CannedMessage>[];
    }
  }

  @override
  Stream<List<OrderMessage>> watchMessages(String orderId) =>
      // Passed through untouched, like [watchOrderStatus]. A dropped socket
      // costs the thread its liveness, not the lines already on screen.
      _dataSource.watchMessages(orderId);

  @override
  Future<void> sendMessage({
    required String orderId,
    required String code,
  }) async {
    try {
      await _dataSource.sendMessage(orderId: orderId, code: code);
    } on OrderMessageFailure {
      // Already carries the service's own sentence. Relabelling it would throw
      // away the only useful thing in it.
      rethrow;
    } on Object catch (_) {
      throw const OrderMessageFailure();
    }
  }

  @override
  Future<void> markMessagesRead(String orderId) async {
    try {
      await _dataSource.markMessagesRead(orderId);
    } on Object catch (_) {
      // A read receipt nobody got. Nothing the customer could do about it.
    }
  }

  @override
  Future<void> cancelOrder({required String orderId, String? reason}) async {
    try {
      await _dataSource.cancelOrder(orderId: orderId, reason: reason);
    } on OrderCancelFailure {
      // Already carries the service's own sentence — "your order is packed and
      // waiting for a rider" — which is the whole answer. Relabelling it would
      // throw away the only part the customer can act on.
      rethrow;
    } on Object catch (_) {
      throw const OrderCancelFailure();
    }
  }

  @override
  Future<List<RestaurantOffer>> getOffers(String restaurantId) async {
    try {
      return await _dataSource.fetchOffers(restaurantId);
    } on Object catch (_) {
      // A missing hint is a missing hint. Checkout still works without it, so
      // this must never take the screen down.
      return const <RestaurantOffer>[];
    }
  }

  @override
  Future<OrderReviewState> getReviewState(String orderId) async {
    try {
      return await _dataSource.fetchReviewState(orderId);
    } on Object catch (_) {
      // Swallowed, like [getRider]: "no prompt" is what an un-reviewable order
      // already shows, so a failed read costs a prompt and not the receipt.
      return OrderReviewState.none;
    }
  }

  @override
  Future<OrderReview?> getMyReview(String orderId) async {
    try {
      return await _dataSource.fetchMyReview(orderId);
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<List<OrderRefund>> getRefunds(String orderId) async {
    try {
      return await _dataSource.fetchRefunds(orderId);
    } on Object catch (_) {
      return const <OrderRefund>[];
    }
  }

  @override
  Future<List<OrderIssue>> getIssues(String orderId) async {
    try {
      return await _dataSource.fetchIssues(orderId);
    } on Object catch (_) {
      return const <OrderIssue>[];
    }
  }

  @override
  Future<void> raiseIssue({
    required String orderId,
    required IssueCategory category,
    String? body,
  }) async {
    try {
      await _dataSource.raiseIssue(
        orderId: orderId,
        category: category,
        body: body,
      );
    } on OrderIssueFailure {
      // The service's own sentence — the caps and the ownership check are all
      // written to be read. Passed straight through.
      rethrow;
    } on Object catch (_) {
      throw const OrderIssueFailure();
    }
  }

  @override
  Future<void> submitReview({
    required String orderId,
    required int foodRating,
    int? riderRating,
    String? comment,
  }) async {
    try {
      await _dataSource.submitReview(
        orderId: orderId,
        foodRating: foodRating,
        riderRating: riderRating,
        comment: comment,
      );
    } on OrderReviewFailure {
      // Already carries the service's own sentence. Relabelling it would throw
      // away the only useful thing in it.
      rethrow;
    } on Object catch (_) {
      throw const OrderReviewFailure();
    }
  }

  @override
  Future<OrderInvoice> getInvoice(String orderId) async {
    try {
      return await _dataSource.fetchInvoice(orderId);
    } on InvoiceFailure {
      rethrow;
    } on Object catch (_) {
      throw const InvoiceFailure();
    }
  }
}
