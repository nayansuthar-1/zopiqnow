import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/profile/data/vendor_restaurant_datasource.dart';
import 'package:zopiq_vendor/features/profile/domain/entities/restaurant_profile.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<VendorRestaurantDataSource> vendorRestaurantDataSourceProvider =
    Provider<VendorRestaurantDataSource>(
      (Ref ref) => const VendorRestaurantSupabaseDataSource(),
    );

/// The signed-in restaurant's editable profile. A one-shot read, re-fetched by
/// [ProfileController] after a save so the view reflects what the database
/// actually stored.
final FutureProvider<RestaurantProfile> restaurantProfileProvider =
    FutureProvider<RestaurantProfile>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        throw StateError('No signed-in vendor to read a profile for.');
      }
      return ref
          .watch(vendorRestaurantDataSourceProvider)
          .fetch(vendor.restaurantId);
    });

/// The one write the profile screen makes. Returns null on success, or a
/// sentence to show the vendor — the same shape the menu and order controllers
/// use.
class ProfileController extends Notifier<void> {
  @override
  void build() {}

  Future<String?> save({
    required String name,
    required List<String> cuisines,
    required int priceForTwo,
    required bool isVeg,
    required String? promoText,
    required int etaMinutes,
  }) async {
    try {
      await ref
          .read(vendorRestaurantDataSourceProvider)
          .save(
            name: name,
            cuisines: cuisines,
            priceForTwo: priceForTwo,
            isVeg: isVeg,
            promoText: promoText,
            etaMinutes: etaMinutes,
          );
      // The name lives in two places that must not drift: the profile the screen
      // shows, and the session the queue's header reads. Refresh one and update
      // the other, or the kitchen keeps its new name everywhere but the top of
      // its own order screen.
      ref.read(vendorAuthControllerProvider.notifier).applyRestaurantName(name);
      ref.invalidate(restaurantProfileProvider);
      return null;
    } on ProfileWriteFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t save your changes. Please try again.';
    }
  }
}

final NotifierProvider<ProfileController, void> profileControllerProvider =
    NotifierProvider<ProfileController, void>(ProfileController.new);
