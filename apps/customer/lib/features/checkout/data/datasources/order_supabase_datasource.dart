import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Orders and coupons, over the `validate_coupon` and `place_order` functions.
///
/// The tables behind them are invisible to this key — RLS is on with no select
/// policy — so these two functions are the entire surface. Everything the
/// customer is charged is decided inside them.
class OrderSupabaseDataSource implements OrderDataSource {
  const OrderSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// Postgres raises `P0001` for the rules we wrote, with a message written for
  /// the customer. Any other code is a bug or an outage — not something to put
  /// in front of a human.
  static const String _businessRuleErrorCode = 'P0001';

  @override
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
  }) async {
    try {
      final dynamic discount = await _db.rpc<dynamic>(
        'validate_coupon',
        params: <String, dynamic>{'p_code': code, 'p_subtotal': subtotal},
      );
      return AppliedCoupon(
        code: code.trim().toUpperCase(),
        discount: (discount as num).toInt(),
      );
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw CouponFailure(e.message);
      rethrow;
    }
  }

  @override
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
    required String userPhone,
    String? couponCode,
    String? paymentId,
  }) async {
    try {
      // The session's JWT rides along on the RPC, and `place_order` takes the
      // buyer from `auth.uid()`. That is why no user id is sent: the one value
      // the client must not be trusted with is who it is.
      final Map<String, dynamic> receipt = await _db
          .rpc<Map<String, dynamic>>(
            'place_order',
            params: <String, dynamic>{
              'p_user_phone': userPhone,
              'p_restaurant_id': cart.restaurantId,
              // Ids and quantities only. No prices leave this device.
              'p_items': cart.lines
                  .map(
                    (CartLine l) => <String, dynamic>{
                      'menu_item_id': l.item.id,
                      'quantity': l.quantity,
                    },
                  )
                  .toList(),
              'p_delivery_to': deliveryAddress.shortDisplay,
              'p_delivery_lat': deliveryAddress.latitude,
              'p_delivery_lng': deliveryAddress.longitude,
              'p_payment_method': paymentMethod.name,
              'p_coupon_code': couponCode,
              'p_payment_id': paymentId,
            },
          );

      return PlacedOrder(
        id: receipt['id'] as String,
        restaurantName: receipt['restaurant_name'] as String,
        deliveryTo: receipt['delivery_to'] as String,
        total: (receipt['total'] as num).toInt(),
        paymentMethod: paymentMethod,
        etaMinutes: (receipt['eta_minutes'] as num).toInt(),
        paymentId: receipt['payment_id'] as String?,
      );
    } on PostgrestException catch (e) {
      // "Your cart is empty", "Something in your cart is no longer available" —
      // rules we wrote, phrased for the customer, so they are worth showing.
      if (e.code == _businessRuleErrorCode) {
        throw OrderPlacementFailure(e.message);
      }
      throw const OrderPlacementFailure();
    }
  }

  /// How far back "your orders" goes. A customer with a thousand orders does not
  /// want a thousand cards, and an unbounded select is how a screen that was
  /// fast in testing gets slow in production. Paging arrives if anyone asks.
  static const int _historyLimit = 25;

  @override
  Future<List<CustomerOrder>> fetchOrders() async {
    // No `.eq('user_id', …)`. The row-level policy on `orders` already answers
    // "whose?" from the JWT, and a filter here would only be a second, weaker
    // copy of that rule — one that a bug could get wrong and that an attacker
    // could simply omit.
    final List<Map<String, dynamic>> rows = await _db
        .from('orders')
        .select(
          'id, restaurant_id, restaurant_name, status, created_at, delivery_to, '
          'eta_minutes, payment_method, payment_id, subtotal, delivery_fee, '
          'taxes, discount, total, coupon_code, '
          // The catalog join is for the photo alone — the name is on the order,
          // so a delisted restaurant costs us an image and not an identity.
          'restaurants(image_url), '
          'order_items(menu_item_id, name, unit_price, quantity, line_total)',
        )
        .order('created_at', ascending: false)
        .limit(_historyLimit);

    return rows.map(_orderFrom).toList(growable: false);
  }

  CustomerOrder _orderFrom(Map<String, dynamic> row) {
    final Map<String, dynamic>? restaurant =
        row['restaurants'] as Map<String, dynamic>?;

    final List<OrderLine> lines =
        (row['order_items'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> i) => OrderLine(
                menuItemId: i['menu_item_id'] as String,
                name: i['name'] as String,
                unitPrice: (i['unit_price'] as num).toInt(),
                quantity: (i['quantity'] as num).toInt(),
                lineTotal: (i['line_total'] as num).toInt(),
              ),
            )
            .toList()
          // PostgREST does not promise an order within an embedded list, and a
          // receipt whose lines shuffle between two reads of the same order
          // looks broken. Sorting by name is arbitrary but stable.
          ..sort((OrderLine a, OrderLine b) => a.name.compareTo(b.name));

    return CustomerOrder(
      id: row['id'] as String,
      restaurantId: row['restaurant_id'] as String,
      restaurantName: row['restaurant_name'] as String,
      restaurantImageUrl: restaurant?['image_url'] as String? ?? '',
      status: OrderStatus.fromWire(row['status'] as String),
      placedAt: DateTime.parse(row['created_at'] as String).toLocal(),
      deliveryTo: row['delivery_to'] as String,
      etaMinutes: (row['eta_minutes'] as num).toInt(),
      paymentMethod: PaymentMethod.values.byName(row['payment_method'] as String),
      paymentId: row['payment_id'] as String?,
      subtotal: (row['subtotal'] as num).toInt(),
      deliveryFee: (row['delivery_fee'] as num).toInt(),
      taxes: (row['taxes'] as num).toInt(),
      discount: (row['discount'] as num).toInt(),
      total: (row['total'] as num).toInt(),
      couponCode: row['coupon_code'] as String?,
      lines: lines,
    );
  }

  @override
  Future<List<String>> fetchCouponHints() async {
    final List<Map<String, dynamic>> rows = await _db
        .from('coupons')
        .select('code, flat_off, percent_off, max_off')
        // Easiest coupon to qualify for, first. (`ascending: true` — see the
        // note in RestaurantSupabaseDataSource; the default is descending.)
        .order('min_subtotal', ascending: true);

    return rows.map((Map<String, dynamic> r) {
      final String code = r['code'] as String;
      final num? flatOff = r['flat_off'] as num?;
      return flatOff != null
          ? '$code · ₹$flatOff off'
          : '$code · ${r['percent_off']}% off up to ₹${r['max_off']}';
    }).toList(growable: false);
  }
}
