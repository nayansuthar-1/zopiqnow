import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The catalog read contract, implemented by the mock and by Supabase.
///
/// This interface is what makes the backend swap a one-line provider change:
/// the repository above it names *this*, not either implementation. Tests keep
/// using the mock; the app talks to Postgres.
abstract interface class RestaurantDataSource {
  Future<List<Restaurant>> fetchNearby();

  /// Null when no restaurant carries [id]. The repository maps that to a
  /// domain-level not-found, which is not the same thing as a transport error.
  Future<Restaurant?> fetchById(String id);

  Future<List<Restaurant>> search(String query);
}
