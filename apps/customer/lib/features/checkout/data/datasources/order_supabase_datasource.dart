import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
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
