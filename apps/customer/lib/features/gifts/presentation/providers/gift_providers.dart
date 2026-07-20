import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/gifts/data/datasources/gift_datasource.dart';
import 'package:zopiqnow/features/gifts/data/datasources/gift_supabase_datasource.dart';
import 'package:zopiqnow/features/gifts/data/repositories/gift_repository_impl.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/domain/repositories/gift_repository.dart';

/// Data source binding — Supabase. Tests override it with a fake to inject
/// latency and failure without a network.
final Provider<GiftDataSource> giftDataSourceProvider =
    Provider<GiftDataSource>((Ref ref) => const GiftSupabaseDataSource());

/// Repository binding — the seam the UI depends on.
final Provider<GiftRepository> giftRepositoryProvider =
    Provider<GiftRepository>(
      (Ref ref) => GiftRepositoryImpl(ref.watch(giftDataSourceProvider)),
    );

/// The storefront rail: every active gift shop, highest-rated first.
final FutureProvider<List<GiftShop>> giftShopsProvider =
    FutureProvider<List<GiftShop>>(
      (Ref ref) => ref.watch(giftRepositoryProvider).getShops(),
    );

/// The Gifts feed: every available item across all shops, ordered for browsing.
/// Retry = `ref.invalidate(giftItemsProvider)`.
final FutureProvider<List<GiftItem>> giftItemsProvider =
    FutureProvider<List<GiftItem>>(
      (Ref ref) => ref.watch(giftRepositoryProvider).getItems(),
    );

/// A single shop, for its storefront page. A family so a cold link to
/// `/gifts/shop/:id` resolves without the Gifts feed ever having loaded.
final AutoDisposeFutureProviderFamily<GiftShop, String> giftShopByIdProvider =
    FutureProvider.autoDispose.family<GiftShop, String>(
      (Ref ref, String id) =>
          ref.watch(giftRepositoryProvider).getShopById(id),
    );

/// The items of one shop, grouped-ready (ordered by shelf then rank).
final AutoDisposeFutureProviderFamily<List<GiftItem>, String>
giftItemsByShopProvider =
    FutureProvider.autoDispose.family<List<GiftItem>, String>(
      (Ref ref, String shopId) =>
          ref.watch(giftRepositoryProvider).getItemsByShop(shopId),
    );
