import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/gifts/data/datasources/gift_datasource.dart';
import 'package:zopiqnow/features/gifts/data/datasources/gift_row.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
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
