import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_refund.dart';
import 'package:zopiqnow/features/gifts/data/datasources/gift_datasource.dart';
import 'package:zopiqnow/features/gifts/data/datasources/gift_supabase_datasource.dart';
import 'package:zopiqnow/features/gifts/data/repositories/gift_repository_impl.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_cart.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_order.dart';
import 'package:zopiqnow/features/gifts/domain/repositories/gift_repository.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_cart_providers.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

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

// --- Ordering (migration 0096) ----------------------------------------------

/// The gift *ordering* data source. Its own binding beside the catalogue one so
/// a test can fake a failing checkout without faking the shop list too.
final Provider<GiftOrderDataSource> giftOrderDataSourceProvider =
    Provider<GiftOrderDataSource>(
      (Ref ref) => const GiftOrderSupabaseDataSource(),
    );

/// What the bag currently in hand costs, priced by the service (0112).
///
/// Watches the bag, so editing it reprices rather than leaving the checkout
/// screen quoting a total for something else. A `loading` here is the reason the
/// Pay button waits — an amount is not something to guess at while it arrives.
final AutoDisposeFutureProvider<GiftQuote?> giftQuoteProvider =
    FutureProvider.autoDispose<GiftQuote?>((Ref ref) {
      final GiftCart bag = ref.watch(giftCartProvider);
      if (bag.isEmpty) return null;
      return ref
          .watch(giftOrderDataSourceProvider)
          .quoteBag(shopId: bag.shopId, items: bag.toOrderItems());
    });

/// This customer's gift orders, newest first.
///
/// Auto-disposed and watching auth, like the food history: signing out and back
/// in as somebody else must refetch rather than serve the last account's
/// receipts out of a cache.
final AutoDisposeFutureProvider<List<GiftOrder>> giftOrdersProvider =
    FutureProvider.autoDispose<List<GiftOrder>>((Ref ref) {
      ref.watch(authControllerProvider);
      return ref.watch(giftOrderDataSourceProvider).fetchOrders();
    });

/// One gift order, by id, out of the list above.
///
/// A lookup rather than a fetch: unlike the food detail screen there is no way
/// to reach a gift order except through the list, and no push that deep-links to
/// one. If that changes this becomes a fetch, like `orderByIdProvider` did.
final AutoDisposeProviderFamily<GiftOrder?, String> giftOrderByIdProvider =
    Provider.autoDispose.family<GiftOrder?, String>((Ref ref, String id) {
      final List<GiftOrder> all =
          ref.watch(giftOrdersProvider).valueOrNull ?? const <GiftOrder>[];
      for (final GiftOrder o in all) {
        if (o.id == id) return o;
      }
      return null;
    });

/// The lines on one gift order.
final AutoDisposeFutureProviderFamily<List<GiftOrderLine>, String>
giftOrderLinesProvider =
    FutureProvider.autoDispose.family<List<GiftOrderLine>, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(giftOrderDataSourceProvider).fetchOrderLines(orderId);
    });

/// Complaints raised about one gift order (0114), newest first.
///
/// The food side's `orderIssuesProvider` with a different function behind it.
/// Invalidated by the report sheet's caller the moment one is filed, so the
/// receipt stops looking exactly as it did before somebody complained.
final AutoDisposeFutureProviderFamily<List<OrderIssue>, String>
giftOrderIssuesProvider =
    FutureProvider.autoDispose.family<List<OrderIssue>, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(giftOrderDataSourceProvider).fetchIssues(orderId);
    });

/// Money owed back on one gift order (0115), oldest first.
///
/// The food side's `orderRefundsProvider` with a different function behind it.
/// Empty on almost every order, and the section renders nothing at all when it
/// is — including while the read is in flight, so a receipt does not jump.
final AutoDisposeFutureProviderFamily<List<OrderRefund>, String>
giftOrderRefundsProvider =
    FutureProvider.autoDispose.family<List<OrderRefund>, String>((
      Ref ref,
      String orderId,
    ) {
      return ref.watch(giftOrderDataSourceProvider).fetchRefunds(orderId);
    });

/// The receipt the acknowledgement screen shows.
///
/// Held here rather than passed through the route for the reason
/// `lastPlacedOrderProvider` is: a router rebuild must not blank the one screen
/// that exists to tell somebody their money went somewhere.
final NotifierProvider<LastGiftOrderNotifier, GiftOrder?>
lastGiftOrderProvider =
    NotifierProvider<LastGiftOrderNotifier, GiftOrder?>(
      LastGiftOrderNotifier.new,
    );

class LastGiftOrderNotifier extends Notifier<GiftOrder?> {
  @override
  GiftOrder? build() => null;

  void set(GiftOrder order) => state = order;
  void clear() => state = null;
}
