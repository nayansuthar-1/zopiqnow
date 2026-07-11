import 'package:zopiqnow/features/home/data/datasources/restaurant_datasource.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// In-memory stand-in for the restaurant discovery API. Simulates network
/// latency (so the shimmer is exercised) and can be told to fail, to drive the
/// error state.
///
/// The app now reads Postgres ([RestaurantSupabaseDataSource]); this stays as
/// the tests' data source, where a real network would be a liability, not a
/// feature.
///
/// `imageUrl`s point at foodish-api, a free food-photo dataset, on fixed paths so
/// a restaurant always gets the same picture. Its categories are coarse — Sushi
/// Ninja gets a rice dish — so treat the pairings as indicative, not accurate.
///
/// This is **mock data**: it exists to exercise the image pipeline against a real
/// network, and it disappears with this class when the CDN lands. Production must
/// never fetch imagery from a third-party host.
class RestaurantMockDataSource implements RestaurantDataSource {
  const RestaurantMockDataSource({
    this.latency = const Duration(milliseconds: 900),
    this.shouldFail = false,
  });

  final Duration latency;
  final bool shouldFail;

  @override
  Future<List<Restaurant>> fetchNearby() async {
    await Future<void>.delayed(latency);
    if (shouldFail) {
      throw const _MockNetworkException();
    }
    return _seed;
  }

  @override
  Future<Restaurant?> fetchById(String id) async {
    await Future<void>.delayed(latency);
    if (shouldFail) {
      throw const _MockNetworkException();
    }
    for (final Restaurant r in _seed) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Substring match on name and cuisines. The real search service will do
  /// tokenising, typo tolerance and ranking server-side; this only has to be
  /// good enough to build the screen against.
  @override
  Future<List<Restaurant>> search(String query) async {
    await Future<void>.delayed(latency);
    if (shouldFail) {
      throw const _MockNetworkException();
    }
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return const <Restaurant>[];

    return _seed.where((Restaurant r) {
      if (r.name.toLowerCase().contains(q)) return true;
      return r.cuisines.any((String c) => c.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  static const List<Restaurant> _seed = <Restaurant>[
    Restaurant(
      id: 'r1',
      name: 'Paradise Biryani',
      cuisines: <String>['Biryani', 'Hyderabadi', 'Kebabs'],
      rating: 4.4,
      ratingCount: 12800,
      etaMinutes: 32,
      priceForTwo: 500,
      distanceKm: 2.1,
      isVeg: false,
      imageUrl: 'https://foodish-api.com/images/biryani/biryani1.jpg',
      promoText: '50% OFF up to ₹100',
    ),
    Restaurant(
      id: 'r2',
      name: 'Green Theory',
      cuisines: <String>['Healthy', 'Salads', 'Continental'],
      rating: 4.6,
      ratingCount: 3400,
      etaMinutes: 24,
      priceForTwo: 450,
      distanceKm: 1.3,
      isVeg: true,
      imageUrl: 'https://foodish-api.com/images/pasta/pasta5.jpg',
      promoText: 'Free delivery',
    ),
    Restaurant(
      id: 'r3',
      name: 'Sultan\'s Grill',
      cuisines: <String>['Mughlai', 'North Indian', 'BBQ'],
      rating: 4.2,
      ratingCount: 8900,
      etaMinutes: 40,
      priceForTwo: 700,
      distanceKm: 3.7,
      isVeg: false,
      imageUrl:
          'https://foodish-api.com/images/butter-chicken/butter-chicken1.jpg',
    ),
    Restaurant(
      id: 'r4',
      name: 'Dosa Junction',
      cuisines: <String>['South Indian', 'Dosa', 'Idli'],
      rating: 4.5,
      ratingCount: 15600,
      etaMinutes: 18,
      priceForTwo: 300,
      distanceKm: 0.8,
      isVeg: true,
      imageUrl: 'https://foodish-api.com/images/dosa/dosa1.jpg',
      promoText: '₹75 OFF above ₹199',
    ),
    Restaurant(
      id: 'r5',
      name: 'Napoli Wood-Fired',
      cuisines: <String>['Pizza', 'Italian', 'Pasta'],
      rating: 4.3,
      ratingCount: 5200,
      etaMinutes: 35,
      priceForTwo: 850,
      distanceKm: 4.2,
      isVeg: false,
      imageUrl: 'https://foodish-api.com/images/pizza/pizza1.jpg',
    ),
    Restaurant(
      id: 'r6',
      name: 'Chai & Chaat Co.',
      cuisines: <String>['Street Food', 'Snacks', 'Beverages'],
      rating: 4.1,
      ratingCount: 2100,
      etaMinutes: 22,
      priceForTwo: 200,
      distanceKm: 1.9,
      isVeg: true,
      imageUrl: 'https://foodish-api.com/images/samosa/samosa1.jpg',
    ),
    Restaurant(
      id: 'r7',
      name: 'Sushi Ninja',
      cuisines: <String>['Japanese', 'Sushi', 'Asian'],
      rating: 4.7,
      ratingCount: 1800,
      etaMinutes: 45,
      priceForTwo: 1200,
      distanceKm: 5.6,
      isVeg: false,
      imageUrl: 'https://foodish-api.com/images/rice/rice5.jpg',
      promoText: '20% OFF',
    ),
    Restaurant(
      id: 'r8',
      name: 'The Waffle Window',
      cuisines: <String>['Desserts', 'Waffles', 'Ice Cream'],
      rating: 4.4,
      ratingCount: 6700,
      etaMinutes: 28,
      priceForTwo: 350,
      distanceKm: 2.8,
      isVeg: true,
      imageUrl: 'https://foodish-api.com/images/dessert/dessert1.jpg',
    ),
  ];
}

class _MockNetworkException implements Exception {
  const _MockNetworkException();
}
