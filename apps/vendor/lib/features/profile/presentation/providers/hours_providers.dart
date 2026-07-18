import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/profile/data/restaurant_hours_datasource.dart';
import 'package:zopiq_vendor/features/profile/domain/entities/opening_hours.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<RestaurantHoursDataSource> restaurantHoursDataSourceProvider =
    Provider<RestaurantHoursDataSource>(
      (Ref ref) => const RestaurantHoursSupabaseDataSource(),
    );

/// The signed-in restaurant's opening hours — only the open days, ascending.
/// Empty means an unset week, which the database reads as "always open".
final FutureProvider<List<OpeningHours>> restaurantHoursProvider =
    FutureProvider<List<OpeningHours>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        return Future<List<OpeningHours>>.value(const <OpeningHours>[]);
      }
      return ref
          .watch(restaurantHoursDataSourceProvider)
          .fetch(vendor.restaurantId);
    });

/// The one write the hours screen makes. Returns null on success or a sentence to
/// show the vendor — the same shape [MenuController] and the order queue use.
class HoursController extends Notifier<void> {
  @override
  void build() {}

  Future<String?> save(List<OpeningHours> hours) async {
    if (ref.read(vendorProvider) == null) return 'You\'re signed out.';
    try {
      await ref.read(restaurantHoursDataSourceProvider).save(hours);
      ref.invalidate(restaurantHoursProvider);
      return null;
    } on HoursWriteFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t save your hours. Please try again.';
    }
  }
}

final NotifierProvider<HoursController, void> hoursControllerProvider =
    NotifierProvider<HoursController, void>(HoursController.new);
