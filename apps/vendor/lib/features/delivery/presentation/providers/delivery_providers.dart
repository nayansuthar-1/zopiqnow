import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/delivery/data/delivery_datasource.dart';
import 'package:zopiq_vendor/features/delivery/domain/entities/order_delivery.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<DeliveryDataSource> deliveryDataSourceProvider =
    Provider<DeliveryDataSource>((Ref ref) => const DeliverySupabaseDataSource());

/// Who is carrying what, keyed by order id.
///
/// Re-fetched whenever the order stream pushes — which is exactly when a
/// delivery is most likely to have changed, since a rider confirming pickup
/// writes `orders.status` in the same transaction as `deliveries.state`. That
/// makes one query per queue change, and none while a kitchen sits idle.
///
/// An empty map on failure rather than an error: the rider strip is an extra
/// line on a ticket, and a kitchen must never lose its queue because the
/// delivery table was briefly unreachable.
final FutureProvider<Map<String, OrderDelivery>> deliveriesProvider =
    FutureProvider<Map<String, OrderDelivery>>((Ref ref) async {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) return const <String, OrderDelivery>{};

      ref.watch(ordersProvider);

      try {
        return await ref.watch(deliveryDataSourceProvider).fetchActive();
      } on Object {
        return const <String, OrderDelivery>{};
      }
    });

/// The rider on one order, or null when nobody has claimed it.
final ProviderFamily<OrderDelivery?, String> orderDeliveryProvider =
    Provider.family<OrderDelivery?, String>((Ref ref, String orderId) {
      return ref
          .watch(deliveriesProvider)
          .maybeWhen(
            data: (Map<String, OrderDelivery> all) => all[orderId],
            orElse: () => null,
          );
    });
