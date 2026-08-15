import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The catalog read contract, implemented by the mock and by Supabase.
///
/// This interface is what makes the backend swap a one-line provider change:
/// the repository above it names *this*, not either implementation. Tests keep
/// using the mock; the app talks to Postgres.
abstract interface class RestaurantDataSource {
  /// The catalogue of the town named by [areaId] — `sadri`, `falna` (0126).
  ///
  /// Required rather than optional so a new call site cannot forget it and
  /// silently serve the whole platform. The caller resolves the town from the
  /// delivery address and does not call this at all until it has one.
  Future<List<Restaurant>> fetchNearby({required String areaId});

  /// Null when no restaurant carries [id]. The repository maps that to a
  /// domain-level not-found, which is not the same thing as a transport error.
  ///
  /// **Not filtered by town**, unlike the two list reads. A deep link into a
  /// kitchen in the next town should open its menu and be refused at checkout,
  /// which says something true; filtering here would say "this restaurant is no
  /// longer available", which does not.
  Future<Restaurant?> fetchById(String id);

  Future<List<Restaurant>> search(String query, {required String areaId});
}
