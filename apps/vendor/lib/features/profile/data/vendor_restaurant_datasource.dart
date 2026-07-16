import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/profile/domain/entities/restaurant_profile.dart';

/// The vendor's read and write of its own `restaurants` row.
///
/// Reading is a plain select — the vendor may see their own restaurant even when
/// inactive (0009). Writing is the RPC and only the RPC: there is no `update`
/// grant on `restaurants`, so `update_restaurant_profile` (0012) is the one door,
/// and it can reach only the six editable columns.
abstract interface class VendorRestaurantDataSource {
  Future<RestaurantProfile> fetch(String restaurantId);

  Future<void> save({
    required String name,
    required List<String> cuisines,
    required int priceForTwo,
    required bool isVeg,
    required String? promoText,
    required int etaMinutes,
  });
}

/// A profile write the database refused — a validation rule (`P0001`, with a
/// human sentence) or an outage. The message is the one the form shows.
class ProfileWriteFailure implements Exception {
  const ProfileWriteFailure([
    this.message = 'We couldn\'t save your changes. Please try again.',
  ]);

  final String message;
}

class VendorRestaurantSupabaseDataSource implements VendorRestaurantDataSource {
  const VendorRestaurantSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  static const String _businessRuleErrorCode = 'P0001';

  static const String _columns =
      'name, cuisines, price_for_two, is_veg, promo_text, eta_minutes, '
      'rating, rating_count';

  @override
  Future<RestaurantProfile> fetch(String restaurantId) async {
    final Map<String, dynamic> row = await _db
        .from('restaurants')
        .select(_columns)
        .eq('id', restaurantId)
        .single();

    return RestaurantProfile(
      name: row['name'] as String,
      cuisines: (row['cuisines'] as List<dynamic>).cast<String>(),
      priceForTwo: (row['price_for_two'] as num).toInt(),
      isVeg: row['is_veg'] as bool,
      promoText: row['promo_text'] as String?,
      etaMinutes: (row['eta_minutes'] as num).toInt(),
      rating: (row['rating'] as num).toDouble(),
      ratingCount: (row['rating_count'] as num).toInt(),
    );
  }

  @override
  Future<void> save({
    required String name,
    required List<String> cuisines,
    required int priceForTwo,
    required bool isVeg,
    required String? promoText,
    required int etaMinutes,
  }) async {
    try {
      await _db.rpc<void>(
        'update_restaurant_profile',
        params: <String, dynamic>{
          'p_name': name,
          'p_cuisines': cuisines,
          'p_price_for_two': priceForTwo,
          'p_is_veg': isVeg,
          'p_promo_text': promoText,
          'p_eta_minutes': etaMinutes,
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw ProfileWriteFailure(e.message);
      throw const ProfileWriteFailure();
    }
  }
}
