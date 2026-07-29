import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/reviews/domain/entities/vendor_review.dart';

/// What customers said, and the two figures that summarise it.
///
/// Both calls are RPCs, for the reason the staff roster's are: `reviews` has no
/// select policy at all (0062) and is unreachable through PostgREST. The two
/// functions answer narrow questions about the caller's own restaurant, and
/// neither of them returns a customer.
abstract interface class ReviewsDataSource {
  Future<VendorReviewSummary> fetchSummary();

  Future<List<VendorReview>> fetchReviews();
}

class ReviewsSupabaseDataSource implements ReviewsDataSource {
  const ReviewsSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<VendorReviewSummary> fetchSummary() async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'vendor_review_summary',
    );
    if (rows.isEmpty) return VendorReviewSummary.empty;
    return VendorReviewSummary.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Future<List<VendorReview>> fetchReviews() async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>('vendor_reviews');
    return rows
        .cast<Map<String, dynamic>>()
        .map(VendorReview.fromJson)
        .toList(growable: false);
  }
}
