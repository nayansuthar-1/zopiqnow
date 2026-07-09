import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

/// In-memory stand-in for the menu API. Returns a plausible categorized menu
/// after a short delay so the shimmer is exercised. Swap for HTTP later.
class MenuMockDataSource {
  const MenuMockDataSource({
    this.latency = const Duration(milliseconds: 700),
    this.shouldFail = false,
  });

  final Duration latency;
  final bool shouldFail;

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
            description: 'Cottage cheese in a rich, buttery tomato gravy.',
            price: 260,
            isVeg: true,
            isBestseller: true,
            rating: 4.3,
          ),
          MenuItem(
            id: id('m3'),
            name: 'Veg Hakka Noodles',
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
            description: 'Crispy paneer tossed in a spicy indo-chinese sauce.',
            price: 240,
            isVeg: true,
            rating: 4.2,
          ),
          MenuItem(
            id: id('s2'),
            name: 'Chicken 65',
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
            description: 'Warm, syrup-soaked milk dumplings.',
            price: 90,
            isVeg: true,
            rating: 4.4,
          ),
          MenuItem(
            id: id('d2'),
            name: 'Chocolate Brownie',
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
