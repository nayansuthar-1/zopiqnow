import 'package:zopiqnow/features/menu/data/datasources/menu_datasource.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

/// In-memory stand-in for the menu API. Returns a plausible categorized menu
/// after a short delay so the shimmer is exercised.
///
/// The app now reads Postgres ([MenuSupabaseDataSource]); this stays as the
/// tests' data source. Dish photos come from foodish-api — mock data only, never
/// production. Laccha Paratha deliberately has no `imageUrl`: vendors routinely
/// skip photos, and the fallback path has to be exercised somewhere real.
class MenuMockDataSource implements MenuDataSource {
  const MenuMockDataSource({
    this.latency = const Duration(milliseconds: 700),
    this.shouldFail = false,
  });

  final Duration latency;
  final bool shouldFail;

  @override
  Future<List<MenuCategory>> fetchMenu(String restaurantId) async {
    await Future<void>.delayed(latency);
    if (shouldFail) {
      throw const _MockMenuException();
    }
    // Prefix ids with the restaurant so cart lines are unambiguous per vendor.
    String id(String local) => '$restaurantId-$local';

    return <MenuCategory>[
      MenuCategory(
        title: 'Recommended',
        items: <MenuItem>[
          MenuItem(
            id: id('m1'),
            name: 'Signature Chicken Biryani',
            imageUrl: 'https://foodish-api.com/images/biryani/biryani2.jpg',
            description:
                'Slow-cooked basmati, tender chicken, house masala, served with raita.',
            price: 320,
            isVeg: false,
            isBestseller: true,
            rating: 4.5,
          ),
          MenuItem(
            id: id('m2'),
            name: 'Paneer Butter Masala',
            imageUrl:
                'https://foodish-api.com/images/butter-chicken/butter-chicken2.jpg',
            description: 'Cottage cheese in a rich, buttery tomato gravy.',
            price: 260,
            isVeg: true,
            isBestseller: true,
            rating: 4.3,
          ),
          MenuItem(
            id: id('m3'),
            name: 'Veg Hakka Noodles',
            imageUrl: 'https://foodish-api.com/images/pasta/pasta2.jpg',
            description: 'Wok-tossed noodles with crunchy vegetables.',
            price: 210,
            isVeg: true,
          ),
        ],
      ),
      MenuCategory(
        title: 'Starters',
        items: <MenuItem>[
          MenuItem(
            id: id('s1'),
            name: 'Chilli Paneer',
            imageUrl:
                'https://foodish-api.com/images/butter-chicken/butter-chicken3.jpg',
            description: 'Crispy paneer tossed in a spicy indo-chinese sauce.',
            price: 240,
            isVeg: true,
            rating: 4.2,
          ),
          MenuItem(
            id: id('s2'),
            name: 'Chicken 65',
            imageUrl: 'https://foodish-api.com/images/samosa/samosa2.jpg',
            description: 'Fiery, deep-fried chicken with curry leaves.',
            price: 280,
            isVeg: false,
            isBestseller: true,
            rating: 4.6,
          ),
        ],
      ),
      MenuCategory(
        title: 'Breads',
        items: <MenuItem>[
          MenuItem(
            id: id('b1'),
            name: 'Butter Garlic Naan',
            imageUrl:
                'https://foodish-api.com/images/butter-chicken/butter-chicken5.jpg',
            description: 'Tandoor-baked naan brushed with garlic butter.',
            price: 70,
            isVeg: true,
          ),
          MenuItem(
            id: id('b2'),
            name: 'Laccha Paratha',
            description: 'Flaky, multi-layered whole-wheat paratha.',
            price: 60,
            isVeg: true,
          ),
        ],
      ),
      MenuCategory(
        title: 'Desserts',
        items: <MenuItem>[
          MenuItem(
            id: id('d1'),
            name: 'Gulab Jamun (2 pcs)',
            imageUrl: 'https://foodish-api.com/images/dessert/dessert1.jpg',
            description: 'Warm, syrup-soaked milk dumplings.',
            price: 90,
            isVeg: true,
            rating: 4.4,
          ),
          MenuItem(
            id: id('d2'),
            name: 'Chocolate Brownie',
            imageUrl: 'https://foodish-api.com/images/dessert/dessert2.jpg',
            description: 'Fudgy brownie, best with ice cream.',
            price: 130,
            isVeg: true,
          ),
        ],
      ),
    ];
  }
}

class _MockMenuException implements Exception {
  const _MockMenuException();
}
