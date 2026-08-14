import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/checkout/data/datasources/order_ad_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_ad.dart';

final Provider<OrderAdDataSource> orderAdDataSourceProvider =
    Provider<OrderAdDataSource>((Ref ref) => const OrderAdDataSource());

/// The ad currently beside the tracking map, or null when none is live.
///
/// **Not** auto-disposed, and that is the point: the tracking screen rebuilds on
/// every rider ping, and an auto-disposed future would refetch the ad each time
/// the customer left the map for the full-screen one and came back. One fetch
/// per app run is right for a row that changes when an admin says so.
final FutureProvider<OrderAd?> liveOrderAdProvider = FutureProvider<OrderAd?>(
  (Ref ref) => ref.watch(orderAdDataSourceProvider).fetchLive(),
);
