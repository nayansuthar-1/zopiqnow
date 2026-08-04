import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/gifts/data/datasources/gift_datasource.dart';
import 'package:zopiqnow/features/gifts/data/datasources/gift_row.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_order.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';

/// The real Gifts catalog: `public.gift_shops` and `public.gift_items` over
/// PostgREST.
///
/// Row-level security already restricts these to active shops and available
/// items (migration 0022), so the queries carry no such filter — a client-side
/// one would be decoration, since a client cannot be trusted to apply it anyway.
class GiftSupabaseDataSource implements GiftDataSource {
  const GiftSupabaseDataSource();

  /// Resolved per call rather than injected: `Supabase.instance` only exists
  /// after `Supabase.initialize` in `main`, and widget tests never call it.
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<GiftShop>> fetchShops() async {
    final List<Map<String, dynamic>> rows = await _db
        .from('gift_shops')
        .select(giftShopColumns)
        // Highest-rated first. `ascending: false` is explicit because
        // postgrest-dart's `order()` defaults to descending anyway, but every
        // order in this app states its direction.
        .order('rating', ascending: false);
    return rows.map(giftShopFromRow).toList(growable: false);
  }

  @override
  Future<List<GiftItem>> fetchItems() async {
    final List<Map<String, dynamic>> rows = await _db
        .from('gift_items')
        .select(giftItemColumns)
        .order('category_rank', ascending: true)
        .order('item_rank', ascending: true);
    return rows.map(giftItemFromRow).toList(growable: false);
  }

  @override
  Future<GiftShop?> fetchShopById(String id) async {
    final Map<String, dynamic>? row = await _db
        .from('gift_shops')
        .select(giftShopColumns)
        .eq('id', id)
        // Not `.single()`: "no such shop" is an answer, not a failure. The
        // repository decides what it means.
        .maybeSingle();
    return row == null ? null : giftShopFromRow(row);
  }

  @override
  Future<List<GiftItem>> fetchItemsByShop(String shopId) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('gift_items')
        .select(giftItemColumns)
        .eq('shop_id', shopId)
        .order('category_rank', ascending: true)
        .order('item_rank', ascending: true);
    return rows.map(giftItemFromRow).toList(growable: false);
  }
}

/// Gift ordering over the RPCs migration 0096 added.
///
/// Every one of them is a `security definer` function and there is no grant on
/// `gift_orders` at all, so this class could not read or write those rows
/// directly if it tried — which is the point.
class GiftOrderSupabaseDataSource implements GiftOrderDataSource {
  const GiftOrderSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// The SQLSTATE `raise ... using errcode = 'P0001'` arrives as. Everything the
  /// gift functions refuse is written for the customer to read, so this is the
  /// code that decides whether to pass a message through or replace it.
  static const String _businessRuleErrorCode = 'P0001';

  @override
  Future<GiftOrder> placeOrder({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String userPhone,
    required String deliveryTo,
    String? deliveryNotes,
    String? paymentId,
    String? idempotencyKey,
  }) async {
    try {
      final Map<String, dynamic> receipt = await _db
          .rpc<Map<String, dynamic>>(
            'place_gift_order',
            params: <String, dynamic>{
              'p_user_phone': userPhone,
              'p_shop_id': shopId,
              'p_items': items,
              'p_delivery_to': deliveryTo,
              'p_delivery_notes': deliveryNotes,
              'p_payment_id': paymentId,
              'p_idempotency_key': idempotencyKey,
            },
          );

      // The receipt is deliberately thin — it is what the acknowledgement screen
      // needs and nothing more. The full order comes back from `my_gift_orders`
      // the moment that screen is left, so the fields absent here are filled
      // with what the caller already knows rather than fetched again.
      return GiftOrder(
        id: receipt['id'] as String,
        shopName: receipt['shop_name'] as String? ?? '',
        subtotal: 0,
        deliveryFee: 0,
        taxes: 0,
        total: (receipt['total'] as num).toInt(),
        status: GiftOrderStatus.fromWire(
          receipt['status'] as String? ?? 'placed',
        ),
        deliveryTo: receipt['delivery_to'] as String? ?? deliveryTo,
        createdAt: DateTime.now(),
        itemCount: items.length,
      );
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw GiftOrderFailure(e.message);
      throw const GiftOrderFailure();
    }
  }

  @override
  Future<List<GiftOrder>> fetchOrders() async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>('my_gift_orders');
    return rows
        .cast<Map<String, dynamic>>()
        .map(GiftOrder.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<GiftOrderLine>> fetchOrderLines(String orderId) async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'my_gift_order_items',
      params: <String, dynamic>{'p_order_id': orderId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(GiftOrderLine.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> cancelOrder({required String orderId, String? reason}) async {
    try {
      await _db.rpc<String>(
        'cancel_my_gift_order',
        params: <String, dynamic>{'p_order_id': orderId, 'p_reason': reason},
      );
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw GiftOrderFailure(e.message);
      throw const GiftOrderFailure();
    }
  }
}
