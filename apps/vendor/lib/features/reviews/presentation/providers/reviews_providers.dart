import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/reviews/data/reviews_datasource.dart';
import 'package:zopiq_vendor/features/reviews/domain/entities/vendor_review.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<ReviewsDataSource> reviewsDataSourceProvider =
    Provider<ReviewsDataSource>((Ref ref) => const ReviewsSupabaseDataSource());

/// The headline: the average and how many reviews are behind it.
final FutureProvider<VendorReviewSummary> reviewSummaryProvider =
    FutureProvider<VendorReviewSummary>(
      (Ref ref) => ref.watch(reviewsDataSourceProvider).fetchSummary(),
    );

/// The reviews themselves, newest first.
///
/// A one-shot read, like the staff roster's: a review arriving while the owner
/// is reading the list is what the *notification* is for (0062 posts one), and a
/// held-open socket on a screen somebody visits weekly is a socket for nothing.
final FutureProvider<List<VendorReview>> reviewsProvider =
    FutureProvider<List<VendorReview>>(
      (Ref ref) => ref.watch(reviewsDataSourceProvider).fetchReviews(),
    );
