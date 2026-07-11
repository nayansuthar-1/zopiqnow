import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/domain/entities/offer.dart';

/// Static Home merchandising content: the dish-category rail and the offers
/// carousel.
///
/// Deliberately synchronous. Unlike the restaurant feed these are small,
/// slow-changing lists that Swiggy renders immediately — modelling them as
/// futures would buy nothing but a shimmer nobody sees. When they move behind
/// the API, this class grows the `async` and the providers become FutureProviders.
class HomeCatalogDataSource {
  const HomeCatalogDataSource();

  List<FoodCategory> fetchCategories() => _categories;

  List<Offer> fetchOffers() => _offers;

  /// Artwork is Microsoft Fluent Emoji (3D) — MIT licensed, free to ship. See
  /// ATTRIBUTIONS.md. Each category maps to its closest food emoji; these are
  /// stand-ins for commissioned renders, and swapping one is a single edit here.
  static const String _art = 'assets/categories';

  static const List<FoodCategory> _categories = <FoodCategory>[
    FoodCategory(id: 'biryani', label: 'Biryani', imageAsset: '$_art/biryani.png'),
    FoodCategory(id: 'pizza', label: 'Pizza', imageAsset: '$_art/pizza.png'),
    FoodCategory(id: 'burger', label: 'Burger', imageAsset: '$_art/burger.png'),
    FoodCategory(id: 'rolls', label: 'Rolls', imageAsset: '$_art/rolls.png'),
    FoodCategory(id: 'north_indian', label: 'North Indian', imageAsset: '$_art/north_indian.png'),
    FoodCategory(id: 'chinese', label: 'Chinese', imageAsset: '$_art/chinese.png'),
    FoodCategory(id: 'dosa', label: 'Dosa', imageAsset: '$_art/dosa.png'),
    FoodCategory(id: 'idli', label: 'Idli', imageAsset: '$_art/idli.png'),
    FoodCategory(id: 'momos', label: 'Momos', imageAsset: '$_art/momos.png'),
    FoodCategory(id: 'cake', label: 'Cake', imageAsset: '$_art/cake.png'),
    FoodCategory(id: 'ice_cream', label: 'Ice Cream', imageAsset: '$_art/ice_cream.png'),
    FoodCategory(id: 'noodles', label: 'Noodles', imageAsset: '$_art/noodles.png'),
    FoodCategory(id: 'shawarma', label: 'Shawarma', imageAsset: '$_art/shawarma.png'),
    FoodCategory(id: 'paratha', label: 'Paratha', imageAsset: '$_art/paratha.png'),
    FoodCategory(id: 'chaat', label: 'Chaat', imageAsset: '$_art/chaat.png'),
    FoodCategory(id: 'pure_veg', label: 'Pure Veg', imageAsset: '$_art/pure_veg.png'),
  ];

  static const List<Offer> _offers = <Offer>[
    Offer(id: 'o1', headline: '60% OFF', detail: 'UPTO ₹120', code: 'TRYNEW'),
    Offer(
      id: 'o2',
      headline: 'FLAT ₹150 OFF',
      detail: 'ABOVE ₹399',
      code: 'ZOPIQ150',
    ),
    Offer(
      id: 'o3',
      headline: 'FREE DELIVERY',
      detail: 'ON FIRST ORDER',
      code: 'WELCOME',
    ),
    Offer(id: 'o4', headline: '30% OFF', detail: 'UPTO ₹75', code: 'SAVE30'),
  ];
}
