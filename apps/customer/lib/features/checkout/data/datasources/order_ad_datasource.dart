import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_ad.dart';

/// The ad beside the tracking map: `public.order_ads` over PostgREST, plus the
/// one write that counts what happened to it.
///
/// Modelled on `HeroSlideDataSource` and for the same reasons — no repository
/// and no abstract seam, because there is no failure state worth injecting. An
/// error here is no ad, and no ad is a map with an empty corner, which is what
/// the screen looked like last week.
///
/// **There is no `is_active` / `starts_at` / `ends_at` filter below and there
/// must not be.** 0125's read policy applies all three server-side.
class OrderAdDataSource {
  const OrderAdDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// The ad to show, or null when no campaign is live.
  ///
  /// One row, not a carousel: the corner of a map holds one puck, and an ad that
  /// rotated under the customer's thumb while they watched a scooter move would
  /// be a different tap than the one they aimed at.
  Future<OrderAd?> fetchLive() async {
    final List<Map<String, dynamic>> rows = await _db
        .from('order_ads')
        .select('id, logo_url, image_url, headline, cta_label, cta_target')
        // Explicitly ascending — postgrest-dart's `order()` defaults to
        // descending, which would make sort_order run backwards.
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true)
        .limit(1);

    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Counts a view or a click. Fire-and-forget, and deliberately swallowing:
  /// this is called from the tracking screen, and an analytics ping is never a
  /// reason for the screen showing a customer their dinner to show an error.
  ///
  /// The server drops a second view for the same order, so calling this on
  /// every rebuild is safe and counts once (0125).
  Future<void> record({
    required String adId,
    required String kind,
    String? orderId,
  }) async {
    try {
      await _db.rpc<void>(
        'record_ad_event',
        params: <String, dynamic>{
          'p_ad_id': adId,
          'p_kind': kind,
          'p_order_id': orderId,
        },
      );
    } on Object {
      // Nothing. See above.
    }
  }
}

OrderAd _fromRow(Map<String, dynamic> row) => OrderAd(
  id: row['id'] as String,
  logoUrl: row['logo_url'] as String,
  imageUrl: row['image_url'] as String,
  headline: (row['headline'] as String?) ?? '',
  ctaLabel: (row['cta_label'] as String?) ?? '',
  ctaTarget: (row['cta_target'] as String?) ?? '',
);
