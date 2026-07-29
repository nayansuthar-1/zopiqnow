import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/offers/domain/entities/vendor_offer.dart';

/// The kitchen's own promotions.
///
/// Every call is an RPC, and every one of them is scoped inside the function
/// rather than by an argument: `vendor_save_offer` takes no restaurant id, and
/// `vendor_set_offer_active` will not touch a row whose `restaurant_id` is not
/// the caller's. A client that could name the restaurant could discount
/// somebody else's food.
abstract interface class OffersDataSource {
  Future<List<VendorOffer>> fetch();

  /// Creates or updates. Returns the full code the database settled on — the
  /// vendor types `WEEKEND` and gets `R3-WEEKEND`, because a kitchen may not
  /// squat on a name the platform or another restaurant might want.
  Future<String> save({
    required String code,
    required int minSubtotal,
    int? flatOff,
    int? percentOff,
    int? maxOff,
    DateTime? validUntil,
  });

  Future<void> setActive({required String code, required bool isActive});
}

/// A call the database refused — a rule in 0064 (`P0001`: not the owner, a code
/// already in use, an offer that is neither flat nor percentage) or an outage.
class OfferWriteFailure implements Exception {
  const OfferWriteFailure([
    this.message = 'We couldn\'t save that offer. Please try again.',
  ]);

  final String message;
}

class OffersSupabaseDataSource implements OffersDataSource {
  const OffersSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  static const String _businessRuleErrorCode = 'P0001';

  @override
  Future<List<VendorOffer>> fetch() async {
    final List<dynamic> rows = await _guard<List<dynamic>>(
      () => _db.rpc<List<dynamic>>('vendor_offers'),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(VendorOffer.fromJson)
        .toList(growable: false);
  }

  @override
  Future<String> save({
    required String code,
    required int minSubtotal,
    int? flatOff,
    int? percentOff,
    int? maxOff,
    DateTime? validUntil,
  }) {
    return _guard<String>(
      () => _db.rpc<String>(
        'vendor_save_offer',
        params: <String, dynamic>{
          'p_code': code,
          'p_min_subtotal': minSubtotal,
          'p_flat_off': flatOff,
          'p_percent_off': percentOff,
          'p_max_off': maxOff,
          'p_valid_until': validUntil?.toUtc().toIso8601String(),
        },
      ),
    );
  }

  @override
  Future<void> setActive({required String code, required bool isActive}) =>
      _guard<void>(
        () => _db.rpc<void>(
          'vendor_set_offer_active',
          params: <String, dynamic>{'p_code': code, 'p_active': isActive},
        ),
      );

  /// Every refusal in 0064 is raised as `P0001` with a sentence already written
  /// for a human — "An offer is either a flat amount off or a percentage, not
  /// both." Passing it through beats inventing a vaguer one here.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw OfferWriteFailure(e.message);
      throw const OfferWriteFailure();
    }
  }
}
